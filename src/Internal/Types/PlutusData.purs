module Ctl.Internal.Types.PlutusData
  ( PlutusData
      ( Constr
      , Map
      , List
      , Integer
      , Bytes
      )
  ) where

import Prelude

import Aeson
  ( class DecodeAeson
  , class EncodeAeson
  , JsonDecodeError(UnexpectedValue)
  , decodeAeson
  , encodeAeson
  , toStringifiedNumbersJson
  , (.:)
  )
import Control.Alt ((<|>))
import Ctl.Internal.Types.BigNum (BigNum)
import Ctl.Internal.Types.ByteArray (ByteArray, hexToByteArray)
import Data.BigInt (BigInt)
import Data.Either (Either(Left))
import Data.Generic.Rep (class Generic)
import Data.Maybe (Maybe(Just, Nothing))
import Data.Show.Generic (genericShow)
import Data.Traversable (for)
import Data.Tuple (Tuple)
import Data.Tuple.Nested ((/\))

-- Doesn't distinguish "BuiltinData" and "Data" like Plutus:
data PlutusData
  = Constr BigNum (Array PlutusData)
  | Map (Array (Tuple PlutusData PlutusData))
  | List (Array PlutusData)
  | Integer BigInt
  | Bytes ByteArray

derive instance Eq PlutusData
derive instance Ord PlutusData
derive instance Generic PlutusData _

instance Show PlutusData where
  show x = genericShow x

-- Ogmios Datum Cache Json format
instance DecodeAeson PlutusData where
  decodeAeson aeson = decodeConstr
    <|> decodeMap
    <|> decodeList
    <|> decodeInteger
    <|> decodeBytes
    where
    decodeConstr :: Either JsonDecodeError PlutusData
    decodeConstr = do
      x <- decodeAeson aeson
      constr <- x .: "constr"
      fields <- x .: "fields"
      pure $ Constr constr fields

    decodeMap :: Either JsonDecodeError PlutusData
    decodeMap = do
      obj <- decodeAeson aeson
      map1 <- (obj .: "map" :: Either _ (Array _))
      kvs <- for map1 \entryJson -> do
        key <- entryJson .: "key"
        value <- entryJson .: "value"
        pure $ key /\ value
      pure $ Map kvs

    decodeList :: Either JsonDecodeError PlutusData
    decodeList = do
      List <$> decodeAeson aeson

    decodeInteger :: Either JsonDecodeError PlutusData
    decodeInteger = do
      Integer <$> decodeAeson aeson

    decodeBytes :: Either JsonDecodeError PlutusData
    decodeBytes = do
      bytesHex <- decodeAeson aeson
      case hexToByteArray bytesHex of
        Nothing -> Left $ UnexpectedValue $ toStringifiedNumbersJson $
          encodeAeson bytesHex
        Just res -> pure $ Bytes res

instance EncodeAeson PlutusData where
  encodeAeson (Constr constr fields) = encodeAeson
    { "constr": constr
    , "fields": fields
    }
  encodeAeson (Map elems) = encodeAeson
    { "map": encodeAeson $ map
        ( \(k /\ v) ->
            { "key": k
            , "value": v
            }
        )
        elems
    }
  encodeAeson (List elems) = encodeAeson elems
  encodeAeson (Integer bi) = encodeAeson bi
  encodeAeson (Bytes ba) = encodeAeson ba
