-- | A module that defines the different transaction data types, balancing
-- | functionality, transaction fees, signing and submission.
module Contract.Transaction
  ( BalancedSignedTransaction(BalancedSignedTransaction)
  , balanceTx
  , balanceTxM
  , balanceTxWithConstraints
  , balanceTxs
  , balanceTxsWithConstraints
  , calculateMinFee
  , createAdditionalUtxos
  , getTxFinalFee
  , getTxMetadata
  , module BalanceTxError
  , module FinalizedTransaction
  , module NativeScript
  , module OutputDatum
  , module PTransaction
  , module PTransactionUnspentOutput
  , module ReindexRedeemersExport
  , module ScriptLookups
  , module ScriptRef
  , module Scripts
  , module Transaction
  , module UnbalancedTx
  , module X
  , signTransaction
  , submit
  , submitE
  , submitTxFromConstraints
  , submitTxFromConstraintsReturningFee
  , withBalancedTx
  , withBalancedTxWithConstraints
  , withBalancedTxs
  , withBalancedTxsWithConstraints
  ) where

import Prelude

import Aeson (class EncodeAeson)
import Contract.ClientError (ClientError)
import Contract.Metadata (GeneralTransactionMetadata)
import Contract.Monad
  ( Contract
  , liftContractM
  , liftedE
  , liftedM
  , runContractInEnv
  )
import Contract.PlutusData (class IsData)
import Contract.ScriptLookups (mkUnbalancedTx)
import Contract.Scripts (class ValidatorTypes)
import Contract.TxConstraints (TxConstraints)
import Control.Monad.Error.Class (catchError, liftEither, throwError)
import Control.Monad.Reader (ReaderT, asks, runReaderT)
import Control.Monad.Reader.Class (ask)
import Ctl.Internal.BalanceTx (FinalizedTransaction)
import Ctl.Internal.BalanceTx (FinalizedTransaction(FinalizedTransaction)) as FinalizedTransaction
import Ctl.Internal.BalanceTx (balanceTxWithConstraints) as BalanceTx
import Ctl.Internal.BalanceTx.Constraints (BalanceTxConstraintsBuilder)
import Ctl.Internal.BalanceTx.Error
  ( Actual(Actual)
  , BalanceTxError
      ( BalanceInsufficientError
      , CouldNotConvertScriptOutputToTxInput
      , CouldNotGetChangeAddress
      , CouldNotGetCollateral
      , CouldNotGetUtxos
      , CollateralReturnError
      , CollateralReturnMinAdaValueCalcError
      , ExUnitsEvaluationFailed
      , InsufficientUtxoBalanceToCoverAsset
      , ReindexRedeemersError
      , UtxoLookupFailedFor
      , UtxoMinAdaValueCalculationFailed
      )
  , Expected(Expected)
  , ImpossibleError(Impossible)
  , InvalidInContext(InvalidInContext)
  ) as BalanceTxError
import Ctl.Internal.Cardano.Types.NativeScript
  ( NativeScript
      ( ScriptPubkey
      , ScriptAll
      , ScriptAny
      , ScriptNOfK
      , TimelockStart
      , TimelockExpiry
      )
  ) as NativeScript
import Ctl.Internal.Cardano.Types.ScriptRef
  ( ScriptRef(NativeScriptRef, PlutusScriptRef)
  , scriptRefFromMintingPolicy
  ) as ScriptRef
import Ctl.Internal.Cardano.Types.Transaction
  ( AuxiliaryData(AuxiliaryData)
  , AuxiliaryDataHash(AuxiliaryDataHash)
  , BootstrapWitness
  , Certificate
      ( StakeRegistration
      , StakeDeregistration
      , StakeDelegation
      , PoolRegistration
      , PoolRetirement
      , GenesisKeyDelegation
      , MoveInstantaneousRewardsCert
      )
  , CostModel(CostModel)
  , Costmdls(Costmdls)
  , Ed25519Signature
  , Epoch(Epoch)
  , ExUnitPrices
  , ExUnits
  , GenesisHash(GenesisHash)
  , Mint(Mint)
  , Nonce(IdentityNonce, HashNonce)
  , PoolPubKeyHash(PoolPubKeyHash)
  , ProposedProtocolParameterUpdates(ProposedProtocolParameterUpdates)
  , ProtocolParamUpdate
  , ProtocolVersion
  , PublicKey
  , Redeemer
  , RequiredSigner(RequiredSigner)
  , ScriptDataHash(ScriptDataHash)
  , SubCoin
  , Transaction(Transaction)
  , TransactionWitnessSet(TransactionWitnessSet)
  , TxBody(TxBody)
  , URL(URL)
  , UnitInterval
  , Update
  , Vkey(Vkey)
  , Vkeywitness(Vkeywitness)
  , _auxiliaryData
  , _auxiliaryDataHash
  , _body
  , _bootstraps
  , _certs
  , _collateral
  , _fee
  , _inputs
  , _isValid
  , _mint
  , _nativeScripts
  , _networkId
  , _outputs
  , _plutusData
  , _plutusScripts
  , _referenceInputs
  , _requiredSigners
  , _scriptDataHash
  , _ttl
  , _update
  , _validityStartInterval
  , _vkeys
  , _withdrawals
  , _witnessSet
  , mkPoolPubKeyHash
  , poolPubKeyHashToBech32
  ) as Transaction
