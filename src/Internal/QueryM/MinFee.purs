module Ctl.Internal.QueryM.MinFee (calculateMinFee) where

import Prelude

import Ctl.Internal.Cardano.Types.Transaction
  ( Transaction
  , UtxoMap
  , _body
  , _collateral
  , _inputs
  )
import Ctl.Internal.Cardano.Types.TransactionUnspentOutput
  ( TransactionUnspentOutput
  )
import Ctl.Internal.Cardano.Types.Value (Coin)
import Ctl.Internal.Helpers (liftM, liftedM)
import Ctl.Internal.QueryM (QueryM, getProtocolParameters, getWalletAddresses)
import Ctl.Internal.QueryM.Utxos (getUtxo, getWalletCollateral)
import Ctl.Internal.Serialization.Address
  ( Address
  , addressPaymentCred
  , addressStakeCred
  , stakeCredentialToKeyHash
  )
import Ctl.Internal.Serialization.Hash (Ed25519KeyHash)
import Ctl.Internal.Serialization.MinFee (calculateMinFeeCsl)
import Ctl.Internal.Types.Transaction (TransactionInput)
import Data.Array (fromFoldable, mapMaybe)
import Data.Array as Array
import Data.Lens.Getter ((^.))
import Data.Map (empty, fromFoldable, keys, lookup, values) as Map
import Data.Maybe (fromMaybe, maybe)
import Data.Newtype (unwrap)
import Data.Set (Set)
import Data.Set (difference, fromFoldable, intersection, mapMaybe, union) as Set
import Data.Traversable (for)
import Data.Tuple.Nested ((/\))
import Effect.Aff (error)

-- | Calculate `min_fee` using CSL with protocol parameters from Ogmios.
calculateMinFee :: Transaction -> UtxoMap -> QueryM Coin
calculateMinFee tx additionalUtxos = do
  selfSigners <- getSelfSigners tx additionalUtxos
  pparams <- getProtocolParameters
  calculateMinFeeCsl pparams selfSigners tx

getSelfSigners :: Transaction -> UtxoMap -> QueryM (Set Ed25519KeyHash)
getSelfSigners tx additionalUtxos = do

  -- Get all tx inputs and remove the additional ones.
  let
    txInputs :: Set TransactionInput
    txInputs =
      Set.difference
        (tx ^. _body <<< _inputs)
        (Map.keys additionalUtxos)

    additionalUtxosAddrs :: Set Address
    additionalUtxosAddrs = Set.fromFoldable $
      (_.address <<< unwrap) <$> Map.values additionalUtxos

  (inUtxosAddrs :: Set Address) <- setFor txInputs $ \txInput ->
    liftedM (error $ "Couldn't get tx output for " <> show txInput) $
      (map <<< map) (_.address <<< unwrap) (getUtxo txInput)

  -- Get all tx output addressses
  let
    txCollats :: Set TransactionInput
    txCollats = Set.fromFoldable <<< fromMaybe [] $ tx ^. _body <<< _collateral

  walletCollats <- maybe Map.empty toUtxoMap <$> getWalletCollateral

  (inCollatAddrs :: Set Address) <- setFor txCollats
    ( \txCollat ->
        liftM (error $ "Couldn't get tx output for " <> show txCollat)
          $ (map (_.address <<< unwrap) <<< Map.lookup txCollat)
          $ walletCollats
    )

  -- Get own addressses
  (ownAddrs :: Set Address) <- Set.fromFoldable <$> getWalletAddresses

  -- Combine to get all self tx input addresses
  let
    txOwnAddrs = ownAddrs `Set.intersection`
      (additionalUtxosAddrs `Set.union` inUtxosAddrs `Set.union` inCollatAddrs)

  -- Extract payment pub key hashes from addresses.
  paymentPkhs <- map (Set.mapMaybe identity) $ setFor txOwnAddrs $ \addr -> do
    paymentCred <-
      liftM
        ( error $ "Could not extract payment credential from Address: " <> show
            addr
        ) $ addressPaymentCred addr
    pure $ stakeCredentialToKeyHash paymentCred

  -- Extract stake pub key hashes from addresses
  let
    stakePkhs = Set.fromFoldable $
      (stakeCredentialToKeyHash <=< addressStakeCred) `mapMaybe`
        Array.fromFoldable txOwnAddrs

  pure $ paymentPkhs <> stakePkhs
  where
  setFor
    :: forall (a :: Type) (b :: Type) (m :: Type -> Type)
     . Monad m
    => Ord a
    => Ord b
    => Set a
    -> (a -> m b)
    -> m (Set b)
  setFor txIns f = Set.fromFoldable <$> for (fromFoldable txIns) f

  toUtxoMap :: Array TransactionUnspentOutput -> UtxoMap
  toUtxoMap = Map.fromFoldable <<< map
    (unwrap >>> \({ input, output }) -> input /\ output)
