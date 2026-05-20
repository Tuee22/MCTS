module MCTS.Crypto.SHA256
    ( sha256
    , sha256Hex
    ) where

import qualified Data.Bits as Bits
import qualified Data.ByteString as BS
import Data.Word (Word32, Word64, Word8)

sha256 :: BS.ByteString -> BS.ByteString
sha256 input =
    BS.pack (concatMap word32Bytes finalState)
  where
    finalState = foldl compress initialHash (chunksOf 64 (pad input))

sha256Hex :: BS.ByteString -> String
sha256Hex =
    concatMap byteHex . BS.unpack . sha256

initialHash :: [Word32]
initialHash =
    [ 0x6a09e667
    , 0xbb67ae85
    , 0x3c6ef372
    , 0xa54ff53a
    , 0x510e527f
    , 0x9b05688c
    , 0x1f83d9ab
    , 0x5be0cd19
    ]

kConstants :: [Word32]
kConstants =
    [ 0x428a2f98
    , 0x71374491
    , 0xb5c0fbcf
    , 0xe9b5dba5
    , 0x3956c25b
    , 0x59f111f1
    , 0x923f82a4
    , 0xab1c5ed5
    , 0xd807aa98
    , 0x12835b01
    , 0x243185be
    , 0x550c7dc3
    , 0x72be5d74
    , 0x80deb1fe
    , 0x9bdc06a7
    , 0xc19bf174
    , 0xe49b69c1
    , 0xefbe4786
    , 0x0fc19dc6
    , 0x240ca1cc
    , 0x2de92c6f
    , 0x4a7484aa
    , 0x5cb0a9dc
    , 0x76f988da
    , 0x983e5152
    , 0xa831c66d
    , 0xb00327c8
    , 0xbf597fc7
    , 0xc6e00bf3
    , 0xd5a79147
    , 0x06ca6351
    , 0x14292967
    , 0x27b70a85
    , 0x2e1b2138
    , 0x4d2c6dfc
    , 0x53380d13
    , 0x650a7354
    , 0x766a0abb
    , 0x81c2c92e
    , 0x92722c85
    , 0xa2bfe8a1
    , 0xa81a664b
    , 0xc24b8b70
    , 0xc76c51a3
    , 0xd192e819
    , 0xd6990624
    , 0xf40e3585
    , 0x106aa070
    , 0x19a4c116
    , 0x1e376c08
    , 0x2748774c
    , 0x34b0bcb5
    , 0x391c0cb3
    , 0x4ed8aa4a
    , 0x5b9cca4f
    , 0x682e6ff3
    , 0x748f82ee
    , 0x78a5636f
    , 0x84c87814
    , 0x8cc70208
    , 0x90befffa
    , 0xa4506ceb
    , 0xbef9a3f7
    , 0xc67178f2
    ]

pad :: BS.ByteString -> [Word8]
pad bytes =
    let raw = BS.unpack bytes
        bitLength = fromIntegral (length raw) * 8 :: Word64
        withOne = raw <> [0x80]
        zeroCount = (56 - length withOne) `mod` 64
     in withOne <> replicate zeroCount 0 <> word64Bytes bitLength

compress :: [Word32] -> [Word8] -> [Word32]
compress hash chunk =
    case hash of
        [a0, b0, c0, d0, e0, f0, g0, h0] ->
            let (a, b, c, d, e, f, g, h) =
                    foldl
                        roundStep
                        (a0, b0, c0, d0, e0, f0, g0, h0)
                        (zip kConstants schedule)
             in zipWith (+) hash [a, b, c, d, e, f, g, h]
        _ -> hash
  where
    schedule = messageSchedule chunk

roundStep
    :: (Word32, Word32, Word32, Word32, Word32, Word32, Word32, Word32)
    -> (Word32, Word32)
    -> (Word32, Word32, Word32, Word32, Word32, Word32, Word32, Word32)
