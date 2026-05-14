-- | Binary equity sidecar codec plus the matching `.envelope` neighbour
-- file. Atomic same-directory temp-file plus rename writes per
-- [00-overview.md → Hard Constraints item 13](../../DEVELOPMENT_PLAN/00-overview.md)
-- and [phase-2-transcript-codec-and-determinism.md → Sprint 2.7](../../DEVELOPMENT_PLAN/phase-2-transcript-codec-and-determinism.md).
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
    , writeEquitySidecarStream
    , listEquitySidecars
    , pruneEquitySidecars
    , isCurrentSidecar
    ) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy as LBS
import Data.List (sortOn)
import Data.Word (Word16, Word32, Word64, Word8)
import GHC.Float (castWord64ToDouble)
import MCTS.Transcript (encodeEnvelope, hostArch, resolveCacheRoot)
import MCTS.Types
import System.Directory
    ( createDirectoryIfMissing
    , doesDirectoryExist
    , doesFileExist
    , listDirectory
    , removeFile
    , renameFile
    )
import System.FilePath (replaceExtension, takeExtension, takeFileName, (</>))
import System.IO (Handle, hClose, hFlush, openBinaryTempFile)

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

-- ---------------------------------------------------------------------------
-- Binary codec for the .eq sidecar
--
-- Wire layout (all little-endian, no padding):
--   magic u32     = 'M','E','Q','1'  (0x4D 0x45 0x51 0x31)
--   version u16   = 1
--   backend u8
--   transcript_hash_len u8 (≤ 64)
--   transcript_hash[64]   length-prefixed ASCII NUL-padded
--   build_id_len u8 (≤ 63)
--   build_id[63]          length-prefixed ASCII NUL-padded
--   record_count u32
--   record_count × {
--     game_id u32
--     move_index u16
--     chosen u8
--     equity f64 (IEEE-754 bit-cast u64 little-endian)
--   }
--   terminator u32 = 0xFFFFFFFF
-- ---------------------------------------------------------------------------

eqMagic :: BS.ByteString
eqMagic = BS.pack [0x4D, 0x45, 0x51, 0x31]

eqTerminator :: Word32
eqTerminator = 0xFFFFFFFF

encodeEqStream :: EqStream -> BS.ByteString
encodeEqStream stream =
    LBS.toStrict . Builder.toLazyByteString $
        Builder.byteString eqMagic
            <> Builder.word16LE 1
            <> Builder.word8 (backendId (eqBackend stream))
            <> lengthPrefixed 64 (eqTranscriptHash stream)
            <> lengthPrefixed 63 (eqBuildId stream)
            <> Builder.word32LE (fromIntegral (length (eqRecords stream)))
            <> mconcat (map encodeEqRecord (eqRecords stream))
            <> Builder.word32LE eqTerminator

encodeEqRecord :: EqRecord -> Builder.Builder
encodeEqRecord record =
    Builder.word32LE (eqGameId record)
        <> Builder.word16LE (eqMoveIndex record)
        <> Builder.word8 (actionId (eqChosen record))
        <> Builder.doubleLE (eqEquity record)

decodeEqStream :: BS.ByteString -> Either String EqStream
decodeEqStream bytes = case runGet eqStreamGet (BS.unpack bytes) of
    Left err -> Left err
    Right (stream, _) -> Right stream

eqStreamGet :: Get EqStream
eqStreamGet = do
    magic <- takeBytes 4
    if magic /= BS.unpack eqMagic
        then failGet "bad equity sidecar magic"
        else pure ()
    version <- getWord16
    if version /= 1 then failGet "unsupported equity sidecar version" else pure ()
    backendByte <- getWord8
    backend <- case lookup backendByte [(backendId b, b) | b <- [CppLegacy, CppImperative, CppFunctional, Rust, Haskell]] of
        Just value -> pure value
        Nothing -> failGet "bad sidecar backend"
    transcriptHash <- getLengthPrefixed 64
    buildId <- getLengthPrefixed 63
    count <- getWord32
    records <- countGet (fromIntegral count) eqRecordGet
    terminator <- getWord32
    if terminator /= eqTerminator
        then failGet "bad equity sidecar terminator"
        else
            pure
                EqStream
                    { eqTranscriptHash = transcriptHash
                    , eqBackend = backend
                    , eqBuildId = buildId
                    , eqRecords = records
                    }

eqRecordGet :: Get EqRecord
eqRecordGet = do
    gid <- getWord32
    idx <- getWord16
    chosenByte <- getWord8
    chosen <- case actionFromId chosenByte of
        Just value -> pure value
        Nothing -> failGet "bad chosen action in sidecar record"
    equity <- getDouble
    pure
        EqRecord
            { eqGameId = gid
            , eqMoveIndex = idx
            , eqChosen = chosen
            , eqEquity = equity
            }

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

-- | Atomically write the `.eq` and `.envelope` files using the same
-- temp-file plus rename strategy as the transcript codec. The `.eq`
-- stream carries the zero-equity placeholder (`equityStreamForTranscript`);
-- callers that need real recomputed equity values must build the stream
-- via `MCTS.Engine.Recompute.recomputeEqStream` and pass it through
-- `writeEquitySidecarStream`.
writeEquitySidecar :: Maybe FilePath -> String -> Transcript -> IO SidecarEntry
writeEquitySidecar explicit transcriptHash transcript =
    writeEquitySidecarStream explicit transcript (equityStreamForTranscript transcriptHash transcript)

