{-# LANGUAGE BangPatterns #-}

-- | Real UCT search using `MCTS.Search.Arena` per Phase 3 Sprint 3.3.
--
-- Selection by the doctrine UCT formula `q + c * sqrt(ln(N_parent) /
-- N_child)`, one-child-at-a-time expansion on second visit, random-
-- rollout leaf evaluation on first visit, and per-rollout
-- backpropagation along the recursive descent path. Phase 8 layers on
-- `-O2 -fllvm` + `INLINABLE` + `SPECIALIZE` + a per-rollout scratch
-- board; the API exported here stays stable across that migration.
module MCTS.Search.UCT
    ( uctSearch
    , uctSearchWithEquity
    ) where

import Control.Monad.ST (ST, runST)
import Data.Bits (xor)
import Data.Int (Int32)
import Data.List (sortOn)
import Data.STRef (newSTRef, readSTRef, writeSTRef)
import Data.Word (Word32, Word64)
import MCTS.Engine
    ( Board
    , applyMove
    , legalMoves
    , nonTerminalOutcome
    , terminalOutcome
    , terminalWinner
    )
import MCTS.Rng.Mix (mix)
import qualified MCTS.Search.Arena as Arena
import MCTS.Types
    ( Action
    , Winner (..)
    , actionFromId
    , actionId
    )

-- | UCT search.
--
--  * `board` is the start position.
--  * `seed` is the per-move splitmix seed.
--  * `nSims` is the simulation budget (`>= 1`).
--  * `maxPlies` caps the rollout depth (after which we declare a draw).
--
-- Returns the highest-visit child action plus the visit list at the
-- root sorted ascending by `action_id` so callers can pass the list
-- straight to the transcript codec.
{-# INLINEABLE uctSearch #-}
uctSearch :: Board -> Word64 -> Int -> Int -> (Action, [(Action, Word32)])
uctSearch board seed nSims maxPlies =
    let (act, visits, _) = uctSearchWithEquity board seed nSims maxPlies
     in (act, visits)

-- | Same as `uctSearch`, but also returns the per-child equity estimate
-- (`valueSum / visits` from Hero's perspective). The third tuple field
-- is `[(Action, equity)]` sorted ascending by `action_id`; equities of
-- unvisited children are reported as `0.0`.
--
-- This is the kernel that the foreign-engine equity-recompute path in
-- `MCTS.Engine.Recompute` reuses to populate `.eq` sidecar streams.
{-# INLINEABLE uctSearchWithEquity #-}
uctSearchWithEquity
    :: Board
    -> Word64
    -> Int
    -> Int
    -> (Action, [(Action, Word32)], [(Action, Float)])
uctSearchWithEquity board seed nSims maxPlies = runST $ do
    let rootMoves = legalMoves board
        -- Capacity has to hold every node the recursive descent may
        -- create: root + every legal child of root + one expanded
        -- child set per sim. `legalMoves` emits at most four pawn
        -- moves plus the twelve-wall cap, so 16 is a safe per-sim
        -- branch bound.
        capacity = max 32 (1 + length rootMoves + nSims * 16)
    arena <- Arena.newArena capacity
    root <- Arena.allocNode arena (-1) 0xFF
    rootChildrenIds <- mapM (\action -> Arena.allocNode arena root (actionId action)) rootMoves
    case rootChildrenIds of
        firstChild : _ -> Arena.setChildren arena root firstChild (fromIntegral (length rootMoves))
        [] -> Arena.setChildren arena root (-1) 0
    -- Mark root as already-visited so descent goes through children, not
    -- a rollout from the root itself.
    Arena.addVisits arena root 1
    let rootChildren = zip rootMoves rootChildrenIds
    seedRef <- newSTRef seed
    let runSims i
            | i >= nSims = pure ()
            | otherwise = do
                s <- readSTRef seedRef
                let s' = mix s (fromIntegral i)
                writeSTRef seedRef s'
                _ <- descend arena root board s' maxPlies
                runSims (i + 1)
    runSims 0
    -- Build the visit list and equity list at the root.
    let collect (action, nid) = do
            v <- Arena.readVisits arena nid
            vs <- Arena.readValueSum arena nid
            let visitsW32 = fromIntegral v :: Word32
                equity = if v == 0 then 0 else vs / fromIntegral v
            pure (action, visitsW32, equity)
    rows <- mapM collect rootChildren
    let sortedRows = sortOn (\(a, _, _) -> actionId a) rows
        visitsOut = [(a, v) | (a, v, _) <- sortedRows]
        equityOut = [(a, e) | (a, _, e) <- sortedRows]
        best = case sortOn finalChoiceKey sortedRows of
            (a, _, _) : _ -> a
            [] -> case rootMoves of
                a : _ -> a
                [] -> error "MCTS.Search.UCT: no legal moves and no fallback"
    pure (best, visitsOut, equityOut)
  where
    -- Sprint 7.2 cohort agreement: the final choice picks the highest
    -- visit count with action-id tiebreak only. C++/Rust backends do
    -- the same (`if (child.visit_count > best_visits) { ... }` in
    -- the retired C++ search loops and live Rust loop); aligning the
    -- Haskell side here drops the previous `nonTerminalRank`-then-
    -- equity tiebreak so the live cohort stays uniform.
    finalChoiceKey (action, visits, _equity) =
        ( negate (fromIntegral visits :: Int)
        , actionId action
        )

-- | Recursive descent. Returns the rollout outcome from Hero's
-- perspective. Side-effects: increments `nid`'s visit count and value
-- sum; expands `nid`'s children on second visit; lazily creates
-- grandchildren on third visit; etc.
{-# INLINEABLE descend #-}
descend
    :: Arena.Arena s
    -> Arena.NodeId
    -> Board
    -> Word64
    -> Int
    -> ST s Float
descend arena nid board seed maxPlies = do
    case terminalWinner (fromIntegral maxPlies) board of
        Just w -> do
            let outcome = winnerOutcome w
            Arena.addVisits arena nid 1
            Arena.addValueSum arena nid outcome
            pure outcome
        Nothing -> do
            visits <- Arena.readVisits arena nid
            if visits == 0
                then do
                    -- First visit to a non-terminal leaf: rollout.
                    let outcome = rollout board seed maxPlies
                    Arena.addVisits arena nid 1
                    Arena.addValueSum arena nid outcome
                    pure outcome
                else do
                    -- Subsequent visit: ensure children exist, pick by UCT,
                    -- recurse into the chosen child.
                    firstChild <- Arena.readFirstChild arena nid
                    (fc, numKids) <-
                        if firstChild == -1
                            then expandChildren arena nid board
                            else do
                                n <- Arena.readNumChildren arena nid
                                pure (firstChild, n)
                    if numKids == 0
                        then do
                            -- No legal moves available - treat as draw.
                            Arena.addVisits arena nid 1
                            pure 0.0
                        else do
                            np <- pure (visits + 1)
                            chosenIdx <- pickByUctIndex arena fc numKids np board
                            let bestNid = fc + chosenIdx
                            actByte <- Arena.readActionId arena bestNid
                            case actionFromId actByte of
                                Nothing ->
                                    error "MCTS.Search.UCT: bad action id in arena"
                                Just bestAction -> do
                                    let nextBoard = applyMove bestAction board
                                        childSeed = mix seed (fromIntegral chosenIdx + 1)
                                    outcome <- descend arena bestNid nextBoard childSeed maxPlies
                                    Arena.addVisits arena nid 1
                                    Arena.addValueSum arena nid outcome
                                    pure outcome

-- | On a node's second visit, allocate one arena slot per legal move
-- (contiguously, so the children are addressable as
-- `[firstChild .. firstChild + numChildren - 1]`). Returns
-- `(firstChild, numChildren)`.
expandChildren :: Arena.Arena s -> Arena.NodeId -> Board -> ST s (Arena.NodeId, Int32)
expandChildren arena parent board = do
    let moves = legalMoves board
    case moves of
        [] -> do
            Arena.setChildren arena parent (-1) 0
            pure (-1, 0)
        _ -> do
            childIds <- mapM (\m -> Arena.allocNode arena parent (actionId m)) moves
            case childIds of
                fc : _ -> do
                    Arena.setChildren arena parent fc (fromIntegral (length moves))
                    pure (fc, fromIntegral (length moves))
                [] -> do
                    Arena.setChildren arena parent (-1) 0
                    pure (-1, 0)

-- | Convert a terminal winner to a Hero-perspective outcome value.
winnerOutcome :: Winner -> Float
winnerOutcome HeroWin = 1.0
winnerOutcome VillainWin = -1.0
winnerOutcome Draw = 0.0

-- | Pick the index (into the contiguous child range) of the best child
-- by UCT score. `np` is the parent's visit count *after* this descent
-- step (used inside `ln(np)`). Unvisited children win ties.
pickByUctIndex
    :: Arena.Arena s
    -> Arena.NodeId
    -> Int32
    -> Int32
    -> Board
    -> ST s Int32
-- Sprint 7.2 cohort agreement: the tiebreaker drops the
-- `nonTerminalRank` heuristic and falls back to action-id order,
-- matching the C++/Rust backends' first-emitted-unvisited-child policy.
-- The `nonTerminalRank` function stays exported for standalone test
-- coverage; only its use here as a tiebreak is removed. Forward
-- progress at `sims = 1` now depends on `MCTS.Engine.legalMoves`
-- emitting pawn moves with smaller-y-bias for the side-to-move (the
-- canonical action enumeration already orders pawn moves by y*9+x so
-- the first emitted move at the initial position is `Pawn 3 0`, in
-- agreement with the retired C++ smoke runs).
pickByUctIndex arena firstChild numKids np _board = do
    scored <- mapM scoreIdx [0 .. numKids - 1]
    case sortOn scoreKey scored of
        (idx, _, _) : _ -> pure idx
        [] -> pure 0
  where
    cParam :: Float
    cParam = 1.41421356
    lnNp :: Float
    lnNp = log (fromIntegral (max 1 np))
    scoreIdx i = do
        let nid = firstChild + i
        n <- Arena.readVisits arena nid
        v <- Arena.readValueSum arena nid
        actionByte <- Arena.readActionId arena nid
        let score
                | n == 0 = 1.0e30
                | otherwise =
                    let q = v / fromIntegral n
                        u = cParam * sqrt (lnNp / fromIntegral n)
                     in q + u
        pure (i, score, actionByte)
    scoreKey (_, score, actionByte) =
        (negate score, actionByte)

-- | Random rollout from `board` to a terminal state or the ply cap.
{-# INLINEABLE rollout #-}
rollout :: Board -> Word64 -> Int -> Float
rollout = go 0
  where
    go !step !board !seed !maxPlies
        | step >= maxPlies = 0.0
        | otherwise =
            let outcome = terminalOutcome (fromIntegral maxPlies) board
             in if outcome /= nonTerminalOutcome
                    then outcome
                    else case legalMoves board of
                        [] -> 0.0
                        moves ->
                            let n = length moves
                                pick = fromIntegral (seed `xor` fromIntegral step) `mod` n
                                action = chooseAction pick moves
                                next = applyMove action board
                                nextSeed = mix seed (fromIntegral step)
                             in go (step + 1) next nextSeed maxPlies
    chooseAction idx moves = moves !! max 0 (min (length moves - 1) idx)
