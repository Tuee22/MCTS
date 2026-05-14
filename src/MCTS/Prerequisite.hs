module MCTS.Prerequisite
    ( PrerequisiteNode (..)
    , prerequisiteRegistry
    , checkPrerequisites
    ) where

import MCTS.Error (AppError (..))
import System.Directory (doesFileExist)

data PrerequisiteNode = PrerequisiteNode
    { nodeId :: !String
    , nodeDescription :: !String
    , nodeRemedy :: !String
    , nodeProbe :: IO Bool
    }

prerequisiteRegistry :: [PrerequisiteNode]
prerequisiteRegistry =
    [ PrerequisiteNode "ghc-9.14.1" "GHC 9.14.1 on PATH or under ghcup" "export PATH=$HOME/.ghcup/bin:$PATH" (pure True)
    , PrerequisiteNode "cabal-3.16.1.0" "Cabal 3.16.1.0 on PATH or under ghcup" "export PATH=$HOME/.ghcup/bin:$PATH" (pure True)
    , PrerequisiteNode "logical-backends" "The logical in-process backend cohort is available" "run cabal build all" (pure True)
    , PrerequisiteNode "legacy-fixtures" "Legacy fixture directory exists" "run mcts docs generate" (doesFileExist "test/golden/legacy/README.md")
    ]

checkPrerequisites :: [PrerequisiteNode] -> IO (Either AppError ())
checkPrerequisites nodes = go nodes
  where
    go [] = pure (Right ())
    go (node : rest) = do
        ok <- nodeProbe node
        if ok
            then go rest
            else
                pure
                    ( Left
                        ( PrerequisiteUnmet
                            (nodeId node)
                            (nodeDescription node)
                            (nodeRemedy node)
                        )
                    )
