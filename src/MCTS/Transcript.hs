module MCTS.Transcript
    ( TranscriptRef (..)
    , encodeTranscript
    , decodeTranscript
    , encodeRunConfig
    , encodeEnvelope
    , runConfigHash
    , playTranscriptHash
    , resolveCacheRoot
    , hostArch
    , transcriptPath
    , writeTranscript
    , writePlayTranscript
    , writeTranscriptPerGame
    , readTranscriptFile
    , lookupByPrefix
    , listTranscriptFiles
    ) where

import Control.Exception (IOException, try)
import Data.Bits (shiftL)
import qualified Data.Bits as Bits
import qualified Data.ByteString as BS
import Data.ByteString.Builder
    ( Builder
    , byteString
    , toLazyByteString
    , word16LE
    , word32LE
    , word64LE
    , word8
    )
import qualified Data.ByteString.Lazy as LBS
import Data.Char (isHexDigit)
import Data.List (isSuffixOf, sort, sortOn)
import Data.Word (Word16, Word32, Word64, Word8)
import MCTS.Crypto.SHA256 (sha256Hex)
import MCTS.Error (AppError (..))
import MCTS.Types
import System.Directory
    ( createDirectoryIfMissing
    , doesDirectoryExist
    , doesFileExist
    , getCurrentDirectory
    , getDirectoryContents
    , removeFile
    , renameFile
    )
import System.FilePath ((</>))
import System.IO (Handle, hFlush, openBinaryTempFile)
import qualified System.Info as Info
import qualified System.Posix.IO as PosixIO
import qualified System.Posix.Unistd as PosixUnistd

data TranscriptRef = TranscriptRef
    { transcriptRefHash :: !String
    , transcriptRefPath :: !FilePath
    }
    deriving (Eq, Show)

encodeTranscript :: Transcript -> BS.ByteString
encodeTranscript transcript =
    LBS.toStrict . toLazyByteString $
        encodeHeader (transcriptConfig transcript)
            <> encodeEnvelope (transcriptEnvelope transcript)
            <> mconcat (map encodeGame (transcriptGames transcript))

decodeTranscript :: BS.ByteString -> Either AppError Transcript
decodeTranscript bytes =
    case runGet parseHeader (BS.unpack bytes) of
        Left err -> Left (TranscriptFormatUnsupported err)
        Right (config, restAfterHeader) ->
            case runGet (parseEnvelope (runBackend config)) restAfterHeader of
                Left err -> Left (TranscriptFormatUnsupported err)
                Right (envelope, body) ->
                    case parseGames body of
                        Left err -> Left (TranscriptFormatUnsupported err)
                        Right games ->
                            -- Backend (i) cpp-legacy has no draw rule per
                            -- README §"Draw rule"; reject draw winners on
                            -- decode.
                            if runBackend config == CppLegacy && any ((== Draw) . gameWinner) games
                                then Left (TranscriptFormatUnsupported "cpp-legacy transcripts must not record draw winners")
                                else
                                    Right
                                        Transcript
                                            { transcriptConfig =
                                                config
                                                    { runGames = fromIntegral (length games)
                                                    , runGameIndex = decodedGameIndex config games
                                                    }
                                            , transcriptEnvelope = envelope
                                            , transcriptGames = games
                                            }

decodedGameIndex :: RunConfig -> [GameTranscript] -> Word32
decodedGameIndex config games =
    case games of
        [game] -> gameId game
        _ -> runGameIndex config

encodeRunConfig :: RunConfig -> BS.ByteString
encodeRunConfig config =
    LBS.toStrict . toLazyByteString $
        word8 (backendId (runBackend config))
            <> word8
                ( case runWorkload config of
                    Rollouts -> 0
                    Selfplay -> 1
                )
            <> encodeThreading (runThreading config)
            <> word8
                ( case runRngSource config of
                    NativeRng -> 0
                    CppRng -> 1
                )
            <> word64LE (runMasterSeed config)
            <> word32LE (runInitialSims config)
            <> word32LE (runPerMoveSims config)
            <> word16LE (runMaxPlies config)
            <> word32LE (runGameIndex config)
            <> word64LE (runCParamBits config)

