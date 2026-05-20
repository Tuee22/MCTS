module Main where

import MCTS.Driver
import MCTS.Error (AppError (..))
import MCTS.Types
import MCTS.Verify (VerifyResult (..), legacyParityRunDetailed)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, assertFailure, testCase, (@?=))

main :: IO ()
main =
    defaultMain $
        testGroup
            "mcts-legacy-parity"
            [ testCase "all five backend slots complete legacy selfplay envelope" legacySelfplayCheck
            , testCase "legacy parity requires the complete five-backend cohort" legacyCohortCheck
            ]

legacySelfplayCheck :: IO ()
legacySelfplayCheck = do
    result <-
        legacyParityRunDetailed
            False
            Selfplay
            allBackends
            legacyInputs
                { inputRng = NativeRng
                , inputThreading = MultiThreaded 8
                , inputMaxPlies = 12
                }
    case result of
        Left err -> assertFailure ("legacy parity selfplay failed: " <> show err)
        Right verifyResult -> do
            length (verifyBatches verifyResult) @?= length allBackends
            let configs = map (transcriptConfig . batchTranscript) (verifyBatches verifyResult)
            assertBool "legacy parity pins cpp RNG" (all ((== CppRng) . runRngSource) configs)
            assertBool "legacy parity pins single-threading" (all ((== SingleThreaded) . runThreading) configs)
            assertBool "legacy parity pins max_plies=10000" (all ((== 10000) . runMaxPlies) configs)
            assertEqual "legacy parity backend order" allBackends (map runBackend configs)

legacyCohortCheck :: IO ()
legacyCohortCheck = do
    result <- legacyParityRunDetailed False Rollouts [CppLegacy, Haskell] legacyInputs
    case result of
        Left (VerifyCohortTooSmall _) -> pure ()
        other -> assertFailure ("expected complete-cohort rejection, got " <> show other)

legacyInputs :: RunInputs
legacyInputs =
    defaultRunInputs
        { inputGames = 1
        , inputSeed = 42
        , inputSims = FixedSims 4
        , inputCacheDir = Just "/tmp/mcts-legacy-parity"
        }
