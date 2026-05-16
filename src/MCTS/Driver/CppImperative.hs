module MCTS.Driver.CppImperative
    ( runGameCppImperative
    ) where

import Data.Word (Word32)
import MCTS.Driver (RunInputs)
import MCTS.Driver.ForeignSearch (runForeignSearchGame)
import MCTS.Error (AppError)
import MCTS.FFI.CppImperative (withCppImperativeSearchGame)
import MCTS.Types (GameTranscript)

runGameCppImperative :: RunInputs -> Word32 -> IO (Either AppError GameTranscript)
runGameCppImperative =
    runForeignSearchGame withCppImperativeSearchGame
