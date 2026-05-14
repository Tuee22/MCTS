module MCTS.Transcript
    ( encodeTranscript
    , decodeTranscript
    , encodeRunConfig
    , runConfigHash
    , playTranscriptHash
    , resolveCacheRoot
    , hostArch
    , transcriptPath
    , writeTranscript
    , readTranscriptFile
    , lookupByPrefix
    , listTranscriptFiles
    ) where

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
import qualified Data.Bits as Bits
import Data.Bits (shiftL)
import Data.Char (isHexDigit)
import Data.List (isSuffixOf, sort)
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
    )
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import qualified System.Info as Info

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
            case runGet parseEnvelope restAfterHeader of
                Left err -> Left (TranscriptFormatUnsupported err)
                Right (envelope, body) ->
                    case parseGames body of
                        Left err -> Left (TranscriptFormatUnsupported err)
                        Right games -> Right Transcript{transcriptConfig = config, transcriptEnvelope = envelope, transcriptGames = games}

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
            <> word32LE (runGames config)
            <> word64LE (runCParamBits config)

runConfigHash :: RunConfig -> String
runConfigHash = sha256Hex . encodeRunConfig

playTranscriptHash :: RunConfig -> [MoveRecord] -> String
playTranscriptHash config records =
    sha256Hex (encodeRunConfig config <> LBS.toStrict (toLazyByteString (mconcat (map encodeRecord records))))

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
        <> word16LE 0
        <> word32LE 48

encodeThreading :: Threading -> Builder
encodeThreading threading =
    case threading of
        SingleThreaded -> word8 0 <> word16LE 1
        MultiThreaded n -> word8 1 <> word16LE (fromIntegral (max 1 n))

encodeEnvelope :: Envelope -> Builder
encodeEnvelope envelope =
    let payload = stringBytes (backendIdentifier (envelopeBackend envelope)) <> stringBytes (envelopeHostArch envelope) <> stringBytes (envelopeBuildId envelope)
        payloadBytes = LBS.toStrict (toLazyByteString payload)
        totalLength = 2 + 4 + BS.length payloadBytes
     in word16LE (envelopeVersion envelope)
            <> word32LE (fromIntegral totalLength)
            <> byteString payloadBytes

encodeGame :: GameTranscript -> Builder
encodeGame game =
    word32LE (gameId game)
        <> mconcat (map encodeRecord (gameMoves game))
        <> word8 0xFF
        <> word8
            ( case gameWinner game of
                HeroWin -> 0
                VillainWin -> 1
                Draw -> 2
            )
        <> word16LE (fromIntegral (length (gameMoves game)))

encodeRecord :: MoveRecord -> Builder
encodeRecord record =
    let visits = take 254 (moveVisits record)
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
    _reserved <- getWord16
    _offset <- getWord32
    pure
        RunConfig
            { runBackend = backend
            , runWorkload = Selfplay
            , runThreading = threading
            , runRngSource = rng
            , runMasterSeed = seed
            , runInitialSims = initial
            , runPerMoveSims = perMove
            , runMaxPlies = maxPlies
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

parseEnvelope :: Get Envelope
parseEnvelope = do
    version <- getWord16
    byteLength <- getWord32
    if byteLength < 6 then failGet "bad envelope length" else pure ()
    backendName <- getString
    archName <- getString
    buildId <- getString
    backend <-
        case parseBackend backendName of
            Just value -> pure value
            Nothing -> failGet "bad envelope backend"
    pure Envelope{envelopeVersion = version, envelopeBackend = backend, envelopeHostArch = archName, envelopeBuildId = buildId}

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
        0xFF : winnerByte : lo : hi : rest ->
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

stringBytes :: String -> Builder
stringBytes value =
    let bytes = map (fromIntegral . fromEnum) value
     in word8 (fromIntegral (length bytes)) <> byteString (BS.pack bytes)

getString :: Get String
getString = do
    len <- getWord8
    bytes <- takeBytes (fromIntegral len)
    pure (map (toEnum . fromIntegral) bytes)

resolveCacheRoot :: Maybe FilePath -> IO FilePath
resolveCacheRoot explicit =
    case explicit of
        Just path -> pure path
        Nothing -> do
            env <- lookupEnv "MCTS_CACHE_DIR"
            case env of
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
    let config = (transcriptConfig transcript){runGames = fromIntegral (length (transcriptGames transcript))}
        hashValue = runConfigHash config
        path = transcriptPath root hashValue
    createDirectoryIfMissing True (root </> "transcripts" </> hostArch)
    BS.writeFile path (encodeTranscript transcript{transcriptConfig = config})
    pure (Right (hashValue, path))

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

lookupByPrefix :: Maybe FilePath -> String -> IO (Either AppError FilePath)
lookupByPrefix explicit prefix
    | length prefix < 4 || any (not . isHexDigit) prefix =
        pure (Left (TranscriptNotFound prefix))
    | otherwise = do
        files <- listTranscriptFiles explicit
        let matches = [file | file <- files, prefix `isPrefixOfPathHash` file]
        pure $
            case matches of
                [] -> Left (TranscriptNotFound prefix)
                [one] -> Right one
                many -> Left (TranscriptAmbiguous prefix many)

isPrefixOfPathHash :: String -> FilePath -> Bool
isPrefixOfPathHash prefix path =
    take (length prefix) (takeWhile (/= '.') (reverse (takeWhile (/= '/') (reverse path)))) == prefix