roundStep (a, b, c, d, e, f, g, h) (k, w) =
    let t1 = h + bigSigma1 e + choose e f g + k + w
        t2 = bigSigma0 a + majority a b c
     in (t1 + t2, a, b, c, d + t1, e, f, g)

messageSchedule :: [Word8] -> [Word32]
messageSchedule chunk =
    extend 16 base
  where
    base = map word32FromBytes (chunksOf 4 chunk)
    extend idx wordsSoFar
        | idx >= 64 = wordsSoFar
        | otherwise =
            let next =
                    smallSigma1 (wordAt (idx - 2) wordsSoFar)
                        + wordAt (idx - 7) wordsSoFar
                        + smallSigma0 (wordAt (idx - 15) wordsSoFar)
                        + wordAt (idx - 16) wordsSoFar
             in extend (idx + 1) (wordsSoFar <> [next])
    wordAt idx values =
        case indexAt idx values of
            Just word -> word
            Nothing -> 0

choose :: Word32 -> Word32 -> Word32 -> Word32
choose x y z = (x Bits..&. y) `Bits.xor` (Bits.complement x Bits..&. z)

majority :: Word32 -> Word32 -> Word32 -> Word32
majority x y z = (x Bits..&. y) `Bits.xor` (x Bits..&. z) `Bits.xor` (y Bits..&. z)

bigSigma0 :: Word32 -> Word32
bigSigma0 x = rotateR x 2 `Bits.xor` rotateR x 13 `Bits.xor` rotateR x 22

bigSigma1 :: Word32 -> Word32
bigSigma1 x = rotateR x 6 `Bits.xor` rotateR x 11 `Bits.xor` rotateR x 25

smallSigma0 :: Word32 -> Word32
smallSigma0 x = rotateR x 7 `Bits.xor` rotateR x 18 `Bits.xor` Bits.shiftR x 3

smallSigma1 :: Word32 -> Word32
smallSigma1 x = rotateR x 17 `Bits.xor` rotateR x 19 `Bits.xor` Bits.shiftR x 10

rotateR :: Word32 -> Int -> Word32
rotateR = Bits.rotateR

word32FromBytes :: [Word8] -> Word32
word32FromBytes bytes =
    case bytes of
        [a, b, c, d] ->
            Bits.shiftL (fromIntegral a) 24
                + Bits.shiftL (fromIntegral b) 16
                + Bits.shiftL (fromIntegral c) 8
                + fromIntegral d
        _ -> 0

word32Bytes :: Word32 -> [Word8]
word32Bytes word =
    [ fromIntegral (Bits.shiftR word 24)
    , fromIntegral (Bits.shiftR word 16)
    , fromIntegral (Bits.shiftR word 8)
    , fromIntegral word
    ]

word64Bytes :: Word64 -> [Word8]
word64Bytes word =
    [ fromIntegral (Bits.shiftR word 56)
    , fromIntegral (Bits.shiftR word 48)
    , fromIntegral (Bits.shiftR word 40)
    , fromIntegral (Bits.shiftR word 32)
    , fromIntegral (Bits.shiftR word 24)
    , fromIntegral (Bits.shiftR word 16)
    , fromIntegral (Bits.shiftR word 8)
    , fromIntegral word
    ]

chunksOf :: Int -> [a] -> [[a]]
chunksOf _ [] = []
chunksOf n values =
    let (chunk, rest) = splitAt n values
     in chunk : chunksOf n rest

byteHex :: Word8 -> String
byteHex byte =
    [nibbleHex (fromIntegral (Bits.shiftR byte 4)), nibbleHex (fromIntegral (byte Bits..&. 0x0f))]
  where
    hex = "0123456789abcdef"
    nibbleHex idx =
        case indexAt idx hex of
            Just ch -> ch
            Nothing -> '?'

indexAt :: Int -> [a] -> Maybe a
indexAt n _
    | n < 0 = Nothing
indexAt _ [] = Nothing
indexAt 0 (value : _) = Just value
indexAt n (_ : rest) = indexAt (n - 1) rest
