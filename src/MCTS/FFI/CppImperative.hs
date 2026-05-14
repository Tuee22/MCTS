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

import MCTS.Error (AppError)
import MCTS.FFI.Common (liftFFI)
import MCTS.Types (Backend (CppImperative))

data CppImperativeBoard = CppImperativeBoard ()

withCppImperativeBoard :: (CppImperativeBoard -> IO a) -> IO (Either AppError a)
withCppImperativeBoard body =
    liftFFI CppImperative "mcts_imperative_new_board" $
        body (CppImperativeBoard ())
