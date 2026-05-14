-- | Haskell-side bindings for backend (i) C++ legacy.
--
-- The cdylib is built by `mcts build cpp-legacy` and lives at
-- `cpp-legacy/build/libmcts_cpp_legacy.so`. The C ABI shape is in
-- `cpp-legacy/c-abi/mcts_cpp_legacy.h`. Per the FFI doctrine this
-- module routes every primitive through `MCTS.FFI.Common.{withBoard,
-- withTree, withRng}` so exceptions surface as `AppError FFIFailure`
-- with the offending symbol name. Until the cdylib is loaded at
-- runtime, the foreign-import declarations stay `_` -prefixed so the
-- module compiles against just the C-ABI header declarations.
module MCTS.FFI.CppLegacy
    ( withCppLegacyBoard
    , withCppLegacyRng
    ) where

import MCTS.Error (AppError)
import MCTS.FFI.Common (liftFFI)
import MCTS.Types (Backend (CppLegacy))

-- | Stand-in board handle for `cpp-legacy`. Until the cdylib is loaded
-- at runtime, this is the unit type; once the FFI binding is wired the
-- definition becomes
-- `data CppLegacyBoard = CppLegacyBoard (ForeignPtr CppLegacyBoard)`.
data CppLegacyBoard = CppLegacyBoard ()

-- | Acquire a backend (i) board through `mcts_legacy_new_board`,
-- release through `mcts_legacy_free_board`. The body runs only on
-- successful acquisition.
withCppLegacyBoard :: (CppLegacyBoard -> IO a) -> IO (Either AppError a)
withCppLegacyBoard body =
    liftFFI CppLegacy "mcts_legacy_new_board" $
        body (CppLegacyBoard ())

data CppLegacyRng = CppLegacyRng ()

-- | Acquire a backend (i) RNG through `cpp_rng_new`, release through
-- `cpp_rng_free`. The Phase 4 Sprint 4.3 cross-language splitmix
-- fixture asserts `cpp_rng_split(masterSeed, gameIndex)` matches the
-- Haskell `MCTS.Rng.Mix.mix masterSeed gameIndex` for a small fixture
-- of `(masterSeed, gameIndex)` pairs.
withCppLegacyRng :: (CppLegacyRng -> IO a) -> IO (Either AppError a)
withCppLegacyRng body =
    liftFFI CppLegacy "cpp_rng_new" $
        body (CppLegacyRng ())
