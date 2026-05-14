module Main where

import Data.List (isPrefixOf, isSuffixOf)
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>))

main :: IO ()
main = do
    files <- walk "."
    problems <- fmap concat (mapM inspect files)
    if null problems
        then putStrLn "mcts-haskell-style PASS"
        else error (unlines problems)

walk :: FilePath -> IO [FilePath]
walk root = do
    names <- listDirectory root
    fmap concat $
        mapM
            ( \name -> do
                let path = root </> name
                isDir <- doesDirectoryExist path
                isFile <- doesFileExist path
                if ignored path
                    then pure []
                    else
                        if isDir
                            then walk path
                            else pure [path | isFile && ".hs" `isSuffixOf` path]
            )
            names

ignored :: FilePath -> Bool
ignored path =
    any (`isPrefixOf` path) ["./.git", "./dist-newstyle", "./.mcts-cache"]

inspect :: FilePath -> IO [String]
inspect path = do
    content <- readFile path
    let rows = zip [(1 :: Int) ..] (lines content)
    pure
        [ "tab character: " <> path <> ":" <> show n
        | (n, row) <- rows
        , '\t' `elem` row
        ]
