{-# LANGUAGE BangPatterns #-}

-- | MCTS tree arena in the `ST s` monad per Phase 3 Sprint 3.2 / Hard
-- Constraint 20.
--
-- Layout is structure-of-arrays. Each tree allocation lives in an
-- `Arena s` value containing six parallel mutable arrays plus a cursor
-- (`arenaSize`) tracking how many nodes have been allocated. Node IDs are
-- 32-bit signed integers; `-1` sentinels indicate "no parent" / "no
-- child".
--
-- This is the current measured Haskell engine baseline. Sprint 8.17
-- evaluated a hand-rolled single-buffer migration (one `STUArray s Int
-- Word32` carrying the same SoA fields at named per-field offsets) and
-- recorded a focused-bench regression (`Q1a` `-5.5%` ST, `Q1b` `-1.1%`
-- ST) versus this baseline, so the migration was reverted and recorded
-- as `measured but rejected` per the Performance Measurement Doctrine.
-- The exported API is the load-bearing surface and remains stable
-- across any future profile-driven migration.
--
-- Sprint 8.18 uses `Data.Array.Base.unsafeRead`/`unsafeWrite` for all
-- hot-path arena slot accesses. Indices are produced by `allocNode`
-- (which advances the cursor monotonically up to `arenaCapacity_`) and
-- by `firstChild + i` arithmetic in `MCTS.Search.UCT` (where
-- `0 <= i < numChildren` and every child slot was allocated before
-- it is read). Indices are therefore provably in `[0, capacity)`; the
-- bounds checks that `Data.Array.ST.readArray`/`writeArray` emit are
-- pure overhead on this call path.
module MCTS.Search.Arena
    ( NodeId
    , Arena
    , newArena
    , freeArena
    , arenaCapacity
    , arenaSize
    , allocNode
    , readVisits
    , addVisits
    , readValueSum
    , addValueSum
    , addVisitValue
    , readActionId
    , readParent
    , readFirstChild
    , readNumChildren
    , setChildren
    , treeRoot
    , treeReroot
    , bulkVisits
    ) where

import Control.Monad.ST (ST)
import Data.Array.Base (unsafeRead, unsafeWrite)
import Data.Array.ST (STUArray, newArray)
import Data.Int (Int32)
import Data.STRef (STRef, modifySTRef', newSTRef, readSTRef, writeSTRef)
import Data.Word (Word8)

type NodeId = Int32

data Arena s = Arena
    { arenaCapacity_ :: !Int
    , arenaCursor :: !(STRef s Int)
    , arenaParent :: !(STUArray s NodeId NodeId)
    , arenaFirstChild :: !(STUArray s NodeId NodeId)
    , arenaNumChildren :: !(STUArray s NodeId Int32)
    , arenaActionId :: !(STUArray s NodeId Word8)
    , arenaVisits :: !(STUArray s NodeId Int32)
    , arenaValueSum :: !(STUArray s NodeId Float)
    }

newArena :: Int -> ST s (Arena s)
newArena capacity
    | capacity <= 0 = error "MCTS.Search.Arena: capacity must be positive"
    | otherwise = do
        cursor <- newSTRef 0
        let upper = fromIntegral (capacity - 1)
        parent <- newArray (0, upper) (-1)
        firstChild <- newArray (0, upper) (-1)
        numChildren <- newArray (0, upper) 0
        actionId <- newArray (0, upper) 0
        visits <- newArray (0, upper) 0
        valueSum <- newArray (0, upper) 0
        pure
            Arena
                { arenaCapacity_ = capacity
                , arenaCursor = cursor
                , arenaParent = parent
                , arenaFirstChild = firstChild
                , arenaNumChildren = numChildren
                , arenaActionId = actionId
                , arenaVisits = visits
                , arenaValueSum = valueSum
                }

-- | Reset an arena for reuse. Sets the cursor to 0; arrays are left
-- physically allocated. The next `allocNode` overwrites slot 0.
freeArena :: Arena s -> ST s ()
freeArena arena = writeSTRef (arenaCursor arena) 0

arenaCapacity :: Arena s -> Int
arenaCapacity = arenaCapacity_

arenaSize :: Arena s -> ST s Int
arenaSize = readSTRef . arenaCursor

allocNode :: Arena s -> NodeId -> Word8 -> ST s NodeId
allocNode arena parent action = do
    !idx <- readSTRef (arenaCursor arena)
    if idx >= arenaCapacity_ arena
        then error "MCTS.Search.Arena: arena overflow"
        else do
            let nid = fromIntegral idx :: NodeId
                off = idx
            unsafeWrite (arenaParent arena) off parent
            unsafeWrite (arenaFirstChild arena) off (-1)
            unsafeWrite (arenaNumChildren arena) off 0
            unsafeWrite (arenaActionId arena) off action
            unsafeWrite (arenaVisits arena) off 0
            unsafeWrite (arenaValueSum arena) off 0
            modifySTRef' (arenaCursor arena) (+ 1)
            pure nid

{-# INLINEABLE readVisits #-}
readVisits :: Arena s -> NodeId -> ST s Int32
readVisits arena nid =
    unsafeRead (arenaVisits arena) (fromIntegral nid)

{-# INLINEABLE addVisits #-}
addVisits :: Arena s -> NodeId -> Int32 -> ST s ()
addVisits arena nid n = do
    let !off = fromIntegral nid
    !current <- unsafeRead (arenaVisits arena) off
    unsafeWrite (arenaVisits arena) off (current + n)

{-# INLINEABLE readValueSum #-}
readValueSum :: Arena s -> NodeId -> ST s Float
readValueSum arena nid =
    unsafeRead (arenaValueSum arena) (fromIntegral nid)

{-# INLINEABLE addValueSum #-}
addValueSum :: Arena s -> NodeId -> Float -> ST s ()
addValueSum arena nid v = do
    let !off = fromIntegral nid
    !current <- unsafeRead (arenaValueSum arena) off
    unsafeWrite (arenaValueSum arena) off (current + v)

{-# INLINEABLE addVisitValue #-}
addVisitValue :: Arena s -> NodeId -> Float -> ST s ()
addVisitValue arena nid v = do
    let !off = fromIntegral nid
    !currentVisits <- unsafeRead (arenaVisits arena) off
    unsafeWrite (arenaVisits arena) off (currentVisits + 1)
    !currentValue <- unsafeRead (arenaValueSum arena) off
    unsafeWrite (arenaValueSum arena) off (currentValue + v)

{-# INLINEABLE readActionId #-}
readActionId :: Arena s -> NodeId -> ST s Word8
readActionId arena nid =
    unsafeRead (arenaActionId arena) (fromIntegral nid)

{-# INLINEABLE readParent #-}
readParent :: Arena s -> NodeId -> ST s NodeId
readParent arena nid =
    unsafeRead (arenaParent arena) (fromIntegral nid)

{-# INLINEABLE readFirstChild #-}
readFirstChild :: Arena s -> NodeId -> ST s NodeId
readFirstChild arena nid =
    unsafeRead (arenaFirstChild arena) (fromIntegral nid)

{-# INLINEABLE readNumChildren #-}
readNumChildren :: Arena s -> NodeId -> ST s Int32
readNumChildren arena nid =
    unsafeRead (arenaNumChildren arena) (fromIntegral nid)

setChildren :: Arena s -> NodeId -> NodeId -> Int32 -> ST s ()
setChildren arena nid firstChild count = do
    let !off = fromIntegral nid
    unsafeWrite (arenaFirstChild arena) off firstChild
    unsafeWrite (arenaNumChildren arena) off count

treeRoot :: Arena s -> ST s NodeId
treeRoot arena = do
    cursor <- readSTRef (arenaCursor arena)
    pure (if cursor == 0 then -1 else 0)

-- | Re-root the tree at `newRoot`. Inherited visit counts on the new
-- root subtree are preserved; the arena cursor is left intact. The
-- discarded-subtree compaction happens in Phase 8's optimised arena.
treeReroot :: Arena s -> NodeId -> ST s NodeId
treeReroot _ newRoot = pure newRoot

-- | Snapshot visits for the first `n` slots.
bulkVisits :: Arena s -> Int -> ST s [(NodeId, Int32)]
bulkVisits arena n = do
    cursor <- readSTRef (arenaCursor arena)
    let limit = min n cursor
    mapM
        ( \nid -> do
            v <- unsafeRead (arenaVisits arena) (fromIntegral nid)
            pure (nid, v)
        )
        [0 .. fromIntegral (limit - 1)]
