module MCTS.Driver.Rust
    ( runGameRust
    ) where

import Data.Word (Word32)
import MCTS.Driver (RunInputs)
import MCTS.Driver.ForeignSmoke (runDynamicSmokeGame)
import MCTS.Error (AppError)
import MCTS.FFI.Rust (withRustGame)
import MCTS.Types (GameTranscript)

runGameRust :: RunInputs -> Word32 -> IO (Either AppError GameTranscript)
runGameRust =
    runDynamicSmokeGame withRustGame
