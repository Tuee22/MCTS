-- | Per-backend driver dispatch for `mcts bench` and `mcts verify`.
--
-- The pure in-process Haskell `runBatch` covers the logical fallback.
-- Backends (i) `cpp-legacy`, (ii) `cpp-imperative`, and (iii)
-- `cpp-functional` are retired from live dispatch after Sprints 8.4,
-- 8.5, and 8.6; their historical transcripts live under `test/golden/`.
-- When a live foreign backend's shared library is present, `--backend X`
-- routes through the per-backend FFI driver so the transcript carries
-- both the engine's real per-move `(action_id, visits)` records and the
-- live `mcts_<backend>_get_envelope()` payload. The C++/Rust search ABI
-- currently has a fixed 60-ply search horizon, matching the Haskell
-- rollout cap; runs with lower `max_plies` use the in-process fallback
-- until that ABI grows an explicit per-run search cap. When a library is
-- absent the in-process driver is also used so `cabal test all` stays
-- self-contained.
module MCTS.Driver.Dispatch
    ( runBatchDispatch
    , runBatchNoWriteDispatch
    ) where

import qualified Data.Text as Text
import Data.Word (Word32)
import qualified MCTS.Driver as Driver
import MCTS.Driver.ForeignSearch (runForeignSearchGame)
import MCTS.Error (AppError, renderError)
import MCTS.FFI.Common (EngineEnvelope, engineEnvelopeToEnvelope)
import MCTS.FFI.Rust (loadRustEnvelope, rustLibraryPath, withRustSearchGame)
import MCTS.Types (Backend (..), GameTranscript)
import System.Directory (doesFileExist)

runBatchDispatch :: Driver.RunInputs -> IO (Either String Driver.BatchResult)
runBatchDispatch inputs =
    case Driver.inputBackend inputs of
        CppLegacy -> pure (Left "cpp-legacy is retired from live dispatch; use test/golden/cpp-legacy/")
        CppImperative -> pure (Left "cpp-imperative is retired from live dispatch; use test/golden/cpp-imperative/")
        CppFunctional -> pure (Left "cpp-functional is retired from live dispatch; use test/golden/cpp-functional/")
        Rust -> do
            present <- doesFileExist rustLibraryPath
            if present && canUseCappedForeignSearch inputs
                then
                    runWithLiveEnvelope
                        loadRustEnvelope
                        (runWithRunner (runForeignSearchGame withRustSearchGame) inputs)
                        inputs
                else Driver.runBatch inputs
        _ -> Driver.runBatch inputs

runBatchNoWriteDispatch :: Driver.RunInputs -> IO (Either String ())
runBatchNoWriteDispatch inputs =
    case Driver.inputBackend inputs of
        CppLegacy -> pure (Left "cpp-legacy is retired from live dispatch; use test/golden/cpp-legacy/")
        CppImperative -> pure (Left "cpp-imperative is retired from live dispatch; use test/golden/cpp-imperative/")
        CppFunctional -> pure (Left "cpp-functional is retired from live dispatch; use test/golden/cpp-functional/")
        Rust -> do
            present <- doesFileExist rustLibraryPath
            if present && canUseCappedForeignSearch inputs
                then
                    Driver.runBatchNoWriteWithGame
                        (runWithRunner (runForeignSearchGame withRustSearchGame) inputs)
                        inputs
                else Driver.runBatchNoWrite inputs
        _ -> Driver.runBatchNoWrite inputs

canUseCappedForeignSearch :: Driver.RunInputs -> Bool
canUseCappedForeignSearch inputs =
    Driver.inputMaxPlies inputs >= 60

runWithLiveEnvelope
    :: IO (Either AppError EngineEnvelope)
    -> (Word32 -> IO (Either String GameTranscript))
    -> Driver.RunInputs
    -> IO (Either String Driver.BatchResult)
runWithLiveEnvelope loadEnvelope runOne inputs = do
    loaded <- loadEnvelope
    case loaded of
        Left err -> pure (Left (Text.unpack (renderError err)))
        Right envelope ->
            Driver.runBatchWithGameEnvelope
                (engineEnvelopeToEnvelope envelope)
                runOne
                inputs

runWithRunner
    :: (Driver.RunInputs -> Word32 -> IO (Either AppError GameTranscript))
    -> Driver.RunInputs
    -> Word32
    -> IO (Either String GameTranscript)
runWithRunner runner inputs gid = do
    result <- runner inputs gid
    pure $ case result of
        Right game -> Right game
        Left err -> Left (Text.unpack (renderError err))