runConfigHash :: RunConfig -> String
runConfigHash = sha256Hex . encodeRunConfig

playTranscriptHash :: RunConfig -> [MoveRecord] -> String
playTranscriptHash config records =
    sha256Hex
        (encodeRunConfig config <> LBS.toStrict (toLazyByteString (mconcat (map encodeRecord records))))

encodeHeader :: RunConfig -> Builder
encodeHeader config =
    byteString (BS.pack [0x4D, 0x43, 0x54, 0x52])
        <> word16LE 1
        <> word8 (backendId (runBackend config))
        <> encodeThreading (runThreading config)
        <> word8
            ( case runRngSource config of
                NativeRng -> 0
                CppRng -> 1
            )
        <> word8 (archId hostArch)
        <> word64LE (runCParamBits config)
        <> word32LE 0
        <> word64LE (runMasterSeed config)
        <> word32LE (runInitialSims config)
        <> word32LE (runPerMoveSims config)
        <> word16LE (runMaxPlies config)
        <> word16LE (workloadId (runWorkload config))
        <> word32LE 48

workloadId :: Workload -> Word16
workloadId workload =
    case workload of
        Rollouts -> 0
        Selfplay -> 1

encodeThreading :: Threading -> Builder
encodeThreading threading =
    case threading of
        SingleThreaded -> word8 0 <> word16LE 1
        MultiThreaded n -> word8 1 <> word16LE (fromIntegral (max 1 n))

-- | v1 envelope wire format. Display-only fields such as backend and
-- build-label stay outside the encoded block; they are recovered from the
-- transcript header and `engine_build_id` when decoding.
encodeEnvelope :: Envelope -> Builder
encodeEnvelope envelope =
    let payload =
            word8 (rngSourceId (envelopeRngSource envelope))
                <> word8 (archId (envelopeHostArch envelope))
                <> fixedHex32Bytes (envelopeSharedRngBuildId envelope)
                <> fixedHex32Bytes (envelopeCohortConfigHash envelope)
                <> fixedHex32Bytes (envelopeEngineBuildId envelope)
                <> fixedStringBytes 40 (envelopeEngineGitCommit envelope)
                <> word8 (envelopeCompilerId envelope)
                <> lengthPrefixed63 (envelopeCompilerVersion envelope)
                <> word32LE (envelopeFpFlags envelope)
                <> lengthPrefixed63 (envelopeLibmId envelope)
                <> word32LE (envelopeCpuFeatures envelope)
                <> word8 (envelopeFpEnv envelope)
        payloadBytes = LBS.toStrict (toLazyByteString payload)
        totalLength = 2 + 4 + BS.length payloadBytes
     in word16LE (envelopeVersion envelope)
            <> word32LE (fromIntegral totalLength)
            <> byteString payloadBytes

rngSourceId :: RngSource -> Word8
rngSourceId NativeRng = 0
rngSourceId CppRng = 1

-- | Encode a 32-byte digest stored as a 64-character hex string. Pads with
-- '0' if shorter; truncates if longer.
fixedHex32Bytes :: ByteString32 -> Builder
fixedHex32Bytes (ByteString32 hex) =
    let normalized = take 64 (hex <> replicate 64 '0')
     in byteString (BS.pack (hexPairsToBytes normalized))

hexPairsToBytes :: String -> [Word8]
hexPairsToBytes [] = []
hexPairsToBytes [_] = []
hexPairsToBytes (a : b : rest) = readHexPair a b : hexPairsToBytes rest

readHexPair :: Char -> Char -> Word8
readHexPair a b = fromIntegral (hexDigit a * 16 + hexDigit b)

hexDigit :: Char -> Int
hexDigit c
    | c >= '0' && c <= '9' = fromEnum c - fromEnum '0'
    | c >= 'a' && c <= 'f' = 10 + fromEnum c - fromEnum 'a'
    | c >= 'A' && c <= 'F' = 10 + fromEnum c - fromEnum 'A'
    | otherwise = 0

