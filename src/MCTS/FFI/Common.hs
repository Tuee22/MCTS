-- | Shared FFI helpers per Phase 4 Sprint 4.2 /
-- [../../documents/engineering/backend_ffi_contract.md → Haskell-Side Import Policy](../../documents/engineering/backend_ffi_contract.md).
--
-- This module owns the `bracket`-based RAII pattern for foreign board
-- handles, the `AppError` `FFIFailure` lifting of foreign exceptions, and the `EngineEnvelope`
-- record type that mirrors the C ABI `mcts_<backend>_envelope` struct.
-- Per-backend modules such as `MCTS.FFI.Rust` supply the typed
-- foreign-imported pointers and call this module's helpers.
--
-- Note: the per-backend modules load the live shared libraries dynamically.
-- These helpers keep the opaque handle types and bracket discipline centralized
-- so C++ and Rust call-out paths share one error and lifetime boundary.
module MCTS.FFI.Common
    ( ForeignBoard
    , EngineEnvelope (..)
    , DynamicGame (..)
    , withBoard
    , withDynamicBoard
    , withDynamicGame
    , withDynamicSearchGame
    , withDynamicBenchmarkGame
    , withDynamicRecomputeGame
    , DynamicSearchGame (..)
    , DynamicBenchmarkGame (..)
    , DynamicRecomputeGame (..)
    , engineEnvelopeToEnvelope
    , loadDynamicEnvelope
    , liftFFI
    , withPinnedDynamicLibrary
    ) where

import Control.Concurrent.MVar (MVar, modifyMVar, newMVar)
import Control.Exception (SomeException, bracket, finally, try)
import Data.Char (chr)
import Data.Int (Int32)
import Data.Word (Word16, Word32, Word64, Word8)
import Foreign.C.Types (CInt (..))
import Foreign.Marshal.Alloc (alloca)
import Foreign.Marshal.Array (allocaArray, peekArray)
import Foreign.Ptr (FunPtr, Ptr, castPtr, plusPtr)
import Foreign.Storable (peek, peekByteOff)
import MCTS.Error (AppError (..))
import MCTS.Types
    ( Backend
    , ByteString32 (..)
    , Envelope (..)
    , RngSource (..)
    )
import Numeric (showHex)
import System.Environment (lookupEnv)
import System.IO.Unsafe (unsafePerformIO)
import qualified System.Posix.DynamicLinker as DL

-- | Opaque foreign pointers. Each `MCTS.FFI.*` module re-exports these
-- newtype-tagged to its backend.
type ForeignBoard backend = Ptr backend

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

engineEnvelopeToEnvelope :: EngineEnvelope -> Envelope
engineEnvelopeToEnvelope engine =
    Envelope
        { envelopeVersion = engineEnvVersion engine
        , envelopeBackend = backend
        , envelopeRngSource = rngSourceName (engineEnvRngSource engine)
        , envelopeHostArch = hostArchName (engineEnvHostArch engine)
        , envelopeSharedRngBuildId = ByteString32 (engineEnvSharedRngBuildId engine)
        , envelopeCohortConfigHash = ByteString32 (engineEnvCohortConfigHash engine)
        , envelopeEngineBuildId = ByteString32 (engineEnvBuildId engine)
        , envelopeEngineGitCommit = engineEnvGitCommit engine
        , envelopeCompilerId = engineEnvCompilerId engine
        , envelopeCompilerVersion = engineEnvCompilerVersion engine
        , envelopeFpFlags = engineEnvFpFlags engine
        , envelopeLibmId = engineEnvLibmId engine
        , envelopeCpuFeatures = engineEnvCpuFeatures engine
        , envelopeFpEnv = engineEnvFpEnv engine
        , envelopeBuildId =
            if all (== '0') (take 64 (engineEnvBuildId engine))
                then "logical"
                else take 16 (engineEnvBuildId engine)
        }
  where
    backend = engineEnvBackend engine

    rngSourceName value =
        case value of
            1 -> CppRng
            _ -> NativeRng

    hostArchName value =
        case value of
            1 -> "arm64"
            _ -> "amd64"

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
    , searchGameApplyAction :: !(Word8 -> IO (Either AppError ()))
    , searchGameSearchMove
        :: !(Word64 -> Word32 -> IO (Either AppError (Word8, [(Word8, Word32)])))
    }

