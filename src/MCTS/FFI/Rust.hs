-- | Haskell-side bindings for backend (iv) Rust.
--
-- The cdylib is built by `mcts build rust` (PGO + BOLT + `mimalloc`)
-- and lives at `rust/target/release/libmcts_rust.{dylib,so}`. The C ABI
-- mirrors the C++ backends' shape; the Rust source declares
-- `#[repr(C)]` for every type crossing the boundary so layouts match.
-- Per the FFI doctrine this module routes through `MCTS.FFI.Common`.
module MCTS.FFI.Rust
    ( withRustBoard
    ) where

import MCTS.Error (AppError)
import MCTS.FFI.Common (liftFFI)
import MCTS.Types (Backend (Rust))

data RustBoard = RustBoard ()

withRustBoard :: (RustBoard -> IO a) -> IO (Either AppError a)
withRustBoard body =
    liftFFI Rust "mcts_rust_new_board" $
        body (RustBoard ())