-- | Encode a fixed-size ASCII field NUL-padded to `n` bytes.
fixedStringBytes :: Int -> String -> Builder
fixedStringBytes n value =
    let bytes = map (fromIntegral . fromEnum) value :: [Word8]
        padded = take n (bytes <> repeat 0)
     in byteString (BS.pack padded)

-- | Encode a length-prefixed ASCII field with a u8 length byte followed by
-- exactly 63 bytes of payload (NUL-padded). The valid prefix range is the
-- first `length_byte` bytes.
lengthPrefixed63 :: String -> Builder
lengthPrefixed63 value =
    let bytes = map (fromIntegral . fromEnum) value :: [Word8]
        truncated = take 63 bytes
        len = length truncated
        padded = truncated <> replicate (63 - len) 0
     in word8 (fromIntegral len) <> byteString (BS.pack padded)

encodeGame :: GameTranscript -> Builder
encodeGame game =
    word32LE (gameId game)
        <> mconcat (map encodeRecord (gameMoves game))
        <> word16LE 0xFFFF
        <> word8
            ( case gameWinner game of
                HeroWin -> 0
                VillainWin -> 1
                Draw -> 2
            )
        <> word16LE (fromIntegral (length (gameMoves game)))

encodeRecord :: MoveRecord -> Builder
encodeRecord record =
    let visits = take 254 (sortOn (actionId . fst) (moveVisits record))
     in word16LE (moveIndex record)
            <> word8 (actionId (moveChosen record))
            <> word8 (fromIntegral (length visits))
            <> mconcat
                [ word8 (actionId action) <> word32LE count
                | (action, count) <- visits
                ]

parseHeader :: Get RunConfig
parseHeader = do
    magic <- takeBytes 4
    if magic /= [0x4D, 0x43, 0x54, 0x52]
        then failGet "bad magic"
        else pure ()
    version <- getWord16
    if version /= 1 then failGet "unsupported version" else pure ()
    backend <- parseBackendId =<< getWord8
    threadingTag <- getWord8
    workers <- getWord16
    let threading = if threadingTag == 0 then SingleThreaded else MultiThreaded (fromIntegral workers)
    rngTag <- getWord8
    rng <-
        case rngTag of
            0 -> pure NativeRng
            1 -> pure CppRng
            _ -> failGet "bad rng source"
    _arch <- getWord8
    cParam <- getWord64
    flags <- getWord32
    if flags /= 0 then failGet "non-zero flags" else pure ()
    seed <- getWord64
    initial <- getWord32
    perMove <- getWord32
    maxPlies <- getWord16
    workloadTag <- getWord16
    workload <-
        case workloadTag of
            0 -> pure Rollouts
            1 -> pure Selfplay
            _ -> failGet "bad workload"
    _offset <- getWord32
    pure
        RunConfig
            { runBackend = backend
            , runWorkload = workload
            , runThreading = threading
            , runRngSource = rng
            , runMasterSeed = seed
            , runInitialSims = initial
            , runPerMoveSims = perMove
            , runMaxPlies = maxPlies
            , runGameIndex = 0
            , runGames = 0
            , runCParamBits = cParam
            }

parseBackendId :: Word8 -> Get Backend
parseBackendId ident =
    case ident of
        0 -> pure CppLegacy
        1 -> pure CppImperative
        2 -> pure CppFunctional
        3 -> pure Rust
        4 -> pure Haskell
        _ -> failGet "bad backend"

parseEnvelope :: Backend -> Get Envelope
parseEnvelope backend = do
    version <- getWord16
    byteLength <- getWord32
    if byteLength < 6 then failGet "bad envelope length" else pure ()
    payloadBytes <- takeBytes (fromIntegral byteLength - 6)
    case runGet (parseEnvelopePayload backend version) payloadBytes of
        Left err -> failGet err
        Right (envelope, _) -> pure envelope

