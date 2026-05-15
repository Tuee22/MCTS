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

import Foreign.Ptr (Ptr)
import MCTS.Error (AppError)
import MCTS.FFI.Common (withDynamicBoard)
import MCTS.Types (Backend (Rust))
import qualified System.Info as Info

newtype RustBoard = RustBoard (Ptr ())

withRustBoard :: (RustBoard -> IO a) -> IO (Either AppError a)
withRustBoard body =
    withDynamicBoard Rust rustLibraryPath "mcts_rust" $
        body . RustBoard

rustLibraryPath :: FilePath
rustLibraryPath =
    case Info.os of
        "darwin" -> "rust/target/release/libmcts_rust.dylib"
        _ -> "rust/target/release/libmcts_rust.so"
