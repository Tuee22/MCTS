{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RankNTypes #-}

module MCTS.Verify.Semantic
    ( SemanticBackendResult (..)
    , SemanticCheckResult (..)
    , runSemanticParity
    , semanticBackends
    , semanticHistories
    ) where

import Control.Monad (foldM)
import Data.Bits (xor)
import Data.List (nub)
import Data.Word (Word32, Word64, Word8)
import MCTS.Engine
    ( Board
    , applyMove
    , boardSideToMove
    , initialBoard
    , legalMoves
    , terminalWinner
    )
import MCTS.Error (AppError (..))
import MCTS.FFI.Common (DynamicSearchGame (..))
import MCTS.FFI.CppFunctional (withCppFunctionalSearchGame)
import MCTS.FFI.CppImperative (withCppImperativeSearchGame)
import MCTS.FFI.Rust (withRustSearchGame)
import MCTS.Search.UCT (uctSearch)
import MCTS.Types
    ( Action
    , Backend (..)
    , Side (..)
    , actionFromId
    , actionId
    , backendIdentifier
    )

data SemanticCheckResult = SemanticCheckResult
    { semanticBackendResults :: ![SemanticBackendResult]
    , semanticHistoryCount :: !Int
    }
    deriving (Eq, Show)

data SemanticBackendResult = SemanticBackendResult
    { semanticBackend :: !Backend
    , semanticReplayChecks :: !Int
    , semanticSearchChecks :: !Int
    , semanticTerminalRejectionChecks :: !Int
    }
    deriving (Eq, Show)

type SearchOpener =
    forall a. (DynamicSearchGame -> IO a) -> IO (Either AppError a)

semanticBackends :: [Backend]
semanticBackends =
    [ CppImperative
    , CppFunctional
    , Rust
    , Haskell
    ]

semanticMaxPlies :: Word32
semanticMaxPlies = 200

semanticSearchSims :: Word32
semanticSearchSims = 16

semanticHistories :: [[Action]]
semanticHistories =
    [ []
    , generatedHistory 7 4
    , generatedHistory 23 8
    , generatedHistory 41 12
    ]

runSemanticParity :: IO (Either AppError SemanticCheckResult)
runSemanticParity = do
    checked <- mapM checkBackend semanticBackends
    pure $ do
        backendResults <- sequence checked
        Right
            SemanticCheckResult
                { semanticBackendResults = backendResults
                , semanticHistoryCount = length semanticHistories
                }

checkBackend :: Backend -> IO (Either AppError SemanticBackendResult)
checkBackend backend = do
    replayResults <- mapM (checkReplay backend) semanticHistories
    searchResults <- mapM (checkSearch backend) (zip [0 :: Int ..] semanticHistories)
    terminalResult <- checkTerminalRejection backend
    pure $ do
        replayCount <- sum <$> sequence replayResults
        searchCount <- sum <$> sequence searchResults
        terminalCount <- terminalResult
        Right
            SemanticBackendResult
                { semanticBackend = backend
                , semanticReplayChecks = replayCount
                , semanticSearchChecks = searchCount
                , semanticTerminalRejectionChecks = terminalCount
                }

checkReplay :: Backend -> [Action] -> IO (Either AppError Int)
checkReplay Haskell history =
    pure $ length history <$ replayHaskellChecked Haskell history
checkReplay backend history =
    runForeignSearchGame backend $ \game ->
        replayForeignChecked backend game history

checkSearch :: Backend -> (Int, [Action]) -> IO (Either AppError Int)
checkSearch backend (idx, history) =
    case replayHaskellChecked backend history of
        Left err -> pure (Left err)
        Right board
            | terminalWinner (fromIntegral semanticMaxPlies) board /= Nothing ->
                pure (Right 0)
            | backend == Haskell ->
                pure (validateSearchResult backend board (haskellSearch board seed))
            | otherwise ->
                runForeignSearchGame backend $ \game -> do
                    replayed <- replayForeignChecked backend game history
                    case replayed of
                        Left err -> pure (Left err)
                        Right _ -> do
                            searched <- searchGameSearchMove game seed semanticSearchSims
                            pure $
                                validateSearchResult backend board $
                                    decodeForeignSearchResult backend board searched
  where
    seed = 0x517cc1b727220a95 `xor` fromIntegral idx

checkTerminalRejection :: Backend -> IO (Either AppError Int)
checkTerminalRejection Haskell =
    pure $ do
        board <- replayHaskellChecked Haskell terminalHeroHistory
        case terminalWinner (fromIntegral semanticMaxPlies) board of
            Just _ -> Right 1
            Nothing -> semanticFailure Haskell "terminal history did not reach a terminal board"
checkTerminalRejection backend =
    runForeignSearchGame backend $ \game -> do
        replayed <- replayForeignChecked backend game terminalHeroHistory
        case replayed of
            Left err -> pure (Left err)
            Right _ -> do
                terminal <- searchGameIsTerminal game
                if not terminal
                    then pure (semanticFailure backend "foreign terminal history was not terminal")
                    else do
                        searched <- searchGameSearchMove game 0x9e3779b97f4a7c15 semanticSearchSims
                        pure $
                            case searched of
                                Left _ -> Right 1
                                Right _ ->
                                    semanticFailure
                                        backend
                                        "foreign search accepted a terminal board"

replayForeignChecked
    :: Backend
    -> DynamicSearchGame
    -> [Action]
    -> IO (Either AppError Int)
replayForeignChecked backend game history =
    foldM applyStep (Right (initialBoard, 0 :: Int)) history >>= \case
        Left err -> pure (Left err)
        Right (_, count) -> pure (Right count)
  where
    applyStep (Left err) _ = pure (Left err)
    applyStep (Right (board, count)) action =
        case checkedApply backend board action of
            Left err -> pure (Left err)
            Right nextBoard -> do
                applied <- searchGameApplyAction game (foreignActionId board action)
                case applied of
                    Left err -> pure (Left err)
                    Right () -> do
                        foreignTerminal <- searchGameIsTerminal game
                        let haskellTerminal =
                                terminalWinner (fromIntegral semanticMaxPlies) nextBoard /= Nothing
                        if foreignTerminal == haskellTerminal
                            then pure (Right (nextBoard, count + 1))
                            else
                                pure $
                                    semanticFailure
                                        backend
                                        ( "terminal-state mismatch after replay step "
                                            <> show count
                                        )

replayHaskellChecked :: Backend -> [Action] -> Either AppError Board
replayHaskellChecked backend =
    foldM (checkedApply backend) initialBoard

checkedApply :: Backend -> Board -> Action -> Either AppError Board
checkedApply backend board action
    | action `elem` legalMoves board = Right (applyMove action board)
    | otherwise =
        semanticFailure
            backend
            ("generated history contains illegal action " <> show action)

haskellSearch :: Board -> Word64 -> Either AppError (Action, [(Action, Word32)])
haskellSearch board seed =
    Right (uctSearch board seed (fromIntegral semanticSearchSims) (fromIntegral semanticMaxPlies))

decodeForeignSearchResult
    :: Backend
    -> Board
    -> Either AppError (Word8, [(Word8, Word32)])
    -> Either AppError (Action, [(Action, Word32)])
decodeForeignSearchResult _ _ (Left err) = Left err
decodeForeignSearchResult backend board (Right (rawChosen, rawVisits)) = do
    chosen <- actionFromForeignId backend board rawChosen
    visits <-
        mapM
            ( \(rawAction, count) -> do
                action <- actionFromForeignId backend board rawAction
                Right (action, count)
            )
            rawVisits
    Right (chosen, visits)

validateSearchResult
    :: Backend
    -> Board
    -> Either AppError (Action, [(Action, Word32)])
    -> Either AppError Int
validateSearchResult backend board searched = do
    (chosen, visits) <- searched
    let legal = legalMoves board
        visitActions = map fst visits
        visitIds = map actionId visitActions
        visitCounts = map snd visits
    if null visits
        then semanticFailure backend "search returned an empty visit vector"
        else
            if chosen `notElem` legal
                then semanticFailure backend ("search chose illegal action " <> show chosen)
                else
                    if any (`notElem` legal) visitActions
                        then semanticFailure backend "visit vector contains illegal action"
                        else
                            if length visitIds /= length (nub visitIds)
                                then semanticFailure backend "visit vector contains duplicate action ids"
                                else
                                    if any (> semanticSearchSims) visitCounts
                                        then
                                            semanticFailure
                                                backend
                                                "visit vector contains a count above the simulation budget"
                                        else case lookup chosen visits of
                                            Nothing ->
                                                semanticFailure
                                                    backend
                                                    "chosen action is absent from visit vector"
                                            Just chosenVisits
                                                | chosenVisits == maximum visitCounts -> Right 1
                                                | otherwise ->
                                                    semanticFailure
                                                        backend
                                                        "chosen action is not a max-visit candidate"

withForeignSearchGame :: Backend -> SearchOpener
withForeignSearchGame backend =
    case backend of
        CppImperative -> withCppImperativeSearchGame
        CppFunctional -> withCppFunctionalSearchGame
        Rust -> withRustSearchGame
        Haskell -> \_ -> pure (Left (IOErrorText "Haskell has no foreign search game"))
        CppLegacy -> \_ -> pure (Left (IOErrorText "Q7 excludes backend (i) cpp-legacy"))

runForeignSearchGame
    :: Backend
    -> (DynamicSearchGame -> IO (Either AppError a))
    -> IO (Either AppError a)
runForeignSearchGame backend action = do
    outer <- withForeignSearchGame backend action
    pure $
        case outer of
            Left err -> Left err
            Right inner -> inner

actionFromForeignId :: Backend -> Board -> Word8 -> Either AppError Action
actionFromForeignId backend board raw =
    case actionFromId (applyFlip (needsFlip (boardSideToMove board)) raw) of
        Just action -> Right action
        Nothing -> semanticFailure backend ("invalid foreign action id " <> show raw)

foreignActionId :: Board -> Action -> Word8
foreignActionId board action =
    applyFlip (needsFlip (boardSideToMove board)) (actionId action)

needsFlip :: Side -> Bool
needsFlip Hero = True
needsFlip Villain = False

applyFlip :: Bool -> Word8 -> Word8
applyFlip False action = action
applyFlip True action
    | action <= 80 = 80 - action
    | action <= 144 = 225 - action
    | action <= 208 = fromIntegral (353 - fromIntegral action :: Int)
    | otherwise = action

generatedHistory :: Int -> Int -> [Action]
generatedHistory salt maxDepth = go initialBoard 0 []
  where
    go board depth acc
        | depth >= maxDepth = reverse acc
        | terminalWinner (fromIntegral semanticMaxPlies) board /= Nothing = reverse acc
        | null moves = reverse acc
        | otherwise =
            let idx = (salt + depth * 7) `mod` length moves
             in case drop idx moves of
                    action : _ -> go (applyMove action board) (depth + 1) (action : acc)
                    [] -> reverse acc
      where
        moves = legalMoves board

terminalHeroHistory :: [Action]
terminalHeroHistory =
    [ pawn 4 1
    , pawn 3 8
    , pawn 4 2
    , pawn 2 8
    , pawn 4 3
    , pawn 1 8
    , pawn 4 4
    , pawn 0 8
    , pawn 4 5
    , pawn 0 7
    , pawn 4 6
    , pawn 0 6
    , pawn 4 7
    , pawn 0 5
    , pawn 4 8
    ]
  where
    pawn :: Int -> Int -> Action
    pawn x y =
        case actionFromId (fromIntegral (y * 9 + x)) of
            Just action -> action
            Nothing -> error "MCTS.Verify.Semantic: invalid terminal fixture action"

semanticFailure :: Backend -> String -> Either AppError a
semanticFailure backend message =
    Left (IOErrorText ("semantic parity " <> backendIdentifier backend <> ": " <> message))
