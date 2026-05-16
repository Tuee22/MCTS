-- | Haskell-side bindings for backend (iii) C++ functional-style.
--
-- The cdylib is built by `mcts build cpp-functional` and lives at
-- `cpp-functional/build/libmcts_cpp_functional.so`. C ABI in
-- `cpp-functional/c-abi/mcts_cpp_functional.h`. Per the FFI doctrine,
-- this module routes through `MCTS.FFI.Common`.
module MCTS.FFI.CppFunctional
    ( CppFunctionalGame
    , withCppFunctionalBoard
    , withCppFunctionalGame
    , withCppFunctionalSearchGame
    , loadCppFunctionalEnvelope
    , cppFunctionalLibraryPath
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
import MCTS.Types (Backend (CppFunctional))

newtype CppFunctionalBoard = CppFunctionalBoard (Ptr ())

type CppFunctionalGame = DynamicGame

cppFunctionalLibraryPath :: FilePath
cppFunctionalLibraryPath = "cpp-functional/build/libmcts_cpp_functional.so"

withCppFunctionalBoard :: (CppFunctionalBoard -> IO a) -> IO (Either AppError a)
withCppFunctionalBoard body =
    withDynamicBoard CppFunctional cppFunctionalLibraryPath "mcts_functional" $
        body . CppFunctionalBoard

withCppFunctionalGame :: (CppFunctionalGame -> IO a) -> IO (Either AppError a)
withCppFunctionalGame =
    withDynamicGame CppFunctional cppFunctionalLibraryPath "mcts_functional"

withCppFunctionalSearchGame
    :: (DynamicSearchGame -> IO a) -> IO (Either AppError a)
withCppFunctionalSearchGame =
    withDynamicSearchGame CppFunctional cppFunctionalLibraryPath "mcts_functional"

loadCppFunctionalEnvelope :: IO (Either AppError EngineEnvelope)
loadCppFunctionalEnvelope =
    loadDynamicEnvelope CppFunctional cppFunctionalLibraryPath "mcts_functional"
