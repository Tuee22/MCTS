{-# LANGUAGE RankNTypes #-}

-- | Shared driver for FFI-backed backends exposing the doctrine's
-- full search ABI (`<prefix>_search_move`, `<prefix>_apply_action`,
-- and the standard `new/free/is_terminal` triplet). Each per-backend module supplies
-- a `withCpp*SearchGame` opener; this module wraps the per-move
-- loop with the same perspective-flip translation that
-- `MCTS.Driver.CppLegacy` uses.
module MCTS.Driver.ForeignSearch
    ( runForeignSearchGame
    , foreignSearchMove
    , ForeignSearchOpener
    ) where

import Data.Bits (xor)
import Data.Word (Word16, Word32, Word64, Word8)
import MCTS.Driver (RunInputs (..))
import MCTS.Engine (Board, applyMove, boardSideToMove, initialBoard, legalMoves, terminalWinner)
import MCTS.Error (AppError (..))
import MCTS.FFI.Common (DynamicSearchGame (..))
import MCTS.Rng.Mix (backendNativeSalt, mix)
import MCTS.Types

legacyMaxRolloutIters :: Int
legacyMaxRolloutIters = 10000

type ForeignSearchOpener =
    forall a. (DynamicSearchGame -> IO a) -> IO (Either AppError a)

-- | Run a single game through a `DynamicSearchGame` opener. Mirrors
-- `MCTS.Driver.CppLegacy.runGameCppLegacy` and applies the same
-- legacy-coordinate flip when the side-to-move (in Haskell) is Hero,
-- because the engine source under `cpp-imperative/engine/` is a
-- byte-for-byte copy of the legacy core.
runForeignSearchGame
    :: ForeignSearchOpener
    -> RunInputs
    -> Word32
    -> IO (Either AppError GameTranscript)
runForeignSearchGame openGame inputs gid = do
    outer <- openGame $ \game -> do
        let gameSeed = mix (inputSeed inputs) (fromIntegral gid)
        go game gameSeed initialBoard (0 :: Int) []
    case outer of
        Left err -> pure (Left err)
        Right (Left err) -> pure (Left err)
        Right (Right (records, finalBoard)) ->
            case terminalWinner (inputMaxPlies inputs) finalBoard of
                Just winner ->
                    pure $
                        Right
                            GameTranscript
                                { gameId = gid
                                , gameMoves = reverse records
                                , gameWinner = winner
                                }
                Nothing ->
                    pure $
                        Left $
                            LegacyParityRolloutOverflow
                                (fromIntegral (inputSeed inputs))
                                (fromIntegral gid)
                                (length records)
  where
    go
        :: DynamicSearchGame
        -> Word64
        -> Board
        -> Int
        -> [MoveRecord]
        -> IO (Either AppError ([MoveRecord], Board))
    go game seed board moveNo acc
        | moveNo >= legacyMaxRolloutIters =
            pure $
                Left $
                    LegacyParityRolloutOverflow
                        (fromIntegral (inputSeed inputs))
                        (fromIntegral gid)
                        moveNo
        | otherwise = do
            cxxTerminal <- searchGameIsTerminal game
            if cxxTerminal || terminalWinner (inputMaxPlies inputs) board /= Nothing
                then pure (Right (acc, board))
                else case legacyWinner board of
                    Just _ -> pure (Right (acc, board))
                    Nothing -> do
                        let budget = moveBudget inputs
                            salt = backendNativeSalt (inputRng inputs) (inputBackend inputs)
                            effectiveSeed = seed `xor` salt `xor` fromIntegral (moveNo * 257 + 1)
                        searched <- searchGameSearchMove game effectiveSeed budget
                        case searched of
                            Left err -> pure (Left err)
                            Right (rawChosen, rawVisits) ->
                                let flipped = needsFlip (boardSideToMove board)
                                    chosen = resolveAction board (applyFlip flipped rawChosen)
                                    visits = decodeVisits (map (\(aid, n) -> (applyFlip flipped aid, n)) rawVisits)
                                    record =
                                        MoveRecord
                                            { moveIndex = fromIntegral moveNo
                                            , moveChosen = chosen
                                            , moveVisits = visits
                                            }
                                    nextBoard = applyMove chosen board
                                 in go game seed nextBoard (moveNo + 1) (record : acc)

-- | Search one move from an arbitrary Haskell `Board` by rebuilding a
-- fresh foreign board from the already-played move history, then
-- calling the backend's `search_move` ABI. Used by `mcts play`, where
-- human moves can interleave with backend-selected AI moves and no
-- long-lived foreign board can be trusted after `:undo`.
foreignSearchMove
    :: Backend
    -> ForeignSearchOpener
    -> RngSource
    -> Word64
    -> Word16
    -> Int
    -> Board
    -> [MoveRecord]
    -> IO (Either AppError (Action, [(Action, Word32)]))
foreignSearchMove backend openGame rng gameSeed maxPlies sims board history = do
    outer <- openGame $ \game -> do
        synced <- syncHistory game initialBoard history
        case synced of
            Left err -> pure (Left err)
            Right rebuilt
                | rebuilt /= board ->
                    pure $
                        Left $
                            FFIFailure
                                backend
                                "foreignSearchMove"
                                "Haskell board and replayed foreign history diverged"
                | terminalWinner maxPlies board /= Nothing ->
                    pure $
                        Left $
                            FFIFailure
                                backend
                                "foreignSearchMove"
                                "cannot search from terminal board"
                | otherwise -> do
                    let moveNo = length history
                        budget = fromIntegral (max 1 sims)
                        salt = backendNativeSalt rng backend
                        effectiveSeed = gameSeed `xor` salt `xor` fromIntegral (moveNo * 257 + 1)
                    searched <- searchGameSearchMove game effectiveSeed budget
                    pure (decodeSearchResult backend board searched)
    pure $ case outer of
        Left err -> Left err
        Right result -> result

syncHistory
    :: DynamicSearchGame
    -> Board
    -> [MoveRecord]
    -> IO (Either AppError Board)
syncHistory _ board [] = pure (Right board)
syncHistory game board (record : rest) = do
    let rawAction = foreignActionId board (moveChosen record)
    applied <- searchGameApplyAction game rawAction
    case applied of
        Left err -> pure (Left err)
        Right () -> syncHistory game (applyMove (moveChosen record) board) rest

decodeSearchResult
    :: Backend
    -> Board
    -> Either AppError (Word8, [(Word8, Word32)])
    -> Either AppError (Action, [(Action, Word32)])
decodeSearchResult _ board (Right (rawChosen, rawVisits)) =
    let flipped = needsFlip (boardSideToMove board)
        chosen = resolveAction board (applyFlip flipped rawChosen)
        visits = decodeVisits (map (\(aid, n) -> (applyFlip flipped aid, n)) rawVisits)
     in Right (chosen, visits)
decodeSearchResult _ _ (Left err) = Left err

moveBudget :: RunInputs -> Word32
moveBudget inputs =
    fromIntegral $
        max 1 $
            case inputWorkload inputs of
                Rollouts -> 1
                Selfplay -> simPerMove (inputSims inputs)

decodeVisits :: [(Word8, Word32)] -> [(Action, Word32)]
decodeVisits raw =
    [ (action, visits)
    | (rawId, visits) <- raw
    , Just action <- [actionFromId rawId]
    ]

resolveAction :: Board -> Word8 -> Action
resolveAction board raw =
    case actionFromId raw of
        Just action -> action
        Nothing -> case legalMoves board of
            action : _ -> action
            [] -> Pawn 0 0

legacyWinner :: Board -> Maybe Winner
legacyWinner board =
    case terminalWinner maxBound board of
        Just Draw -> Nothing
        other -> other

needsFlip :: Side -> Bool
needsFlip Hero = True
needsFlip Villain = False

foreignActionId :: Board -> Action -> Word8
foreignActionId board action =
    applyFlip (needsFlip (boardSideToMove board)) (actionId action)

applyFlip :: Bool -> Word8 -> Word8
applyFlip False aid = aid
applyFlip True aid
    | aid <= 80 = 80 - aid
    | aid <= 144 = 225 - aid
    | aid <= 208 = fromIntegral (353 - fromIntegral aid :: Int)
    | otherwise = aid