import Ctl.Internal.Cardano.Types.Transaction
  ( Transaction
  , TransactionOutput
  , _body
  , _outputs
  )
import Ctl.Internal.Contract.AwaitTxConfirmed
  ( awaitTxConfirmed
  , awaitTxConfirmedWithTimeout
  , awaitTxConfirmedWithTimeoutSlots
  , isTxConfirmed
  ) as X
import Ctl.Internal.Contract.MinFee (calculateMinFee) as Contract
import Ctl.Internal.Contract.QueryHandle (getQueryHandle)
import Ctl.Internal.Contract.QueryHandle.Error (GetTxMetadataError)
import Ctl.Internal.Contract.QueryHandle.Error
  ( GetTxMetadataError
      ( GetTxMetadataTxNotFoundError
      , GetTxMetadataMetadataEmptyOrMissingError
      , GetTxMetadataClientError
      )
  ) as X
import Ctl.Internal.Contract.Sign (signTransaction) as Contract
import Ctl.Internal.Hashing (transactionHash) as Hashing
import Ctl.Internal.Plutus.Conversion
  ( fromPlutusUtxoMap
  , toPlutusCoin
  , toPlutusTxOutputWithRefScript
  )
import Ctl.Internal.Plutus.Types.Transaction
  ( TransactionOutput(TransactionOutput)
  , TransactionOutputWithRefScript(TransactionOutputWithRefScript)
  ) as PTransaction
import Ctl.Internal.Plutus.Types.Transaction (UtxoMap)
import Ctl.Internal.Plutus.Types.TransactionUnspentOutput
  ( TransactionUnspentOutput(TransactionUnspentOutput)
  , _input
  , _output
  , lookupTxHash
  , mkTxUnspentOut
  ) as PTransactionUnspentOutput
import Ctl.Internal.Plutus.Types.Value (Coin)
import Ctl.Internal.ReindexRedeemers
  ( ReindexErrors(CannotGetTxOutRefIndexForRedeemer)
  ) as ReindexRedeemersExport
import Ctl.Internal.ReindexRedeemers (reindexSpentScriptRedeemers) as X
import Ctl.Internal.Serialization (convertTransaction)
import Ctl.Internal.Types.OutputDatum
  ( OutputDatum(NoOutputDatum, OutputDatumHash, OutputDatum)
  , outputDatumDataHash
  , outputDatumDatum
  ) as OutputDatum
import Ctl.Internal.Types.RewardAddress
  ( RewardAddress
  , rewardAddressFromBech32
  , rewardAddressFromBytes
  , rewardAddressToBech32
  , rewardAddressToBytes
  ) as X
import Ctl.Internal.Types.ScriptLookups
  ( MkUnbalancedTxError
      ( TypeCheckFailed
      , ModifyTx
      , TxOutRefNotFound
      , TxOutRefWrongType
      , DatumNotFound
      , MintingPolicyNotFound
      , MintingPolicyHashNotCurrencySymbol
      , CannotMakeValue
      , ValidatorHashNotFound
      , OwnPubKeyAndStakeKeyMissing
      , TypedValidatorMissing
      , DatumWrongHash
      , CannotQueryDatum
      , CannotHashDatum
      , CannotConvertPOSIXTimeRange
      , CannotGetMintingPolicyScriptIndex
      , CannotGetValidatorHashFromAddress
      , TypedTxOutHasNoDatumHash
      , CannotHashMintingPolicy
      , CannotHashValidator
      , CannotConvertPaymentPubKeyHash
      , CannotSatisfyAny
      )
  , ScriptLookups
  ) as ScriptLookups
