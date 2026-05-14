module MCTS.Transcript.EquitySidecar
    ( EqRecord (..)
    , EqStream (..)
    , SidecarEntry (..)
    , encodeEqStream
    , decodeEqStream
    , equityStreamForTranscript
    , sidecarDirectory
    , sidecarStem
    , writeEquitySidecar
    , listEquitySidecars
    , pruneEquitySidecars
    , isCurrentSidecar
    ) where

import qualified Data.ByteString.Char8 as C8
import Data.List (sortOn)
import Data.Word (Word16, Word32)
import MCTS.Transcript (hostArch, resolveCacheRoot)
import MCTS.Types
import System.Directory
    ( createDirectoryIfMissing
    , doesDirectoryExist
    , doesFileExist
    , listDirectory
    , removeFile
    )
import System.FilePath (replaceExtension, takeExtension, takeFileName, (</>))
import Text.Read (readMaybe)

data EqRecord = EqRecord
    { eqGameId :: !Word32
    , eqMoveIndex :: !Word16
    , eqChosen :: !Action
    , eqEquity :: !Double
    }
    deriving (Eq, Show, Read)

data EqStream = EqStream
    { eqTranscriptHash :: !String
    , eqBackend :: !Backend
    , eqBuildId :: !String
    , eqRecords :: ![EqRecord]
    }
    deriving (Eq, Show, Read)

data SidecarEntry = SidecarEntry
    { sidecarTranscriptHash :: !String
    , sidecarBackend :: !Backend
    , sidecarBuildId :: !String
    , sidecarEqPath :: !FilePath
    , sidecarEnvelopePath :: !FilePath
    }
    deriving (Eq, Show)

encodeEqStream :: EqStream -> C8.ByteString
encodeEqStream stream = C8.pack (show stream)

decodeEqStream :: C8.ByteString -> Either String EqStream
decodeEqStream bytes =
    case readMaybe (C8.unpack bytes) of
        Just stream -> Right stream
        Nothing -> Left "bad equity sidecar stream"

equityStreamForTranscript :: String -> Transcript -> EqStream
equityStreamForTranscript transcriptHash transcript =
    EqStream
        { eqTranscriptHash = transcriptHash
        , eqBackend = envelopeBackend envelope
        , eqBuildId = envelopeBuildId envelope
        , eqRecords =
            [ EqRecord
                { eqGameId = gameId game
                , eqMoveIndex = moveIndex record
                , eqChosen = moveChosen record
                , eqEquity = 0.0
                }
            | game <- transcriptGames transcript
            , record <- gameMoves game
            ]
        }
  where
    envelope = transcriptEnvelope transcript

sidecarDirectory :: FilePath -> String -> FilePath
sidecarDirectory root transcriptHash =
    root </> "transcripts" </> hostArch </> transcriptHash

sidecarStem :: Backend -> String -> String
sidecarStem backend buildId =
    backendIdentifier backend <> "-" <> take 16 buildId

writeEquitySidecar :: Maybe FilePath -> String -> Transcript -> IO SidecarEntry
writeEquitySidecar explicit transcriptHash transcript = do
    root <- resolveCacheRoot explicit
    let envelope = transcriptEnvelope transcript
        dir = sidecarDirectory root transcriptHash
        stem = sidecarStem (envelopeBackend envelope) (envelopeBuildId envelope)
        eqPath = dir </> stem <> ".eq"
        envelopePath = dir </> stem <> ".envelope"
        stream = equityStreamForTranscript transcriptHash transcript
    createDirectoryIfMissing True dir
    C8.writeFile eqPath (encodeEqStream stream)
    writeFile envelopePath (show envelope <> "\n")
    pure
        SidecarEntry
            { sidecarTranscriptHash = transcriptHash
            , sidecarBackend = envelopeBackend envelope
            , sidecarBuildId = envelopeBuildId envelope
            , sidecarEqPath = eqPath
            , sidecarEnvelopePath = envelopePath
            }

listEquitySidecars :: Maybe FilePath -> IO [SidecarEntry]
listEquitySidecars explicit = do
    root <- resolveCacheRoot explicit
    let archDir = root </> "transcripts" </> hostArch
    exists <- doesDirectoryExist archDir
    if not exists
        then pure []
        else do
            names <- listDirectory archDir
            entries <- concat <$> mapM (listHashDirectory archDir) names
            pure (sortOn sidecarSortKey entries)

pruneEquitySidecars :: Maybe FilePath -> Bool -> IO Int
pruneEquitySidecars explicit keepCurrent = do
    entries <- listEquitySidecars explicit
    let stale =
            if keepCurrent
                then filter (not . isCurrentSidecar) entries
                else entries
    mapM_ removeSidecar stale
    pure (length stale)

isCurrentSidecar :: SidecarEntry -> Bool
isCurrentSidecar entry =
    sidecarBuildId entry == backendIdentifier (sidecarBackend entry) <> "-logical"

listHashDirectory :: FilePath -> FilePath -> IO [SidecarEntry]
listHashDirectory archDir hashName = do
    let dir = archDir </> hashName
    isDir <- doesDirectoryExist dir
    if not isDir
        then pure []
        else do
            names <- listDirectory dir
            concat <$> mapM (entryFor dir hashName) [name | name <- names, takeExtension name == ".eq"]

entryFor :: FilePath -> String -> FilePath -> IO [SidecarEntry]
entryFor dir transcriptHash eqName = do
    let eqPath = dir </> eqName
        envelopePath = replaceExtension eqPath "envelope"
    envelopeExists <- doesFileExist envelopePath
    if not envelopeExists
        then pure []
        else do
            raw <- readFile envelopePath
            case readMaybe raw of
                Nothing -> pure []
                Just envelope ->
                    pure
                        [ SidecarEntry
                            { sidecarTranscriptHash = transcriptHash
                            , sidecarBackend = envelopeBackend envelope
                            , sidecarBuildId = envelopeBuildId envelope
                            , sidecarEqPath = eqPath
                            , sidecarEnvelopePath = envelopePath
                            }
                        ]

removeSidecar :: SidecarEntry -> IO ()
removeSidecar entry = do
    removeFileIfExists (sidecarEqPath entry)
    removeFileIfExists (sidecarEnvelopePath entry)

removeFileIfExists :: FilePath -> IO ()
removeFileIfExists path = do
    exists <- doesFileExist path
    if exists then removeFile path else pure ()

sidecarSortKey :: SidecarEntry -> (String, String, String, FilePath)
sidecarSortKey entry =
    ( sidecarTranscriptHash entry
    , backendIdentifier (sidecarBackend entry)
    , sidecarBuildId entry
    , takeFileName (sidecarEqPath entry)
    )
