-- | A module for `QueryM` queries related to utxos.
module Ctl.Internal.QueryM.Utxos
  ( filterLockedUtxos
  , getUtxo
  , getWalletBalance
  , utxosAt
  , getWalletCollateral
  , getWalletUtxos
  ) where

import Prelude

import Control.Monad.Reader (withReaderT)
import Control.Monad.Reader.Trans (ReaderT, asks)
import Ctl.Internal.Cardano.Types.Transaction (TransactionOutput, UtxoMap)
import Ctl.Internal.Cardano.Types.TransactionUnspentOutput
  ( TransactionUnspentOutput
  )
import Ctl.Internal.Cardano.Types.Value (Value)
import Ctl.Internal.Helpers as Helpers
import Ctl.Internal.QueryM
  ( QueryM
  , callCip30Wallet
  , getNetworkId
  , getWalletAddresses
  )
import Ctl.Internal.QueryM.Kupo (getUtxoByOref, utxosAt) as Kupo
import Ctl.Internal.Serialization.Address (Address)
import Ctl.Internal.Types.Transaction (TransactionInput)
import Ctl.Internal.Types.UsedTxOuts (UsedTxOuts, isTxOutRefUsed)
import Ctl.Internal.Wallet (Wallet(Gero, Nami, Flint, Lode, Eternl, KeyWallet))
import Data.Array (head)
import Data.Array as Array
import Data.Either (hush)
import Data.Foldable (fold, foldr)
import Data.Map as Map
import Data.Maybe (Maybe(Nothing), fromMaybe, maybe)
import Data.Newtype (unwrap, wrap)
import Data.Traversable (for, for_, traverse)
import Data.Tuple.Nested ((/\))
import Data.UInt as UInt
import Effect.Aff (Aff)
import Effect.Aff.Class (liftAff)
import Effect.Class (liftEffect)
import Effect.Exception (throw)

--------------------------------------------------------------------------------
-- UtxosAt
--------------------------------------------------------------------------------

-- If required, we can change to `Either` with more granular error handling.
-- | Gets utxos at an (internal) `Address` in terms of (internal) `Cardano.Transaction.Types`.
-- | Results may vary depending on `Wallet` type.
utxosAt :: Address -> QueryM (Maybe UtxoMap)
utxosAt address = mkUtxoQuery (hush <$> Kupo.utxosAt address)

-- | Queries for an utxo given a transaction input.
getUtxo :: TransactionInput -> QueryM (Maybe TransactionOutput)
getUtxo = map (join <<< hush) <<< Kupo.getUtxoByOref

mkUtxoQuery :: QueryM (Maybe UtxoMap) -> QueryM (Maybe UtxoMap)
mkUtxoQuery allUtxosAt =
  maybe allUtxosAt utxosAtByWallet =<< asks (_.wallet <<< _.runtime)
  where
  -- Add more wallet types here:
  utxosAtByWallet :: Wallet -> QueryM (Maybe UtxoMap)
  utxosAtByWallet = case _ of
    Nami _ -> cip30UtxosAt
    Gero _ -> cip30UtxosAt
    Flint _ -> cip30UtxosAt
    Eternl _ -> cip30UtxosAt
    Lode _ -> cip30UtxosAt
    KeyWallet _ -> allUtxosAt

  cip30UtxosAt :: QueryM (Maybe UtxoMap)
  cip30UtxosAt = getWalletCollateral >>= maybe
    (liftEffect $ throw "CIP-30 wallet missing collateral")
    \collateralUtxos ->
      allUtxosAt <#> \utxos' ->
        foldr
          ( \collateralUtxo utxoAcc ->
              (Map.delete (unwrap collateralUtxo).input) <$> utxoAcc
          )
          utxos'
          collateralUtxos

--------------------------------------------------------------------------------
-- Used Utxos helpers
--------------------------------------------------------------------------------

filterLockedUtxos :: UtxoMap -> QueryM UtxoMap
filterLockedUtxos utxos =
  withTxRefsCache $
    flip Helpers.filterMapWithKeyM utxos
      (\k _ -> not <$> isTxOutRefUsed (unwrap k))

