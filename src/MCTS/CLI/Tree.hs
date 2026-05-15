module MCTS.CLI.Tree
    ( renderCommandList
    , renderCommandTree
    ) where

import qualified MCTS.CLI.Spec as Spec

renderCommandList :: String
renderCommandList = Spec.renderCommandList

renderCommandTree :: String
renderCommandTree = Spec.renderCommandTree
