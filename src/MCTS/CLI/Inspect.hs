module MCTS.CLI.Inspect
    ( runInspect
    , InspectRow (..)
    , renderInspectRows
    , renderTranscript
    ) where

import Data.List (intercalate, sortOn)
import MCTS.CLI.Command
import MCTS.CLI.Output (OutputFormat (..), OutputOptions (..), outputLine, renderError)
import qualified MCTS.Engine.Recompute as Recompute
import MCTS.Notation (renderMove, renderWinner)
import MCTS.Transcript
import MCTS.Transcript.EquitySidecar
import MCTS.Types
import MCTS.Verify.Divergence
import System.Directory (getModificationTime)
import System.FilePath (takeBaseName)

runInspect :: OutputOptions -> InspectCommand -> IO Int
runInspect output command =
    case command of
        InspectList cacheDir -> inspectList output cacheDir
        InspectShow options -> inspectShow output options
        InspectReplay options -> inspectReplay options
        InspectCache (CacheList cacheDir) -> inspectCacheList output cacheDir
        InspectCache (CachePrune keepCurrent cacheDir) -> inspectCachePrune output keepCurrent cacheDir
        InspectDivergence options -> inspectDivergence output options

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
        Left err -> outputLine (renderError err) >> pure 1
        Right path -> do
            decoded <- readTranscriptFile path
            case decoded of
                Left err -> outputLine (renderError err) >> pure 1
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
                                    Left err -> outputLine (renderError err) >> pure Nothing
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

inspectReplay :: ReplayOptions -> IO Int
inspectReplay options = do
    found <- lookupByPrefix (replayCacheDir options) (replayRef options)
    case found of
        Left err -> outputLine (renderError err) >> pure 1
        Right path -> do
            decoded <- readTranscriptFile path
            case decoded of
                Left err -> outputLine (renderError err) >> pure 1
                Right transcript -> do
                    let totalMoves = sum (map (length . gameMoves) (transcriptGames transcript))
                        hashValue = take 8 (takeBaseName path)
                    outputLine (hashValue <> " | move 0 / " <> show totalMoves <> " | press ? for help")
                    outputLine
                        ("top=" <> show (replayTopN options) <> " cache-states=" <> show (replayCacheStates options))
                    pure 0

inspectCacheList :: OutputOptions -> Maybe FilePath -> IO Int
inspectCacheList output cacheDir = do
    sidecars <- listEquitySidecars cacheDir
    outputLine $
        case outputFormat output of
            JsonFormat ->
                "["
                    <> intercalate
                        ","
                        [ "{\"transcript\":\""
                            <> sidecarTranscriptHash entry
                            <> "\",\"backend\":\""
                            <> backendIdentifier (sidecarBackend entry)
                            <> "\",\"build_id\":\""
                            <> sidecarBuildId entry
                            <> "\",\"path\":\""
                            <> sidecarEqPath entry
                            <> "\"}"
                        | entry <- sidecars
                        ]
                    <> "]"
            _ ->
                if null sidecars
                    then "no equity sidecars cached"
                    else unlines ("transcript backend          build-id          path" : map renderSidecar sidecars)
    pure 0
  where
    renderSidecar entry =
        take 8 (sidecarTranscriptHash entry)
            <> "  "
            <> pad 15 (backendIdentifier (sidecarBackend entry))
            <> "  "
            <> pad 16 (take 16 (sidecarBuildId entry))
            <> "  "
            <> sidecarEqPath entry

inspectCachePrune :: OutputOptions -> Bool -> Maybe FilePath -> IO Int
inspectCachePrune output keepCurrent cacheDir = do
    count <- pruneEquitySidecars cacheDir keepCurrent
    outputLine $
        case outputFormat output of
            JsonFormat -> "{\"pruned\":" <> show count <> "}"
            _ -> "pruned " <> show count <> " equity sidecar" <> if count == 1 then "" else "s"
    pure 0

inspectDivergence :: OutputOptions -> DivergenceOptions -> IO Int
inspectDivergence output options = do
    found <- lookupByPrefix (divergenceCacheDir options) (divergenceRef options)
    case found of
        Left err -> outputLine (renderError err) >> pure 1
        Right path -> do
            decoded <- readTranscriptFile path
            case decoded of
                Left err -> outputLine (renderError err) >> pure 1
                Right transcript -> do
                    sidecars <-
                        filter ((== takeBaseName path) . sidecarTranscriptHash)
                            <$> listEquitySidecars (divergenceCacheDir options)
                    let origin = backendIdentifier (envelopeBackend (transcriptEnvelope transcript))
                        labels =
                            case sidecars of
                                [] -> [origin <> "/origin"]
                                entries -> [origin <> "/" <> backendIdentifier (sidecarBackend entry) | entry <- entries]
                        metrics = divergenceRate transcript transcript
                    outputLine (renderDivergence output (takeBaseName path) (length sidecars) labels metrics)
                    pure 0

renderDivergence :: OutputOptions -> String -> Int -> [String] -> DivergenceMetrics -> String
renderDivergence output hashValue sidecarCount labels metrics =
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
                    | label <- labels
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
                    : map (`renderDivergenceMetrics` metrics) labels
                )

pad :: Int -> String -> String
pad n value = take n (value <> repeat ' ')
