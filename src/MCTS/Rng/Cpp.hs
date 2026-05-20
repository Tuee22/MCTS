module MCTS.Rng.Cpp
    ( cppMoveSeedsIfAvailable
    , cppRngAvailable
    , cppRngLibraryPath
    , cppSplitSeed
    ) where

import Data.Word (Word64)
import Foreign.C.Types (CInt (..))
import Foreign.Marshal.Array (allocaArray, peekArray)
import Foreign.Ptr (FunPtr, Ptr)
import MCTS.Error (AppError)
import MCTS.FFI.Common (liftFFI, withPinnedDynamicLibrary)
import MCTS.Types (Backend (CppLegacy))
import System.Directory (doesFileExist)
import qualified System.Info as Info
import qualified System.Posix.DynamicLinker as DL

foreign import ccall "dynamic"
    mkSplitSeed :: FunPtr (Word64 -> Word64 -> IO Word64) -> Word64 -> Word64 -> IO Word64

foreign import ccall "dynamic"
    mkFillU64
        :: FunPtr (Word64 -> Word64 -> Ptr Word64 -> Word64 -> IO CInt)
        -> Word64
        -> Word64
        -> Ptr Word64
        -> Word64
        -> IO CInt

cppRngAvailable :: IO Bool
cppRngAvailable = doesFileExist cppRngLibraryPath

cppRngLibraryPath :: FilePath
cppRngLibraryPath =
    case Info.os of
        "darwin" -> "cpp-legacy/build/libmcts_cpp_rng.dylib"
        _ -> "cpp-legacy/build/libmcts_cpp_rng.so"

cppSplitSeed :: Word64 -> Word64 -> IO (Either AppError Word64)
cppSplitSeed masterSeed gameIndex =
    liftFFI CppLegacy "cpp_rng_split_seed" $
        withPinnedDynamicLibrary cppRngLibraryPath $ \library -> do
            splitSeed <- DL.dlsym library "cpp_rng_split_seed"
            mkSplitSeed splitSeed masterSeed gameIndex

cppMoveSeedsIfAvailable :: Word64 -> Word64 -> Int -> IO (Maybe [Word64])
cppMoveSeedsIfAvailable masterSeed gameIndex count = do
    present <- cppRngAvailable
    if not present
        then pure Nothing
        else do
            generated <- cppMoveSeeds masterSeed gameIndex (max 0 count)
            pure $
                case generated of
                    Left _ -> Nothing
                    Right seeds -> Just seeds

cppMoveSeeds :: Word64 -> Word64 -> Int -> IO (Either AppError [Word64])
cppMoveSeeds masterSeed gameIndex count =
    liftFFI CppLegacy "cpp_rng_fill_u64" $
        withPinnedDynamicLibrary cppRngLibraryPath $ \library -> do
            fill <- DL.dlsym library "cpp_rng_fill_u64"
            allocaArray count $ \buffer -> do
                ret <- mkFillU64 fill masterSeed gameIndex buffer (fromIntegral count)
                if ret == 0
                    then peekArray count buffer
                    else ioError (userError ("cpp_rng_fill_u64 returned " <> show ret))