parseEnvelopePayload :: Backend -> Word16 -> Get Envelope
parseEnvelopePayload backend version = do
    rngTag <- getWord8
    rng <- case rngTag of
        0 -> pure NativeRng
        1 -> pure CppRng
        _ -> failGet "bad envelope rng_source"
    archByte <- getWord8
    let archName = case archByte of
            0 -> "amd64"
            1 -> "arm64"
            _ -> "unknown"
    sharedRngBuildId <- ByteString32 <$> getHex32
    cohortConfigHash <- ByteString32 <$> getHex32
    engineBuildId <- ByteString32 <$> getHex32
    engineGitCommit <- getFixedString 40
    compilerId <- getWord8
    compilerVersion <- getLengthPrefixed63
    fpFlags <- getWord32
    libmId <- getLengthPrefixed63
    cpuFeatures <- getWord32
    fpEnv <- getWord8
    pure
        Envelope
            { envelopeVersion = version
            , envelopeBackend = backend
            , envelopeRngSource = rng
            , envelopeHostArch = archName
            , envelopeSharedRngBuildId = sharedRngBuildId
            , envelopeCohortConfigHash = cohortConfigHash
            , envelopeEngineBuildId = engineBuildId
            , envelopeEngineGitCommit = engineGitCommit
            , envelopeCompilerId = compilerId
            , envelopeCompilerVersion = compilerVersion
            , envelopeFpFlags = fpFlags
            , envelopeLibmId = libmId
            , envelopeCpuFeatures = cpuFeatures
            , envelopeFpEnv = fpEnv
            , envelopeBuildId = buildLabelFromEngineId backend engineBuildId
            }

buildLabelFromEngineId :: Backend -> ByteString32 -> String
buildLabelFromEngineId backend digest@(ByteString32 hex)
    | digest == zeroDigest = backendIdentifier backend <> "-logical"
    | otherwise = backendIdentifier backend <> "-" <> take 16 hex

getHex32 :: Get String
getHex32 = do
    bytes <- takeBytes 32
    pure (concatMap byteToHex bytes)

byteToHex :: Word8 -> String
byteToHex byte =
    [hexChar (fromIntegral byte `div` 16), hexChar (fromIntegral byte `mod` 16)]
  where
    hexChar n
        | n < 10 = toEnum (fromEnum '0' + n)
        | otherwise = toEnum (fromEnum 'a' + n - 10)

-- | Read a fixed-size NUL-padded ASCII field, stopping at the first NUL.
getFixedString :: Int -> Get String
getFixedString n = do
    bytes <- takeBytes n
    pure (map (toEnum . fromIntegral) (takeWhile (/= 0) bytes))

-- | Read a length-prefixed ASCII field stored as `len :: u8` plus 63
-- bytes of payload; the valid range is the first `len` bytes.
getLengthPrefixed63 :: Get String
getLengthPrefixed63 = do
    len <- getWord8
    bytes <- takeBytes 63
    let valid = take (fromIntegral len) bytes
    pure (map (toEnum . fromIntegral) valid)

parseGames :: [Word8] -> Either String [GameTranscript]
parseGames [] = Right []
parseGames bytes =
    case runGet getWord32 bytes of
        Left err -> Left err
        Right (gid, afterGameId) ->
            case parseRecords [] afterGameId of
                Left err -> Left err
                Right (records, winner, rest) ->
                    (GameTranscript gid records winner :) <$> parseGames rest

parseRecords :: [MoveRecord] -> [Word8] -> Either String ([MoveRecord], Winner, [Word8])
parseRecords acc bytes =
    case bytes of
        0xFF : 0xFF : winnerByte : lo : hi : rest ->
            let total = fromIntegral lo + shiftL (fromIntegral hi) 8 :: Int
             in if total == length acc
                    then do
                        winner <- parseWinner winnerByte
                        Right (reverse acc, winner, rest)
                    else Left "terminator move count mismatch"
        _ ->
            case runGet parseRecord bytes of
                Left err -> Left err
                Right (record, rest) -> parseRecords (record : acc) rest

