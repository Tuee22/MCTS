module MCTS.Verify
    ( compareTranscripts
    , VerifyResult (..)
    , verifyRun
    , verifyRunDetailed
    , legacyParityRun
    , legacyParityRunDetailed
    ) where

import Data.List (sortOn)
import Data.Word (Word32)
import MCTS.Driver
import MCTS.Driver.Dispatch (runBatchDispatch)
import MCTS.Error (AppError (..))
import MCTS.Types
import MCTS.Verify.Envelope (checkTranscriptEnvelopesLive)

data VerifyResult = VerifyResult
    { verifyWarnings :: ![AppError]
    , verifyBatches :: ![BatchResult]
    }
    deriving (Eq, Show)

compareTranscripts :: Backend -> Transcript -> Backend -> Transcript -> Either AppError ()
compareTranscripts leftBackend left rightBackend right =
    compareTranscriptsWith visitComparable leftBackend left rightBackend right

compareTranscriptsWith
    :: (Eq key)
    => (MoveRecord -> key)
    -> Backend
    -> Transcript
    -> Backend
    -> Transcript
    -> Either AppError ()
compareTranscriptsWith comparable leftBackend left rightBackend right =
    case firstMismatch of
        Nothing -> Right ()
        Just (gid, idx, leftRecord, rightRecord) ->
            Left (VerifyMismatch leftBackend rightBackend gid idx leftRecord rightRecord)
  where
    pairs =
        zip (transcriptGames left) (transcriptGames right)

    firstMismatch =
        findMismatch pairs

    findMismatch [] = Nothing
    findMismatch ((leftGame, rightGame) : rest) =
        case findRecordMismatch (zip (gameMoves leftGame) (gameMoves rightGame)) of
            Just (idx, l, r) -> Just (fromIntegral (gameId leftGame), idx, l, r)
            Nothing -> findMismatch rest

    findRecordMismatch [] = Nothing
    findRecordMismatch ((l, r) : rest)
        | comparable l == comparable r = findRecordMismatch rest
        | otherwise = Just (fromIntegral (moveIndex l), l, r)

-- Sprint 7.2: Q3 compares visit lists as conceptually unordered sets of
-- `(Action, count)` pairs, and different backends emit different enumerations
-- of zero-visit entries. Cohort agreement is the contract that *visited*
-- actions have the same visit counts across backends, not that the enumeration
-- shape matches. We filter zero-visit entries before sorting so the comparison
-- sees only the meaningful set.
visitComparable :: MoveRecord -> (Action, [(Action, Word32)])
visitComparable record =
    ( moveChosen record
    , sortOn fst (filter ((> 0) . snd) (moveVisits record))
    )

verifyRun :: Workload -> [Backend] -> RunInputs -> IO (Either AppError [BatchResult])
verifyRun workload backends inputs =
    fmap verifyBatches <$> verifyRunDetailed False workload backends inputs

verifyRunDetailed :: Bool -> Workload -> [Backend] -> RunInputs -> IO (Either AppError VerifyResult)
verifyRunDetailed allowStale workload backends inputs
    | length backends < 2 =
        pure (Left (VerifyCohortTooSmall "at least two non-legacy backends are required"))
    | any (== CppLegacy) backends =
        pure (Left (VerifyCohortTooSmall "cpp-legacy is excluded from mcts verify; use legacy-parity"))
    | otherwise = runAndCompare allowStale workload backends inputs{inputRng = CppRng}

legacyParityRun :: Workload -> [Backend] -> RunInputs -> IO (Either AppError [BatchResult])
legacyParityRun workload backends inputs =
    fmap verifyBatches <$> legacyParityRunDetailed False workload backends inputs

legacyParityRunDetailed
    :: Bool -> Workload -> [Backend] -> RunInputs -> IO (Either AppError VerifyResult)
legacyParityRunDetailed allowStale workload backends inputs
    | length backends < 2 =
        pure (Left (VerifyCohortTooSmall "legacy parity needs at least two backends"))
    | CppLegacy `notElem` backends =
        pure (Left (VerifyCohortTooSmall "legacy parity cohort must include cpp-legacy"))
    | otherwise =
        runWithoutTranscriptComparison
            allowStale
            workload
            backends
            inputs{inputRng = CppRng, inputThreading = SingleThreaded, inputMaxPlies = 10000}

runAndCompare :: Bool -> Workload -> [Backend] -> RunInputs -> IO (Either AppError VerifyResult)
runAndCompare =
    runAndCompareWith compareTranscripts

runAndCompareWith
    :: (Backend -> Transcript -> Backend -> Transcript -> Either AppError ())
    -> Bool
    -> Workload
    -> [Backend]
    -> RunInputs
    -> IO (Either AppError VerifyResult)
runAndCompareWith compareOneTranscript allowStale workload backends inputs = do
    results <-
        mapM
            ( \backend ->
                runBatchDispatch inputs{inputBackend = backend, inputWorkload = workload}
            )
            backends
    case sequence results of
        Left message -> pure (Left (IOErrorText message))
        Right batchResults -> do
            envelopeResult <- checkTranscriptEnvelopesLive allowStale (map batchTranscript batchResults)
            case envelopeResult of
                Left err -> pure (Left err)
                Right warnings ->
                    case compareAllWith compareOneTranscript batchResults of
                        Left err -> pure (Left err)
                        Right () -> pure (Right VerifyResult{verifyWarnings = warnings, verifyBatches = batchResults})

runWithoutTranscriptComparison
    :: Bool
    -> Workload
    -> [Backend]
    -> RunInputs
    -> IO (Either AppError VerifyResult)
runWithoutTranscriptComparison allowStale workload backends inputs = do
    results <-
        mapM
            ( \backend ->
                runBatchDispatch inputs{inputBackend = backend, inputWorkload = workload}
            )
            backends
    case sequence results of
        Left message -> pure (Left (IOErrorText message))
        Right batchResults -> do
            envelopeResult <- checkTranscriptEnvelopesLive allowStale (map batchTranscript batchResults)
            pure $ case envelopeResult of
                Left err -> Left err
                Right warnings -> Right VerifyResult{verifyWarnings = warnings, verifyBatches = batchResults}

compareAllWith
    :: (Backend -> Transcript -> Backend -> Transcript -> Either AppError ())
    -> [BatchResult]
    -> Either AppError ()
compareAllWith _ [] = Right ()
compareAllWith compareOneTranscript (x : xs) = mapM_ (compareOne x) xs >> compareAllWith compareOneTranscript xs
  where
    compareOne left right =
        compareOneTranscript
            (runBackend (transcriptConfig (batchTranscript left)))
            (batchTranscript left)
            (runBackend (transcriptConfig (batchTranscript right)))
            (batchTranscript right)
