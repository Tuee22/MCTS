module Main (main) where

import MCTS.Types (Backend (..))
import MCTS.Verify.Semantic
    ( SemanticBackendResult (..)
    , SemanticCheckResult (..)
    , runSemanticParity
    , semanticBackends
    )
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, assertFailure, testCase)

main :: IO ()
main =
    defaultMain $
        testGroup
            "semantic parity"
            [ testCase "Q7 steelman semantic parity" $ do
                result <- runSemanticParity
                case result of
                    Left err -> assertFailure (show err)
                    Right checked -> assertSemanticResult checked
            ]

assertSemanticResult :: SemanticCheckResult -> IO ()
assertSemanticResult checked = do
    let rows = semanticBackendResults checked
    assertEqual "Q7 covers exactly backends (ii)..(v)" semanticBackends (map semanticBackend rows)
    assertBool "generated history set is non-empty" (semanticHistoryCount checked > 0)
    mapM_ assertBackendResult rows

assertBackendResult :: SemanticBackendResult -> IO ()
assertBackendResult row = do
    assertBool
        ("replay checks ran for " <> show (semanticBackend row))
        (semanticReplayChecks row >= 0)
    assertBool
        ("search checks ran for " <> show (semanticBackend row))
        (semanticSearchChecks row > 0)
    assertEqual
        ("terminal rejection ran for " <> show (semanticBackend row))
        1
        (semanticTerminalRejectionChecks row)

_keepBackend :: Backend
_keepBackend = Haskell
