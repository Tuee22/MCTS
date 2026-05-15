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
    ( CppLegacyGame
    , withCppLegacyBoard
    , withCppLegacyGame
    , cppLegacyIsTerminal
    , cppLegacySelectMove
    , loadCppLegacyEnvelope
    , withCppLegacyRng
    ) where

import Control.Exception (bracket)
import Data.Word (Word32, Word64, Word8)
import Foreign.C.Types (CInt (..))
import Foreign.Ptr (FunPtr, Ptr)
import MCTS.Error (AppError)
import MCTS.FFI.Common (EngineEnvelope, liftFFI, loadDynamicEnvelope, withDynamicBoard)
import MCTS.Types (Backend (CppLegacy))
import qualified System.Posix.DynamicLinker as DL

-- | Stand-in board handle for `cpp-legacy`. Until the cdylib is loaded
-- at runtime, this is the unit type; once the FFI binding is wired the
-- definition becomes
-- `data CppLegacyBoard = CppLegacyBoard (ForeignPtr CppLegacyBoard)`.
newtype CppLegacyBoard = CppLegacyBoard (Ptr ())

data CppLegacyGame = CppLegacyGame
    { legacyBoardPtr :: !(Ptr ())
    , legacyIsTerminal :: !(Ptr () -> IO CInt)
    , legacySelectMove :: !(Ptr () -> Word64 -> Word32 -> IO Word8)
    }

-- | Acquire a backend (i) board through `mcts_legacy_new_board`,
-- release through `mcts_legacy_free_board`. The body runs only on
-- successful acquisition.
withCppLegacyBoard :: (CppLegacyBoard -> IO a) -> IO (Either AppError a)
withCppLegacyBoard body =
    withDynamicBoard CppLegacy "cpp-legacy/build/libmcts_cpp_legacy.so" "mcts_legacy" $
        body . CppLegacyBoard

foreign import ccall "dynamic" mkLegacyBoardNew :: FunPtr (IO (Ptr ())) -> IO (Ptr ())
foreign import ccall "dynamic" mkLegacyBoardFree :: FunPtr (Ptr () -> IO ()) -> Ptr () -> IO ()
foreign import ccall "dynamic" mkLegacyIsTerminal :: FunPtr (Ptr () -> IO CInt) -> Ptr () -> IO CInt
foreign import ccall "dynamic"
    mkLegacySelectMove
        :: FunPtr (Ptr () -> Word64 -> Word32 -> IO Word8) -> Ptr () -> Word64 -> Word32 -> IO Word8

withCppLegacyGame :: (CppLegacyGame -> IO a) -> IO (Either AppError a)
withCppLegacyGame body =
    liftFFI CppLegacy "mcts_legacy_game" $
        bracketLibrary $ \library -> do
            newFun <- DL.dlsym library "mcts_legacy_new_board"
            freeFun <- DL.dlsym library "mcts_legacy_free_board"
            isTerminalFun <- DL.dlsym library "mcts_legacy_is_terminal"
            selectMoveFun <- DL.dlsym library "mcts_legacy_select_uct_move"
            let isTerminal = mkLegacyIsTerminal isTerminalFun
                selectMove = mkLegacySelectMove selectMoveFun
            bracketBoard (mkLegacyBoardNew newFun) (mkLegacyBoardFree freeFun) $ \board ->
                body
                    CppLegacyGame
                        { legacyBoardPtr = board
                        , legacyIsTerminal = isTerminal
                        , legacySelectMove = selectMove
                        }
  where
    bracketLibrary = bracket (DL.dlopen legacyLibraryPath [DL.RTLD_NOW]) DL.dlclose
    bracketBoard = bracket

cppLegacyIsTerminal :: CppLegacyGame -> IO Bool
cppLegacyIsTerminal game =
    (/= 0) <$> legacyIsTerminal game (legacyBoardPtr game)

cppLegacySelectMove :: CppLegacyGame -> Word64 -> Word32 -> IO Word8
cppLegacySelectMove game seed sims =
    legacySelectMove game (legacyBoardPtr game) seed sims

loadCppLegacyEnvelope :: IO (Either AppError EngineEnvelope)
loadCppLegacyEnvelope =
    loadDynamicEnvelope CppLegacy legacyLibraryPath "mcts_legacy"

legacyLibraryPath :: FilePath
legacyLibraryPath = "cpp-legacy/build/libmcts_cpp_legacy.so"

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
