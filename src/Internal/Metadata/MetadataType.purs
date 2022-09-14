module CTL.Internal.Metadata.MetadataType
  ( class MetadataType
  , metadataLabel
  , fromGeneralTxMetadata
  , toGeneralTxMetadata
  ) where

import Prelude

import Data.Map (lookup, singleton) as Map
import Data.Maybe (Maybe)
import Data.Newtype (wrap, unwrap)
import CTL.Internal.Metadata.FromMetadata (class FromMetadata, fromMetadata)
import CTL.Internal.Metadata.ToMetadata (class ToMetadata, toMetadata)
import Type.Proxy (Proxy(Proxy))
import CTL.Internal.Types.TransactionMetadata
  ( GeneralTransactionMetadata
  , TransactionMetadatumLabel
  )

class (FromMetadata a, ToMetadata a) <= MetadataType (a :: Type) where
  metadataLabel :: Proxy a -> TransactionMetadatumLabel

fromGeneralTxMetadata
  :: forall (a :: Type). MetadataType a => GeneralTransactionMetadata -> Maybe a
fromGeneralTxMetadata =
  fromMetadata <=< Map.lookup (metadataLabel (Proxy :: Proxy a)) <<< unwrap

toGeneralTxMetadata
  :: forall (a :: Type). MetadataType a => a -> GeneralTransactionMetadata
toGeneralTxMetadata =
  wrap <<< Map.singleton (metadataLabel (Proxy :: Proxy a)) <<< toMetadata
