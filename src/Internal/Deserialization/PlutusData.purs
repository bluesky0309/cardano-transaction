module Ctl.Internal.Deserialization.PlutusData
  ( convertPlutusData
  , deserializeData
  ) where

import Prelude

import Control.Alt ((<|>))
import Ctl.Internal.Deserialization.BigInt (convertBigInt)
import Ctl.Internal.Deserialization.FromBytes (fromBytes)
import Ctl.Internal.FfiHelpers
  ( ContainerHelper
  , MaybeFfiHelper
  , containerHelper
  , maybeFfiHelper
  )
import Ctl.Internal.FromData (class FromData, fromData)
import Ctl.Internal.Serialization.Types
  ( BigInt
  , ConstrPlutusData
  , PlutusData
  , PlutusList
  , PlutusMap
  )
import Ctl.Internal.Types.BigNum (BigNum)
import Ctl.Internal.Types.ByteArray (ByteArray)
import Ctl.Internal.Types.CborBytes (CborBytes)
import Ctl.Internal.Types.PlutusData
  ( PlutusData(Constr, Map, List, Integer, Bytes)
  ) as T
import Data.Maybe (Maybe, fromJust)
import Data.Newtype (unwrap)
import Data.Tuple (Tuple(Tuple))
import Data.Tuple.Nested (type (/\), (/\))
import Partial.Unsafe (unsafePartial)

convertPlutusData :: PlutusData -> T.PlutusData
-- Unsafe fromJust here is correct, because we cover every PlutusData
-- constructor, and Just will be returned by one of functions
convertPlutusData pd = unsafePartial $ fromJust $
  convertPlutusConstr pd
    <|> convertPlutusMap pd
    <|> convertPlutusList pd
    <|> convertPlutusInteger pd
    <|> convertPlutusBytes pd

convertPlutusConstr :: PlutusData -> Maybe T.PlutusData
convertPlutusConstr pd = do
  constr <- _PlutusData_constr maybeFfiHelper pd
  let
    data' = convertPlutusData <$>
      _unpackPlutusList containerHelper (_ConstrPlutusData_data constr)
    alt = _ConstrPlutusData_alternative constr
  pure $ T.Constr alt data'

convertPlutusMap :: PlutusData -> Maybe T.PlutusData
convertPlutusMap pd = do
  entries <- _PlutusData_map maybeFfiHelper pd <#>
    _unpackPlutusMap containerHelper Tuple >>> map
      \(k /\ v) -> (convertPlutusData k /\ convertPlutusData v)

  pure $ T.Map entries

convertPlutusList :: PlutusData -> Maybe T.PlutusData
convertPlutusList pd = T.List <$> do
  _PlutusData_list maybeFfiHelper pd <#>
    ( _unpackPlutusList containerHelper >>>
        map convertPlutusData
    )

convertPlutusInteger :: PlutusData -> Maybe T.PlutusData
convertPlutusInteger pd = T.Integer <$> do
  _PlutusData_integer maybeFfiHelper pd >>= convertBigInt

convertPlutusBytes :: PlutusData -> Maybe T.PlutusData
convertPlutusBytes pd = T.Bytes <$> _PlutusData_bytes maybeFfiHelper pd

deserializeData :: forall (a :: Type). FromData a => CborBytes -> Maybe a
deserializeData = fromData <=< map convertPlutusData <<< fromBytes <<< unwrap

foreign import _PlutusData_constr
  :: MaybeFfiHelper -> PlutusData -> Maybe ConstrPlutusData

foreign import _PlutusData_map
  :: MaybeFfiHelper -> PlutusData -> Maybe PlutusMap

foreign import _PlutusData_list
  :: MaybeFfiHelper -> PlutusData -> Maybe PlutusList

foreign import _PlutusData_integer
  :: MaybeFfiHelper -> PlutusData -> Maybe BigInt

foreign import _PlutusData_bytes
  :: MaybeFfiHelper -> PlutusData -> Maybe ByteArray

foreign import _unpackPlutusList
  :: ContainerHelper -> PlutusList -> Array PlutusData

foreign import _ConstrPlutusData_alternative :: ConstrPlutusData -> BigNum
foreign import _ConstrPlutusData_data :: ConstrPlutusData -> PlutusList
foreign import _unpackPlutusMap
  :: ContainerHelper
  -> (forall a b. a -> b -> Tuple a b)
  -> PlutusMap
  -> Array (PlutusData /\ PlutusData)
