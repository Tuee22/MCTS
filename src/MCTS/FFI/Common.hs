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
    , DynamicGame (..)
    , withBoard
    , withTree
    , withRng
    , withDynamicBoard
    , withDynamicGame
    , withDynamicSearchGame
    , DynamicSearchGame (..)
    , loadDynamicEnvelope
    , liftFFI
    ) where

import Control.Exception (SomeException, bracket, try)
import Data.Char (chr)
import Data.Int (Int32)
import Data.Word (Word16, Word32, Word64, Word8)
import Foreign.C.Types (CInt (..))
import Foreign.Marshal.Alloc (alloca)
import Foreign.Marshal.Array (allocaArray, peekArray)
import Foreign.Ptr (FunPtr, Ptr, castPtr, plusPtr)
import Foreign.Storable (peek, peekByteOff)
import MCTS.Error (AppError (..))
import MCTS.Types (Backend)
import Numeric (showHex)
import qualified System.Posix.DynamicLinker as DL

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
    { engineEnvVersion :: !Word16
    , engineEnvBackend :: !Backend
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

data DynamicGame = DynamicGame
    { dynamicGameBoard :: !(Ptr ())
    , dynamicGameIsTerminal :: !(IO Bool)
    , dynamicGameSelectMove :: !(Word64 -> Word32 -> IO Word8)
    }

-- | A dynamically-loaded backend exposing the full search ABI from
-- `documents/engineering/backend_ffi_contract.md → C ABI Shape`:
-- `<prefix>_search_move(board, seed, sims, out_action_ids,
-- out_visits, out_chosen)` plus the standard new/free/is_terminal
-- triplet. Returns sorted `(action_id, visits)` records and the
-- chosen action id. Backends share this ABI; per-backend modules
-- re-export `withDynamicSearchGame` parameterised by their library
-- path and symbol prefix.
data DynamicSearchGame = DynamicSearchGame
    { searchGameBoard :: !(Ptr ())
    , searchGameIsTerminal :: !(IO Bool)
    , searchGameSearchMove
        :: !(Word64 -> Word32 -> IO (Either AppError (Word8, [(Word8, Word32)])))
    }

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

foreign import ccall "dynamic" mkBoardNew :: FunPtr (IO (Ptr ())) -> IO (Ptr ())
foreign import ccall "dynamic" mkBoardFree :: FunPtr (Ptr () -> IO ()) -> Ptr () -> IO ()
foreign import ccall "dynamic"
    mkDynamicIsTerminal :: FunPtr (Ptr () -> IO CInt) -> Ptr () -> IO CInt
foreign import ccall "dynamic"
    mkDynamicSelectMove
        :: FunPtr (Ptr () -> Word64 -> Word32 -> IO Word8) -> Ptr () -> Word64 -> Word32 -> IO Word8
foreign import ccall "dynamic"
    mkDynamicSearchMove
        :: FunPtr
            ( Ptr ()
              -> Word64
              -> Word32
              -> Ptr Word8
              -> Ptr Word32
              -> Ptr Word8
              -> IO Int32
            )
        -> Ptr ()
        -> Word64
        -> Word32
        -> Ptr Word8
        -> Ptr Word32
        -> Ptr Word8
        -> IO Int32
foreign import ccall "dynamic" mkDynamicEnvelope :: FunPtr (IO (Ptr ())) -> IO (Ptr ())

-- | Dynamically load a backend shared library, call its
-- `mcts_<backend>_new_board` / `mcts_<backend>_free_board` pair, and run
-- the body under `bracket`. This is still real Haskell FFI: the
-- resolved C symbols are converted to typed function pointers via
-- `foreign import ccall "dynamic"`, but the library is discovered at
-- runtime so Cabal does not need platform-specific `extra-libraries`
-- entries for every developer shell.
withDynamicBoard
    :: Backend
    -> FilePath
    -> String
    -> (Ptr () -> IO a)
    -> IO (Either AppError a)
withDynamicBoard backend libraryPath symbolPrefix body =
    liftFFI backend (symbolPrefix <> "_new_board") $
        bracket
            (DL.dlopen libraryPath [DL.RTLD_NOW])
            DL.dlclose
            ( \library -> do
                newFun <- DL.dlsym library (symbolPrefix <> "_new_board")
                freeFun <- DL.dlsym library (symbolPrefix <> "_free_board")
                bracket (mkBoardNew newFun) (mkBoardFree freeFun) body
            )

withDynamicGame
    :: Backend
    -> FilePath
    -> String
    -> (DynamicGame -> IO a)
    -> IO (Either AppError a)
withDynamicGame backend libraryPath symbolPrefix body =
    liftFFI backend (symbolPrefix <> "_select_uct_move") $
        bracket
            (DL.dlopen libraryPath [DL.RTLD_NOW])
            DL.dlclose
            ( \library -> do
                newFun <- DL.dlsym library (symbolPrefix <> "_new_board")
                freeFun <- DL.dlsym library (symbolPrefix <> "_free_board")
                isTerminalFun <- DL.dlsym library (symbolPrefix <> "_is_terminal")
                selectMoveFun <- DL.dlsym library (symbolPrefix <> "_select_uct_move")
                bracket (mkBoardNew newFun) (mkBoardFree freeFun) $ \board ->
                    body
                        DynamicGame
                            { dynamicGameBoard = board
                            , dynamicGameIsTerminal = (/= 0) <$> mkDynamicIsTerminal isTerminalFun board
                            , dynamicGameSelectMove = mkDynamicSelectMove selectMoveFun board
                            }
            )

withDynamicSearchGame
    :: Backend
    -> FilePath
    -> String
    -> (DynamicSearchGame -> IO a)
    -> IO (Either AppError a)
withDynamicSearchGame backend libraryPath symbolPrefix body =
    liftFFI backend (symbolPrefix <> "_search_move") $
        bracket
            (DL.dlopen libraryPath [DL.RTLD_NOW])
            DL.dlclose
            ( \library -> do
                newFun <- DL.dlsym library (symbolPrefix <> "_new_board")
                freeFun <- DL.dlsym library (symbolPrefix <> "_free_board")
                isTerminalFun <- DL.dlsym library (symbolPrefix <> "_is_terminal")
                searchMoveFun <- DL.dlsym library (symbolPrefix <> "_search_move")
                let isTerminal board' = (/= 0) <$> mkDynamicIsTerminal isTerminalFun board'
                    searchMove' = mkDynamicSearchMove searchMoveFun
                bracket (mkBoardNew newFun) (mkBoardFree freeFun) $ \board ->
                    body
                        DynamicSearchGame
                            { searchGameBoard = board
                            , searchGameIsTerminal = isTerminal board
                            , searchGameSearchMove = \seed sims ->
                                allocaArray actionCount $ \actionIdsBuf ->
                                    allocaArray actionCount $ \visitsBuf ->
                                        alloca $ \chosenBuf -> do
                                            ret <-
                                                searchMove'
                                                    board
                                                    seed
                                                    sims
                                                    actionIdsBuf
                                                    visitsBuf
                                                    chosenBuf
                                            if ret < 0
                                                then
                                                    pure $
                                                        Left $
                                                            FFIFailure
                                                                backend
                                                                (symbolPrefix <> "_search_move")
                                                                ("simulate returned " <> show ret)
                                                else do
                                                    let count = fromIntegral ret
                                                    actionIds <- peekArray count actionIdsBuf
                                                    visits <- peekArray count visitsBuf
                                                    chosen <- peek chosenBuf
                                                    pure $ Right (chosen, zip actionIds visits)
                            }
            )
  where
    actionCount = 209

loadDynamicEnvelope
    :: Backend
    -> FilePath
    -> String
    -> IO (Either AppError EngineEnvelope)
loadDynamicEnvelope backend libraryPath symbolPrefix =
    liftFFI backend (symbolPrefix <> "_get_envelope") $
        bracket
            (DL.dlopen libraryPath [DL.RTLD_NOW])
            DL.dlclose
            ( \library -> do
                envelopeFun <- DL.dlsym library (symbolPrefix <> "_get_envelope")
                envelopePtr <- mkDynamicEnvelope envelopeFun
                peekEngineEnvelope backend envelopePtr
            )

peekEngineEnvelope :: Backend -> Ptr () -> IO EngineEnvelope
peekEngineEnvelope backend ptr = do
    version <- peekByteOff ptr 0
    rngSource <- peekByteOff ptr 2
    hostArch <- peekByteOff ptr 3
    sharedRng <- digestAt 4
    cohortHash <- digestAt 36
    engineBuild <- digestAt 68
    gitCommit <- asciiAt 100 40 40
    compilerId <- peekByteOff ptr 140
    compilerVersionLen <- peekByteOff ptr 141 :: IO Word8
    compilerVersion <- asciiAt 142 63 (fromIntegral compilerVersionLen)
    fpFlags <- peekByteOff ptr 208
    libmIdLen <- peekByteOff ptr 212 :: IO Word8
    libmId <- asciiAt 213 63 (fromIntegral libmIdLen)
    cpuFeatures <- peekByteOff ptr 276
    fpEnv <- peekByteOff ptr 280
    pure
        EngineEnvelope
            { engineEnvVersion = version
            , engineEnvBackend = backend
            , engineEnvRngSource = rngSource
            , engineEnvHostArch = hostArch
            , engineEnvSharedRngBuildId = sharedRng
            , engineEnvCohortConfigHash = cohortHash
            , engineEnvBuildId = engineBuild
            , engineEnvGitCommit = gitCommit
            , engineEnvCompilerId = compilerId
            , engineEnvCompilerVersion = compilerVersion
            , engineEnvFpFlags = fpFlags
            , engineEnvLibmId = libmId
            , engineEnvCpuFeatures = cpuFeatures
            , engineEnvFpEnv = fpEnv
            }
  where
    digestAt :: Int -> IO String
    digestAt offset = bytesToHex <$> bytesAt offset 32

    asciiAt :: Int -> Int -> Int -> IO String
    asciiAt offset maxLen rawLen = do
        bytes <- bytesAt offset maxLen
        pure (takeWhile (/= '\NUL') (map (chr . fromIntegral) (take rawLen bytes)))

    bytesAt :: Int -> Int -> IO [Word8]
    bytesAt offset len = peekArray len (castPtr (ptr `plusPtr` offset) :: Ptr Word8)

bytesToHex :: [Word8] -> String
bytesToHex =
    concatMap byteToHex
  where
    byteToHex byte =
        let rendered = showHex byte ""
         in if byte < 16 then '0' : rendered else rendered

-- | Lift any IO action into `Either AppError a`. Foreign exceptions
-- surface as `FFIFailure backend symbol message`.
liftFFI :: Backend -> String -> IO a -> IO (Either AppError a)
liftFFI backend symbol action = do
    result <- try action
    pure $ case result of
        Right value -> Right value
        Left exn -> Left (FFIFailure backend symbol (show (exn :: SomeException)))
