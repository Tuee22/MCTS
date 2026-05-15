-- | Haskell-side bindings for backend (ii) C++ imperative steelman.
--
-- The cdylib is built by `mcts build cpp-imperative` (PGO + BOLT +
-- `mimalloc`) and lives at
-- `cpp-imperative/build/libmcts_cpp_imperative.so`. The C ABI shape is
-- in `cpp-imperative/c-abi/mcts_cpp_imperative.h`. Per the FFI doctrine
-- this module routes every primitive through `MCTS.FFI.Common` so
-- exceptions surface as `AppError FFIFailure`.
module MCTS.FFI.CppImperative
    ( withCppImperativeBoard
    ) where

import Foreign.Ptr (Ptr)
import MCTS.Error (AppError)
import MCTS.FFI.Common (withDynamicBoard)
import MCTS.Types (Backend (CppImperative))

newtype CppImperativeBoard = CppImperativeBoard (Ptr ())

withCppImperativeBoard :: (CppImperativeBoard -> IO a) -> IO (Either AppError a)
withCppImperativeBoard body =
    withDynamicBoard CppImperative "cpp-imperative/build/libmcts_cpp_imperative.so" "mcts_imperative" $
        body . CppImperativeBoard