parseRecord :: Get MoveRecord
parseRecord = do
    idx <- getWord16
    chosenId <- getWord8
    chosen <-
        case actionFromId chosenId of
            Just action -> pure action
            Nothing -> failGet "bad chosen action"
    nActions <- getWord8
    visits <- countGet (fromIntegral nActions) parseVisit
    pure MoveRecord{moveIndex = idx, moveChosen = chosen, moveVisits = visits}

parseVisit :: Get (Action, Word32)
parseVisit = do
    actionIdByte <- getWord8
    action <-
        case actionFromId actionIdByte of
            Just value -> pure value
            Nothing -> failGet "bad action"
    count <- getWord32
    pure (action, count)

parseWinner :: Word8 -> Either String Winner
parseWinner word =
    case word of
        0 -> Right HeroWin
        1 -> Right VillainWin
        2 -> Right Draw
        _ -> Left "bad winner"

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

foldLE :: (Integral a, Bits.Bits a) => [Word8] -> a
foldLE bytes =
    sum [fromIntegral byte `shiftL` (8 * idx) | (idx, byte) <- zip [0 :: Int ..] bytes]

resolveCacheRoot :: Maybe FilePath -> IO FilePath
resolveCacheRoot explicit =
    case explicit of
        Just path -> pure path
        Nothing -> do
            cwd <- getCurrentDirectory
            pure (cwd </> ".mcts-cache")

hostArch :: String
hostArch =
    case Info.arch of
        "x86_64" -> "amd64"
        "amd64" -> "amd64"
        "aarch64" -> "arm64"
        "arm64" -> "arm64"
        other -> other

archId :: String -> Word8
archId archName =
    case archName of
        "arm64" -> 1
        _ -> 0

transcriptPath :: FilePath -> String -> FilePath
transcriptPath root hashValue =
    root </> "transcripts" </> hostArch </> hashValue <> ".tr"

writeTranscript :: Maybe FilePath -> Transcript -> IO (Either AppError (String, FilePath))
writeTranscript explicit transcript = do
    root <- resolveCacheRoot explicit
    let config = configForWrite (transcriptConfig transcript) (transcriptGames transcript)
        hashValue = runConfigHash config
        path = transcriptPath root hashValue
        dir = root </> "transcripts" </> hostArch
    createDirectoryIfMissing True dir
    writeFileAtomically dir path (encodeTranscript transcript{transcriptConfig = config})
    pure (Right (hashValue, path))

writePlayTranscript :: Maybe FilePath -> Transcript -> IO (Either AppError (String, FilePath))
writePlayTranscript explicit transcript = do
    root <- resolveCacheRoot explicit
    let config = configForWrite (transcriptConfig transcript) (transcriptGames transcript)
        records = concatMap gameMoves (transcriptGames transcript)
        hashValue = playTranscriptHash config records
        path = transcriptPath root hashValue
        dir = root </> "transcripts" </> hostArch
    createDirectoryIfMissing True dir
    writeFileAtomically dir path (encodeTranscript transcript{transcriptConfig = config})
    pure (Right (hashValue, path))

configForWrite :: RunConfig -> [GameTranscript] -> RunConfig
configForWrite config games =
    config
        { runGames = fromIntegral (length games)
        , runGameIndex =
            case games of
                [game] -> gameId game
                _ -> runGameIndex config
        }

-- | Split a batch transcript into N single-game transcripts and write
-- each to its own `.tr` file. Each per-game file keeps the original
-- master seed and records the game id in `runGameIndex`, making the
-- cache key `sha256(run_config{game_index = game_id})`.
writeTranscriptPerGame
    :: Maybe FilePath
    -> Transcript
    -> IO (Either AppError [(String, FilePath)])
