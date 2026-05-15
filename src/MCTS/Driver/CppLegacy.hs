module MCTS.Driver.CppLegacy
    ( runGameCppLegacy
    ) where

import Data.Bits (xor)
import Data.Word (Word16, Word32, Word8)
import MCTS.Driver (RunInputs (..))
import MCTS.Engine (Board, applyMove, initialBoard, legalMoves, terminalWinner)
import MCTS.Error (AppError)
import MCTS.FFI.CppLegacy
    ( cppLegacyIsTerminal
    , cppLegacySelectMove
    , withCppLegacyGame
    )
import MCTS.Rng.Mix (mix)
import MCTS.Types

runGameCppLegacy :: RunInputs -> Word32 -> IO (Either AppError GameTranscript)
runGameCppLegacy inputs gid =
    withCppLegacyGame $ \game -> do
        let gameSeed = mix (inputSeed inputs) (fromIntegral gid)
        (records, finalBoard) <- go game gameSeed initialBoard (0 :: Int) []
        let winner =
                case terminalWinner (effectiveMaxPlies inputs) finalBoard of
                    Just value -> value
                    Nothing -> Draw
        pure GameTranscript{gameId = gid, gameMoves = reverse records, gameWinner = winner}
  where
    go game seed board moveNo acc = do
        cxxTerminal <- cppLegacyIsTerminal game
        case terminalWinner (effectiveMaxPlies inputs) board of
            Just _ -> pure (acc, board)
            Nothing
                | cxxTerminal -> pure (acc, board)
                | moveNo >= fromIntegral (effectiveMaxPlies inputs) -> pure (acc, board)
                | otherwise -> do
                    let budget = moveBudget inputs
                        effectiveSeed = seed `xor` fromIntegral (moveNo * 257 + 1)
                    rawAction <- cppLegacySelectMove game effectiveSeed budget
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
