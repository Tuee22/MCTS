module MCTS.Driver.CppImperative
    ( runGameCppImperative
    ) where

import Data.Word (Word32)
import MCTS.Driver (RunInputs)
import MCTS.Driver.ForeignSmoke (runDynamicSmokeGame)
import MCTS.Error (AppError)
import MCTS.FFI.CppImperative (withCppImperativeGame)
import MCTS.Types (GameTranscript)

runGameCppImperative :: RunInputs -> Word32 -> IO (Either AppError GameTranscript)
runGameCppImperative =
    runDynamicSmokeGame withCppImperativeGame
