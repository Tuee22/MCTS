module Main where

import qualified Data.ByteString as BS
import MCTS.Crypto.SHA256 (sha256Hex)
import MCTS.CLI.Command (Command (..), VerifyCommand (..))
import MCTS.CLI.Parser (parseBackends, parseCommand)
import MCTS.CLI.Spec (CommandSpec (..), commandSpec, leafSpecs, renderCommandJson, renderCommandTree)
import MCTS.Driver
import MCTS.Engine (initialBoard, legalMoves)
import MCTS.Error (AppError (..), EnvelopeMismatchScope (..))
import MCTS.Notation (parseMove, renderMove)
import MCTS.Rng.Mix (mix)
import MCTS.Transcript (decodeTranscript, encodeTranscript, runConfigHash)
import MCTS.Transcript.EquitySidecar
import MCTS.Verify.Divergence
import MCTS.Verify.Envelope
import MCTS.Types
import System.Directory (doesDirectoryExist, removePathForcibly)

main :: IO ()
main = do
    assert "command tree mentions verify" ("verify" `contains` renderCommandTree)
    assert "command json is object" (take 1 renderCommandJson == "{")
    assert "all leaves have examples" (all (not . null . examples) (leafSpecs commandSpec))
    assert "backend parser" (parseBackends "cpp-imperative,rust,haskell" == Right [CppImperative, Rust, Haskell])
    assert "command parser" (isRight (parseCommand ["bench", "selfplay", "--backend", "haskell", "--games", "1", "--seed", "42"]))
    assert "legacy parity workload parser" (parsesLegacyRollouts (parseCommand ["verify", "legacy-parity", "rollouts", "--backend", "cpp-legacy,haskell"]))
    assert "allow stale parser" (parsesAllowStale (parseCommand ["verify", "selfplay", "--backend", "cpp-imperative,haskell", "--allow-stale"]))
    assert "splitmix is deterministic" (mix 42 0 == mix 42 0 && mix 42 0 /= mix 42 1)
    assert "sha256 known vector" (sha256Hex (BS.pack []) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    assert "action enumeration roundtrip" (all (\a -> actionFromId (actionId a) == Just a) allActions)
    assert "notation roundtrip" (all (\a -> parseMove (renderMove a) == Just a) [Pawn 4 4, WallH 1 2, WallV 3 4])
    assert "initial board has legal moves" (not (null (legalMoves initialBoard)))
    let inputs = defaultRunInputs{inputGames = 2, inputSeed = 42, inputSims = FixedSims 12}
        transcript = Transcript (makeRunConfig inputs) (Envelope 1 Haskell "test" "haskell-logical") [runGame inputs 0, runGame inputs 1]
        encoded = encodeTranscript transcript
    assert "transcript encoding non-empty" (BS.length encoded > 48)
    assert "transcript roundtrip" (decodeTranscript encoded == Right transcript{transcriptConfig = (transcriptConfig transcript){runGames = 0}})
    assert "hash deterministic" (runConfigHash (makeRunConfig inputs) == runConfigHash (makeRunConfig inputs))
    assert "divergence same transcript is zero" (divergenceRate transcript transcript == DivergenceMetrics 0.0 0.0 0.0)
    let changed = transcript{transcriptGames = mapFirstGame changeFirstMove (transcriptGames transcript)}
    assert "divergence catches changed move" (moveDisagreementRate (divergenceRate transcript changed) > 0.0)
    exerciseEnvelopeChecks transcript
    exerciseSidecars transcript
    putStrLn "mcts-unit PASS"

assert :: String -> Bool -> IO ()
assert label ok =
    if ok
        then pure ()
        else error ("assertion failed: " <> label)

contains :: String -> String -> Bool
contains needle haystack = any (needle `prefixOf`) (tails haystack)

prefixOf :: String -> String -> Bool
prefixOf prefix value = take (length prefix) value == prefix

tails :: [a] -> [[a]]
tails [] = [[]]
tails xs@(_ : rest) = xs : tails rest

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight _ = False

parsesLegacyRollouts :: Either AppError Command -> Bool
parsesLegacyRollouts parsed =
    case parsed of
        Right (Verify (VerifyLegacyParity Rollouts False [CppLegacy, Haskell] inputs)) -> inputWorkload inputs == Rollouts
        _ -> False

parsesAllowStale :: Either AppError Command -> Bool
parsesAllowStale parsed =
    case parsed of
        Right (Verify (VerifySelfplay True [CppImperative, Haskell] _)) -> True
        _ -> False

exerciseEnvelopeChecks :: Transcript -> IO ()
exerciseEnvelopeChecks transcript = do
    assert "cohort envelope check" (checkCohortInvariant [transcript, transcript] == Right ())
    let archMismatch =
            transcript
                { transcriptEnvelope =
                    (transcriptEnvelope transcript)
                        { envelopeHostArch = "other-arch"
                        }
                }
        stale =
            transcript
                { transcriptEnvelope =
                    (transcriptEnvelope transcript)
                        { envelopeBuildId = "haskell-old"
                        }
                }
        expectedStale = EngineEnvelopeMismatch (BackendSlot Haskell) "build_id" "haskell-logical" "haskell-old"
    assert "cohort arch mismatch" (checkCohortInvariant [transcript, archMismatch] == Left (ArchEnvelopeMismatch "test" "other-arch"))
    assert "backend slot stale hard fail" (checkBackendSlot False stale == Left expectedStale)
    assert "backend slot stale warning" (checkBackendSlot True stale == Right [expectedStale])

exerciseSidecars :: Transcript -> IO ()
exerciseSidecars transcript = do
    let cacheRoot = ".mcts-cache-unit-sidecar"
        hashValue = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        stale =
            transcript
                { transcriptEnvelope =
                    (transcriptEnvelope transcript)
                        { envelopeBuildId = "haskell-old"
                        }
                }
    removeDirectoryIfExists cacheRoot
    currentEntry <- writeEquitySidecar (Just cacheRoot) hashValue transcript
    _ <- writeEquitySidecar (Just cacheRoot) hashValue stale
    decoded <- decodeEqStream <$> BS.readFile (sidecarEqPath currentEntry)
    assert "equity sidecar roundtrip" (decoded == Right (equityStreamForTranscript hashValue transcript))
    listed <- listEquitySidecars (Just cacheRoot)
    assert "equity sidecar list" (length listed == 2)
    pruned <- pruneEquitySidecars (Just cacheRoot) True
    assert "equity sidecar keep-current prune" (pruned == 1)
    remaining <- listEquitySidecars (Just cacheRoot)
    assert "equity sidecar current remains" (map sidecarBuildId remaining == ["haskell-logical"])
    removeDirectoryIfExists cacheRoot

removeDirectoryIfExists :: FilePath -> IO ()
removeDirectoryIfExists path = do
    exists <- doesDirectoryExist path
    if exists then removePathForcibly path else pure ()

changeFirstMove :: GameTranscript -> GameTranscript
changeFirstMove game =
    case gameMoves game of
        [] -> game
        record : rest ->
            let replacement = if moveChosen record == Pawn 0 0 then Pawn 1 0 else Pawn 0 0
             in game{gameMoves = record{moveChosen = replacement} : rest}

mapFirstGame :: (GameTranscript -> GameTranscript) -> [GameTranscript] -> [GameTranscript]
mapFirstGame _ [] = []
mapFirstGame f (game : rest) = f game : rest
