module MCTS.CLI.Verify
    ( renderVerifyJson
    , runVerifyCommand
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Char (ord)
import qualified Data.Text as Text
import MCTS.CLI.Command
    ( VerifyCommand (..)
    , verifyBackendsToBackends
    )
import MCTS.CLI.Output
    ( OutputFormat (..)
    , OutputOptions (..)
    , errLine
    , outputLine
    , renderErrorString
    )
import qualified MCTS.Env as Env
import MCTS.Error (AppError (..), EnvelopeMismatchScope (..), renderError)
import MCTS.Types
import MCTS.Verify
import Numeric (showHex)
import System.Exit (ExitCode (..))

runVerifyCommand :: VerifyCommand -> Env.App ExitCode
runVerifyCommand command = do
    env <- Env.askEnv
    runWithOutput (Env.envOutputOptions env) command

runWithOutput :: OutputOptions -> VerifyCommand -> Env.App ExitCode
runWithOutput output command =
    case command of
        VerifyRollouts allowStale backends inputs ->
            run
                "verify rollouts"
                "agree on visit counts"
                (verifyRunDetailed allowStale Rollouts (verifyBackendsToBackends backends) inputs)
        VerifySelfplay allowStale backends inputs ->
            run
                "verify selfplay"
                "agree on visit counts"
                (verifyRunDetailed allowStale Selfplay (verifyBackendsToBackends backends) inputs)
  where
    run label agreement action = do
        result <- liftIO action
        case result of
            Left err -> liftIO (outputLine (renderErrorString output err)) >> pure (ExitFailure 1)
            Right verifyResult -> do
                liftIO (mapM_ (errLine . renderErrorString output) (verifyWarnings verifyResult))
                let batches = verifyBatches verifyResult
                liftIO $
                    outputLine $
                        case outputFormat output of
                            JsonFormat ->
                                renderVerifyJson label verifyResult
                            _ ->
                                label
                                    <> " PASS ("
                                    <> show (length batches)
                                    <> " backends "
                                    <> agreement
                                    <> ")"
                pure ExitSuccess

renderVerifyJson :: String -> VerifyResult -> String
renderVerifyJson label verifyResult =
    "{\"status\":\"PASS\",\"cohort\":"
        <> show (length (verifyBatches verifyResult))
        <> ",\"warnings\":"
        <> show (length warnings)
        <> ",\"warning_details\":["
        <> joinWith "," (map renderWarningJson warnings)
        <> "],\"label\":"
        <> jsonString label
        <> "}"
  where
    warnings = verifyWarnings verifyResult

renderWarningJson :: AppError -> String
renderWarningJson warning =
    case warning of
        EngineEnvelopeMismatch scope field expected got ->
            "{\"type\":\"EngineEnvelopeMismatch\","
                <> renderScopeJson scope
                <> ",\"field\":"
                <> jsonString field
                <> ",\"expected\":"
                <> jsonString expected
                <> ",\"got\":"
                <> jsonString got
                <> ",\"message\":"
                <> jsonString (Text.unpack (renderError warning))
                <> "}"
        _ ->
            "{\"type\":"
                <> jsonString (warningType warning)
                <> ",\"message\":"
                <> jsonString (Text.unpack (renderError warning))
                <> "}"

renderScopeJson :: EnvelopeMismatchScope -> String
renderScopeJson scope =
    case scope of
        CohortLevel -> "\"scope\":\"CohortLevel\""
        BackendSlot backend ->
            "\"scope\":\"BackendSlot\",\"backend\":"
                <> jsonString (backendIdentifier backend)

warningType :: AppError -> String
warningType warning =
    case warning of
        TranscriptNotFound _ -> "TranscriptNotFound"
        TranscriptAmbiguous _ _ -> "TranscriptAmbiguous"
        TranscriptFormatUnsupported _ -> "TranscriptFormatUnsupported"
        VerifyMismatch _ _ _ _ _ _ -> "VerifyMismatch"
        VerifyLengthMismatch _ _ _ _ _ -> "VerifyLengthMismatch"
        VerifyTerminatorMismatch _ _ _ _ _ -> "VerifyTerminatorMismatch"
        VerifyCohortTooSmall _ -> "VerifyCohortTooSmall"
        RecomputeMismatch _ _ _ _ _ -> "RecomputeMismatch"
        LegacyParityRolloutOverflow _ _ _ -> "LegacyParityRolloutOverflow"
        ArchEnvelopeMismatch _ _ -> "ArchEnvelopeMismatch"
        EngineEnvelopeMismatch _ _ _ _ -> "EngineEnvelopeMismatch"
        PrerequisiteUnmet _ _ _ -> "PrerequisiteUnmet"
        SubprocessFailed _ _ -> "SubprocessFailed"
        FFIFailure _ _ _ -> "FFIFailure"
        DocsCheckDrift _ _ -> "DocsCheckDrift"
        UnknownCommand _ -> "UnknownCommand"
        InvalidMove _ -> "InvalidMove"
        ParseError _ -> "ParseError"
        IOErrorText _ -> "IOErrorText"

jsonString :: String -> String
jsonString value =
    "\"" <> concatMap escapeJson value <> "\""

escapeJson :: Char -> String
escapeJson char =
    case char of
        '"' -> "\\\""
        '\\' -> "\\\\"
        '\b' -> "\\b"
        '\f' -> "\\f"
        '\n' -> "\\n"
        '\r' -> "\\r"
        '\t' -> "\\t"
        _
            | ord char < 0x20 -> "\\u" <> padLeft 4 '0' (showHex (ord char) "")
            | otherwise -> [char]

padLeft :: Int -> Char -> String -> String
padLeft width filler value =
    replicate (max 0 (width - length value)) filler <> value

joinWith :: String -> [String] -> String
joinWith _ [] = ""
joinWith _ [x] = x
joinWith delimiter (x : xs) = x <> delimiter <> joinWith delimiter xs
