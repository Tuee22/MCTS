-- | Haskell-side bindings for backend (ii) C++ imperative steelman.
module MCTS.FFI.CppImperative
    ( CppImperativeGame
    , withCppImperativeBoard
    , withCppImperativeGame
    , withCppImperativeSearchGame
    , withCppImperativeRecomputeGame
    , loadCppImperativeEnvelope
    , cppImperativeLibraryPath
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
import MCTS.Types (Backend (CppImperative))
import qualified System.Info as Info

newtype CppImperativeBoard = CppImperativeBoard (Ptr ())

type CppImperativeGame = DynamicGame

withCppImperativeBoard :: (CppImperativeBoard -> IO a) -> IO (Either AppError a)
withCppImperativeBoard body =
    withDynamicBoard CppImperative cppImperativeLibraryPath "mcts_imperative" $
        body . CppImperativeBoard

withCppImperativeGame :: (CppImperativeGame -> IO a) -> IO (Either AppError a)
withCppImperativeGame =
    withDynamicGame CppImperative cppImperativeLibraryPath "mcts_imperative"

withCppImperativeSearchGame
    :: (DynamicSearchGame -> IO a) -> IO (Either AppError a)
withCppImperativeSearchGame =
    withDynamicSearchGame CppImperative cppImperativeLibraryPath "mcts_imperative"

withCppImperativeRecomputeGame
    :: (DynamicRecomputeGame -> IO a) -> IO (Either AppError a)
withCppImperativeRecomputeGame =
    withDynamicRecomputeGame CppImperative cppImperativeLibraryPath "mcts_imperative"

loadCppImperativeEnvelope :: IO (Either AppError EngineEnvelope)
loadCppImperativeEnvelope =
    loadDynamicEnvelope CppImperative cppImperativeLibraryPath "mcts_imperative"

cppImperativeLibraryPath :: FilePath
cppImperativeLibraryPath =
    case Info.os of
        "darwin" -> "cpp-imperative/build/libmcts_cpp_imperative.dylib"
        _ -> "cpp-imperative/build/libmcts_cpp_imperative.so"
