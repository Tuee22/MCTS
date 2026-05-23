-- | Haskell-side bindings for backend (iv) Rust.
--
-- The Dockerfile builds the cdylib through `mcts build rust` (PGO + BOLT +
-- `mimalloc`) and leaves it at `rust/target/release/libmcts_rust.{dylib,so}`. The C ABI
-- mirrors the C++ backends' shape; the Rust source declares
-- `#[repr(C)]` for every type crossing the boundary so layouts match.
-- Per the FFI doctrine this module routes through `MCTS.FFI.Common`.
module MCTS.FFI.Rust
    ( RustGame
    , withRustBoard
    , withRustGame
    , withRustSearchGame
    , withRustRecomputeGame
    , loadRustEnvelope
    , rustLibraryPath
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
import MCTS.Types (Backend (Rust))
import qualified System.Info as Info

newtype RustBoard = RustBoard (Ptr ())

type RustGame = DynamicGame

withRustBoard :: (RustBoard -> IO a) -> IO (Either AppError a)
withRustBoard body =
    withDynamicBoard Rust rustLibraryPath "mcts_rust" $
        body . RustBoard

withRustGame :: (RustGame -> IO a) -> IO (Either AppError a)
withRustGame =
    withDynamicGame Rust rustLibraryPath "mcts_rust"

-- | Sprint 6.4: full visit-vector search opener for backend (iv).
-- Routes through `mcts_rust_search_move` exposed by the cdylib.
withRustSearchGame
    :: (DynamicSearchGame -> IO a) -> IO (Either AppError a)
withRustSearchGame =
    withDynamicSearchGame Rust rustLibraryPath "mcts_rust"

-- | Sprint 6.5: recompute opener exposing real parent-perspective
-- equity from the search tree's chosen child via
-- `mcts_rust_recompute_move`.
withRustRecomputeGame
    :: (DynamicRecomputeGame -> IO a) -> IO (Either AppError a)
withRustRecomputeGame =
    withDynamicRecomputeGame Rust rustLibraryPath "mcts_rust"

loadRustEnvelope :: IO (Either AppError EngineEnvelope)
loadRustEnvelope =
    loadDynamicEnvelope Rust rustLibraryPath "mcts_rust"

rustLibraryPath :: FilePath
rustLibraryPath =
    case Info.os of
        "darwin" -> "rust/target/release/libmcts_rust.dylib"
        _ -> "rust/target/release/libmcts_rust.so"
