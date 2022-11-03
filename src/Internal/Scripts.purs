module Ctl.Internal.Scripts
  ( mintingPolicyHash
  , nativeScriptHashEnterpriseAddress
  , nativeScriptStakeValidatorHash
  , plutusScriptStakeValidatorHash
  , scriptCurrencySymbol
  , typedValidatorBaseAddress
  , typedValidatorEnterpriseAddress
  , validatorHash
  , validatorHashBaseAddress
  , validatorHashEnterpriseAddress
  ) where

import Prelude

import Ctl.Internal.Hashing (plutusScriptHash)
import Ctl.Internal.NativeScripts (NativeScriptHash, nativeScriptHash)
import Ctl.Internal.Plutus.Types.CurrencySymbol (CurrencySymbol, mpsSymbol)
import Ctl.Internal.Serialization.Address
  ( Address
  , NetworkId
  , baseAddressToAddress
  , enterpriseAddress
  , enterpriseAddressToAddress
  , scriptAddress
  , scriptHashCredential
  )
import Ctl.Internal.Types.Scripts
  ( MintingPolicy(NativeMintingPolicy, PlutusMintingPolicy)
  , MintingPolicyHash
  , NativeScriptStakeValidator
  , PlutusScriptStakeValidator
  , StakeValidatorHash
  , Validator
  , ValidatorHash
  )
import Ctl.Internal.Types.TypedValidator (TypedValidator(TypedValidator))
import Data.Maybe (Maybe)
import Data.Newtype (unwrap, wrap)

-- | Helpers for `PlutusScript` and `ScriptHash` newtype wrappers, separate from
-- | the data type definitions to prevent cylic dependencies.

-- | Converts a Plutus-style `TypedValidator` to an `BaseAddress`
typedValidatorBaseAddress
  :: forall (a :: Type). NetworkId -> TypedValidator a -> Address
typedValidatorBaseAddress networkId (TypedValidator typedVal) =
  baseAddressToAddress $ scriptAddress networkId $ unwrap typedVal.validatorHash

-- | Converts a Plutus-style `TypedValidator` to an `Address` as an
-- | `EnterpriseAddress`. This is likely what you will use since Plutus
-- | currently uses `scriptHashAddress` on non-staking addresses which is
-- | invoked in `validatorAddress`
typedValidatorEnterpriseAddress
  :: forall (a :: Type). NetworkId -> TypedValidator a -> Address
typedValidatorEnterpriseAddress network (TypedValidator typedVal) =
  validatorHashEnterpriseAddress network typedVal.validatorHash

-- | Converts a Plutus-style `MintingPolicy` to an `MintingPolicyHash`
mintingPolicyHash :: MintingPolicy -> MintingPolicyHash
mintingPolicyHash = case _ of
  PlutusMintingPolicy script -> wrap $ plutusScriptHash script
  NativeMintingPolicy nscript -> wrap $ unwrap $ nativeScriptHash nscript

-- | Converts a Plutus-style `Validator` to an `ValidatorHash`
validatorHash :: Validator -> ValidatorHash
validatorHash = wrap <<< plutusScriptHash <<< unwrap

-- | Converts a Plutus-style `ValidatorHash` to a `Address` as a `BaseAddress`
validatorHashBaseAddress :: NetworkId -> ValidatorHash -> Address
validatorHashBaseAddress networkId =
  baseAddressToAddress <<< scriptAddress networkId <<< unwrap

-- | Converts a Plutus-style `ValidatorHash` to an `Address` as an
-- | `EnterpriseAddress`. This is likely what you will use since Plutus
-- | currently uses `scriptHashAddress` on non-staking addresses which is
-- | invoked in `validatorAddress`
validatorHashEnterpriseAddress :: NetworkId -> ValidatorHash -> Address
validatorHashEnterpriseAddress network valHash =
  enterpriseAddressToAddress $
    enterpriseAddress
      { network
      , paymentCred: scriptHashCredential (unwrap valHash)
      }

-- | Converts a `NativeScriptHash` to an `Address` as an `EnterpriseAddress`.
nativeScriptHashEnterpriseAddress :: NetworkId -> NativeScriptHash -> Address
nativeScriptHashEnterpriseAddress network nsHash =
  validatorHashEnterpriseAddress network (wrap $ unwrap nsHash)

-- | Calculates a hash of a PlutusScript stake validator
plutusScriptStakeValidatorHash
  :: PlutusScriptStakeValidator -> StakeValidatorHash
plutusScriptStakeValidatorHash = unwrap >>> plutusScriptHash >>> wrap

-- | Calculates a hash of a NativeScript stake validator
nativeScriptStakeValidatorHash
  :: NativeScriptStakeValidator -> StakeValidatorHash
nativeScriptStakeValidatorHash = unwrap >>> nativeScriptHash >>> unwrap >>> wrap

-- | Converts a `MintingPolicy` to a `CurrencySymbol`.
scriptCurrencySymbol :: MintingPolicy -> Maybe CurrencySymbol
scriptCurrencySymbol = mpsSymbol <<< mintingPolicyHash