-- | Lower-level benchmark ABI for Sprint 3.8. These hooks measure
-- explicit primitive units from the current board without complete-game
-- transcript generation:
-- `<prefix>_benchmark_terminal_playouts(board, seed, count, max_plies)`
-- and `<prefix>_benchmark_search_iters(board, seed, count, max_plies)`.
-- Both return an opaque checksum so the optimizer cannot discard the
-- work; the Haskell caller counts the requested units, not the checksum.
data DynamicBenchmarkGame = DynamicBenchmarkGame
    { benchmarkGameBoard :: !(Ptr ())
    , benchmarkGameTerminalPlayouts :: !(Word64 -> Word32 -> Word16 -> IO Word64)
    , benchmarkGameSearchIters :: !(Word64 -> Word32 -> Word16 -> IO Word64)
    }

-- | Sprint 6.5: dynamically-loaded backend exposing the
-- `mcts_<backend>_recompute_move(board, seed, sims, out_action_ids,
-- out_visits, out_chosen, out_equity)` ABI on top of the search
-- triplet. Returns sorted `(action_id, visits)` records, the chosen
-- action id, and the parent-perspective `chosen_equity` recovered
-- from the search tree's chosen child. The Haskell driver layered
-- on top walks a transcript move-by-move and emits an `EqStream`
-- usable by `inspect divergence` and the report-card divergence
-- matrix.
data DynamicRecomputeGame = DynamicRecomputeGame
    { recomputeGameBoard :: !(Ptr ())
    , recomputeGameIsTerminal :: !(IO Bool)
    , recomputeGameRecomputeMove
        :: !(Word64 -> Word32 -> IO (Either AppError (Word8, [(Word8, Word32)], Double)))
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
foreign import ccall "dynamic"
    mkDynamicApplyAction :: FunPtr (Ptr () -> Word8 -> IO CInt) -> Ptr () -> Word8 -> IO CInt
foreign import ccall "dynamic"
    mkDynamicRecomputeMove
        :: FunPtr
            ( Ptr ()
              -> Word64
              -> Word32
              -> Ptr Word8
              -> Ptr Word32
              -> Ptr Word8
              -> Ptr Double
              -> IO Int32
            )
        -> Ptr ()
        -> Word64
        -> Word32
        -> Ptr Word8
        -> Ptr Word32
        -> Ptr Word8
        -> Ptr Double
        -> IO Int32
foreign import ccall "dynamic"
    mkDynamicBenchmark
        :: FunPtr (Ptr () -> Word64 -> Word32 -> Word16 -> IO Word64)
        -> Ptr ()
        -> Word64
        -> Word32
        -> Word16
        -> IO Word64
foreign import ccall "dynamic" mkDynamicEnvelope :: FunPtr (IO (Ptr ())) -> IO (Ptr ())
foreign import ccall "dynamic" mkDynamicProfileDump :: FunPtr (IO ()) -> IO ()

{-# NOINLINE pinnedDynamicLibraries #-}
pinnedDynamicLibraries :: MVar [(FilePath, DL.DL)]
pinnedDynamicLibraries = unsafePerformIO (newMVar [])

-- | Open a foreign backend shared object once per process and keep the
-- `DL` handle reachable for the process lifetime. The C++ and Rust
-- backends expose process-static envelope storage and link allocator /
-- runtime state that should not be cycled by repeated dlopen/dlclose
-- pairs during verification.
withPinnedDynamicLibrary :: FilePath -> (DL.DL -> IO a) -> IO a
withPinnedDynamicLibrary libraryPath action = do
    scoped <- (== Just "1") <$> lookupEnv "MCTS_SCOPED_DYNAMIC_LIBRARY"
    if scoped
        then bracket (DL.dlopen libraryPath [DL.RTLD_NOW]) DL.dlclose action
        else do
            library <-
                modifyMVar pinnedDynamicLibraries $ \libraries ->
                    case lookup libraryPath libraries of
                        Just existing -> pure (libraries, existing)
                        Nothing -> do
                            opened <- DL.dlopen libraryPath [DL.RTLD_NOW]
                            pure ((libraryPath, opened) : libraries, opened)
            action library

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
        withPinnedDynamicLibrary libraryPath $ \library -> do
            newFun <- DL.dlsym library (symbolPrefix <> "_new_board")
            freeFun <- DL.dlsym library (symbolPrefix <> "_free_board")
            withDynamicProfileFlush library symbolPrefix $
                bracket (mkBoardNew newFun) (mkBoardFree freeFun) body

withDynamicGame
    :: Backend
    -> FilePath
    -> String
    -> (DynamicGame -> IO a)
    -> IO (Either AppError a)
withDynamicGame backend libraryPath symbolPrefix body =
    liftFFI backend (symbolPrefix <> "_select_uct_move") $
        withPinnedDynamicLibrary libraryPath $ \library -> do
            newFun <- DL.dlsym library (symbolPrefix <> "_new_board")
            freeFun <- DL.dlsym library (symbolPrefix <> "_free_board")
            isTerminalFun <- DL.dlsym library (symbolPrefix <> "_is_terminal")
            selectMoveFun <- DL.dlsym library (symbolPrefix <> "_select_uct_move")
            withDynamicProfileFlush library symbolPrefix $
                bracket (mkBoardNew newFun) (mkBoardFree freeFun) $ \board ->
                    body
                        DynamicGame
                            { dynamicGameBoard = board
                            , dynamicGameIsTerminal = (/= 0) <$> mkDynamicIsTerminal isTerminalFun board
                            , dynamicGameSelectMove = mkDynamicSelectMove selectMoveFun board
                            }

withDynamicSearchGame
    :: Backend
    -> FilePath
    -> String
    -> (DynamicSearchGame -> IO a)
    -> IO (Either AppError a)
withDynamicSearchGame backend libraryPath symbolPrefix body =
    liftFFI backend (symbolPrefix <> "_search_move") $
        withPinnedDynamicLibrary libraryPath $ \library -> do
            newFun <- DL.dlsym library (symbolPrefix <> "_new_board")
            freeFun <- DL.dlsym library (symbolPrefix <> "_free_board")
            isTerminalFun <- DL.dlsym library (symbolPrefix <> "_is_terminal")
            applyActionFun <- DL.dlsym library (symbolPrefix <> "_apply_action")
            searchMoveFun <- DL.dlsym library (symbolPrefix <> "_search_move")
            let isTerminal board' = (/= 0) <$> mkDynamicIsTerminal isTerminalFun board'
                applyAction' = mkDynamicApplyAction applyActionFun
                searchMove' = mkDynamicSearchMove searchMoveFun
            withDynamicProfileFlush library symbolPrefix $
                bracket (mkBoardNew newFun) (mkBoardFree freeFun) $ \board ->
                    body
                        DynamicSearchGame
                            { searchGameBoard = board
                            , searchGameIsTerminal = isTerminal board
                            , searchGameApplyAction = \actionId -> do
                                ret <- applyAction' board actionId
                                pure $
                                    if ret == 0
                                        then Right ()
                                        else
                                            Left $
                                                FFIFailure
                                                    backend
                                                    (symbolPrefix <> "_apply_action")
                                                    ("apply returned " <> show ret)
                            , searchGameSearchMove = \seed sims -> do
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
  where
    actionCount = 209

withDynamicBenchmarkGame
    :: Backend
    -> FilePath
    -> String
    -> (DynamicBenchmarkGame -> IO a)
    -> IO (Either AppError a)
withDynamicBenchmarkGame backend libraryPath symbolPrefix body =
    liftFFI backend (symbolPrefix <> "_benchmark_terminal_playouts") $
        withPinnedDynamicLibrary libraryPath $ \library -> do
            newFun <- DL.dlsym library (symbolPrefix <> "_new_board")
            freeFun <- DL.dlsym library (symbolPrefix <> "_free_board")
            terminalFun <- DL.dlsym library (symbolPrefix <> "_benchmark_terminal_playouts")
            searchFun <- DL.dlsym library (symbolPrefix <> "_benchmark_search_iters")
            let terminalBench = mkDynamicBenchmark terminalFun
                searchBench = mkDynamicBenchmark searchFun
            withDynamicProfileFlush library symbolPrefix $
                bracket (mkBoardNew newFun) (mkBoardFree freeFun) $ \board ->
                    body
                        DynamicBenchmarkGame
                            { benchmarkGameBoard = board
                            , benchmarkGameTerminalPlayouts = terminalBench board
                            , benchmarkGameSearchIters = searchBench board
                            }

-- | Sprint 6.5: open a dynamic backend exposing the
-- `mcts_<backend>_recompute_move` ABI. The body sees a
-- `DynamicRecomputeGame` whose `recomputeGameRecomputeMove` peeks
-- the per-move visit vector, chosen action id, and chosen-action
-- parent-perspective equity out of the foreign engine. Symbol set
-- is `<prefix>_new_board`, `<prefix>_free_board`,
-- `<prefix>_is_terminal`, `<prefix>_recompute_move`.
withDynamicRecomputeGame
    :: Backend
    -> FilePath
    -> String
    -> (DynamicRecomputeGame -> IO a)
    -> IO (Either AppError a)
withDynamicRecomputeGame backend libraryPath symbolPrefix body =
    liftFFI backend (symbolPrefix <> "_recompute_move") $
        withPinnedDynamicLibrary libraryPath $ \library -> do
            newFun <- DL.dlsym library (symbolPrefix <> "_new_board")
            freeFun <- DL.dlsym library (symbolPrefix <> "_free_board")
            isTerminalFun <- DL.dlsym library (symbolPrefix <> "_is_terminal")
            recomputeFun <- DL.dlsym library (symbolPrefix <> "_recompute_move")
            let isTerminal board' = (/= 0) <$> mkDynamicIsTerminal isTerminalFun board'
                recompute' = mkDynamicRecomputeMove recomputeFun
            withDynamicProfileFlush library symbolPrefix $
                bracket (mkBoardNew newFun) (mkBoardFree freeFun) $ \board ->
                    body
                        DynamicRecomputeGame
                            { recomputeGameBoard = board
                            , recomputeGameIsTerminal = isTerminal board
                            , recomputeGameRecomputeMove = \seed sims ->
                                allocaArray actionCount $ \actionIdsBuf ->
                                    allocaArray actionCount $ \visitsBuf ->
                                        alloca $ \chosenBuf ->
                                            alloca $ \equityBuf -> do
                                                ret <-
                                                    recompute'
                                                        board
                                                        seed
                                                        sims
                                                        actionIdsBuf
                                                        visitsBuf
                                                        chosenBuf
                                                        equityBuf
                                                if ret < 0
                                                    then
                                                        pure $
                                                            Left $
                                                                FFIFailure
                                                                    backend
                                                                    (symbolPrefix <> "_recompute_move")
                                                                    ("recompute returned " <> show ret)
                                                    else do
                                                        let count = fromIntegral ret
                                                        actionIds <- peekArray count actionIdsBuf
                                                        visits <- peekArray count visitsBuf
                                                        chosen <- peek chosenBuf
                                                        equity <- peek equityBuf
                                                        pure $
                                                            Right
                                                                ( chosen
                                                                , zip actionIds visits
                                                                , equity
                                                                )
                            }
  where
    actionCount = 209

loadDynamicEnvelope
    :: Backend
    -> FilePath
    -> String
    -> IO (Either AppError EngineEnvelope)
loadDynamicEnvelope backend libraryPath symbolPrefix =
    liftFFI backend (symbolPrefix <> "_get_envelope") $
        withPinnedDynamicLibrary libraryPath $ \library -> do
            withDynamicProfileFlush library symbolPrefix $ do
                envelopeFun <- DL.dlsym library (symbolPrefix <> "_get_envelope")
                envelopePtr <- mkDynamicEnvelope envelopeFun
                peekEngineEnvelope backend envelopePtr

withDynamicProfileFlush :: DL.DL -> String -> IO a -> IO a
withDynamicProfileFlush library symbolPrefix action =
    action `finally` flushDynamicProfile library symbolPrefix

flushDynamicProfile :: DL.DL -> String -> IO ()
flushDynamicProfile library symbolPrefix = do
    scoped <- (== Just "1") <$> lookupEnv "MCTS_SCOPED_DYNAMIC_LIBRARY"
    if scoped
        then do
            dumpResult <-
                try (DL.dlsym library (symbolPrefix <> "_dump_profile") :: IO (FunPtr (IO ())))
                    :: IO (Either SomeException (FunPtr (IO ())))
            case dumpResult of
                Right dumpProfile -> mkDynamicProfileDump dumpProfile
                Left _ -> pure ()
        else pure ()

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