writeTranscriptPerGame explicit transcript = do
    root <- resolveCacheRoot explicit
    let dir = root </> "transcripts" </> hostArch
    createDirectoryIfMissing True dir
    written <- mapM (writeOne root dir) (transcriptGames transcript)
    pure (Right written)
  where
    writeOne root dir game = do
        let baseConfig = transcriptConfig transcript
            perGameConfig =
                baseConfig
                    { runGames = 1
                    , runGameIndex = gameId game
                    }
            perGameTranscript =
                Transcript
                    perGameConfig
                    (transcriptEnvelope transcript)
                    [game]
            hashValue = runConfigHash perGameConfig
            path = transcriptPath root hashValue
        writeFileAtomically dir path (encodeTranscript perGameTranscript)
        pure (hashValue, path)

-- | Atomic write: temp file in the same directory, fsync the temp file,
-- rename to the final path, fsync the parent directory. Per Phase 2.2 /
-- [00-overview.md → Hard Constraints item 13](../../DEVELOPMENT_PLAN/00-overview.md).
writeFileAtomically :: FilePath -> FilePath -> BS.ByteString -> IO ()
writeFileAtomically dir path bytes = do
    (tmpPath, handle) <- openBinaryTempFile dir ".tmp-transcript"
    writeAndFsync tmpPath handle bytes
    renameFile tmpPath path
    fsyncDirectory dir

writeAndFsync :: FilePath -> Handle -> BS.ByteString -> IO ()
writeAndFsync tmpPath handle bytes = do
    result <- try $ do
        BS.hPut handle bytes
        hFlush handle
        -- `handleToFd` closes the handle but returns the underlying Fd
        -- so we can fsync it before releasing.
        fd <- PosixIO.handleToFd handle
        PosixUnistd.fileSynchronise fd
        PosixIO.closeFd fd
    case result of
        Right () -> pure ()
        Left err -> do
            exists <- doesFileExist tmpPath
            if exists then removeFile tmpPath else pure ()
            ioError err

-- | fsync the directory entry so the rename is durable across crashes.
-- Best-effort: macOS in particular allows O_RDONLY fsync but does not
-- guarantee directory durability; the call is harmless and matches the
-- doctrine's atomic-write contract.
fsyncDirectory :: FilePath -> IO ()
fsyncDirectory dir = do
    result <- try $ do
        fd <- PosixIO.openFd dir PosixIO.ReadOnly PosixIO.defaultFileFlags
        PosixUnistd.fileSynchronise fd
        PosixIO.closeFd fd
    case result :: Either IOException () of
        Right () -> pure ()
        Left _ -> pure ()

readTranscriptFile :: FilePath -> IO (Either AppError Transcript)
readTranscriptFile path = do
    exists <- doesFileExist path
    if not exists
        then pure (Left (TranscriptNotFound path))
        else decodeTranscript <$> BS.readFile path

listTranscriptFiles :: Maybe FilePath -> IO [FilePath]
listTranscriptFiles explicit = do
    root <- resolveCacheRoot explicit
    let dir = root </> "transcripts" </> hostArch
    exists <- doesDirectoryExist dir
    if not exists
        then pure []
        else do
            names <- getDirectoryContents dir
            pure (sort [dir </> name | name <- names, ".tr" `isSuffixOf` name])

lookupByPrefix :: Maybe FilePath -> String -> IO (Either AppError TranscriptRef)
lookupByPrefix explicit prefix
    | length prefix < 4 || any (not . isHexDigit) prefix =
        pure (Left (TranscriptNotFound prefix))
    | otherwise = do
        files <- listTranscriptFiles explicit
        let matches = [file | file <- files, prefix `isPrefixOfPathHash` file]
        pure $
            case matches of
                [] -> Left (TranscriptNotFound prefix)
                [one] -> Right (TranscriptRef (pathHash one) one)
                many -> Left (TranscriptAmbiguous prefix (map pathHash many))

isPrefixOfPathHash :: String -> FilePath -> Bool
isPrefixOfPathHash prefix path =
    take (length prefix) (pathHash path) == prefix

pathHash :: FilePath -> String
pathHash path =
    takeWhile (/= '.') (reverse (takeWhile (/= '/') (reverse path)))
