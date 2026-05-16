module MCTS.Driver.CppLegacy
    ( runGameCppLegacy
    , legacyMaxRolloutIters
    ) where

import Data.Bits (xor)
import Data.Word (Word32, Word64, Word8)
import MCTS.Driver (RunInputs (..))
import MCTS.Engine (Board, applyMove, boardSideToMove, initialBoard, legalMoves, terminalWinner)
import MCTS.Error (AppError (..))
import MCTS.FFI.CppLegacy
    ( CppLegacyGame
    , cppLegacyIsTerminal
    , cppLegacySearchMove
    , withCppLegacyGame
    )
import MCTS.Rng.Mix (mix)
import MCTS.Types

-- | Hard safety cap on the per-game ply count for backend (i). The
-- legacy's `MAX_ROLLOUT_ITERS = 10000` constant lives in
-- `cpp-legacy/legacy-core/mcts.hpp`; using the same value here matches
-- the legacy's notion of "runaway game" and lets
-- `mcts verify legacy-parity` surface
-- `AppError LegacyParityRolloutOverflow` cohesively.
legacyMaxRolloutIters :: Int
legacyMaxRolloutIters = 10000

-- | Run a single backend (i) game through the legacy C ABI. The
-- transcript carries the full sorted `(action_id, visits)` vector
-- emitted by `mcts_legacy_search_move`, the chosen action committed by
-- `choose_best_action`, and the legacy's no-draw-rule terminal label
-- mapped onto the Phase 2 wire format.
--
-- Per [phase-4-cpp-legacy-port-and-ffi-bridge.md → Sprint 4.4](../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md)
-- the `--max-plies` CLI flag is silently ignored for backend (i): the
-- driver follows the legacy's no-draw terminal semantics. The hard
-- internal cap is `legacyMaxRolloutIters = 10000` (the legacy's own
-- `MAX_ROLLOUT_ITERS`); hitting it surfaces as
-- `AppError LegacyParityRolloutOverflow`.
runGameCppLegacy :: RunInputs -> Word32 -> IO (Either AppError GameTranscript)
runGameCppLegacy inputs gid = do
    bracketed <- withCppLegacyGame $ \game -> do
        let gameSeed = mix (inputSeed inputs) (fromIntegral gid)
        go game gameSeed initialBoard (0 :: Int) []
    case bracketed of
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
        :: CppLegacyGame
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
            cxxTerminal <- cppLegacyIsTerminal game
            if cxxTerminal
                then pure (Right (acc, board))
                else case legacyWinner board of
                    Just _ -> pure (Right (acc, board))
                    Nothing -> do
                        let budget = moveBudget inputs
                            effectiveSeed = seed `xor` fromIntegral (moveNo * 257 + 1)
                        searched <- cppLegacySearchMove game effectiveSeed budget
                        case searched of
                            Left err -> pure (Left err)
                            Right (rawChosen, rawVisits) ->
                                -- The legacy stores the board in a perspective
                                -- where the side-to-move is always at y=0
                                -- (`board::action::flip()` mirrors through the
                                -- centre on every move). Haskell's `Board`
                                -- carries `boardSideToMove` and uses absolute
                                -- coordinates, so action ids emitted by the
                                -- legacy must be flipped on Villain's turn.
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

-- | Map the legacy's `(action_id, visits)` records onto the Haskell
-- action enumeration. The legacy's child set is authoritative for the
-- per-move visit vector — every entry comes from the legacy's own
-- legal-move generator. Records whose action_id falls outside the
-- canonical enumeration are dropped silently so the transcript remains
-- well-typed; cross-backend bit-for-bit visit-count agreement is owned
-- by Phase 7 and lives outside this driver.
decodeVisits :: [(Word8, Word32)] -> [(Action, Word32)]
decodeVisits raw =
    [ (action, visits)
    | (rawId, visits) <- raw
    , Just action <- [actionFromId rawId]
    ]

-- | Map the legacy's flipped-then-canonicalised `out_chosen` byte onto a
-- Haskell `Action`. We trust the legacy's action enumeration: at this
-- point `raw` is in the absolute (Hero-at-y=0) action ID space and may
-- legitimately refer to walls outside Haskell's
-- `legalMoves`-truncated set. Falling back to Haskell's enumeration
-- would mask the legacy's real choice with the first legal pawn move,
-- desynchronising the two boards.
resolveAction :: Board -> Word8 -> Action
resolveAction board raw =
    case actionFromId raw of
        Just action -> action
        Nothing -> case legalMoves board of
            action : _ -> action
            [] -> Pawn 0 0

-- | The legacy has no draw rule: a terminal position is exactly a
-- pawn-at-goal. `Nothing` means the loop's hard ply cap fired before
-- either side reached its goal.
legacyWinner :: Board -> Maybe Winner
legacyWinner board =
    case terminalWinner maxBound board of
        Just Draw -> Nothing
        other -> other

-- | The legacy stores each child's `_action` after a `flip()` through
-- the board centre (see `Deep_Copy(source, true)` in
-- `cpp-legacy/legacy-core/board.cpp`). The action text emitted by
-- `get_action_text(false)` is therefore in the *child's* perspective —
-- i.e. the opposite of the player who just chose the move. To recover
-- Haskell's absolute (Hero-at-y=0) coordinate system we flip the
-- action id whenever the current player (in Haskell terms) is Hero,
-- because Hero's move lands the child in Villain-view; Villain's move
-- lands the child back in Hero-view (two flips cancel).
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
