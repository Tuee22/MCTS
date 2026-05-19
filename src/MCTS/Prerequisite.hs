module MCTS.Prerequisite
    ( PrerequisiteNode (..)
    , prerequisiteRegistry
    , prerequisitesForBuild
    , prerequisitesForTest
    , checkPrerequisites
    , transitiveClosure
    , registryHasCycle
    ) where

import Data.List (nub)
import MCTS.Error (AppError (..))
import MCTS.Subprocess (ProcessOutput (..), Subprocess (..), capture)
import System.Directory (doesDirectoryExist, doesFileExist, findExecutable)

data PrerequisiteNode = PrerequisiteNode
    { nodeId :: !String
    , nodeDescription :: !String
    , nodeRemedy :: !String
    , nodeDependsOn :: ![String]
    , nodeProbe :: IO Bool
    }

prerequisiteRegistry :: [PrerequisiteNode]
prerequisiteRegistry =
    [ executableNode
        "ghcup"
        "ghcup installer present"
        "install ghcup from https://www.haskell.org/ghcup/"
        []
        "ghcup"
    , versionNode
        "ghc-9.14.1"
        "GHC 9.14.1 on PATH or under ghcup"
        "export PATH=$HOME/.ghcup/bin:$PATH and run ghcup install ghc 9.14.1"
        ["ghcup"]
        "ghc-9.14.1"
        ["--numeric-version"]
        "9.14.1"
    , versionNode
        "cabal-3.16.1.0"
        "Cabal 3.16.1.0 on PATH or under ghcup"
        "export PATH=$HOME/.ghcup/bin:$PATH and run ghcup install cabal 3.16.1.0"
        ["ghcup"]
        "cabal"
        ["--numeric-version"]
        "3.16.1.0"
    , versionPrefixNode
        "cxx"
        "GCC/G++ C++ compiler for C ABI backends"
        "install GCC/G++ from ubuntu:24.04 build-essential and expose c++ on PATH"
        []
        "c++"
        ["--version"]
        ""
    , versionPrefixNode
        "llvm"
        "LLVM 19 toolchain (shared by GHC -fllvm and BOLT)"
        "install LLVM 19 and expose llvm-config on PATH"
        []
        "llvm-config"
        ["--version"]
        "19."
    , versionContainsNode
        "bolt"
        "LLVM BOLT 19 post-link optimizer"
        "install LLVM BOLT 19 (llvm-bolt) for the cpp-imperative/cpp-functional/rust steelman stacks"
        ["llvm"]
        "llvm-bolt"
        ["--version"]
        "LLVM version 19."
    , executableNode
        "perf"
        "Linux perf profiler for BOLT profile generation"
        "install linux-tools/perf in the project container before running full BOLT profile generation"
        []
        "perf"
    , executableNode
        "lld-linker"
        "LLVM LLD 19 linker for the Rust backend"
        "install LLVM LLD 19 and expose ld.lld-19 on PATH"
        ["llvm"]
        "ld.lld-19"
    , versionContainsNode
        "rustup"
        "rustup toolchain manager"
        "install rustup from https://rustup.rs"
        []
        "rustup"
        ["--version"]
        "rustup"
    , versionContainsNode
        "cargo"
        "Cargo for the Rust 1.95.0 backend"
        "install rustup/cargo 1.95.0 and expose cargo on PATH"
        ["rustup"]
        "cargo"
        ["--version"]
        "1.95.0"
    , versionContainsNode
        "rustc"
        "rustc 1.95.0 for the Rust backend"
        "install rustup/rustc 1.95.0 and expose rustc on PATH"
        ["rustup"]
        "rustc"
        ["--version"]
        "1.95.0"
    , PrerequisiteNode
        "mimalloc"
        "mimalloc allocator (linked into the steelman backends)"
        "install libmimalloc-dev; the Docker image uses the Ubuntu Noble package"
        []
        mimallocProbe
    , PrerequisiteNode
        "pgo-profiles"
        "Profile directory root for PGO/BOLT builds"
        "create container-local .build/profiles when running optimized backend builds"
        []
        (doesDirectoryExist ".build/profiles")
    , profileDirectoryNode "cpp-imperative-pgo-profile" "cpp-imperative/pgo-profile"
    , profileDirectoryNode "cpp-imperative-bolt-profile" "cpp-imperative/bolt-profile"
    , profileDirectoryNode "cpp-functional-pgo-profile" "cpp-functional/pgo-profile"
    , profileDirectoryNode "cpp-functional-bolt-profile" "cpp-functional/bolt-profile"
    , profileDirectoryNode "rust-pgo-profile" "rust/pgo-profile"
    , PrerequisiteNode
        "logical-backends"
        "The logical in-process backend cohort is available"
        "run docker compose run --rm mcts mcts check-code"
        []
        (pure True)
    , PrerequisiteNode
        "legacy-fixtures"
        "Legacy fixture directory exists"
        "run docker compose run --rm mcts mcts docs generate"
        []
        (doesFileExist "test/golden/legacy/README.md")
    , PrerequisiteNode
        "libmcts-cpp-legacy-built"
        "cpp-legacy shared library exists for dynamic FFI smoke tests"
        "run docker compose run --rm mcts mcts build cpp-legacy"
        ["cxx"]
        (doesFileExist "cpp-legacy/build/libmcts_cpp_legacy.so")
    , PrerequisiteNode
        "libmcts-cpp-imperative-built"
        "cpp-imperative shared library exists for dynamic FFI smoke tests"
        "run docker compose run --rm mcts mcts build cpp-imperative"
        ["cxx"]
        (doesFileExist "cpp-imperative/build/libmcts_cpp_imperative.so")
    , PrerequisiteNode
        "libmcts-cpp-functional-built"
        "cpp-functional shared library exists for dynamic FFI smoke tests"
        "run docker compose run --rm mcts mcts build cpp-functional"
        ["cxx"]
        (doesFileExist "cpp-functional/build/libmcts_cpp_functional.so")
    , PrerequisiteNode
        "libmcts-rust-built"
        "Rust cdylib exists for dynamic FFI smoke tests"
        "run docker compose run --rm mcts mcts build rust"
        ["cargo", "rustc"]
        (doesFileExist "rust/target/release/libmcts_rust.so")
    ]

