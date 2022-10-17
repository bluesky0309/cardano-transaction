-- | CborBytes. A wrapper over `ByteArray` to indicate that the bytes are cbor.
module Ctl.Internal.Types.CborBytes
  ( CborBytes(CborBytes)
  , cborBytesToByteArray
  , cborBytesFromByteArray
  , cborBytesFromAscii
  , cborBytesToIntArray
  , cborBytesFromIntArray
  , cborBytesFromIntArrayUnsafe
  , cborBytesToHex
  , cborByteLength
  , hexToCborBytes
  , hexToCborBytesUnsafe
  , rawBytesAsCborBytes
  ) where

import Prelude

import Aeson (class DecodeAeson, class EncodeAeson)
import Ctl.Internal.Metadata.FromMetadata (class FromMetadata)
import Ctl.Internal.Metadata.ToMetadata (class ToMetadata)
import Ctl.Internal.Types.ByteArray (ByteArray)
import Ctl.Internal.Types.ByteArray as BytesArray
import Ctl.Internal.Types.RawBytes (RawBytes)
import Data.Maybe (Maybe)
import Data.Newtype (class Newtype, unwrap, wrap)
import Test.QuickCheck.Arbitrary (class Arbitrary)

-- | An array of Bytes containing CBOR data
newtype CborBytes = CborBytes ByteArray

instance Show CborBytes where
  show rb = "(hexToCborBytesUnsafe " <> show (cborBytesToHex rb) <>
    ")"

derive instance Newtype CborBytes _

derive newtype instance Eq CborBytes
derive newtype instance Ord CborBytes
derive newtype instance Semigroup CborBytes
derive newtype instance Monoid CborBytes
derive newtype instance EncodeAeson CborBytes
derive newtype instance DecodeAeson CborBytes
derive newtype instance Arbitrary CborBytes
derive newtype instance ToMetadata CborBytes
derive newtype instance FromMetadata CborBytes

cborBytesToIntArray :: CborBytes -> Array Int
cborBytesToIntArray = BytesArray.byteArrayToIntArray <<< unwrap

cborBytesFromIntArray :: Array Int -> Maybe CborBytes
cborBytesFromIntArray = map wrap <<< BytesArray.byteArrayFromIntArray

cborBytesFromIntArrayUnsafe :: Array Int -> CborBytes
cborBytesFromIntArrayUnsafe = wrap <<< BytesArray.byteArrayFromIntArrayUnsafe

cborBytesToHex :: CborBytes -> String
cborBytesToHex = BytesArray.byteArrayToHex <<< unwrap

cborByteLength :: CborBytes -> Int
cborByteLength = BytesArray.byteLength <<< unwrap

hexToCborBytes :: String -> Maybe CborBytes
hexToCborBytes = map wrap <<< BytesArray.hexToByteArray

hexToCborBytesUnsafe :: String -> CborBytes
hexToCborBytesUnsafe = wrap <<< BytesArray.hexToByteArrayUnsafe

cborBytesToByteArray :: CborBytes -> ByteArray
cborBytesToByteArray = unwrap

cborBytesFromByteArray :: ByteArray -> CborBytes
cborBytesFromByteArray = wrap

cborBytesFromAscii :: String -> Maybe CborBytes
cborBytesFromAscii = map wrap <<< BytesArray.byteArrayFromAscii

rawBytesAsCborBytes :: RawBytes -> CborBytes
rawBytesAsCborBytes = wrap <<< unwrap
