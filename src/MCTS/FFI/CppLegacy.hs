-- | Haskell-side bindings for backend (i) C++ legacy.
--
-- The shared object is built by `mcts build cpp-legacy` and loaded
-- dynamically so Cabal does not need platform-specific C++ linker
-- settings. The exported C ABI uses the historical `mcts_legacy`
-- symbol prefix.
module MCTS.FFI.CppLegacy
    ( CppLegacyGame
    , withCppLegacyBoard
    , withCppLegacyGame
    , withCppLegacySearchGame
    , withCppLegacyRecomputeGame
    , loadCppLegacyEnvelope
    , cppLegacyLibraryPath
    ) where

import Foreign.Ptr (Ptr)
import MCTS.Error (AppError)
import MCTS.FFI.Common
    ( DynamicGame
    , DynamicRecomputeGame
    , DynamicSearchGame
    , EngineEnvelope
    , loadDynamicEnvelope
    , withDynamicBoard
    , withDynamicGame
    , withDynamicRecomputeGame
    , withDynamicSearchGame
    )
import MCTS.Types (Backend (CppLegacy))
import qualified System.Info as Info

newtype CppLegacyBoard = CppLegacyBoard (Ptr ())

type CppLegacyGame = DynamicGame

withCppLegacyBoard :: (CppLegacyBoard -> IO a) -> IO (Either AppError a)
withCppLegacyBoard body =
    withDynamicBoard CppLegacy cppLegacyLibraryPath "mcts_legacy" $
        body . CppLegacyBoard

withCppLegacyGame :: (CppLegacyGame -> IO a) -> IO (Either AppError a)
withCppLegacyGame =
    withDynamicGame CppLegacy cppLegacyLibraryPath "mcts_legacy"

withCppLegacySearchGame
    :: (DynamicSearchGame -> IO a) -> IO (Either AppError a)
withCppLegacySearchGame =
    withDynamicSearchGame CppLegacy cppLegacyLibraryPath "mcts_legacy"

withCppLegacyRecomputeGame
    :: (DynamicRecomputeGame -> IO a) -> IO (Either AppError a)
withCppLegacyRecomputeGame =
    withDynamicRecomputeGame CppLegacy cppLegacyLibraryPath "mcts_legacy"

loadCppLegacyEnvelope :: IO (Either AppError EngineEnvelope)
loadCppLegacyEnvelope =
    loadDynamicEnvelope CppLegacy cppLegacyLibraryPath "mcts_legacy"

cppLegacyLibraryPath :: FilePath
cppLegacyLibraryPath =
    case Info.os of
        "darwin" -> "cpp-legacy/build/libmcts_cpp_legacy.dylib"
        _ -> "cpp-legacy/build/libmcts_cpp_legacy.so"