-- | Like `writeEquitySidecar` but accepts an explicit `EqStream` so a
-- recompute-driven stream can be persisted.
writeEquitySidecarStream :: Maybe FilePath -> Transcript -> EqStream -> IO SidecarEntry
writeEquitySidecarStream explicit transcript stream = do
    root <- resolveCacheRoot explicit
    let envelope = transcriptEnvelope transcript
        transcriptHash = eqTranscriptHash stream
        dir = sidecarDirectory root transcriptHash
        stem = sidecarStem (envelopeBackend envelope) (envelopeBuildId envelope)
        eqPath = dir </> stem <> ".eq"
        envelopePath = dir </> stem <> ".envelope"
        envelopeBytes = LBS.toStrict (Builder.toLazyByteString (encodeEnvelope envelope))
    createDirectoryIfMissing True dir
    writeFileAtomically dir eqPath (encodeEqStream stream)
    writeFileAtomically dir envelopePath envelopeBytes
    pure
        SidecarEntry
            { sidecarTranscriptHash = transcriptHash
            , sidecarBackend = envelopeBackend envelope
            , sidecarBuildId = envelopeBuildId envelope
            , sidecarEqPath = eqPath
            , sidecarEnvelopePath = envelopePath
            }

writeFileAtomically :: FilePath -> FilePath -> BS.ByteString -> IO ()
writeFileAtomically dir path bytes = do
    (tmpPath, handle) <- openBinaryTempFile dir ".tmp-sidecar"
    writeAndClose tmpPath handle bytes
    renameFile tmpPath path

writeAndClose :: FilePath -> Handle -> BS.ByteString -> IO ()
writeAndClose _tmpPath handle bytes = do
    BS.hPut handle bytes
    hFlush handle
    hClose handle

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
    eqBytes <- BS.readFile eqPath
    case decodeEqStream eqBytes of
        Left _ -> pure []
        Right stream ->
            pure
                [ SidecarEntry
                    { sidecarTranscriptHash = transcriptHash
                    , sidecarBackend = eqBackend stream
                    , sidecarBuildId = eqBuildId stream
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

-- ---------------------------------------------------------------------------
-- Minimal binary Get monad shared with Transcript.hs. Duplicated here to
-- keep the EquitySidecar codec independent of the transcript codec's
-- internals; the parser shape is intentionally identical.
-- ---------------------------------------------------------------------------

newtype Get a = Get {unGet :: [Word8] -> Either String (a, [Word8])}

instance Functor Get where
    fmap f parser = Get $ \input -> do
        (value, rest) <- unGet parser input
        pure (f value, rest)

instance Applicative Get where
    pure value = Get $ \input -> Right (value, input)
    left <*> right = Get $ \input -> do
        (f, afterLeft) <- unGet left input
        (value, afterRight) <- unGet right afterLeft
        pure (f value, afterRight)

instance Monad Get where
    parser >>= next = Get $ \input -> do
        (value, rest) <- unGet parser input
        unGet (next value) rest

runGet :: Get a -> [Word8] -> Either String (a, [Word8])
runGet = unGet

failGet :: String -> Get a
failGet message = Get $ \_ -> Left message

takeBytes :: Int -> Get [Word8]
takeBytes n = Get $ \input ->
    let (prefix, suffix) = splitAt n input
     in if length prefix == n
            then Right (prefix, suffix)
            else Left "unexpected eof"

countGet :: Int -> Get a -> Get [a]
countGet n parser
    | n <= 0 = pure []
    | otherwise = (:) <$> parser <*> countGet (n - 1) parser

getWord8 :: Get Word8
getWord8 = do
    bytes <- takeBytes 1
    case bytes of
        [b] -> pure b
        _ -> failGet "unexpected eof"

getWord16 :: Get Word16
getWord16 = do
    bytes <- takeBytes 2
    pure (foldLE bytes)

getWord32 :: Get Word32
getWord32 = do
    bytes <- takeBytes 4
    pure (foldLE bytes)

getWord64 :: Get Word64
getWord64 = do
    bytes <- takeBytes 8
    pure (foldLE bytes)

getDouble :: Get Double
getDouble = castWord64ToDouble <$> getWord64

-- | Encode a length-prefixed ASCII field. `n` is the fixed payload width
-- in bytes; the on-wire layout is `len u8` plus `n` bytes of NUL-padded
-- payload. The valid range is the first `len` bytes.
lengthPrefixed :: Int -> String -> Builder.Builder
lengthPrefixed n value =
    let bytes = map (fromIntegral . fromEnum) value :: [Word8]
        truncated = take n bytes
        len = length truncated
        padded = truncated <> replicate (n - len) 0
     in Builder.word8 (fromIntegral len) <> Builder.byteString (BS.pack padded)

getLengthPrefixed :: Int -> Get String
getLengthPrefixed n = do
    len <- getWord8
    bytes <- takeBytes n
    let valid = take (fromIntegral len) bytes
    pure (map (toEnum . fromIntegral) valid)

foldLE :: (Integral a, Num a) => [Word8] -> a
foldLE bytes = sum [fromIntegral byte * (256 ^ idx) | (idx, byte) <- zip [0 :: Int ..] bytes]

