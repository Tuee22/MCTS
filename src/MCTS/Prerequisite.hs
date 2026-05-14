module MCTS.Prerequisite
    ( PrerequisiteNode (..)
    , prerequisiteRegistry
    , prerequisitesForBuild
    , checkPrerequisites
    , transitiveClosure
    , registryHasCycle
    ) where

import Data.List (nub)
import MCTS.Error (AppError (..))
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
    , (executableNode "ghc-9.14.1" "GHC 9.14.1 on PATH or under ghcup" "export PATH=$HOME/.ghcup/bin:$PATH" ["ghcup"] "ghc-9.14.1")
    , (executableNode "cabal-3.16.1.0" "Cabal 3.16.1.0 on PATH or under ghcup" "export PATH=$HOME/.ghcup/bin:$PATH" ["ghcup"] "cabal")
    , executableNode
        "cxx"
        "C++ compiler for C ABI backends"
        "install GCC or Clang and expose c++ on PATH"
        []
        "c++"
    , executableNode
        "llvm"
        "LLVM toolchain (shared by GHC -fllvm and BOLT)"
        "install LLVM; pin one minor across GHC -fllvm and BOLT"
        []
        "llvm-config"
    , executableNode
        "bolt"
        "BOLT post-link optimizer"
        "install LLVM BOLT (llvm-bolt) for the cpp-imperative/cpp-functional/rust steelman stacks"
        ["llvm"]
        "llvm-bolt"
    , executableNode
        "rustup"
        "rustup toolchain manager"
        "install rustup from https://rustup.rs"
        []
        "rustup"
    , executableNode
        "cargo"
        "Cargo for the Rust backend"
        "install rustup/cargo and expose cargo on PATH"
        ["rustup"]
        "cargo"
    , executableNode
        "rustc"
        "rustc for the Rust backend"
        "install rustup/rustc and expose rustc on PATH"
        ["rustup"]
        "rustc"
    , PrerequisiteNode
        "mimalloc"
        "mimalloc allocator (linked into the steelman backends)"
        "install mimalloc; the Docker image pins one version"
        []
        (fmap (/= Nothing) (findExecutable "mimalloc-redirect"))
    , PrerequisiteNode
        "pgo-profiles"
        "Profile directory root for PGO/BOLT builds"
        "create .build/profiles when running optimized backend builds"
        []
        (doesDirectoryExist ".build/profiles")
    , PrerequisiteNode
        "logical-backends"
        "The logical in-process backend cohort is available"
        "run cabal build all"
        []
        (pure True)
    , PrerequisiteNode
        "legacy-fixtures"
        "Legacy fixture directory exists"
        "run mcts docs generate"
        []
        (doesFileExist "test/golden/legacy/README.md")
    ]

prerequisitesForBuild :: String -> [PrerequisiteNode]
prerequisitesForBuild backend =
    transitiveClosure prerequisiteRegistry $
        case backend of
            "rust" -> ["cargo", "rustc", "pgo-profiles"]
            "cpp-legacy" -> ["cxx"]
            "cpp-imperative" -> ["cxx", "llvm", "bolt", "pgo-profiles", "mimalloc"]
            "cpp-functional" -> ["cxx", "llvm", "bolt", "pgo-profiles", "mimalloc"]
            _ -> []

executableNode :: String -> String -> String -> [String] -> String -> PrerequisiteNode
executableNode ident description remedy deps exe =
    PrerequisiteNode ident description remedy deps ((/= Nothing) <$> findExecutable exe)

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