import Ctl.Internal.Types.ScriptLookups (UnattachedUnbalancedTx)
import Ctl.Internal.Types.Scripts
  ( Language(PlutusV1, PlutusV2)
  , plutusV1Script
  , plutusV2Script
  ) as Scripts
import Ctl.Internal.Types.Transaction
  ( DataHash(DataHash)
  , TransactionHash(TransactionHash)
  , TransactionInput(TransactionInput)
  ) as Transaction
import Ctl.Internal.Types.Transaction
  ( TransactionHash
  , TransactionInput(TransactionInput)
  )
import Ctl.Internal.Types.UnbalancedTransaction
  ( UnbalancedTx(UnbalancedTx)
  , _transaction
  , _utxoIndex
  , emptyUnbalancedTx
  ) as UnbalancedTx
import Ctl.Internal.Types.UsedTxOuts
  ( UsedTxOuts
  , lockTransactionInputs
  , unlockTransactionInputs
  )
import Ctl.Internal.Types.VRFKeyHash
  ( VRFKeyHash
  , vrfKeyHashFromBytes
  , vrfKeyHashToBytes
  ) as X
import Data.Array.NonEmpty as NonEmptyArray
import Data.Bifunctor (lmap)
import Data.BigInt (BigInt)
import Data.Either (Either, hush)
import Data.Foldable (foldl, length)
import Data.Generic.Rep (class Generic)
import Data.Lens.Getter (view)
import Data.Map (empty, insert) as Map
import Data.Maybe (Maybe)
import Data.Newtype (class Newtype, unwrap)
import Data.Show.Generic (genericShow)
import Data.Traversable (class Traversable, for_, traverse)
import Data.Tuple (Tuple(Tuple), fst)
import Data.Tuple.Nested (type (/\), (/\))
import Data.UInt (UInt)
import Effect.Aff (bracket, error)
import Effect.Aff.Class (liftAff)
import Effect.Class (liftEffect)
import Effect.Exception (try)

-- | Signs a transaction with potential failure.
signTransaction
  :: forall (tx :: Type)
   . Newtype tx Transaction
  => tx
  -> Contract BalancedSignedTransaction
signTransaction =
  map BalancedSignedTransaction
    <<< liftedM "Error signing the transaction"
    <<< Contract.signTransaction
    <<< unwrap

-- | Submits a `BalancedSignedTransaction`, which is the output of
-- | `signTransaction`.
submit
  :: BalancedSignedTransaction
  -> Contract TransactionHash
submit tx = do
  eiTxHash <- submitE tx
  liftEither $ flip lmap eiTxHash \err -> error $
    "Failed to submit tx:\n" <> show err

-- | Submits a `BalancedSignedTransaction`, which is the output of
-- | `signTransaction`. Preserves the errors returned by the backend in
-- | the case they need to be inspected.
submitE
  :: BalancedSignedTransaction
  -> Contract (Either ClientError TransactionHash)
submitE tx = do
  queryHandle <- getQueryHandle
  eiTxHash <- liftAff $ queryHandle.submitTx $ unwrap tx
  void $ asks (_.hooks >>> _.onSubmit) >>=
    traverse \hook -> liftEffect $ void $ try $ hook $ unwrap tx
  pure eiTxHash

-- | Calculate the minimum transaction fee.
calculateMinFee
  :: Transaction
  -> UtxoMap
  -> Contract Coin
calculateMinFee tx additionalUtxos = do
  networkId <- asks _.networkId
  let additionalUtxos' = fromPlutusUtxoMap networkId additionalUtxos
  toPlutusCoin <$> Contract.calculateMinFee tx additionalUtxos'

-- | Helper to adapt to UsedTxOuts.
withUsedTxOuts
  :: forall (a :: Type)
   . ReaderT UsedTxOuts Contract a
  -> Contract a
withUsedTxOuts f = asks _.usedTxOuts >>= runReaderT f

-- Helper to avoid repetition.
withTransactions
  :: forall (a :: Type)
       (t :: Type -> Type)
       (ubtx :: Type)
       (tx :: Type)
   . Traversable t
  => (t ubtx -> Contract (t tx))
  -> (tx -> Transaction)
  -> t ubtx
  -> (t tx -> Contract a)
  -> Contract a
