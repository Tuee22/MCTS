{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE RankNTypes #-}

-- | Sprint 6.5: drive `mcts_<backend>_recompute_move` move-by-move
-- through a transcript and emit an `EqStream` carrying the foreign
-- backend's recompute-equity per move. The opener parameter is
-- supplied by the per-backend `MCTS.FFI.<Backend>` module so this
-- module remains backend-neutral.
--
-- Pairs with `MCTS.Verify.Divergence.divergenceVsEqStream` so
-- `mcts inspect divergence` and the Sprint 7.5 report-card divergence
-- matrix can render real per-backend recompute drift rather than the
-- in-process Haskell-only baseline.
module MCTS.Engine.ForeignRecompute
    ( ForeignRecomputeOpener
    , foreignRecomputeEqStream
    ) where

import Data.Bits (xor)
import Data.Word (Word32, Word64, Word8)
import MCTS.Engine (Board, applyMove, boardSideToMove, initialBoard)
import MCTS.Error (AppError (..))
import MCTS.FFI.Common
    ( DynamicRecomputeGame (..)
    )
import MCTS.Rng.Mix (backendNativeSalt, mix)
import MCTS.Transcript.EquitySidecar (EqRecord (..), EqStream (..))
import MCTS.Types
    ( Action
    , Backend
    , Envelope (..)
    , GameTranscript (..)
    , MoveRecord (..)
    , RngSource (..)
    , RunConfig (..)
    , Side (..)
    , SimBudget (..)
    , Transcript (..)
    , actionFromId
    , actionId
    , simPerMove
    )

type ForeignRecomputeOpener =
    forall a. (DynamicRecomputeGame -> IO a) -> IO (Either AppError a)

-- | Walk `transcript` move-by-move, calling
-- `mcts_<backend>_recompute_move` at each move to read the foreign
-- backend's chosen action, visit vector, and parent-perspective
-- chosen-action equity. Builds an `EqStream` annotated with the
-- supplied backend tag and short build id (matching the sidecar
-- naming convention used by the cache).
foreignRecomputeEqStream
    :: Backend
    -- ^ which backend the opener routes to (for the EqStream tag)
    -> String
    -- ^ transcript hash (hex, 64 chars)
    -> String
    -- ^ short build id to attach to the emitted EqStream
    -> ForeignRecomputeOpener
    -> Transcript
    -> IO (Either AppError EqStream)
foreignRecomputeEqStream backend transcriptHash buildId opener transcript = do
    -- Open the foreign cdylib once per game so each game replay
    -- starts from a fresh `new_board`. Sharing a single board across
    -- games leaves it in the previous game's terminal state, which
    -- the C ABI rejects with `-1` on the next `recompute_move`.
    perGameResults <-
        sequenceEither
            [ recomputeGameMoves strictRecompute backend opener masterSeed rng sims gameRec
            | gameRec <- transcriptGames transcript
            ]
    pure $ case perGameResults of
        Left err -> Left err
        Right perGame ->
            Right
                EqStream
                    { eqTranscriptHash = transcriptHash
                    , eqBackend = backend
                    , eqBuildId = buildId
                    , eqRecords = concat perGame
                    }
  where
    config = transcriptConfig transcript
    envelope = transcriptEnvelope transcript
    masterSeed = runMasterSeed config
    rng = runRngSource config
    strictRecompute =
        rng == CppRng
            && envelopeBackend envelope == backend
            && envelopeBuildId envelope /= "logical"
    sims =
        max 1 $
            fromIntegral $
                simPerMove $
                    let i = runInitialSims config
                        p = runPerMoveSims config
                     in if i == p
                            then FixedSims (fromIntegral p)
                            else RampedSims (fromIntegral i) (fromIntegral p)

recomputeGameMoves
    :: Bool
    -> Backend
    -> ForeignRecomputeOpener
    -> Word64
    -> RngSource
    -> Word32
    -> GameTranscript
    -> IO (Either AppError [EqRecord])
recomputeGameMoves strictRecompute backend opener masterSeed rng sims gameTranscript =
    let perGameSeed = mix masterSeed (fromIntegral (gameId gameTranscript))
     in go perGameSeed initialBoard [] (gameMoves gameTranscript) 0 []
  where
    salt = backendNativeSalt rng backend

    go
        :: Word64
        -> Board
        -> [MoveRecord]
        -> [MoveRecord]
        -> Word64
        -> [EqRecord]
        -> IO (Either AppError [EqRecord])
    go !_ _ _ [] _ acc = pure (Right (reverse acc))
    go !seed board history (recorded : rest) !moveNo acc = do
        let effectiveSeed =
                seed
                    `xor` salt
                    `xor` fromIntegral (moveNo * 257 + 1)
        outcome <- recomputeRecordedCursor board history effectiveSeed
        case outcome of
            Left err -> pure (Left err)
            Right (rawChosen, _rawVisits, equity) ->
                let flipped = needsFlip (boardSideToMove board)
                    chosenId = applyFlip flipped rawChosen
                    visitsResult = decodeVisits (map (\(aid, n) -> (applyFlip flipped aid, n)) _rawVisits)
                 in case (actionFromId chosenId, visitsResult) of
                        (Nothing, _) ->
                            pure $
                                Left $
                                    FFIFailure
                                        backend
                                        "foreignRecomputeEqStream"
                                        ("invalid action id " <> show chosenId)
                        (_, Left badActionId) ->
                            pure $
                                Left $
                                    FFIFailure
                                        backend
                                        "foreignRecomputeEqStream"
                                        ("invalid visit action id " <> show badActionId)
                        (Just chosenAction, Right visits)
                            | strictRecompute
                                && (chosenAction /= moveChosen recorded || visitMismatch visits (moveVisits recorded)) ->
                                let recomputed =
                                        recorded
                                            { moveChosen = chosenAction
                                            , moveVisits = visits
                                            }
                                 in pure $
                                        Left $
                                            RecomputeMismatch
                                                backend
                                                (fromIntegral (gameId gameTranscript))
                                                (fromIntegral moveNo)
                                                recomputed
                                                recorded
                            | otherwise ->
                                let record =
                                        EqRecord
                                            { eqGameId = gameId gameTranscript
                                            , eqMoveIndex = moveIndex recorded
                                            , eqChosen = chosenAction
                                            , eqEquity = equity
                                            }
                                    -- Keep overlay recompute on the recorded line:
                                    -- foreign disagreement is evidence for this row,
                                    -- not the board state for subsequent rows.
                                    nextBoard = applyMove (moveChosen recorded) board
                                 in go seed nextBoard (history <> [recorded]) rest (moveNo + 1) (record : acc)

    recomputeRecordedCursor
        :: Board -> [MoveRecord] -> Word64 -> IO (Either AppError (Word8, [(Word8, Word32)], Double))
    recomputeRecordedCursor board history seed =
        flattenOpener =<< opener (recomputeFromFreshBoard board history seed)

    recomputeFromFreshBoard
        :: Board
        -> [MoveRecord]
        -> Word64
        -> DynamicRecomputeGame
        -> IO (Either AppError (Word8, [(Word8, Word32)], Double))
    recomputeFromFreshBoard targetBoard history seed game = do
        synced <- syncHistory game initialBoard history
        case synced of
            Left err -> pure (Left err)
            Right rebuilt
                | rebuilt /= targetBoard ->
                    pure $
                        Left $
                            FFIFailure
                                backend
                                "foreignRecomputeEqStream"
                                "Haskell board and replayed foreign history diverged"
                | otherwise -> recomputeGameRecomputeMove game seed sims

    flattenOpener
        :: Either AppError (Either AppError (Word8, [(Word8, Word32)], Double))
        -> IO (Either AppError (Word8, [(Word8, Word32)], Double))
    flattenOpener opened =
        pure $
            case opened of
                Left err -> Left err
                Right inner -> inner

    syncHistory :: DynamicRecomputeGame -> Board -> [MoveRecord] -> IO (Either AppError Board)
    syncHistory _ board [] = pure (Right board)
    syncHistory game board (record : rest) = do
        let rawAction = foreignActionId board (moveChosen record)
        applied <- recomputeGameApplyAction game rawAction
        case applied of
            Left err -> pure (Left err)
            Right () -> syncHistory game (applyMove (moveChosen record) board) rest

decodeVisits :: [(Word8, Word32)] -> Either Word8 [(Action, Word32)]
decodeVisits raw =
    traverse decodeOne raw
  where
    decodeOne (rawId, visits) =
        case actionFromId rawId of
            Just action -> Right (action, visits)
            Nothing -> Left rawId

visitMismatch :: [(Action, Word32)] -> [(Action, Word32)] -> Bool
visitMismatch recomputed recorded =
    any
        ( \(action, visits) ->
            lookupVisits action recorded /= visits
        )
        recomputed
  where
    lookupVisits action table =
        case lookup action table of
            Just visits -> visits
            Nothing -> 0

needsFlip :: Side -> Bool
needsFlip Hero = True
needsFlip Villain = False

applyFlip :: Bool -> Word8 -> Word8
applyFlip False aid = aid
applyFlip True aid
    | aid <= 80 = 80 - aid
    | aid <= 144 = 225 - aid
    | aid <= 208 = fromIntegral (353 - fromIntegral aid :: Int)
    | otherwise = aid

foreignActionId :: Board -> Action -> Word8
foreignActionId board action =
    applyFlip (needsFlip (boardSideToMove board)) (actionId action)

-- | Sequence a list of `IO (Either e a)` into `IO (Either e [a])`,
-- short-circuiting on the first `Left`.
sequenceEither :: [IO (Either e a)] -> IO (Either e [a])
sequenceEither = go []
  where
    go acc [] = pure (Right (reverse acc))
    go acc (action : rest) = do
        result <- action
        case result of
            Left err -> pure (Left err)
            Right value -> go (value : acc) rest
