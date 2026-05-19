{-# LANGUAGE GADTs #-}

module MCTS.Types
    ( Backend (..)
    , backendId
    , backendIdentifier
    , backendRoman
    , allBackends
    , parseBackend
    , VerifyBackend (..)
    , toVerifyBackend
    , verifyBackendToBackend
    , Workload (..)
    , workloadName
    , RngSource (..)
    , parseRngSource
    , Threading (..)
    , threadingWorkers
    , threadingName
    , SimBudget (..)
    , simInitial
    , simPerMove
    , parseSimBudget
    , Side (..)
    , otherSide
    , Winner (..)
    , Action (..)
    , actionId
    , actionFromId
    , allActions
    , RunConfig (..)
    , MoveRecord (..)
    , GameTranscript (..)
    , Envelope (..)
    , ByteString32 (..)
    , zeroDigest
    , Transcript (..)
    , shortHash
    ) where

import Data.Bits ((.&.))
import Data.Char (toLower)
import Data.Word (Word16, Word32, Word64, Word8)
import Numeric (readDec)

data Backend
    = CppLegacy
    | CppImperative
    | CppFunctional
    | Rust
    | Haskell
    deriving (Eq, Ord, Enum, Bounded, Show, Read)

backendId :: Backend -> Word8
backendId backend =
    case backend of
        CppLegacy -> 0
        CppImperative -> 1
        CppFunctional -> 2
        Rust -> 3
        Haskell -> 4

backendIdentifier :: Backend -> String
backendIdentifier backend =
    case backend of
        CppLegacy -> "cpp-legacy"
        CppImperative -> "cpp-imperative"
        CppFunctional -> "cpp-functional"
        Rust -> "rust"
        Haskell -> "haskell"

backendRoman :: Backend -> String
backendRoman backend =
    case backend of
        CppLegacy -> "(i)"
        CppImperative -> "(ii)"
        CppFunctional -> "(iii)"
        Rust -> "(iv)"
        Haskell -> "(v)"

-- | Live operator-selectable backends. Backends (i), (ii), and (iii)
-- remain in the transcript wire format as archived backends, but they
-- are retired from CLI selection after Sprints 8.4, 8.5, and 8.6.
allBackends :: [Backend]
allBackends =
    [ Rust
    , Haskell
    ]

parseBackend :: String -> Maybe Backend
parseBackend raw =
    lookup (map toLower raw) [(backendIdentifier b, b) | b <- allBackends]

data VerifyBackend where
    VRust :: VerifyBackend
    VHaskell :: VerifyBackend

instance Eq VerifyBackend where
    left == right = verifyBackendToBackend left == verifyBackendToBackend right

instance Ord VerifyBackend where
    compare left right = compare (verifyBackendToBackend left) (verifyBackendToBackend right)

instance Show VerifyBackend where
    show = backendIdentifier . verifyBackendToBackend

toVerifyBackend :: Backend -> Maybe VerifyBackend
toVerifyBackend backend =
    case backend of
        CppLegacy -> Nothing
        CppImperative -> Nothing
        CppFunctional -> Nothing
        Rust -> Just VRust
        Haskell -> Just VHaskell

verifyBackendToBackend :: VerifyBackend -> Backend
verifyBackendToBackend backend =
    case backend of
        VRust -> Rust
        VHaskell -> Haskell

data Workload = Rollouts | Selfplay
    deriving (Eq, Ord, Show, Read)

workloadName :: Workload -> String
workloadName workload =
    case workload of
        Rollouts -> "rollouts"
        Selfplay -> "selfplay"

data RngSource = NativeRng | CppRng
    deriving (Eq, Ord, Show, Read)

parseRngSource :: String -> Maybe RngSource
parseRngSource raw =
    case map toLower raw of
        "native" -> Just NativeRng
        "cpp" -> Just CppRng
        _ -> Nothing

data Threading
    = SingleThreaded
    | MultiThreaded Int
    deriving (Eq, Ord, Show, Read)

threadingWorkers :: Threading -> Int
threadingWorkers threading =
    case threading of
        SingleThreaded -> 1
        MultiThreaded n -> max 1 n

threadingName :: Threading -> String
threadingName threading =
    case threading of
        SingleThreaded -> "ST"
        MultiThreaded n -> "MT" <> show (max 1 n)

data SimBudget
    = FixedSims Int
    | RampedSims Int Int
    deriving (Eq, Ord, Show, Read)

simInitial :: SimBudget -> Int
simInitial budget =
    case budget of
        FixedSims n -> n
        RampedSims n _ -> n

simPerMove :: SimBudget -> Int
simPerMove budget =
    case budget of
        FixedSims n -> n
        RampedSims _ n -> n

parseSimBudget :: String -> Maybe SimBudget
parseSimBudget raw =
    case break (== ':') raw of
        (one, "") -> FixedSims <$> readPositive one
        (first, ':' : second) -> RampedSims <$> readPositive first <*> readPositive second
        _ -> Nothing

readPositive :: String -> Maybe Int
readPositive raw =
    case readDec raw of
        [(n, "")] | n > 0 -> Just n
        _ -> Nothing

data Side = Hero | Villain
    deriving (Eq, Ord, Show, Read)

otherSide :: Side -> Side
otherSide side =
    case side of
        Hero -> Villain
        Villain -> Hero

data Winner = HeroWin | VillainWin | Draw
    deriving (Eq, Ord, Show, Read)

data Action
    = Pawn !Int !Int
    | WallH !Int !Int
    | WallV !Int !Int
    deriving (Eq, Ord, Show, Read)

actionId :: Action -> Word8
actionId action =
    case action of
        Pawn x y -> fromIntegral (y * 9 + x)
        WallH x y -> fromIntegral (81 + y * 8 + x)
        WallV x y -> fromIntegral (145 + y * 8 + x)

actionFromId :: Word8 -> Maybe Action
actionFromId word
    | word <= 80 =
        let n = fromIntegral word
         in Just (Pawn (n `mod` 9) (n `div` 9))
    | word >= 81 && word <= 144 =
        let n = fromIntegral word - 81
         in Just (WallH (n `mod` 8) (n `div` 8))
    | word >= 145 && word <= 208 =
        let n = fromIntegral word - 145
         in Just (WallV (n `mod` 8) (n `div` 8))
    | otherwise = Nothing

allActions :: [Action]
allActions = [a | ident <- [0 .. 208], Just a <- [actionFromId ident]]

data RunConfig = RunConfig
    { runBackend :: !Backend
    , runWorkload :: !Workload
    , runThreading :: !Threading
    , runRngSource :: !RngSource
    , runMasterSeed :: !Word64
    , runInitialSims :: !Word32
    , runPerMoveSims :: !Word32
    , runMaxPlies :: !Word16
    , runGames :: !Word32
    , runCParamBits :: !Word64
    }
    deriving (Eq, Show, Read)

data MoveRecord = MoveRecord
    { moveIndex :: !Word16
    , moveChosen :: !Action
    , moveVisits :: ![(Action, Word32)]
    }
    deriving (Eq, Show, Read)

data GameTranscript = GameTranscript
    { gameId :: !Word32
    , gameMoves :: ![MoveRecord]
    , gameWinner :: !Winner
    }
    deriving (Eq, Show, Read)

-- | Full v1 engine envelope per
-- [documents/engineering/backend_ffi_contract.md → Engine Envelope](../documents/engineering/backend_ffi_contract.md)
-- and
-- [documents/engineering/transcript_format.md → Envelope Block](../documents/engineering/transcript_format.md).
-- The cohort-invariant slots (`envelopeRngSource`, `envelopeHostArch`,
-- `envelopeSharedRngBuildId`, `envelopeCohortConfigHash`) must agree across
-- every transcript in a verify cohort; the per-backend-slot slots
-- (`envelopeEngineBuildId`, `envelopeCompilerId`, `envelopeCompilerVersion`,
-- `envelopeFpFlags`, `envelopeLibmId`, `envelopeCpuFeatures`,
-- `envelopeFpEnv`) must agree between a cached transcript and the live
-- binary for the same backend slot (unless `--allow-stale` downgrades the
-- check to a warning).
data Envelope = Envelope
    { envelopeVersion :: !Word16
    , envelopeBackend :: !Backend
    , envelopeRngSource :: !RngSource
    , envelopeHostArch :: !String
    , envelopeSharedRngBuildId :: !ByteString32
    , envelopeCohortConfigHash :: !ByteString32
    , envelopeEngineBuildId :: !ByteString32
    , envelopeEngineGitCommit :: !String
    , envelopeCompilerId :: !Word8
    , envelopeCompilerVersion :: !String
    , envelopeFpFlags :: !Word32
    , envelopeLibmId :: !String
    , envelopeCpuFeatures :: !Word32
    , envelopeFpEnv :: !Word8
    , envelopeBuildId :: !String
    -- ^ Convenience: short identifier matching the engine_build_id.
    }
    deriving (Eq, Show, Read)

-- | 32-byte digest stored as a hex-encoded string for ergonomic display
-- and stable Show/Read instances. The wire codec writes 32 raw bytes.
newtype ByteString32 = ByteString32 {unByteString32 :: String}
    deriving (Eq, Show, Read)

-- | An all-zero 32-byte digest sentinel. Used for fields that are
-- patched-in by the build harness post-link (engine_build_id),
-- backend-independent cohort hashing fills (cohort_config_hash), or
-- non-applicable cases (shared_rng_build_id under `--rng native`).
zeroDigest :: ByteString32
zeroDigest = ByteString32 (replicate 64 '0')

data Transcript = Transcript
    { transcriptConfig :: !RunConfig
    , transcriptEnvelope :: !Envelope
    , transcriptGames :: ![GameTranscript]
    }
    deriving (Eq, Show, Read)

shortHash :: String -> String
shortHash = take 8

instance Semigroup RunConfig where
    a <> b =
        a
            { runGames = runGames a + runGames b
            , runMasterSeed = runMasterSeed a .&. runMasterSeed b
            }

instance Monoid RunConfig where
    mempty =
        RunConfig
            { runBackend = Haskell
            , runWorkload = Selfplay
            , runThreading = SingleThreaded
            , runRngSource = NativeRng
            , runMasterSeed = 0
            , runInitialSims = 1
            , runPerMoveSims = 1
            , runMaxPlies = 200
            , runGames = 0
            , runCParamBits = 0
            }
