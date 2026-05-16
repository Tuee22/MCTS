{-# LANGUAGE RankNTypes #-}

-- | Shared driver for FFI-backed backends exposing the doctrine's
-- full search ABI (`<prefix>_search_move` + standard
-- `new/free/is_terminal` triplet). Each per-backend module supplies
-- a `withCpp*SearchGame` opener; this module wraps the per-move
-- loop with the same perspective-flip translation that
-- `MCTS.Driver.CppLegacy` uses.
module MCTS.Driver.ForeignSearch
    ( runForeignSearchGame
    , ForeignSearchOpener
    ) where

import Data.Bits (xor)
import Data.Word (Word32, Word64, Word8)
import MCTS.Driver (RunInputs (..))
import MCTS.Engine (Board, applyMove, boardSideToMove, initialBoard, legalMoves, terminalWinner)
import MCTS.Error (AppError (..))
import MCTS.FFI.Common (DynamicSearchGame (..))
import MCTS.Rng.Mix (mix)
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
            case legacyWinner finalBoard of
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
            if cxxTerminal
                then pure (Right (acc, board))
                else case legacyWinner board of
                    Just _ -> pure (Right (acc, board))
                    Nothing -> do
                        let budget = moveBudget inputs
                            effectiveSeed = seed `xor` fromIntegral (moveNo * 257 + 1)
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

applyFlip :: Bool -> Word8 -> Word8
applyFlip False aid = aid
applyFlip True aid
    | aid <= 80 = 80 - aid
    | aid <= 144 = 225 - aid
    | aid <= 208 = fromIntegral (353 - fromIntegral aid :: Int)
    | otherwise = aid
