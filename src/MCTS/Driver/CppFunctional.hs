module MCTS.Driver.CppFunctional
    ( runGameCppFunctional
    ) where

import Data.Word (Word32)
import MCTS.Driver (RunInputs)
import MCTS.Driver.ForeignSmoke (runDynamicSmokeGame)
import MCTS.Error (AppError)
import MCTS.FFI.CppFunctional (withCppFunctionalGame)
import MCTS.Types (GameTranscript)

runGameCppFunctional :: RunInputs -> Word32 -> IO (Either AppError GameTranscript)
runGameCppFunctional =
    runDynamicSmokeGame withCppFunctionalGame