withTransactions prepare extract utxs action = do
  env <- ask
  let
    run :: forall (b :: Type). _ b -> _ b
    run = runContractInEnv env
  liftAff $ bracket
    (run (prepare utxs))
    (run <<< cleanup)
    (run <<< action)
  where
  cleanup txs = for_ txs
    (withUsedTxOuts <<< unlockTransactionInputs <<< extract)

withSingleTransaction
  :: forall (a :: Type) (ubtx :: Type) (tx :: Type)
   . (ubtx -> Contract tx)
  -> (tx -> Transaction)
  -> ubtx
  -> (tx -> Contract a)
  -> Contract a
withSingleTransaction prepare extract utx action =
  withTransactions (traverse prepare) extract (NonEmptyArray.singleton utx)
    (action <<< NonEmptyArray.head)

-- | Execute an action on an array of balanced
-- | transactions (`balanceTxs` will be called). Within
-- | this function, all transaction inputs used by these
-- | transactions will be locked, so that they are not used
-- | in any other context.
-- | After the function completes, the locks will be removed.
-- | Errors will be thrown.
withBalancedTxsWithConstraints
  :: forall (a :: Type)
   . Array (UnattachedUnbalancedTx /\ BalanceTxConstraintsBuilder)
  -> (Array FinalizedTransaction -> Contract a)
  -> Contract a
withBalancedTxsWithConstraints =
  withTransactions balanceTxsWithConstraints unwrap

-- | Same as `withBalancedTxsWithConstraints`, but uses the default balancer
-- | constraints.
withBalancedTxs
  :: forall (a :: Type)
   . Array UnattachedUnbalancedTx
  -> (Array FinalizedTransaction -> Contract a)
  -> Contract a
withBalancedTxs = withTransactions balanceTxs unwrap

-- | Execute an action on a balanced transaction (`balanceTx` will
-- | be called). Within this function, all transaction inputs
-- | used by this transaction will be locked, so that they are not
-- | used in any other context.
-- | After the function completes, the locks will be removed.
-- | Errors will be thrown.
withBalancedTxWithConstraints
  :: forall (a :: Type)
   . UnattachedUnbalancedTx
  -> BalanceTxConstraintsBuilder
  -> (FinalizedTransaction -> Contract a)
  -> Contract a
withBalancedTxWithConstraints unbalancedTx =
  withSingleTransaction balanceAndLockWithConstraints unwrap
    <<< Tuple unbalancedTx

-- | Same as `withBalancedTxWithConstraints`, but uses the default balancer
-- | constraints.
withBalancedTx
  :: forall (a :: Type)
   . UnattachedUnbalancedTx
  -> (FinalizedTransaction -> Contract a)
  -> Contract a
withBalancedTx = withSingleTransaction balanceAndLock unwrap

-- | Attempts to balance an `UnattachedUnbalancedTx` using the specified
-- | balancer constraints.
balanceTxWithConstraints
  :: UnattachedUnbalancedTx
  -> BalanceTxConstraintsBuilder
  -> Contract (Either BalanceTxError.BalanceTxError FinalizedTransaction)
balanceTxWithConstraints =
  BalanceTx.balanceTxWithConstraints

-- | Same as `balanceTxWithConstraints`, but uses the default balancer
-- | constraints.
balanceTx
  :: UnattachedUnbalancedTx
  -> Contract (Either BalanceTxError.BalanceTxError FinalizedTransaction)
balanceTx = flip balanceTxWithConstraints mempty

-- | Balances each transaction using specified balancer constraint sets and
-- | locks the used inputs so that they cannot be reused by subsequent
-- | transactions.
balanceTxsWithConstraints
  :: forall (t :: Type -> Type)
   . Traversable t
  => t (UnattachedUnbalancedTx /\ BalanceTxConstraintsBuilder)
  -> Contract (t FinalizedTransaction)
balanceTxsWithConstraints unbalancedTxs =
  unlockAllOnError $ traverse balanceAndLockWithConstraints unbalancedTxs
  where
  unlockAllOnError :: forall (a :: Type). Contract a -> Contract a
  unlockAllOnError f = catchError f $ \e -> do
    for_ unbalancedTxs $
      withUsedTxOuts <<< unlockTransactionInputs <<< uutxToTx <<< fst
    throwError e

  uutxToTx :: UnattachedUnbalancedTx -> Transaction
  uutxToTx = _.transaction <<< unwrap <<< _.unbalancedTx <<< unwrap

-- | Same as `balanceTxsWithConstraints`, but uses the default balancer
-- | constraints.
balanceTxs
  :: forall (t :: Type -> Type)
   . Traversable t
  => t UnattachedUnbalancedTx
  -> Contract (t FinalizedTransaction)
