-- | Haskell-side bindings for backend (iii) C++ functional-style.
--
-- The cdylib is built by `mcts build cpp-functional` and lives at
-- `cpp-functional/build/libmcts_cpp_functional.so`. C ABI in
-- `cpp-functional/c-abi/mcts_cpp_functional.h`. Per the FFI doctrine,
-- this module routes through `MCTS.FFI.Common`.
module MCTS.FFI.CppFunctional
    ( withCppFunctionalBoard
    ) where

import MCTS.Error (AppError)
import MCTS.FFI.Common (liftFFI)
import MCTS.Types (Backend (CppFunctional))

data CppFunctionalBoard = CppFunctionalBoard ()

withCppFunctionalBoard :: (CppFunctionalBoard -> IO a) -> IO (Either AppError a)
withCppFunctionalBoard body =
    liftFFI CppFunctional "mcts_functional_new_board" $
        body (CppFunctionalBoard ())
