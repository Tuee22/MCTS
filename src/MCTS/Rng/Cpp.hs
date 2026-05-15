module MCTS.Rng.Cpp
    ( cppSplitSeed
    ) where

import Data.Word (Word64)
import Foreign.Ptr (FunPtr)
import MCTS.Error (AppError)
import MCTS.FFI.Common (liftFFI)
import MCTS.Types (Backend (CppLegacy))
import qualified System.Posix.DynamicLinker as DL

foreign import ccall "dynamic"
    mkSplitSeed :: FunPtr (Word64 -> Word64 -> IO Word64) -> Word64 -> Word64 -> IO Word64

cppSplitSeed :: Word64 -> Word64 -> IO (Either AppError Word64)
cppSplitSeed masterSeed gameIndex =
    liftFFI CppLegacy "cpp_rng_split_seed" $
        DL.withDL "cpp-legacy/build/libmcts_cpp_legacy.so" [DL.RTLD_NOW] $ \library -> do
            splitSeed <- DL.dlsym library "cpp_rng_split_seed"
            mkSplitSeed splitSeed masterSeed gameIndex
