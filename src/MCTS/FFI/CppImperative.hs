-- | Haskell-side bindings for backend (ii) C++ imperative steelman.
--
-- The cdylib is built by `mcts build cpp-imperative` (PGO + BOLT +
-- `mimalloc`) and lives at
-- `cpp-imperative/build/libmcts_cpp_imperative.so`. The C ABI shape
-- mirrors backend (i) so the dispatch helpers from `MCTS.FFI.Common`
-- can drive both backends.
module MCTS.FFI.CppImperative
    ( CppImperativeGame
    , withCppImperativeBoard
    , withCppImperativeGame
    , withCppImperativeSearchGame
    , loadCppImperativeEnvelope
    , cppImperativeLibraryPath
    ) where

import Foreign.Ptr (Ptr)
import MCTS.Error (AppError)
import MCTS.FFI.Common
    ( DynamicGame
    , DynamicSearchGame
    , EngineEnvelope
    , loadDynamicEnvelope
    , withDynamicBoard
    , withDynamicGame
    , withDynamicSearchGame
    )
import MCTS.Types (Backend (CppImperative))

newtype CppImperativeBoard = CppImperativeBoard (Ptr ())

type CppImperativeGame = DynamicGame

cppImperativeLibraryPath :: FilePath
cppImperativeLibraryPath = "cpp-imperative/build/libmcts_cpp_imperative.so"

withCppImperativeBoard :: (CppImperativeBoard -> IO a) -> IO (Either AppError a)
withCppImperativeBoard body =
    withDynamicBoard CppImperative cppImperativeLibraryPath "mcts_imperative" $
        body . CppImperativeBoard

withCppImperativeGame :: (CppImperativeGame -> IO a) -> IO (Either AppError a)
withCppImperativeGame =
    withDynamicGame CppImperative cppImperativeLibraryPath "mcts_imperative"

withCppImperativeSearchGame
    :: (DynamicSearchGame -> IO a) -> IO (Either AppError a)
withCppImperativeSearchGame =
    withDynamicSearchGame CppImperative cppImperativeLibraryPath "mcts_imperative"

loadCppImperativeEnvelope :: IO (Either AppError EngineEnvelope)
loadCppImperativeEnvelope =
    loadDynamicEnvelope CppImperative cppImperativeLibraryPath "mcts_imperative"
