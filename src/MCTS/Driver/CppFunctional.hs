module MCTS.Driver.CppFunctional
    ( runGameCppFunctional
    ) where

import Data.Word (Word32)
import MCTS.Driver (RunInputs)
import MCTS.Driver.ForeignSearch (runForeignSearchGame)
import MCTS.Error (AppError)
import MCTS.FFI.CppFunctional (withCppFunctionalSearchGame)
import MCTS.Types (GameTranscript)

runGameCppFunctional :: RunInputs -> Word32 -> IO (Either AppError GameTranscript)
runGameCppFunctional =
    runForeignSearchGame withCppFunctionalSearchGame
