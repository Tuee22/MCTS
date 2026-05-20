module MCTS.Verify
    ( compareTranscripts
    , VerifyResult (..)
    , verifyRun
    , verifyRunDetailed
    ) where

import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy as LBS
import Data.List (sortOn)
import Data.Word (Word32)
import MCTS.Crypto.SHA256 (sha256Hex)
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

type ComparableMove = (Action, [(Action, Word32)])

compareTranscriptsWith
    :: (MoveRecord -> ComparableMove)
    -> Backend
    -> Transcript
    -> Backend
    -> Transcript
    -> Either AppError ()
compareTranscriptsWith comparable leftBackend left rightBackend right =
    if determinismDigest comparable left == determinismDigest comparable right
        then Right ()
        else compareGames (transcriptGames left) (transcriptGames right)
  where
    compareGames [] [] = Right ()
    compareGames leftGames [] =
        Left (VerifyLengthMismatch leftBackend rightBackend "games" (length leftGames) 0)
    compareGames [] rightGames =
        Left (VerifyLengthMismatch leftBackend rightBackend "games" 0 (length rightGames))
    compareGames (leftGame : leftRest) (rightGame : rightRest) =
        case compareGame leftGame rightGame of
            Right () -> compareGames leftRest rightRest
            Left err -> Left err

    compareGame leftGame rightGame =
        case compareRecords (gameId leftGame) (gameMoves leftGame) (gameMoves rightGame) of
            Right () ->
                if gameWinner leftGame == gameWinner rightGame
                    && length (gameMoves leftGame) == length (gameMoves rightGame)
                    then Right ()
                    else
                        Left
                            ( VerifyTerminatorMismatch
                                leftBackend
                                rightBackend
                                (fromIntegral (gameId leftGame))
                                (terminatorSummary leftGame)
                                (terminatorSummary rightGame)
                            )
            Left err -> Left err

    compareRecords _ [] [] = Right ()
    compareRecords gid leftRecords [] =
        Left
            (VerifyLengthMismatch leftBackend rightBackend ("moves game=" <> show gid) (length leftRecords) 0)
    compareRecords gid [] rightRecords =
        Left
            (VerifyLengthMismatch leftBackend rightBackend ("moves game=" <> show gid) 0 (length rightRecords))
    compareRecords gid (leftRecord : leftRest) (rightRecord : rightRest)
        | comparable leftRecord == comparable rightRecord = compareRecords gid leftRest rightRest
        | otherwise =
            Left
                ( VerifyMismatch
                    leftBackend
                    rightBackend
                    (fromIntegral gid)
                    (fromIntegral (moveIndex leftRecord))
                    leftRecord
                    rightRecord
                )

    terminatorSummary game =
        show (gameWinner game) <> " total_moves=" <> show (length (gameMoves game))

determinismDigest :: (MoveRecord -> ComparableMove) -> Transcript -> String
determinismDigest comparable transcript =
    sha256Hex . LBS.toStrict . Builder.toLazyByteString $
        Builder.word8 (rngId (runRngSource config))
            <> Builder.word64LE (runCParamBits config)
            <> Builder.word64LE (runMasterSeed config)
            <> Builder.word32LE (fromIntegral (runInitialSims config))
            <> Builder.word32LE (fromIntegral (runPerMoveSims config))
            <> Builder.word16LE (runMaxPlies config)
            <> Builder.word32LE (fromIntegral (length (transcriptGames transcript)))
            <> mconcat (map gamePayload (transcriptGames transcript))
  where
    config = transcriptConfig transcript
    gamePayload game =
        Builder.word32LE (gameId game)
            <> Builder.word32LE (fromIntegral (length (gameMoves game)))
            <> mconcat (map recordPayload (gameMoves game))
            <> Builder.word8 (winnerId (gameWinner game))
            <> Builder.word16LE (fromIntegral (length (gameMoves game)))
    recordPayload record =
        let (chosen, visits) = comparable record
         in Builder.word16LE (moveIndex record)
                <> Builder.word8 (actionId chosen)
                <> Builder.word32LE (fromIntegral (length visits))
                <> mconcat (map visitPayload visits)
    visitPayload (action, count) =
        Builder.word8 (actionId action)
            <> Builder.word32LE count
    rngId rng =
        case rng of
            NativeRng -> 0
            CppRng -> 1
    winnerId winner =
        case winner of
            HeroWin -> 0
            VillainWin -> 1
            Draw -> 2

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
    | any (`elem` [CppLegacy, CppImperative, CppFunctional]) backends =
        pure
            (Left (VerifyCohortTooSmall "retired backends are not live verify targets; use frozen anchors"))
    | otherwise = runAndCompare allowStale workload backends inputs{inputRng = CppRng}

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
