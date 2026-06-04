module MCTS.Error
    ( EnvelopeMismatchScope (..)
    , AppError (..)
    , renderError
    ) where

import Data.Text (Text)
import qualified Data.Text as Text
import MCTS.Types (Action, Backend, MoveRecord, backendIdentifier)

data EnvelopeMismatchScope
    = CohortLevel
    | BackendSlot Backend
    deriving (Eq, Show)

data AppError
    = TranscriptNotFound String
    | TranscriptAmbiguous String [String]
    | TranscriptFormatUnsupported String
    | VerifyMismatch Backend Backend Int Int MoveRecord MoveRecord
    | VerifyLengthMismatch Backend Backend String Int Int
    | VerifyTerminatorMismatch Backend Backend Int String String
    | VerifyCohortTooSmall String
    | RecomputeMismatch Backend Int Int MoveRecord MoveRecord
    | LegacyParityRolloutOverflow Integer Int Int
    | ArchEnvelopeMismatch String String
    | EngineEnvelopeMismatch EnvelopeMismatchScope String String String
    | PrerequisiteUnmet String String String
    | SubprocessFailed String Int
    | FFIFailure Backend String String
    | DocsCheckDrift FilePath String
    | UnknownCommand String
    | InvalidMove String
    | ParseError String
    | IOErrorText String
    deriving (Eq, Show)

renderError :: AppError -> Text
renderError err =
    Text.pack $ case err of
        TranscriptNotFound ref ->
            "transcript not found: " <> ref
        TranscriptAmbiguous ref candidates ->
            "transcript prefix is ambiguous: " <> ref <> " candidates=" <> show candidates
        TranscriptFormatUnsupported reason ->
            "unsupported transcript format: " <> reason
        VerifyMismatch left right game move leftRecord rightRecord ->
            "verify mismatch: "
                <> backendIdentifier left
                <> " vs "
                <> backendIdentifier right
                <> " game="
                <> show game
                <> " move="
                <> show move
                <> " left="
                <> show leftRecord
                <> " right="
                <> show rightRecord
        VerifyLengthMismatch left right scope leftCount rightCount ->
            "verify length mismatch: "
                <> backendIdentifier left
                <> " vs "
                <> backendIdentifier right
                <> " scope="
                <> scope
                <> " left="
                <> show leftCount
                <> " right="
                <> show rightCount
        VerifyTerminatorMismatch left right game leftTerminator rightTerminator ->
            "verify terminator mismatch: "
                <> backendIdentifier left
                <> " vs "
                <> backendIdentifier right
                <> " game="
                <> show game
                <> " left="
                <> leftTerminator
                <> " right="
                <> rightTerminator
        VerifyCohortTooSmall reason ->
            "verify cohort too small: " <> reason
        RecomputeMismatch backend game move leftRecord rightRecord ->
            "recompute mismatch: "
                <> backendIdentifier backend
                <> " game="
                <> show game
                <> " move="
                <> show move
                <> " recomputed="
                <> show leftRecord
                <> " recorded="
                <> show rightRecord
        LegacyParityRolloutOverflow seed game move ->
            "legacy parity rollout overflow: seed="
                <> show seed
                <> " game="
                <> show game
                <> " move="
                <> show move
        ArchEnvelopeMismatch expected got ->
            "architecture envelope mismatch: expected=" <> expected <> " got=" <> got
        EngineEnvelopeMismatch scope field expected got ->
            "engine envelope mismatch: "
                <> show scope
                <> " field="
                <> field
                <> " expected="
                <> expected
                <> " got="
                <> got
        PrerequisiteUnmet ident description remedy ->
            "prerequisite unmet: " <> ident <> " (" <> description <> "); remedy: " <> remedy
        SubprocessFailed command code ->
            "subprocess failed: " <> command <> " exit=" <> show code
        FFIFailure backend symbol message ->
            "ffi failure: " <> backendIdentifier backend <> " " <> symbol <> ": " <> message
        DocsCheckDrift path key ->
            "generated docs drift: "
                <> path
                <> " marker="
                <> key
                <> "; run `hostbootstrap run mcts docs generate`"
        UnknownCommand command ->
            "unknown command: " <> command
        InvalidMove raw ->
            "invalid move: " <> raw
        ParseError message ->
            "parse error: " <> message
        IOErrorText message ->
            "io error: " <> message

_keepAction :: Action -> Action
_keepAction = id
