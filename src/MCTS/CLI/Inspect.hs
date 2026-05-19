{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module MCTS.CLI.Inspect
    ( runInspect
    , InspectRow (..)
    , prepareReplayOverlays
    , renderInspectRows
    , renderTranscript
    ) where

import Control.Exception.Safe (IOException)
import qualified Control.Exception.Safe as Catch
import Control.Monad.IO.Class (liftIO)
import qualified Data.ByteString as BS
import Data.List (intercalate, sortOn)
import qualified Data.Text as Text
import MCTS.CLI.Command
import MCTS.CLI.Output (OutputFormat (..), OutputOptions (..), outputLine, renderErrorString)
import qualified MCTS.CLI.Tui.Replay as ReplayTui
import MCTS.Driver (makeLogicalEnvelope)
import qualified MCTS.Engine.ForeignRecompute as ForeignRecompute
import qualified MCTS.Engine.Recompute as Recompute
import qualified MCTS.Env as Env
import qualified MCTS.Error
import MCTS.FFI.CppFunctional (cppFunctionalLibraryPath, withCppFunctionalRecomputeGame)
import MCTS.FFI.CppImperative (cppImperativeLibraryPath, withCppImperativeRecomputeGame)
import MCTS.FFI.CppLegacy (cppLegacyLibraryPath, withCppLegacyRecomputeGame)
import MCTS.FFI.Rust (rustLibraryPath, withRustRecomputeGame)
import MCTS.Notation (renderMove, renderWinner)
import MCTS.Plan (Plan (..), PlanOptions (..), renderPlanWith, writePlanFile)
import MCTS.Transcript
import MCTS.Transcript.EquitySidecar
import MCTS.Types
import MCTS.Verify.Divergence
import System.Directory (doesFileExist, getModificationTime)
import System.Exit (ExitCode (..))
import System.FilePath (takeBaseName)
import System.IO (hIsTerminalDevice, stdin)

runInspect :: InspectCommand -> Env.App ExitCode
runInspect command = do
    env <- Env.askEnv
    code <- liftIO (inspectWithOutput (Env.envOutputOptions env) command)
    pure (intToExitCode code)

inspectWithOutput :: OutputOptions -> InspectCommand -> IO Int
inspectWithOutput output command =
    case command of
        InspectList cacheDir -> inspectList output cacheDir
        InspectShow options -> inspectShow output options
        InspectReplay options -> inspectReplay output options
        InspectCache (CacheList cacheDir) -> inspectCacheList output cacheDir
        InspectCache (CachePrune keepCurrent cacheDir planOptions) -> inspectCachePrune output keepCurrent cacheDir planOptions
        InspectDivergence options -> inspectDivergence output options

intToExitCode :: Int -> ExitCode
intToExitCode 0 = ExitSuccess
intToExitCode n = ExitFailure n

inspectList :: OutputOptions -> Maybe FilePath -> IO Int
inspectList output cacheDir = do
    files <- listTranscriptFiles cacheDir
    rows <- mapM rowFor files
    let sortedRows = reverse (sortOn rowMtime rows)
    outputLine (renderInspectRows output sortedRows)
    pure 0
  where
    rowFor path = do
        mtime <- getModificationTime path
        decoded <- readTranscriptFile path
        let (backend, seed, games, threading, sims, totalMoves) =
                case decoded of
                    Right transcript ->
                        ( backendIdentifier (runBackend (transcriptConfig transcript))
                        , show (runMasterSeed (transcriptConfig transcript))
                        , show (length (transcriptGames transcript))
                        , threadingName (runThreading (transcriptConfig transcript))
                        , show (runInitialSims (transcriptConfig transcript))
                            <> ":"
                            <> show (runPerMoveSims (transcriptConfig transcript))
                        , show (sum (map (length . gameMoves) (transcriptGames transcript)))
                        )
                    Left _ -> ("<bad>", "?", "?", "?", "?", "?")
        pure
            ( InspectRow
                (take 8 (takeBaseName path))
                backend
                seed
                games
                threading
                sims
                totalMoves
                path
                (show mtime)
            )
data InspectRow = InspectRow
    { rowHash :: !String
    , rowBackend :: !String
    , rowSeed :: !String
    , rowGames :: !String
    , rowThreading :: !String
    , rowSims :: !String
    , rowTotalMoves :: !String
    , rowPath :: !FilePath
    , rowMtime :: !String
    }

renderInspectRows :: OutputOptions -> [InspectRow] -> String
renderInspectRows output rows =
    case outputFormat output of
        JsonFormat ->
            "["
                <> intercalate
                    ","
                    [ "{\"hash\":\""
                        <> rowHash row
                        <> "\",\"backend\":\""
                        <> rowBackend row
                        <> "\",\"seed\":"
                        <> rowSeed row
                        <> ",\"games\":"
                        <> rowGames row
                        <> ",\"threading\":\""
                        <> rowThreading row
                        <> "\",\"sims\":\""
                        <> rowSims row
                        <> "\",\"total_moves\":"
                        <> rowTotalMoves row
                        <> ",\"mtime\":\""
                        <> rowMtime row
                        <> "\",\"path\":\""
                        <> rowPath row
                        <> "\"}"
                    | row <- rows
                    ]
                <> "]"
        _ ->
            unlines
                ( "hash      backend          seed  games  thr  sims      moves  mtime                         path"
                    : map renderInspectRow rows
                )

renderInspectRow :: InspectRow -> String
renderInspectRow row =
    rowHash row
        <> "  "
        <> pad 15 (rowBackend row)
        <> "  "
        <> pad 5 (rowSeed row)
        <> "  "
        <> pad 5 (rowGames row)
        <> "  "
        <> pad 4 (rowThreading row)
        <> "  "
        <> pad 8 (rowSims row)
        <> "  "
        <> pad 5 (rowTotalMoves row)
        <> "  "
        <> pad 28 (rowMtime row)
        <> "  "
        <> rowPath row

inspectShow :: OutputOptions -> ShowOptions -> IO Int
inspectShow output options = do
    found <- lookupByPrefix (showCacheDir options) (showRef options)
    case found of
        Left err -> outputLine (renderErrorString output err) >> pure 1
        Right ref -> do
            let path = transcriptRefPath ref
            decoded <- readTranscriptFile path
            case decoded of
                Left err -> outputLine (renderErrorString output err) >> pure 1
                Right transcript -> do
                    stream <-
                        if showWithEquity options
                            then do
                                let envelope = transcriptEnvelope transcript
                                    buildId = envelopeBuildId envelope
                                    transcriptHash = takeBaseName path
                                case Recompute.recomputeEqStream transcriptHash buildId transcript of
                                    Right stream -> do
                                        _ <- writeEquitySidecarStream (showCacheDir options) transcript stream
                                        pure (Just stream)
                                    Left err -> outputLine (renderErrorString output err) >> pure Nothing
                            else pure Nothing
                    outputLine (renderTranscript output options path stream transcript)
                    pure 0

renderTranscript
    :: OutputOptions -> ShowOptions -> FilePath -> Maybe EqStream -> Transcript -> String
renderTranscript output options path stream transcript =
    case outputFormat output of
        JsonFormat ->
            "{\"path\":\""
                <> path
                <> "\",\"backend\":\""
                <> backendIdentifier (runBackend config)
                <> "\",\"games\":"
                <> show (length (transcriptGames transcript))
                <> renderJsonEnvelope
                <> "}"
        _ ->
            unlines $
                [ "path: " <> path
                , "backend: " <> backendIdentifier (runBackend config)
                , "seed: " <> show (runMasterSeed config)
                , "games: " <> show (length (transcriptGames transcript))
                ]
                    <> renderEnvelopeBlock
                    <> concatMap renderGame (transcriptGames transcript)
  where
    config = transcriptConfig transcript
    envelope = transcriptEnvelope transcript
    topN = showTopN options
    renderJsonEnvelope =
        if showEnvelope options
            then
                ",\"envelope\":{\"version\":"
                    <> show (envelopeVersion envelope)
                    <> ",\"backend\":\""
                    <> backendIdentifier (envelopeBackend envelope)
                    <> "\",\"host_arch\":\""
                    <> envelopeHostArch envelope
                    <> "\",\"build_id\":\""
                    <> envelopeBuildId envelope
                    <> "\"}"
            else ""
    renderEnvelopeBlock =
        if showEnvelope options
            then
                [ "envelope.version: " <> show (envelopeVersion envelope)
                , "envelope.backend: " <> backendIdentifier (envelopeBackend envelope)
                , "envelope.host_arch: " <> envelopeHostArch envelope
                , "envelope.build_id: " <> envelopeBuildId envelope
                ]
            else []
    renderGame game =
        ("game " <> show (gameId game) <> " winner=" <> renderWinner (gameWinner game))
            : map renderRecord (gameMoves game)
    renderRecord record =
        let visits = if topN == 0 then moveVisits record else take topN (moveVisits record)
            suffix =
                intercalate
                    " "
                    [ renderMove action <> "=" <> show count
                    | (action, count) <- visits
                    ]
            equitySuffix =
                case (showWithEquity options, stream >>= equityFor record) of
                    (True, Just equity) -> " equity=" <> showEquity equity
                    (True, Nothing) -> " equity=NA"
                    _ -> ""
         in show (moveIndex record) <> " " <> renderMove (moveChosen record) <> " " <> suffix <> equitySuffix

equityFor :: MoveRecord -> EqStream -> Maybe Double
equityFor record stream =
    case [ eqEquity eq
         | eq <- eqRecords stream
         , eqMoveIndex eq == moveIndex record
         , eqChosen eq == moveChosen record
         ] of
        equity : _ -> Just equity
        [] -> Nothing

showEquity :: Double -> String
showEquity value =
    let scaled = fromInteger (round (value * 10000)) / 10000 :: Double
     in show scaled

inspectReplay :: OutputOptions -> ReplayOptions -> IO Int
inspectReplay output options = do
    found <- lookupByPrefix (replayCacheDir options) (replayRef options)
    case found of
        Left err -> outputLine (renderErrorString output err) >> pure 1
        Right ref -> do
            let path = transcriptRefPath ref
            decoded <- readTranscriptFile path
            case decoded of
                Left err -> outputLine (renderErrorString output err) >> pure 1
                Right transcript -> do
                    interactive <- hIsTerminalDevice stdin
                    if interactive
                        then runReplayInteractive options (takeBaseName path) transcript
                        else runReplayNonInteractive output options path transcript

-- | Sprint 7.4: interactive `brick` TUI for `mcts inspect replay`.
-- Dispatches to `MCTS.CLI.Tui.Replay.runReplayTuiWithOverlays` so
-- the operator gets forward/back navigation plus the per-backend
-- equity overlay column populated from cached `.eq` sidecars. The
-- `--cache-states` operator flag overrides the default snapshot
-- cache size on the replay state.
runReplayInteractive :: ReplayOptions -> String -> Transcript -> IO Int
runReplayInteractive options hashValue transcript = do
    (overlays, recomputeMessage) <- prepareReplayOverlays (replayCacheDir options) hashValue transcript
    let baseState = ReplayTui.initialReplayStateWithOverlays hashValue transcript overlays
        configuredState =
            baseState
                { ReplayTui.replayCacheStates = max 1 (replayCacheStates options)
                , ReplayTui.replayOverlayLoader =
                    Just (loadReplayOverlay (replayCacheDir options) hashValue transcript)
                , ReplayTui.replayOverlayCandidates = allBackends
                , ReplayTui.replayMessage =
                    case recomputeMessage of
                        Nothing -> ReplayTui.replayMessage baseState
                        Just message -> message <> " | " <> ReplayTui.replayMessage baseState
                }
    _ <- ReplayTui.runReplayTuiFromState configuredState
    pure 0

-- | Load cached replay overlays and fill the originator column on
-- cache miss. The recompute path performs the visit-count check for
-- `--rng cpp` transcripts before the TUI starts; failures are returned
-- as a status-line message so the replay navigator can still open.
prepareReplayOverlays :: Maybe FilePath -> String -> Transcript -> IO ([EqStream], Maybe String)
prepareReplayOverlays cacheDir hashValue transcript = do
    overlays <- loadOverlayStreams cacheDir hashValue
    if originatorOverlayPresent hashValue transcript overlays
        then pure (overlays, Nothing)
        else do
            recomputed <- recomputeOriginatorOverlay hashValue transcript
            case recomputed of
                OverlaySkipped message -> pure (overlays, Just message)
                OverlayFailed err ->
                    pure
                        ( overlays
                        , Just ("recompute failed: " <> Text.unpack (MCTS.Error.renderError err))
                        )
                OverlayReady stream -> do
                    written <-
                        (Right <$> writeEquitySidecarStream cacheDir transcript stream)
                            `Catch.catch` (\e -> pure (Left (e :: IOException)))
                    let message =
                            case written of
                                Right _ ->
                                    "recomputed "
                                        <> backendIdentifier (eqBackend stream)
                                        <> " replay equity sidecar"
                                Left err ->
                                    "recomputed "
                                        <> backendIdentifier (eqBackend stream)
                                        <> " replay equity but sidecar write failed: "
                                        <> show err
                    pure (overlays <> [stream], Just message)

data OverlayRecomputeResult
    = OverlayReady !EqStream
    | OverlaySkipped !String
    | OverlayFailed !MCTS.Error.AppError

originatorOverlayPresent :: String -> Transcript -> [EqStream] -> Bool
originatorOverlayPresent hashValue transcript =
    any
        ( \stream ->
            eqTranscriptHash stream == hashValue
                && eqBackend stream == originBackend
                && eqBuildId stream == originBuildId
        )
  where
    envelope = transcriptEnvelope transcript
    originBackend = envelopeBackend envelope
    originBuildId = envelopeBuildId envelope

recomputeOriginatorOverlay :: String -> Transcript -> IO OverlayRecomputeResult
recomputeOriginatorOverlay hashValue transcript =
    recomputeBackendOverlay hashValue transcript (envelopeBackend envelope) (envelopeBuildId envelope)
  where
    envelope = transcriptEnvelope transcript

loadReplayOverlay
    :: Maybe FilePath -> String -> Transcript -> Backend -> IO ReplayTui.ReplayOverlayLoadResult
loadReplayOverlay cacheDir hashValue transcript backend = do
    let buildId = envelopeBuildId (makeLogicalEnvelope backend (runRngSource (transcriptConfig transcript)))
    recomputed <- recomputeBackendOverlay hashValue transcript backend buildId
    case recomputed of
        OverlaySkipped message -> pure (ReplayTui.ReplayOverlaySkipped message)
        OverlayFailed err -> pure (ReplayTui.ReplayOverlayFailed (Text.unpack (MCTS.Error.renderError err)))
        OverlayReady stream -> do
            written <-
                (Right <$> writeEquitySidecarStream cacheDir transcript stream)
                    `Catch.catch` (\e -> pure (Left (e :: IOException)))
            pure $
                case written of
                    Right _ -> ReplayTui.ReplayOverlayLoaded stream
                    Left err ->
                        ReplayTui.ReplayOverlayFailed
                            ( "sidecar write failed for "
                                <> backendIdentifier (eqBackend stream)
                                <> ": "
                                <> show err
                            )

recomputeBackendOverlay :: String -> Transcript -> Backend -> String -> IO OverlayRecomputeResult
recomputeBackendOverlay hashValue transcript backend buildId =
    case backend of
        Haskell ->
            pure $
                case Recompute.recomputeEqStream hashValue buildId (retagTranscript Haskell buildId transcript) of
                    Left err -> OverlayFailed err
                    Right stream -> OverlayReady stream
        CppLegacy ->
            recomputeForeign CppLegacy cppLegacyLibraryPath withCppLegacyRecomputeGame
        CppImperative ->
            recomputeForeign CppImperative cppImperativeLibraryPath withCppImperativeRecomputeGame
        CppFunctional ->
            recomputeForeign CppFunctional cppFunctionalLibraryPath withCppFunctionalRecomputeGame
        Rust ->
            recomputeForeign Rust rustLibraryPath withRustRecomputeGame
  where
    retagTranscript taggedBackend taggedBuildId current =
        current
            { transcriptConfig = (transcriptConfig current){runBackend = taggedBackend}
            , transcriptEnvelope =
                (transcriptEnvelope current)
                    { envelopeBackend = taggedBackend
                    , envelopeBuildId = taggedBuildId
                    }
            }

    recomputeForeign
        :: Backend
        -> FilePath
        -> ForeignRecompute.ForeignRecomputeOpener
        -> IO OverlayRecomputeResult
    recomputeForeign foreignBackend libPath opener = do
        present <- doesFileExist libPath
        if not present
            then
                pure $
                    OverlaySkipped
                        ( "no cached "
                            <> backendIdentifier foreignBackend
                            <> " replay sidecar and shared library is not built"
                        )
            else do
                result <-
                    ForeignRecompute.foreignRecomputeEqStream
                        foreignBackend
                        hashValue
                        buildId
                        opener
                        transcript
                        `Catch.catch` ( \(e :: IOException) ->
                                            pure (Left (MCTS.Error.FFIFailure foreignBackend "foreignRecomputeEqStream" (show e)))
                                      )
                pure $
                    case result of
                        Left err -> OverlayFailed err
                        Right stream -> OverlayReady stream

-- | Load every cached `EqStream` whose transcript-hash slot matches
-- `hashValue`. Read failures and decode failures silently drop the
-- offending sidecar so a corrupt cache slot does not block the TUI.
loadOverlayStreams :: Maybe FilePath -> String -> IO [EqStream]
loadOverlayStreams cacheDir hashValue = do
    entries <-
        filter ((== hashValue) . sidecarTranscriptHash)
            <$> listEquitySidecars cacheDir
    fmap (concatMap pickRight) (mapM readEntry entries)
  where
    pickRight x = case x of
        Right s -> [s]
        Left () -> []

    readEntry :: SidecarEntry -> IO (Either () EqStream)
    readEntry entry = do
        bytes <-
            ( do
                content <- BS.readFile (sidecarEqPath entry)
                pure (Right content)
            )
                `Catch.catch` (\(_ :: IOException) -> pure (Left ()))
        pure $ case bytes of
            Left _ -> Left ()
            Right raw -> case decodeEqStream raw of
                Left _ -> Left ()
                Right stream -> Right stream

-- | Non-TTY fallback: render the same one-line status that callers
-- previously consumed when redirecting `mcts inspect replay` into
-- another process or a fixture.
runReplayNonInteractive
    :: OutputOptions -> ReplayOptions -> FilePath -> Transcript -> IO Int
runReplayNonInteractive _output options path transcript = do
    let totalMoves = sum (map (length . gameMoves) (transcriptGames transcript))
        hashValue = take 8 (takeBaseName path)
    outputLine (hashValue <> " | move 0 / " <> show totalMoves <> " | press ? for help")
    outputLine
        ("top=" <> show (replayTopN options) <> " cache-states=" <> show (replayCacheStates options))
    pure 0

inspectCacheList :: OutputOptions -> Maybe FilePath -> IO Int
inspectCacheList output cacheDir = do
    root <- resolveCacheRoot cacheDir
    sidecars <- listEquitySidecars cacheDir
    rows <- mapM (cacheRowFor root) sidecars
    outputLine $
        case outputFormat output of
            JsonFormat ->
                "["
                    <> intercalate
                        ","
                        [ "{\"transcript\":\""
                            <> cacheTranscriptHash row
                            <> "\",\"originator\":"
                            <> cacheOriginJson row
                            <> ",\"backend\":\""
                            <> backendIdentifier (cacheBackend row)
                            <> "\",\"build_id\":\""
                            <> cacheBuildId row
                            <> "\",\"path\":\""
                            <> cacheEqPath row
                            <> "\"}"
                        | row <- rows
                        ]
                    <> "]"
            _ ->
                if null rows
                    then "no equity sidecars cached"
                    else
                        unlines ("transcript origin      backend          build-id          path" : map renderSidecar rows)
    pure 0
  where
    renderSidecar row =
        take 8 (cacheTranscriptHash row)
            <> "  "
            <> pad 10 (cacheOriginLabel row)
            <> "  "
            <> pad 15 (backendIdentifier (cacheBackend row))
            <> "  "
            <> pad 16 (take 16 (cacheBuildId row))
            <> "  "
            <> cacheEqPath row

inspectCachePrune :: OutputOptions -> Bool -> Maybe FilePath -> PlanOptions -> IO Int
inspectCachePrune output keepCurrent cacheDir planOptions = do
    stale <- prunableEquitySidecars cacheDir keepCurrent
    let plan = Plan "inspect cache prune" stale
        renderedPlan = renderPlanWith renderPruneStep plan
    writePlanFile (planFile planOptions) renderedPlan
    if planDryRun planOptions
        then outputLine renderedPlan
        else do
            mapM_ removeEquitySidecar stale
            outputLine $
                case outputFormat output of
                    JsonFormat -> "{\"pruned\":" <> show (length stale) <> "}"
                    _ -> "pruned " <> show (length stale) <> " equity sidecar" <> if length stale == 1 then "" else "s"
    pure 0

renderPruneStep :: SidecarEntry -> String
renderPruneStep entry =
    "delete "
        <> sidecarEqPath entry
        <> " and "
        <> sidecarEnvelopePath entry

data CacheSidecarRow = CacheSidecarRow
    { cacheTranscriptHash :: !String
    , cacheOrigin :: !(Maybe Bool)
    , cacheBackend :: !Backend
    , cacheBuildId :: !String
    , cacheEqPath :: !FilePath
    }

cacheRowFor :: FilePath -> SidecarEntry -> IO CacheSidecarRow
cacheRowFor root entry = do
    decoded <- readTranscriptFile (transcriptPath root (sidecarTranscriptHash entry))
    let origin =
            case decoded of
                Right transcript -> Just (sidecarIsOriginator transcript entry)
                Left _ -> Nothing
    pure
        CacheSidecarRow
            { cacheTranscriptHash = sidecarTranscriptHash entry
            , cacheOrigin = origin
            , cacheBackend = sidecarBackend entry
            , cacheBuildId = sidecarBuildId entry
            , cacheEqPath = sidecarEqPath entry
            }

cacheOriginLabel :: CacheSidecarRow -> String
cacheOriginLabel row =
    case cacheOrigin row of
        Just True -> "originator"
        Just False -> "foreign"
        Nothing -> "unknown"

cacheOriginJson :: CacheSidecarRow -> String
cacheOriginJson row =
    case cacheOrigin row of
        Just True -> "true"
        Just False -> "false"
        Nothing -> "null"

inspectDivergence :: OutputOptions -> DivergenceOptions -> IO Int
inspectDivergence output options = do
    found <- lookupByPrefix (divergenceCacheDir options) (divergenceRef options)
    case found of
        Left err -> outputLine (renderErrorString output err) >> pure 1
        Right ref -> do
            let path = transcriptRefPath ref
            decoded <- readTranscriptFile path
            case decoded of
                Left err -> outputLine (renderErrorString output err) >> pure 1
                Right transcript -> do
                    let transcriptHash = takeBaseName path
                    sidecars <-
                        filter ((== transcriptHash) . sidecarTranscriptHash)
                            <$> listEquitySidecars (divergenceCacheDir options)
                    let origin = backendIdentifier (envelopeBackend (transcriptEnvelope transcript))
                    sidecarRows <- case sidecars of
                        [] ->
                            pure
                                [
                                    ( origin <> "/origin"
                                    , divergenceRate transcript transcript
                                    )
                                ]
                        entries -> mapM (loadSidecarMetrics transcript origin) entries
                    foreignRows <- foreignRecomputeRows transcriptHash transcript origin
                    let rows = sidecarRows <> foreignRows
                    outputLine (renderDivergence output transcriptHash (length sidecars) rows)
                    pure 0

-- | Sprint 7.5: when a foreign cdylib is present in the worktree,
-- drive `mcts_<backend>_recompute_move` through it for the current
-- transcript and add one row per available backend to the divergence
-- output. The row label is `<origin>/foreign:<backend>` so consumers
-- can tell sidecar-derived metrics from live-FFI-derived ones.
foreignRecomputeRows :: String -> Transcript -> String -> IO [(String, DivergenceMetrics)]
foreignRecomputeRows transcriptHash transcript origin = do
    rows <-
        mapM
            (tryForeignRow transcript origin)
            [
                ( CppImperative
                , cppImperativeLibraryPath
                , ForeignRecompute.foreignRecomputeEqStream
                    CppImperative
                    transcriptHash
                    "live"
                    withCppImperativeRecomputeGame
                    transcript
                )
            ,
                ( CppFunctional
                , cppFunctionalLibraryPath
                , ForeignRecompute.foreignRecomputeEqStream
                    CppFunctional
                    transcriptHash
                    "live"
                    withCppFunctionalRecomputeGame
                    transcript
                )
            ,
                ( Rust
                , rustLibraryPath
                , ForeignRecompute.foreignRecomputeEqStream
                    Rust
                    transcriptHash
                    "live"
                    withRustRecomputeGame
                    transcript
                )
            ]
    pure (concat rows)

tryForeignRow
    :: Transcript
    -> String
    -> (Backend, FilePath, IO (Either MCTS.Error.AppError EqStream))
    -> IO [(String, DivergenceMetrics)]
tryForeignRow transcript origin (backend, libPath, driver) = do
    present <- doesFileExist libPath
    if not present
        then pure []
        else do
            result <-
                driver
                    `Catch.catch` ( \(e :: IOException) -> pure (Left (MCTS.Error.FFIFailure backend "foreignRecomputeEqStream" (show e)))
                                  )
            case result of
                Left _ -> pure []
                Right stream ->
                    pure
                        [
                            ( origin <> "/foreign:" <> backendIdentifier backend
                            , divergenceVsEqStream transcript stream
                            )
                        ]

-- | Sprint 7.5: load a `.eq` sidecar and compute the
-- transcript-vs-recompute divergence metrics through
-- `divergenceVsEqStream`. On decode failure, fall back to the
-- self-pair zero metrics so the CLI still emits a row.
loadSidecarMetrics :: Transcript -> String -> SidecarEntry -> IO (String, DivergenceMetrics)
loadSidecarMetrics transcript origin entry = do
    bytes <-
        ( do
            content <- BS.readFile (sidecarEqPath entry)
            pure (Right content)
        )
            `Catch.catch` (\e -> pure (Left (e :: IOException)))
    case bytes of
        Left _ -> pure (label, divergenceRate transcript transcript)
        Right raw -> case decodeEqStream raw of
            Left _ -> pure (label, divergenceRate transcript transcript)
            Right stream -> pure (label, divergenceVsEqStream transcript stream)
  where
    label = origin <> "/" <> backendIdentifier (sidecarBackend entry)

renderDivergence :: OutputOptions -> String -> Int -> [(String, DivergenceMetrics)] -> String
renderDivergence output hashValue sidecarCount rows =
    case outputFormat output of
        JsonFormat ->
            "{\"transcript\":\""
                <> hashValue
                <> "\",\"cached_sidecars\":"
                <> show sidecarCount
                <> ",\"rows\":["
                <> intercalate
                    ","
                    [ "{\"backend_pair\":\""
                        <> label
                        <> "\",\"visit_disagreement_rate\":"
                        <> show (visitDisagreementRate metrics)
                        <> ",\"move_disagreement_rate\":"
                        <> show (moveDisagreementRate metrics)
                        <> ",\"equity_l2_drift\":"
                        <> show (equityL2Drift metrics)
                        <> "}"
                    | (label, metrics) <- rows
                    ]
                <> "]}"
        _ ->
            unlines
                ( ( "divergence "
                        <> take 8 hashValue
                        <> " cached_sidecars="
                        <> show sidecarCount
                  )
                    : "backend-pair visit_disagreement_rate move_disagreement_rate equity_l2_drift"
                    : [renderDivergenceMetrics label metrics | (label, metrics) <- rows]
                )

pad :: Int -> String -> String
pad n value = take n (value <> repeat ' ')
