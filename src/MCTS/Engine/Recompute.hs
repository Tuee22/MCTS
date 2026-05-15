-- | Foreign-engine equity-recompute path per Phase 3 Sprint 3.6.
--
-- Given a transcript, replay the per-move search using the same backend
-- engine (here the in-process Haskell engine) and emit one
-- `(move_index, action_id, visits, equity)` record per move. Under
-- `--rng cpp` the recompute is required to agree with the transcript's
-- recorded visits at every move; disagreement aborts with
-- `AppError RecomputeMismatch (Backend, GameId, MoveIndex,
-- recomputed_record, recorded_record)` per
-- [../../documents/engineering/determinism_contract.md → Recompute Mismatch Output](../../documents/engineering/determinism_contract.md).
module MCTS.Engine.Recompute
    ( recomputeEquities
    , recomputeEqStream
    ) where

import Data.Bits (xor)
import Data.Word (Word32, Word64)
import MCTS.Engine (Board, applyMove, initialBoard)
import MCTS.Error (AppError (..))
import MCTS.Rng.Mix (mix)
import MCTS.Search.UCT (uctSearchWithEquity)
import MCTS.Transcript.EquitySidecar (EqRecord (..), EqStream (..))
import MCTS.Types
    ( Action
    , Backend (Haskell)
    , GameTranscript (..)
    , MoveRecord (..)
    , RngSource (..)
    , RunConfig (..)
    , SimBudget (..)
    , Transcript (..)
    , simPerMove
    )

-- | Replay every move in `transcript` and produce per-move equity
-- records using the in-process Haskell engine. Under `CppRng` the
-- recompute hard-asserts visit equality with the transcript's recorded
-- visits at every move and short-circuits with `RecomputeMismatch` on
-- the first disagreement.
recomputeEquities :: Transcript -> Either AppError [EqRecord]
recomputeEquities transcript =
    let config = transcriptConfig transcript
        masterSeed = runMasterSeed config
        rng = runRngSource config
        sims =
            max
                1
                ( case (runInitialSims config, runPerMoveSims config) of
                    (i, p) ->
                        fromIntegral
                            ( simPerMove
                                (if i == p then FixedSims (fromIntegral p) else RampedSims (fromIntegral i) (fromIntegral p))
                            )
                )
        maxPlies = min 60 (fromIntegral (runMaxPlies config))
     in concatMapEither
            (recomputeGame masterSeed rng sims maxPlies)
            (transcriptGames transcript)

-- | The complete `EqStream` for a transcript's recompute: hash + backend
-- + build id + per-move records.
recomputeEqStream
    :: String
    -> String
    -> Transcript
    -> Either AppError EqStream
recomputeEqStream transcriptHash buildId transcript =
    case recomputeEquities transcript of
        Left err -> Left err
        Right records ->
            Right
                EqStream
                    { eqTranscriptHash = transcriptHash
                    , eqBackend = envelopeBackendOrHaskell transcript
                    , eqBuildId = buildId
                    , eqRecords = records
                    }
  where
    envelopeBackendOrHaskell t = case transcriptGames t of
        _ : _ -> case runBackend (transcriptConfig t) of
            backend -> backend
        [] -> Haskell

recomputeGame
    :: Word64
    -> RngSource
    -> Int
    -> Int
    -> GameTranscript
    -> Either AppError [EqRecord]
recomputeGame masterSeed rng sims maxPlies game =
    let perGameSeed = mix masterSeed (fromIntegral (gameId game))
     in stepRecords perGameSeed initialBoard 0 (gameMoves game) []
  where
    stepRecords :: Word64 -> Board -> Int -> [MoveRecord] -> [EqRecord] -> Either AppError [EqRecord]
    stepRecords _ _ _ [] acc = Right (reverse acc)
    stepRecords seed board moveNo (recorded : rest) acc =
        let salt = case rng of
                CppRng -> 0
                NativeRng -> 0x100000001b3 :: Word64
            effectiveSeed = seed `xor` salt `xor` fromIntegral (moveNo * 257 + 1)
            (_, visitTable, equityTable) = uctSearchWithEquity board effectiveSeed sims maxPlies
            lookupEquity act = lookup act equityTable
            recordEq =
                EqRecord
                    { eqGameId = gameId game
                    , eqMoveIndex = moveIndex recorded
                    , eqChosen = moveChosen recorded
                    , eqEquity = case lookupEquity (moveChosen recorded) of
                        Just e -> realToFrac e
                        Nothing -> 0.0
                    }
         in case rng of
                CppRng ->
                    case visitMismatch visitTable (moveVisits recorded) of
                        Just (acted, recomputedCount, recordedCount) ->
                            Left
                                ( RecomputeMismatch
                                    Haskell
                                    (fromIntegral moveNo)
                                    (fromIntegral (gameId game))
                                    recorded
                                    recorded
                                        { moveVisits =
                                            [(acted, recomputedCount), (acted, recordedCount)]
                                        }
                                )
                        Nothing ->
                            let nextBoard = applyMove (moveChosen recorded) board
                             in stepRecords seed nextBoard (moveNo + 1) rest (recordEq : acc)
                NativeRng ->
                    let nextBoard = applyMove (moveChosen recorded) board
                     in stepRecords seed nextBoard (moveNo + 1) rest (recordEq : acc)

-- | Compare two visit tables under `--rng cpp`. Returns `Just (action,
-- recomputed, recorded)` on the first disagreement, `Nothing` if every
-- action's visit count matches.
visitMismatch
    :: [(Action, Word32)]
    -> [(Action, Word32)]
    -> Maybe (Action, Word32, Word32)
visitMismatch recomputed recorded =
    case [ (a, vRecomputed, vRecorded)
         | (a, vRecomputed) <- recomputed
         , let vRecorded = lookupVisits a recorded
         , vRecomputed /= vRecorded
         ] of
        m : _ -> Just m
        [] -> Nothing
  where
    lookupVisits a table = case lookup a table of
        Just v -> v
        Nothing -> 0

concatMapEither :: (a -> Either e [b]) -> [a] -> Either e [b]
concatMapEither _ [] = Right []
concatMapEither f (x : xs) =
    case f x of
        Left err -> Left err
        Right ys -> case concatMapEither f xs of
            Left err -> Left err
            Right zs -> Right (ys <> zs)
