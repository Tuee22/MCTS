{-# LANGUAGE BangPatterns #-}

-- | Real UCT search using `MCTS.Search.Arena` per Phase 3 Sprint 3.3.
--
-- Selection by the doctrine UCT formula `q + c * sqrt(ln(N_parent) /
-- N_child)`, one-child-at-a-time expansion on second visit, random-
-- rollout leaf evaluation on first visit, and per-rollout
-- backpropagation along the recursive descent path. Phase 8 layers on
-- `-O2 -fllvm` plus `INLINABLE`; the search loop is currently monomorphic,
-- so explicit `SPECIALIZE` pragmas are not needed. The API exported here
-- stays stable across future profile-driven representation work.
module MCTS.Search.UCT
    ( uctSearch
    , uctSearchWithEquity
    , terminalPlayout
    ) where

import Control.Monad.ST (ST, runST)
import Data.Bits (xor)
import Data.Int (Int32, Int64)
import Data.List (sortOn)
import Data.Word (Word16, Word32, Word64, Word8)
import MCTS.Engine
    ( ActionIds
    , Board (..)
    , actionIdAtUnsafe
    , actionIdsLength
    , applyActionId
    , applyActionIdNoPly
    , legalActionSet
    , legalActionSetNonTerminal
    , nonTerminalOutcome
    , terminalOutcome
    )
import MCTS.Rng.Mix (mix)
import qualified MCTS.Search.Arena as Arena
import MCTS.Types
    ( Action
    , actionFromId
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

{-# INLINE terminalPlayout #-}
terminalPlayout :: Board -> Word64 -> Int -> Float
terminalPlayout = rollout

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
    let rootMoves = legalActionSet board
        rootMoveCount = actionIdsLength rootMoves
        -- Capacity has to hold every node the recursive descent may
        -- create: root + every legal child of root + one expanded
        -- child set per sim. `legalActionSet` emits at most four pawn
        -- moves plus the twelve-wall cap, so 16 is a safe per-sim
        -- branch bound.
        capacity = max 32 (1 + rootMoveCount + nSims * 16)
    arena <- Arena.newArena capacity
    root <- Arena.allocNode arena (-1) 0xFF
    (rootFirstChild, rootNumChildren) <- allocChildren arena root rootMoves
    Arena.setChildren arena root rootFirstChild rootNumChildren
    -- Mark root as already-visited so descent goes through children, not
    -- a rollout from the root itself.
    Arena.addVisits arena root 1
    let maxPliesWord = fromIntegral maxPlies
    let runSims !i !simSeed
            | i >= nSims = pure ()
            | otherwise = do
                let s' = mix simSeed (fromIntegral i)
                _ <- descend arena root board s' maxPlies maxPliesWord
                runSims (i + 1) s'
    runSims 0 seed
    -- Build the visit list and equity list at the root.
    let collect i = do
            let actionByte = actionIdAtUnsafe rootMoves i
                nid = rootFirstChild + fromIntegral i
            v <- Arena.readVisits arena nid
            vs <- Arena.readValueSum arena nid
            let visitsW32 = fromIntegral v :: Word32
                equity = if v == 0 then 0 else vs / fromIntegral v
            pure (actionByte, visitsW32, equity)
    rows <- mapM collect [0 .. rootMoveCount - 1]
    let sortedRows = sortOn (\(a, _, _) -> a) rows
        visitsOut = [(actionFromIdUnsafe a, v) | (a, v, _) <- sortedRows]
        equityOut = [(actionFromIdUnsafe a, e) | (a, _, e) <- sortedRows]
        best = case sortOn finalChoiceKey sortedRows of
            (a, _, _) : _ -> actionFromIdUnsafe a
            [] ->
                if rootMoveCount > 0
                    then actionFromIdUnsafe (actionIdAtUnsafe rootMoves 0)
                    else error "MCTS.Search.UCT: no legal moves and no fallback"
    pure (best, visitsOut, equityOut)
  where
    -- Sprint 7.2 cohort agreement: the final choice picks the highest
    -- visit count with action-id tiebreak only. C++/Rust backends do
    -- the same (`if (child.visit_count > best_visits) { ... }` in
    -- the C++ and Rust search loops); aligning the
    -- Haskell side here drops the previous `nonTerminalRank`-then-
    -- equity tiebreak so the live cohort stays uniform.
    finalChoiceKey (actionByte, visits, _equity) =
        ( negate (fromIntegral visits :: Int)
        , actionByte
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
    -> Word16
    -> ST s Float
descend arena nid board seed maxPlies maxPliesWord = do
    let terminal = terminalOutcome maxPliesWord board
    if terminal /= nonTerminalOutcome
        then do
            let outcome = terminal
            Arena.addVisitValue arena nid outcome
            pure outcome
        else do
            visits <- Arena.readVisits arena nid
            if visits == 0
                then do
                    -- First visit to a non-terminal leaf: rollout.
                    let outcome = rollout board seed maxPlies
                    Arena.addVisitValue arena nid outcome
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
                            let !np = visits + 1
                            chosenIdx <- pickByUctIndex arena fc numKids np board
                            let bestNid = fc + chosenIdx
                            actByte <- Arena.readActionId arena bestNid
                            let nextBoard = applyActionId actByte board
                                childSeed = mix seed (fromIntegral chosenIdx + 1)
                            outcome <- descend arena bestNid nextBoard childSeed maxPlies maxPliesWord
                            Arena.addVisitValue arena nid outcome
                            pure outcome

-- | On a node's second visit, allocate one arena slot per legal move
-- (contiguously, so the children are addressable as
-- `[firstChild .. firstChild + numChildren - 1]`). Returns
-- `(firstChild, numChildren)`.
expandChildren :: Arena.Arena s -> Arena.NodeId -> Board -> ST s (Arena.NodeId, Int32)
expandChildren arena parent board = do
    let moves = legalActionSetNonTerminal board
    (firstChild, numKids) <- allocChildren arena parent moves
    Arena.setChildren arena parent firstChild numKids
    pure (firstChild, numKids)

allocChildren :: Arena.Arena s -> Arena.NodeId -> ActionIds -> ST s (Arena.NodeId, Int32)
allocChildren arena parent moves
    | moveCount == 0 = pure (-1, 0)
    | otherwise = do
        firstChild <- go 0 (-1)
        pure (firstChild, fromIntegral moveCount)
  where
    moveCount = actionIdsLength moves
    go i first
        | i >= moveCount = pure first
        | otherwise = do
            nid <- Arena.allocNode arena parent (actionIdAtUnsafe moves i)
            let first' = if i == 0 then nid else first
            go (i + 1) first'

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
-- agreement with the C++ smoke runs).
pickByUctIndex arena firstChild numKids np _board =
    go 0 0 0.0
  where
    cParam :: Float
    cParam = 1.41421356
    lnNp :: Float
    lnNp = log (fromIntegral (max 1 np))
    go !i !bestIdx !bestScore
        | i >= numKids = pure bestIdx
        | otherwise = do
            let nid = firstChild + i
            n <- Arena.readVisits arena nid
            if n == 0
                then pure i
                else do
                    v <- Arena.readValueSum arena nid
                    let q = v / fromIntegral n
                        u = cParam * sqrt (lnNp / fromIntegral n)
                        score = q + u
                        better =
                            i == 0
                                || score > bestScore
                        bestIdx' = if better then i else bestIdx
                        bestScore' = if better then score else bestScore
                    go (i + 1) bestIdx' bestScore'

-- | Random rollout from `board` to a terminal state or the ply cap.
{-# INLINE rollout #-}
rollout :: Board -> Word64 -> Int -> Float
rollout board0 seed0 maxPlies = go 0 (boardPly board0) board0 seed0
  where
    maxPliesWord :: Word16
    maxPliesWord = fromIntegral maxPlies

    go :: Int -> Word16 -> Board -> Word64 -> Float
    go !step !ply !board !seed
        | boardHero board >= 72 = 1.0
        | boardVillain board <= 8 = -1.0
        | ply >= maxPliesWord = 0.0
        | otherwise =
            let moves = legalActionSetNonTerminal board
                n = actionIdsLength moves
             in if n == 0
                    then 0.0
                    else
                        let pick = signedModulo (seed `xor` fromIntegral step) n
                            actionByte = actionIdAtUnsafe moves pick
                            next = applyActionIdNoPly actionByte board
                            nextSeed = mix seed (fromIntegral step)
                         in go (step + 1) (ply + 1) next nextSeed

    signedModulo :: Word64 -> Int -> Int
    signedModulo draw n =
        let signed = fromIntegral draw :: Int64
            width = fromIntegral n :: Int64
            remainder = signed `rem` width
         in fromIntegral (if remainder < 0 then remainder + width else remainder)

actionFromIdUnsafe :: Word8 -> Action
actionFromIdUnsafe ident =
    case actionFromId ident of
        Just action -> action
        Nothing -> error "MCTS.Search.UCT: bad action id in arena"
