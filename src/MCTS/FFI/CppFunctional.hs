-- | Haskell-side bindings for backend (iii) C++ functional-style steelman.
module MCTS.FFI.CppFunctional
    ( CppFunctionalGame
    , withCppFunctionalBoard
    , withCppFunctionalGame
    , withCppFunctionalSearchGame
    , withCppFunctionalRecomputeGame
    , loadCppFunctionalEnvelope
    , cppFunctionalLibraryPath
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
import MCTS.Types (Backend (CppFunctional))
import qualified System.Info as Info

newtype CppFunctionalBoard = CppFunctionalBoard (Ptr ())

type CppFunctionalGame = DynamicGame

withCppFunctionalBoard :: (CppFunctionalBoard -> IO a) -> IO (Either AppError a)
withCppFunctionalBoard body =
    withDynamicBoard CppFunctional cppFunctionalLibraryPath "mcts_functional" $
        body . CppFunctionalBoard

withCppFunctionalGame :: (CppFunctionalGame -> IO a) -> IO (Either AppError a)
withCppFunctionalGame =
    withDynamicGame CppFunctional cppFunctionalLibraryPath "mcts_functional"

withCppFunctionalSearchGame
    :: (DynamicSearchGame -> IO a) -> IO (Either AppError a)
withCppFunctionalSearchGame =
    withDynamicSearchGame CppFunctional cppFunctionalLibraryPath "mcts_functional"

withCppFunctionalRecomputeGame
    :: (DynamicRecomputeGame -> IO a) -> IO (Either AppError a)
withCppFunctionalRecomputeGame =
    withDynamicRecomputeGame CppFunctional cppFunctionalLibraryPath "mcts_functional"

loadCppFunctionalEnvelope :: IO (Either AppError EngineEnvelope)
loadCppFunctionalEnvelope =
    loadDynamicEnvelope CppFunctional cppFunctionalLibraryPath "mcts_functional"

cppFunctionalLibraryPath :: FilePath
cppFunctionalLibraryPath =
    case Info.os of
        "darwin" -> "cpp-functional/build/libmcts_cpp_functional.dylib"
        _ -> "cpp-functional/build/libmcts_cpp_functional.so"
