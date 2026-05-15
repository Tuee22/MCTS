module MCTS.Driver.ForeignSmoke
    ( runDynamicSmokeGame
    ) where

import Data.Bits (xor)
import Data.Word (Word16, Word32, Word8)
import MCTS.Driver (RunInputs (..))
import MCTS.Engine (Board, applyMove, initialBoard, legalMoves, terminalWinner)
import MCTS.Error (AppError)
import MCTS.FFI.Common (DynamicGame (..))
import MCTS.Rng.Mix (mix)
import MCTS.Types

runDynamicSmokeGame
    :: ((DynamicGame -> IO GameTranscript) -> IO (Either AppError GameTranscript))
    -> RunInputs
    -> Word32
    -> IO (Either AppError GameTranscript)
runDynamicSmokeGame withGame inputs gid =
    withGame $ \game -> do
        let gameSeed = mix (inputSeed inputs) (fromIntegral gid)
        (records, finalBoard) <- go game gameSeed initialBoard (0 :: Int) []
        let winner =
                case terminalWinner (effectiveMaxPlies inputs) finalBoard of
                    Just value -> value
                    Nothing -> Draw
        pure GameTranscript{gameId = gid, gameMoves = reverse records, gameWinner = winner}
  where
    go game seed board moveNo acc = do
        foreignTerminal <- dynamicGameIsTerminal game
        case terminalWinner (effectiveMaxPlies inputs) board of
            Just _ -> pure (acc, board)
            Nothing
                | foreignTerminal -> pure (acc, board)
                | moveNo >= fromIntegral (effectiveMaxPlies inputs) -> pure (acc, board)
                | otherwise -> do
                    let budget = moveBudget inputs
                        effectiveSeed = seed `xor` fromIntegral (moveNo * 257 + 1)
                    rawAction <- dynamicGameSelectMove game effectiveSeed budget
                    let chosen = resolveAction board rawAction
                        visits = [(chosen, budget)]
                        record =
                            MoveRecord
                                { moveIndex = fromIntegral moveNo
                                , moveChosen = chosen
                                , moveVisits = visits
                                }
                        nextBoard = applyMove chosen board
                    go game seed nextBoard (moveNo + 1) (record : acc)

moveBudget :: RunInputs -> Word32
moveBudget inputs =
    fromIntegral $
        max 1 $
            case inputWorkload inputs of
                Rollouts -> 1
                Selfplay -> simPerMove (inputSims inputs)

resolveAction :: Board -> Word8 -> Action
resolveAction board raw =
    let legal = legalMoves board
     in case actionFromId raw of
            Just action | action `elem` legal -> action
            _ -> case legal of
                action : _ -> action
                [] -> Pawn 0 0

effectiveMaxPlies :: RunInputs -> Word16
effectiveMaxPlies inputs =
    max 1 (inputMaxPlies inputs)
