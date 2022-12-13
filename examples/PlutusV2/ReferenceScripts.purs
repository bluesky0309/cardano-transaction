module Ctl.Examples.PlutusV2.ReferenceScripts
  ( main
  , example
  , contract
  ) where

import Contract.Prelude

import Contract.Address (ownStakePubKeysHashes, scriptHashAddress)
import Contract.Config (ContractParams, testnetNamiConfig)
import Contract.Credential (Credential(PubKeyCredential))
import Contract.Log (logInfo')
import Contract.Monad (Contract, launchAff_, liftContractM, runContract)
import Contract.PlutusData (PlutusData, unitDatum, unitRedeemer)
import Contract.ScriptLookups as Lookups
import Contract.Scripts (ValidatorHash, validatorHash)
import Contract.Transaction
  ( ScriptRef(PlutusScriptRef)
  , TransactionHash
  , TransactionInput(TransactionInput)
  , awaitTxConfirmed
  , mkTxUnspentOut
  , submitTxFromConstraints
  )
import Contract.TxConstraints
  ( DatumPresence(DatumWitness)
  , InputWithScriptRef(SpendInput)
  , TxConstraints
  )
import Contract.TxConstraints as Constraints
import Contract.Utxos (utxosAt)
import Contract.Value (lovelaceValueOf) as Value
import Ctl.Examples.PlutusV2.Scripts.AlwaysSucceeds (alwaysSucceedsScriptV2)
import Data.Array (head)
import Data.BigInt (fromInt) as BigInt
import Data.Map (toUnfoldable) as Map

main :: Effect Unit
main = example testnetNamiConfig

example :: ContractParams -> Effect Unit
example cfg = launchAff_ do
  runContract cfg contract

contract :: Contract Unit
contract = do
  logInfo' "Running Examples.PlutusV2.ReferenceScripts"
  validator <- alwaysSucceedsScriptV2
  let
    vhash :: ValidatorHash
    vhash = validatorHash validator

    scriptRef :: ScriptRef
    scriptRef = PlutusScriptRef (unwrap validator)

  logInfo' "Attempt to lock value"
  txId <- payWithScriptRefToAlwaysSucceeds vhash scriptRef
  awaitTxConfirmed txId
  logInfo' "Tx submitted successfully, Try to spend locked values"
  spendFromAlwaysSucceeds vhash txId

payWithScriptRefToAlwaysSucceeds
  :: ValidatorHash -> ScriptRef -> Contract TransactionHash
payWithScriptRefToAlwaysSucceeds vhash scriptRef = do
  -- Send to own stake credential. This is used to test
  -- `mustPayToScriptAddressWithScriptRef`
  mbStakeKeyHash <- join <<< head <$> ownStakePubKeysHashes
  let
    constraints :: TxConstraints Unit Unit
    constraints =
      case mbStakeKeyHash of
        Nothing ->
          Constraints.mustPayToScriptWithScriptRef vhash unitDatum DatumWitness
            scriptRef
            (Value.lovelaceValueOf $ BigInt.fromInt 2_000_000)
        Just stakeKeyHash ->
          Constraints.mustPayToScriptAddressWithScriptRef
            vhash
            (PubKeyCredential $ unwrap stakeKeyHash)
            unitDatum
            DatumWitness
            scriptRef
            (Value.lovelaceValueOf $ BigInt.fromInt 2_000_000)

    lookups :: Lookups.ScriptLookups PlutusData
    lookups = mempty

  submitTxFromConstraints lookups constraints

spendFromAlwaysSucceeds :: ValidatorHash -> TransactionHash -> Contract Unit
spendFromAlwaysSucceeds vhash txId = do
  -- Send to own stake credential. This is used to test
  -- `mustPayToScriptAddressWithScriptRef`
  mbStakeKeyHash <- join <<< head <$> ownStakePubKeysHashes
  let
    scriptAddress =
      scriptHashAddress vhash (PubKeyCredential <<< unwrap <$> mbStakeKeyHash)
  utxos <- utxosAt scriptAddress

  txInput /\ txOutput <-
    liftContractM "Could not find unspent output locked at script address"
      $ find hasTransactionId (Map.toUnfoldable utxos :: Array _)

  let
    constraints :: TxConstraints Unit Unit
    constraints =
      Constraints.mustSpendScriptOutputUsingScriptRef txInput unitRedeemer
        (SpendInput $ mkTxUnspentOut txInput txOutput)

    lookups :: Lookups.ScriptLookups PlutusData
    lookups = mempty

  spendTxId <- submitTxFromConstraints lookups constraints
  awaitTxConfirmed spendTxId
  logInfo' "Successfully spent locked values."
  where
  hasTransactionId :: TransactionInput /\ _ -> Boolean
  hasTransactionId (TransactionInput tx /\ _) =
    tx.transactionId == txId
