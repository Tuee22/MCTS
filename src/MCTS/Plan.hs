module MCTS.Plan
    ( Plan (..)
    , PlanOptions (..)
    , renderPlan
    , writePlanFile
    ) where

import MCTS.Subprocess (Subprocess, renderSubprocess)

data Plan a = Plan
    { planName :: !String
    , planSteps :: ![a]
    }
    deriving (Eq, Show)

data PlanOptions = PlanOptions
    { planDryRun :: !Bool
    , planFile :: !(Maybe FilePath)
    }
    deriving (Eq, Show)

renderPlan :: Plan Subprocess -> String
renderPlan plan =
    unlines $
        ("plan: " <> planName plan)
            : [show idx <> ". " <> renderSubprocess step | (idx, step) <- zip [(1 :: Int) ..] (planSteps plan)]

writePlanFile :: Maybe FilePath -> String -> IO ()
writePlanFile Nothing _ = pure ()
writePlanFile (Just path) rendered = writeFile path rendered
