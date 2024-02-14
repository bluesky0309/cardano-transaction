module Ctl.Internal.Plutus.Types.Address
  ( Address(Address)
  , AddressWithNetworkTag(AddressWithNetworkTag)
  , class PlutusAddress
  , getAddress
  , pubKeyHashAddress
  , scriptHashAddress
  -- , toPubKeyHash
  , toValidatorHash
  , toStakingCredential
  ) where

import Prelude

import Aeson
  ( class DecodeAeson
  , class EncodeAeson
  , JsonDecodeError(TypeMismatch)
  , caseAesonObject
  , encodeAeson
  , (.:)
  )
import Cardano.Plutus.Types.PubKeyHash (PubKeyHash(..))
import Cardano.Types.NetworkId (NetworkId)
import Cardano.Types.PaymentPubKeyHash (PaymentPubKeyHash(..))
import Ctl.Internal.FromData (class FromData, genericFromData)
import Ctl.Internal.Plutus.Types.Credential
  ( Credential(PubKeyCredential, ScriptCredential)
  , StakingCredential(StakingHash)
  )
import Ctl.Internal.Plutus.Types.DataSchema
  ( class HasPlutusSchema
  , type (:+)
  , type (:=)
  , type (@@)
  , I
  , PNil
  )
import Ctl.Internal.ToData (class ToData, genericToData)
import Ctl.Internal.TypeLevel.Nat (Z)
import Ctl.Internal.Types.Scripts (ValidatorHash)
import Data.Either (Either(Left))
import Data.Generic.Rep (class Generic)
import Data.Maybe (Maybe(Just, Nothing))
import Data.Newtype (class Newtype, unwrap, wrap)
import Data.Show.Generic (genericShow)

--------------------------------------------------------------------------------
-- Address
--------------------------------------------------------------------------------

class PlutusAddress (t :: Type) where
  getAddress :: t -> Address

newtype AddressWithNetworkTag = AddressWithNetworkTag
  { address :: Address
  , networkId :: NetworkId
  }

instance PlutusAddress Address where
  getAddress = identity

instance PlutusAddress AddressWithNetworkTag where
  getAddress = _.address <<< unwrap

derive instance Eq AddressWithNetworkTag
derive instance Newtype AddressWithNetworkTag _
derive instance Generic AddressWithNetworkTag _

instance Show AddressWithNetworkTag where
  show = genericShow

-- Taken from https://playground.plutus.iohkdev.io/doc/haddock/plutus-ledger-api/html/Plutus-V1-Ledger-Tx.html#t:Address
-- Plutus rev: dbefda30be6490c758aa88b600f5874f12712b3a
-- | Address with two kinds of credentials, normal and staking.
newtype Address = Address
  { addressCredential :: Credential
  , addressStakingCredential :: Maybe StakingCredential
  }

derive instance Eq Address
derive instance Ord Address
derive instance Newtype Address _
derive instance Generic Address _

instance Show Address where
  show = genericShow

instance
  HasPlutusSchema
    Address
    ( "Address"
        :=
          ( "addressCredential" := I Credential :+ "addressStakingCredential"
              := I (Maybe StakingCredential)
              :+ PNil
          )
        @@ Z
        :+ PNil
    )

instance ToData Address where
  toData = genericToData

instance FromData Address where
  fromData = genericFromData

instance DecodeAeson Address where
  decodeAeson = caseAesonObject (Left $ TypeMismatch "Expected object") $
    \obj -> do
      addressCredential <- obj .: "addressCredential"
      addressStakingCredential <- obj .: "addressStakingCredential"
      pure $ Address { addressCredential, addressStakingCredential }

instance EncodeAeson Address where
  encodeAeson (Address addr) = encodeAeson addr

--------------------------------------------------------------------------------
-- Useful functions
--------------------------------------------------------------------------------

-- | The address that should be targeted by a transaction output locked
-- | by the public key with the given hash.
pubKeyHashAddress :: PaymentPubKeyHash -> Maybe Credential -> Address
pubKeyHashAddress (PaymentPubKeyHash pkh) mbStakeCredential = wrap
  { addressCredential: PubKeyCredential $ wrap pkh
  , addressStakingCredential:
      map StakingHash mbStakeCredential
  }

-- | The address that should be used by a transaction output locked
-- | by the given validator script hash.
scriptHashAddress :: ValidatorHash -> Maybe Credential -> Address
scriptHashAddress vh mbStakeCredential = wrap
  { addressCredential: ScriptCredential vh
  , addressStakingCredential: map StakingHash mbStakeCredential
  }

-- -- | The PubKeyHash of the address (if any).
-- toPubKeyHash :: Address -> Maybe PubKeyHash
-- toPubKeyHash addr =
--   case (unwrap addr).addressCredential of
--     PubKeyCredential k -> Just k
--     _ -> Nothing

-- | The validator hash of the address (if any).
toValidatorHash :: Address -> Maybe ValidatorHash
toValidatorHash addr =
  case (unwrap addr).addressCredential of
    ScriptCredential k -> Just k
    _ -> Nothing

-- | The staking credential of an address (if any).
toStakingCredential :: Address -> Maybe StakingCredential
toStakingCredential = _.addressStakingCredential <<< unwrap