prerequisitesForBuild :: String -> [PrerequisiteNode]
prerequisitesForBuild backend =
    transitiveClosure prerequisiteRegistry $
        case backend of
            "rust" -> ["cargo", "rustc", "lld-linker", "pgo-profiles"]
            "cpp-legacy" -> ["cxx"]
            "legacy-fixtures" -> ["cxx"]
            "cpp-imperative" -> ["cxx", "llvm", "bolt", "pgo-profiles", "mimalloc"]
            "cpp-functional" -> ["cxx", "llvm", "bolt", "pgo-profiles", "mimalloc"]
            _ -> []

prerequisitesForTest :: [PrerequisiteNode]
prerequisitesForTest =
    transitiveClosure prerequisiteRegistry ["ghc-9.14.1", "cabal-3.16.1.0", "logical-backends"]

executableNode :: String -> String -> String -> [String] -> String -> PrerequisiteNode
executableNode ident description remedy deps exe =
    PrerequisiteNode ident description remedy deps ((/= Nothing) <$> findExecutable exe)

profileDirectoryNode :: String -> FilePath -> PrerequisiteNode
profileDirectoryNode ident path =
    PrerequisiteNode
        ident
        ("Profile directory exists: " <> path)
        ("create " <> path <> " before running the full optimized backend build")
        ["pgo-profiles"]
        (doesDirectoryExist path)

versionNode
    :: String
    -> String
    -> String
    -> [String]
    -> FilePath
    -> [String]
    -> String
    -> PrerequisiteNode
versionNode ident description remedy deps exe args expected =
    PrerequisiteNode ident description remedy deps $ do
        versionProbe exe args (== expected)

versionPrefixNode
    :: String
    -> String
    -> String
    -> [String]
    -> FilePath
    -> [String]
    -> String
    -> PrerequisiteNode
versionPrefixNode ident description remedy deps exe args expectedPrefix =
    PrerequisiteNode ident description remedy deps $
        versionProbe exe args (prefixMatches expectedPrefix)

versionContainsNode
    :: String
    -> String
    -> String
    -> [String]
    -> FilePath
    -> [String]
    -> String
    -> PrerequisiteNode
versionContainsNode ident description remedy deps exe args expectedNeedle =
    PrerequisiteNode ident description remedy deps $
        versionProbe exe args (contains expectedNeedle)

versionProbe :: FilePath -> [String] -> (String -> Bool) -> IO Bool
versionProbe exe args predicate = do
    executable <- findExecutable exe
    case executable of
        Nothing -> pure False
        Just _ -> do
            result <- capture (Subprocess exe args Nothing Nothing)
            pure $
                case result of
                    Right output -> predicate (firstLine (processStdout output <> processStderr output))
                    Left _ -> False

firstLine :: String -> String
firstLine content =
    case lines content of
        line : _ -> line
        [] -> ""

prefixMatches :: String -> String -> Bool
prefixMatches "" value = not (null value)
prefixMatches prefix value = take (length prefix) value == prefix

contains :: String -> String -> Bool
contains needle haystack = any (prefixMatches needle) (tails haystack)

mimallocProbe :: IO Bool
mimallocProbe = do
    candidates <-
        mapM
            doesFileExist
            [ "/usr/lib/aarch64-linux-gnu/libmimalloc.so"
            , "/usr/lib/x86_64-linux-gnu/libmimalloc.so"
            , "/usr/local/lib/libmimalloc.so"
            ]
    pure (or candidates)

tails :: [a] -> [[a]]
tails [] = [[]]
tails xs@(_ : rest) = xs : tails rest

transitiveClosure :: [PrerequisiteNode] -> [String] -> [PrerequisiteNode]
transitiveClosure registry seeds =
    let resolve visited [] = visited
        resolve visited (ident : rest)
            | ident `elem` map nodeId visited = resolve visited rest
            | otherwise =
                case lookupNode registry ident of
                    Nothing -> resolve visited rest
                    Just node -> resolve (visited <> [node]) (nodeDependsOn node <> rest)
     in resolve [] (nub seeds)

lookupNode :: [PrerequisiteNode] -> String -> Maybe PrerequisiteNode
lookupNode registry ident =
    case filter ((== ident) . nodeId) registry of
        node : _ -> Just node
        [] -> Nothing

registryHasCycle :: [PrerequisiteNode] -> Bool
registryHasCycle registry =
    any (\node -> nodeId node `elem` reachable (nodeDependsOn node)) registry
  where
    reachable seeds = map nodeId (transitiveClosure registry seeds)

checkPrerequisites :: [PrerequisiteNode] -> IO (Either AppError ())
checkPrerequisites nodes = go nodes
  where
    go [] = pure (Right ())
    go (node : rest) = do
        ok <- nodeProbe node
        if ok
            then go rest
            else
                pure
                    ( Left
                        ( PrerequisiteUnmet
                            (nodeId node)
                            (nodeDescription node)
                            (nodeRemedy node)
                        )
                    )
