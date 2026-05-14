module MCTS.CLI.Inspect
    ( runInspect
    ) where

import Data.List (intercalate, sortOn)
import MCTS.CLI.Command
import MCTS.CLI.Output (OutputFormat (..), OutputOptions (..), outputLine, renderError)
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
    outputLine $
        case outputFormat output of
            JsonFormat ->
                "[" <> intercalate "," [ "{\"hash\":\"" <> rowHash row <> "\",\"path\":\"" <> rowPath row <> "\"}" | row <- sortedRows] <> "]"
            _ ->
                unlines ("hash      backend          seed  games  path" : map renderRow sortedRows)
    pure 0
  where
    rowFor path = do
        mtime <- getModificationTime path
        decoded <- readTranscriptFile path
        let (backend, seed, games) =
                case decoded of
                    Right transcript ->
                        ( backendIdentifier (runBackend (transcriptConfig transcript))
                        , show (runMasterSeed (transcriptConfig transcript))
                        , show (length (transcriptGames transcript))
                        )
                    Left _ -> ("<bad>", "?", "?")
        pure (InspectRow (take 8 (takeBaseName path)) backend seed games path (show mtime))
    renderRow row =
        rowHash row
            <> "  "
            <> pad 15 (rowBackend row)
            <> "  "
            <> pad 5 (rowSeed row)
            <> "  "
            <> pad 5 (rowGames row)
            <> "  "
            <> rowPath row

data InspectRow = InspectRow
    { rowHash :: !String
    , rowBackend :: !String
    , rowSeed :: !String
    , rowGames :: !String
    , rowPath :: !FilePath
    , rowMtime :: !String
    }

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
                    if showWithEquity options
                        then do
                            _ <- writeEquitySidecar (showCacheDir options) (takeBaseName path) transcript
                            pure ()
                        else pure ()
                    outputLine (renderTranscript output options path transcript)
                    pure 0

renderTranscript :: OutputOptions -> ShowOptions -> FilePath -> Transcript -> String
renderTranscript output options path transcript =
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
                    [ renderMove action <> "=" <> show count <> equity
                    | (action, count) <- visits
                    , let equity = if showWithEquity options then ":equity=0.0000" else ""
                    ]
         in show (moveIndex record) <> " " <> renderMove (moveChosen record) <> " " <> suffix

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
                    outputLine ("top=" <> show (replayTopN options) <> " cache-states=" <> show (replayCacheStates options))
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
                    sidecars <- filter ((== takeBaseName path) . sidecarTranscriptHash) <$> listEquitySidecars (divergenceCacheDir options)
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
