-- | Per-backend driver dispatch for `mcts bench` and `mcts verify`.
--
-- The pure in-process Haskell `runBatch` covers the logical baseline
-- for every backend. Real FFI-backed drivers (cpp-legacy and
-- cpp-imperative) plug in here. When a backend's shared library is
-- present, `--backend X` routes through the per-backend FFI driver so
-- the transcript carries the engine's real per-move
-- `(action_id, visits)` records. When the library is absent the
-- logical in-process driver is used so `cabal test all` stays
-- self-contained.
module MCTS.Driver.Dispatch
    ( runBatchDispatch
    , cppLegacyLibraryPath
    ) where

import qualified Data.Text as Text
import Data.Word (Word32)
import qualified MCTS.Driver as Driver
import MCTS.Driver.CppFunctional (runGameCppFunctional)
import MCTS.Driver.CppImperative (runGameCppImperative)
import MCTS.Driver.CppLegacy (runGameCppLegacy)
import MCTS.Error (AppError, renderError)
import MCTS.FFI.CppFunctional (cppFunctionalLibraryPath)
import MCTS.FFI.CppImperative (cppImperativeLibraryPath)
import MCTS.Types (Backend (..), GameTranscript)
import System.Directory (doesFileExist)

cppLegacyLibraryPath :: FilePath
cppLegacyLibraryPath = "cpp-legacy/build/libmcts_cpp_legacy.so"

runBatchDispatch :: Driver.RunInputs -> IO (Either String Driver.BatchResult)
runBatchDispatch inputs =
    case Driver.inputBackend inputs of
        CppLegacy -> do
            present <- doesFileExist cppLegacyLibraryPath
            if present
                then Driver.runBatchWithGame (runWithRunner runGameCppLegacy inputs) inputs
                else Driver.runBatch inputs
        CppImperative -> do
            present <- doesFileExist cppImperativeLibraryPath
            if present
                then Driver.runBatchWithGame (runWithRunner runGameCppImperative inputs) inputs
                else Driver.runBatch inputs
        CppFunctional -> do
            present <- doesFileExist cppFunctionalLibraryPath
            if present
                then Driver.runBatchWithGame (runWithRunner runGameCppFunctional inputs) inputs
                else Driver.runBatch inputs
        _ -> Driver.runBatch inputs

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
