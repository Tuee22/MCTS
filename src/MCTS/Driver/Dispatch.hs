{-# LANGUAGE RankNTypes #-}

-- | Per-backend driver dispatch for `mcts bench` and `mcts verify`.
--
-- The pure in-process Haskell `runBatch` covers the logical fallback.
-- When a live foreign backend's shared library is present, `--backend X`
-- routes through the per-backend FFI driver so the transcript carries
-- both the engine's real per-move `(action_id, visits)` records and the
-- live `mcts_<backend>_get_envelope()` payload. The C++/Rust search ABI
-- currently has a fixed 60-ply search horizon, matching the Haskell
-- rollout cap; runs with lower `max_plies` use the in-process fallback
-- until that ABI grows an explicit per-run search cap. When a library is
-- absent the in-process driver is also used so focused test stanzas stay
-- self-contained.
module MCTS.Driver.Dispatch
    ( runBatchDispatch
    , runBatchNoWriteDispatch
    ) where

import qualified Data.Text as Text
import Data.Word (Word32, Word64)
import qualified MCTS.Driver as Driver
import MCTS.Driver.ForeignSearch (ForeignSearchOpener, runForeignSearchGame)
import MCTS.Error (AppError, renderError)
import MCTS.FFI.Common (EngineEnvelope, engineEnvelopeToEnvelope)
import MCTS.FFI.CppFunctional
    ( cppFunctionalLibraryPath
    , loadCppFunctionalEnvelope
    , withCppFunctionalSearchGame
    )
import MCTS.FFI.CppImperative
    ( cppImperativeLibraryPath
    , loadCppImperativeEnvelope
    , withCppImperativeSearchGame
    )
import MCTS.FFI.CppLegacy
    ( cppLegacyLibraryPath
    , loadCppLegacyEnvelope
    , withCppLegacySearchGame
    )
import MCTS.FFI.Rust (loadRustEnvelope, rustLibraryPath, withRustSearchGame)
import MCTS.Rng.Cpp (cppMoveSeedsIfAvailable, cppRngAvailable)
import MCTS.Types (Backend (..), GameTranscript, RngSource (..))
import System.Directory (doesFileExist)

runBatchDispatch :: Driver.RunInputs -> IO (Either String Driver.BatchResult)
runBatchDispatch inputs =
    case Driver.inputBackend inputs of
        CppLegacy ->
            runForeignWhenAvailable
                cppLegacyLibraryPath
                loadCppLegacyEnvelope
                withCppLegacySearchGame
                inputs
        CppImperative ->
            runForeignWhenAvailable
                cppImperativeLibraryPath
                loadCppImperativeEnvelope
                withCppImperativeSearchGame
                inputs
        CppFunctional ->
            runForeignWhenAvailable
                cppFunctionalLibraryPath
                loadCppFunctionalEnvelope
                withCppFunctionalSearchGame
                inputs
        Rust ->
            runForeignWhenAvailable
                rustLibraryPath
                loadRustEnvelope
                withRustSearchGame
                inputs
        Haskell -> runHaskellWhenCppRngAvailable inputs

runBatchNoWriteDispatch :: Driver.RunInputs -> IO (Either String ())
runBatchNoWriteDispatch inputs =
    case Driver.inputBackend inputs of
        CppLegacy -> runForeignNoWriteWhenAvailable cppLegacyLibraryPath withCppLegacySearchGame inputs
        CppImperative -> runForeignNoWriteWhenAvailable cppImperativeLibraryPath withCppImperativeSearchGame inputs
        CppFunctional -> runForeignNoWriteWhenAvailable cppFunctionalLibraryPath withCppFunctionalSearchGame inputs
        Rust -> runForeignNoWriteWhenAvailable rustLibraryPath withRustSearchGame inputs
        Haskell -> Driver.runBatchNoWrite inputs

canUseCappedForeignSearch :: Driver.RunInputs -> Bool
canUseCappedForeignSearch inputs =
    Driver.inputMaxPlies inputs >= 60

runForeignWhenAvailable
    :: FilePath
    -> IO (Either AppError EngineEnvelope)
    -> ForeignSearchOpener
    -> Driver.RunInputs
    -> IO (Either String Driver.BatchResult)
runForeignWhenAvailable libraryPath loadEnvelope opener inputs = do
    present <- doesFileExist libraryPath
    if present && canUseCappedForeignSearch inputs
        then
            runWithLiveEnvelope
                loadEnvelope
                (runWithRunner (runForeignSearchGame opener) inputs)
                inputs
        else Driver.runBatch inputs

runForeignNoWriteWhenAvailable
    :: FilePath
    -> ForeignSearchOpener
    -> Driver.RunInputs
    -> IO (Either String ())
runForeignNoWriteWhenAvailable libraryPath opener inputs = do
    present <- doesFileExist libraryPath
    if present && canUseCappedForeignSearch inputs
        then
            Driver.runBatchNoWriteWithGame
                (runWithRunner (runForeignSearchGame opener) inputs)
                inputs
        else Driver.runBatchNoWrite inputs

runHaskellWhenCppRngAvailable :: Driver.RunInputs -> IO (Either String Driver.BatchResult)
runHaskellWhenCppRngAvailable inputs
    | Driver.inputRng inputs /= CppRng = Driver.runBatch inputs
    | otherwise = do
        present <- cppRngAvailable
        if present
            then Driver.runBatchWithGame (runHaskellCppRngGame inputs) inputs
            else Driver.runBatch inputs

runHaskellCppRngGame :: Driver.RunInputs -> Word32 -> IO (Either String GameTranscript)
runHaskellCppRngGame inputs gid = do
    seeds <-
        cppMoveSeedsIfAvailable
            (Driver.inputSeed inputs)
            (fromIntegral gid)
            (fromIntegral (Driver.inputMaxPlies inputs))
    pure $
        Right $
            case seeds of
                Nothing -> Driver.runGame inputs gid
                Just moveSeeds ->
                    Driver.runGameWithMoveSeed
                        inputs
                        gid
                        (seedAt inputs gid moveSeeds)

seedAt :: Driver.RunInputs -> Word32 -> [Word64] -> Int -> Word64
seedAt inputs gid seeds moveNo =
    case drop moveNo seeds of
        seed : _ -> seed
        [] ->
            let gameSeed = Driver.inputSeed inputs + fromIntegral gid
             in gameSeed + fromIntegral moveNo

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
