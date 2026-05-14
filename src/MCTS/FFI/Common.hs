-- | Shared FFI helpers per Phase 4 Sprint 4.2 /
-- [../../documents/engineering/backend_ffi_contract.md → Haskell-Side Import Policy](../../documents/engineering/backend_ffi_contract.md).
--
-- This module owns the `bracket`-based RAII pattern for every foreign
-- backend handle (`withBoard`, `withTree`, `withRng`), the `AppError
-- FFIFailure` lifting of foreign exceptions, and the `EngineEnvelope`
-- record type that mirrors the C ABI `mcts_<backend>_envelope` struct.
-- Per-backend modules (`MCTS.FFI.CppLegacy`, etc.) supply the typed
-- foreign-imported pointers and call this module's helpers.
--
-- Note: until the foreign shared libraries are actually loaded, the
-- bracket helpers compile against opaque type-level placeholders. The
-- typed boundary is what matters; the call-out wiring lands when the
-- foreign engines ship.
module MCTS.FFI.Common
    ( ForeignBoard
    , ForeignTree
    , ForeignRng
    , EngineEnvelope (..)
    , withBoard
    , withTree
    , withRng
    , liftFFI
    ) where

import Control.Exception (bracket, try, SomeException)
import Data.Word (Word8, Word32)
import Foreign.Ptr (Ptr)
import MCTS.Error (AppError (..))
import MCTS.Types (Backend)

-- | Opaque foreign pointers. Each `MCTS.FFI.*` module re-exports these
-- newtype-tagged to its backend.
type ForeignBoard backend = Ptr backend
type ForeignTree backend = Ptr backend
type ForeignRng backend = Ptr backend

-- | The doctrine `mcts_<backend>_envelope` struct as a Haskell record.
-- Per-backend modules marshal C struct values into this record after
-- calling `mcts_<backend>_get_envelope()`. The field set matches the on-
-- wire envelope block in
-- [../../documents/engineering/transcript_format.md → Envelope Block](../../documents/engineering/transcript_format.md).
data EngineEnvelope = EngineEnvelope
    { engineEnvBackend :: !Backend
    , engineEnvRngSource :: !Word8
    , engineEnvHostArch :: !Word8
    , engineEnvSharedRngBuildId :: !String
    , engineEnvCohortConfigHash :: !String
    , engineEnvBuildId :: !String
    , engineEnvGitCommit :: !String
    , engineEnvCompilerId :: !Word8
    , engineEnvCompilerVersion :: !String
    , engineEnvFpFlags :: !Word32
    , engineEnvLibmId :: !String
    , engineEnvCpuFeatures :: !Word32
    , engineEnvFpEnv :: !Word8
    }
    deriving (Eq, Show)

-- | `bracket`-style RAII for foreign board handles. The acquirer
-- allocates via the per-backend `mcts_<backend>_new_board`; the
-- releaser frees via `mcts_<backend>_free_board`. The body is run only
-- if acquisition succeeded.
withBoard
    :: Backend
    -> IO (Ptr backend)
    -> (Ptr backend -> IO ())
    -> (Ptr backend -> IO a)
    -> IO (Either AppError a)
withBoard backend acquire release body =
    liftFFI backend "withBoard" $
        bracket acquire release body

-- | `bracket`-style RAII for foreign tree arenas.
withTree
    :: Backend
    -> IO (Ptr backend)
    -> (Ptr backend -> IO ())
    -> (Ptr backend -> IO a)
    -> IO (Either AppError a)
withTree backend acquire release body =
    liftFFI backend "withTree" $
        bracket acquire release body

-- | `bracket`-style RAII for foreign RNG handles per the
-- `cpp_rng_*` C ABI in
-- [../../README.md → Cross-backend verification → RNG FFI contract](../../README.md).
withRng
    :: Backend
    -> IO (Ptr backend)
    -> (Ptr backend -> IO ())
    -> (Ptr backend -> IO a)
    -> IO (Either AppError a)
withRng backend acquire release body =
    liftFFI backend "withRng" $
        bracket acquire release body

-- | Lift any IO action into `Either AppError a`. Foreign exceptions
-- surface as `FFIFailure backend symbol message`.
liftFFI :: Backend -> String -> IO a -> IO (Either AppError a)
liftFFI backend symbol action = do
    result <- try action
    pure $ case result of
        Right value -> Right value
        Left exn -> Left (FFIFailure backend symbol (show (exn :: SomeException)))
