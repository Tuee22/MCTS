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
    , loadCppFunctionalEnvelope
    ) where

import Foreign.Ptr (Ptr)
import MCTS.Error (AppError)
import MCTS.FFI.Common
    ( DynamicGame
    , EngineEnvelope
    , loadDynamicEnvelope
    , withDynamicBoard
    , withDynamicGame
    )
import MCTS.Types (Backend (CppFunctional))

newtype CppFunctionalBoard = CppFunctionalBoard (Ptr ())

type CppFunctionalGame = DynamicGame

withCppFunctionalBoard :: (CppFunctionalBoard -> IO a) -> IO (Either AppError a)
withCppFunctionalBoard body =
    withDynamicBoard CppFunctional "cpp-functional/build/libmcts_cpp_functional.so" "mcts_functional" $
        body . CppFunctionalBoard

withCppFunctionalGame :: (CppFunctionalGame -> IO a) -> IO (Either AppError a)
withCppFunctionalGame =
    withDynamicGame CppFunctional "cpp-functional/build/libmcts_cpp_functional.so" "mcts_functional"

loadCppFunctionalEnvelope :: IO (Either AppError EngineEnvelope)
loadCppFunctionalEnvelope =
    loadDynamicEnvelope CppFunctional "cpp-functional/build/libmcts_cpp_functional.so" "mcts_functional"
