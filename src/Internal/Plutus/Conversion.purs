-- | A module for performing conversions between various types and
-- | their Plutus representations.
-- |
-- | Conversion functions come in pairs and must be named as follows:
-- | `fromPlutusType` and `toPlutusType`, where `Type` is to
-- | be replaced by the name of the actual type.
module Ctl.Internal.Plutus.Conversion
  (
    -- Plutus Address <-> CSL Address
    module Conversion.Address

  -- Plutus Value <-> Types.Value
  , module Conversion.Value

  -- Plutus Coin <-> Cardano Coin
  , fromPlutusCoin
  , toPlutusCoin

  -- Plutus TransactionOutput <-> Cardano TransactionOutput
  , fromPlutusTxOutput
  , toPlutusTxOutput

  -- Plutus TransactionOutputWithRefScript <-> Cardano TransactionOutput
  , fromPlutusTxOutputWithRefScript
  , toPlutusTxOutputWithRefScript

  -- Plutus TransactionUnspentOutput <-> Cardano TransactionUnspentOutput
  , fromPlutusTxUnspentOutput
  , toPlutusTxUnspentOutput

  -- Plutus UtxoMap <-> Cardano UtxoMap
  , fromPlutusUtxoMap
  , toPlutusUtxoMap
  ) where

import Prelude

import Cardano.Types.BigNum as BigNum
import Cardano.Types.NetworkId (NetworkId)
import Cardano.Types.TransactionOutput (TransactionOutput) as Cardano
import Cardano.Types.UtxoMap (UtxoMap) as Cardano
import Cardano.Types.Value as Value
import Ctl.Internal.Cardano.Types.ScriptRef (ScriptRef)
import Ctl.Internal.Cardano.Types.TransactionUnspentOutput
  ( TransactionUnspentOutput
  ) as Cardano
import Ctl.Internal.Cardano.Types.Value (Coin) as Cardano
import Ctl.Internal.Hashing (scriptRefHash)
import Ctl.Internal.Helpers (notImplemented)
import Ctl.Internal.Plutus.Conversion.Address
  ( fromPlutusAddress
  , fromPlutusAddressWithNetworkTag
  , toPlutusAddress
  , toPlutusAddressWithNetworkTag
  ) as Conversion.Address
import Ctl.Internal.Plutus.Conversion.Address
  ( fromPlutusAddress
  , toPlutusAddress
  )
import Ctl.Internal.Plutus.Conversion.Value (fromPlutusValue, toPlutusValue)
import Ctl.Internal.Plutus.Conversion.Value (fromPlutusValue, toPlutusValue) as Conversion.Value
import Ctl.Internal.Plutus.Types.Transaction
  ( TransactionOutput
  , TransactionOutputWithRefScript(TransactionOutputWithRefScript)
  , UtxoMap
  ) as Plutus
import Ctl.Internal.Plutus.Types.TransactionUnspentOutput
  ( TransactionUnspentOutput
  ) as Plutus
import Ctl.Internal.Plutus.Types.Value (Coin) as Plutus
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Newtype (unwrap, wrap)
import Data.Traversable (traverse)

--------------------------------------------------------------------------------
-- Plutus Coin <-> Cardano Coin
--------------------------------------------------------------------------------

fromPlutusCoin :: Plutus.Coin -> Maybe Cardano.Coin
fromPlutusCoin = map wrap <<< BigNum.fromBigInt <<< unwrap

toPlutusCoin :: Cardano.Coin -> Plutus.Coin
toPlutusCoin = wrap <<< BigNum.toBigInt <<< unwrap

--------------------------------------------------------------------------------
-- Plutus TransactionOutput <-> Cardano TransactionOutput
--------------------------------------------------------------------------------

fromPlutusTxOutput
  :: NetworkId
  -> Maybe ScriptRef
  -> Plutus.TransactionOutput
  -> Cardano.TransactionOutput
fromPlutusTxOutput networkId scriptRef plutusTxOut =
  let
    rec = unwrap plutusTxOut
  in
    wrap
      { address: fromPlutusAddress networkId rec.address
      , amount: fromMaybe Value.zero $ fromPlutusValue rec.amount
      , datum: Just rec.datum
      , scriptRef
      }

toPlutusTxOutput
  :: Cardano.TransactionOutput -> Maybe Plutus.TransactionOutput
toPlutusTxOutput cardanoTxOut = do
  let rec = notImplemented -- unwrap cardanoTxOut
  address <- toPlutusAddress rec.address
  let
    amount = toPlutusValue rec.amount
    referenceScript = scriptRefHash <$> rec.scriptRef
  pure $ wrap
    { address, amount, datum: rec.datum, referenceScript }

--------------------------------------------------------------------------------
-- Plutus TransactionOutputWithRefScript <-> Cardano TransactionOutput
--------------------------------------------------------------------------------

fromPlutusTxOutputWithRefScript
  :: NetworkId
  -> Plutus.TransactionOutputWithRefScript
  -> Cardano.TransactionOutput
fromPlutusTxOutputWithRefScript
  networkId
  (Plutus.TransactionOutputWithRefScript { output, scriptRef }) =
  fromPlutusTxOutput networkId scriptRef output

toPlutusTxOutputWithRefScript
  :: Cardano.TransactionOutput -> Maybe Plutus.TransactionOutputWithRefScript
toPlutusTxOutputWithRefScript cTxOutput =
  toPlutusTxOutput cTxOutput
    <#> wrap <<< { output: _, scriptRef: (unwrap cTxOutput).scriptRef }

--------------------------------------------------------------------------------
-- Plutus TransactionUnspentOutput <-> Cardano TransactionUnspentOutput
--------------------------------------------------------------------------------

fromPlutusTxUnspentOutput
  :: NetworkId
  -> Plutus.TransactionUnspentOutput
  -> Cardano.TransactionUnspentOutput
fromPlutusTxUnspentOutput networkId txUnspentOutput =
  let
    rec = unwrap txUnspentOutput
  in
    wrap
      { input: rec.input
      , output: fromPlutusTxOutputWithRefScript networkId rec.output
      }

toPlutusTxUnspentOutput
  :: Cardano.TransactionUnspentOutput
  -> Maybe Plutus.TransactionUnspentOutput
toPlutusTxUnspentOutput txUnspentOutput = do
  let rec = unwrap txUnspentOutput
  output <- toPlutusTxOutputWithRefScript rec.output
  pure $ wrap { input: rec.input, output }

--------------------------------------------------------------------------------
-- Plutus UtxoMap <-> Cardano UtxoMap
--------------------------------------------------------------------------------

fromPlutusUtxoMap :: NetworkId -> Plutus.UtxoMap -> Cardano.UtxoMap
fromPlutusUtxoMap networkId =
  map (fromPlutusTxOutputWithRefScript networkId)

toPlutusUtxoMap :: Cardano.UtxoMap -> Maybe Plutus.UtxoMap
toPlutusUtxoMap =
  traverse toPlutusTxOutputWithRefScript