withTxRefsCache
  :: forall (m :: Type -> Type) (a :: Type)
   . ReaderT UsedTxOuts Aff a
  -> QueryM a
withTxRefsCache = wrap <<< withReaderT (_.runtime >>> _.usedTxOuts)

getWalletBalance
  :: QueryM (Maybe Value)
getWalletBalance = do
  asks (_.runtime >>> _.wallet) >>= map join <<< traverse case _ of
    Nami wallet -> liftAff $ wallet.getBalance wallet.connection
    Gero wallet -> liftAff $ wallet.getBalance wallet.connection
    Eternl wallet -> liftAff $ wallet.getBalance wallet.connection
    Flint wallet -> liftAff $ wallet.getBalance wallet.connection
    Lode wallet -> liftAff $ wallet.getBalance wallet.connection
    KeyWallet _ -> do
      -- Implement via `utxosAt`
      addresses <- getWalletAddresses
      fold <$> for addresses \address -> do
        utxosAt address <#> map
          -- Combine `Value`s
          (fold <<< map _.amount <<< map unwrap <<< Map.values)

getWalletUtxos :: QueryM (Maybe UtxoMap)
getWalletUtxos = do
  asks (_.runtime >>> _.wallet) >>= map join <<< traverse case _ of
    Nami wallet -> liftAff $ wallet.getUtxos wallet.connection <#> map toUtxoMap
    Gero wallet -> liftAff $ wallet.getUtxos wallet.connection <#> map toUtxoMap
    Flint wallet -> liftAff $ wallet.getUtxos wallet.connection <#> map
      toUtxoMap
    Eternl wallet -> liftAff $ wallet.getUtxos wallet.connection <#> map
      toUtxoMap
    Lode wallet -> liftAff $ wallet.getUtxos wallet.connection <#> map toUtxoMap
    KeyWallet _ -> do
      mbAddress <- getWalletAddresses <#> head
      map join $ for mbAddress utxosAt
  where
  toUtxoMap :: Array TransactionUnspentOutput -> UtxoMap
  toUtxoMap = Map.fromFoldable <<< map
    (unwrap >>> \({ input, output }) -> input /\ output)

getWalletCollateral :: QueryM (Maybe (Array TransactionUnspentOutput))
getWalletCollateral = do
  mbCollateralUTxOs <- asks (_.runtime >>> _.wallet) >>= maybe (pure Nothing)
    case _ of
      Nami wallet -> liftAff $ callCip30Wallet wallet _.getCollateral
      Gero wallet -> liftAff $ callCip30Wallet wallet _.getCollateral
      Flint wallet -> liftAff $ callCip30Wallet wallet _.getCollateral
      Lode wallet -> liftAff $ callCip30Wallet wallet _.getCollateral
      Eternl wallet -> liftAff $ callCip30Wallet wallet _.getCollateral
      KeyWallet kw -> do
        networkId <- getNetworkId
        addr <- liftAff $ (unwrap kw).address networkId
        utxos <- utxosAt addr <#> fromMaybe Map.empty
          >>= filterLockedUtxos
        pparams <- asks $ _.runtime >>> _.pparams <#> unwrap
        let
          coinsPerUtxoUnit = pparams.coinsPerUtxoUnit
          maxCollateralInputs = UInt.toInt $
            pparams.maxCollateralInputs
        liftEffect $ (unwrap kw).selectCollateral coinsPerUtxoUnit
          maxCollateralInputs
          utxos
  for_ mbCollateralUTxOs \collateralUTxOs -> do
    pparams <- asks $ _.runtime >>> _.pparams
    let
      tooManyCollateralUTxOs =
        UInt.fromInt (Array.length collateralUTxOs) >
          (unwrap pparams).maxCollateralInputs
    when tooManyCollateralUTxOs do
      liftEffect $ throw tooManyCollateralUTxOsError
  pure mbCollateralUTxOs
  where
  tooManyCollateralUTxOsError =
    "Wallet returned too many UTxOs as collateral. This is likely a bug in \
    \the wallet."