balanceTxs = balanceTxsWithConstraints <<< map (flip Tuple mempty)

-- | Attempts to balance an `UnattachedUnbalancedTx` hushing the error.
balanceTxM
  :: UnattachedUnbalancedTx
  -> Contract (Maybe FinalizedTransaction)
balanceTxM = map hush <<< balanceTx

balanceAndLockWithConstraints
  :: UnattachedUnbalancedTx /\ BalanceTxConstraintsBuilder
  -> Contract FinalizedTransaction
balanceAndLockWithConstraints (unbalancedTx /\ constraints) = do
  balancedTx <-
    liftedE $ balanceTxWithConstraints unbalancedTx constraints
  void $ withUsedTxOuts $
    lockTransactionInputs (unwrap balancedTx)
  pure balancedTx

balanceAndLock
  :: UnattachedUnbalancedTx
  -> Contract FinalizedTransaction
balanceAndLock = balanceAndLockWithConstraints <<< flip Tuple mempty

newtype BalancedSignedTransaction = BalancedSignedTransaction Transaction

derive instance Generic BalancedSignedTransaction _
derive instance Newtype BalancedSignedTransaction _
derive newtype instance Eq BalancedSignedTransaction
derive newtype instance EncodeAeson BalancedSignedTransaction

instance Show BalancedSignedTransaction where
  show = genericShow

getTxFinalFee :: BalancedSignedTransaction -> BigInt
getTxFinalFee =
  unwrap <<< view (Transaction._body <<< Transaction._fee) <<< unwrap

-- | Fetch transaction metadata.
-- | Returns `Right` when the transaction exists and metadata was non-empty
getTxMetadata
  :: TransactionHash
  -> Contract (Either GetTxMetadataError GeneralTransactionMetadata)
getTxMetadata th = do
  queryHandle <- getQueryHandle
  liftAff $ queryHandle.getTxMetadata th

-- | Builds an expected utxo set from transaction outputs. Predicts output
-- | references (`TransactionInput`s) for each output by calculating the
-- | transaction hash and indexing the outputs in the order they appear in the
-- | transaction. This function should be used for transaction chaining
-- | in conjunction with `mustUseAdditionalUtxos` balancer constraint.
-- | Throws an exception if conversion to Plutus outputs fails.
createAdditionalUtxos
  :: forall (tx :: Type)
   . Newtype tx Transaction
  => tx
  -> Contract UtxoMap
createAdditionalUtxos tx = do
  transactionId <-
    liftEffect $ Hashing.transactionHash <$> convertTransaction (unwrap tx)
  let
    txOutputs :: Array TransactionOutput
    txOutputs = view (_body <<< _outputs) (unwrap tx)

    txIn :: UInt -> TransactionInput
    txIn index = TransactionInput { transactionId, index }

  plutusOutputs <-
    liftContractM "createAdditionalUtxos: Failed to convert to Plutus outputs"
      (traverse toPlutusTxOutputWithRefScript txOutputs)

  pure $ plutusOutputs #
    foldl (\utxo txOut -> Map.insert (txIn $ length utxo) txOut utxo) Map.empty

submitTxFromConstraintsReturningFee
  :: forall (validator :: Type) (datum :: Type)
       (redeemer :: Type)
   . ValidatorTypes validator datum redeemer
  => IsData datum
  => IsData redeemer
  => ScriptLookups.ScriptLookups validator
  -> TxConstraints redeemer datum
  -> Contract { txHash :: TransactionHash, txFinalFee :: BigInt }
submitTxFromConstraintsReturningFee lookups constraints = do
  unbalancedTx <- liftedE $ mkUnbalancedTx lookups constraints
  balancedTx <- liftedE $ balanceTx unbalancedTx
  balancedSignedTx <- signTransaction balancedTx
  txHash <- submit balancedSignedTx
  pure { txHash, txFinalFee: getTxFinalFee balancedSignedTx }

submitTxFromConstraints
  :: forall (validator :: Type) (datum :: Type)
       (redeemer :: Type)
   . ValidatorTypes validator datum redeemer
  => IsData datum
  => IsData redeemer
  => ScriptLookups.ScriptLookups validator
  -> TxConstraints redeemer datum
  -> Contract TransactionHash
submitTxFromConstraints lookups constraints =
  _.txHash <$> submitTxFromConstraintsReturningFee lookups constraints
