module Contract.Test.Assert
  ( ContractAssertionFailure
      ( CouldNotGetTxByHash
      , CouldNotParseMetadata
      , CustomFailure
      , SkippedTest
      , MaxExUnitsExceeded
      , TransactionHasNoMetadata
      , UnexpectedDatumInOutput
      , UnexpectedLovelaceDelta
      , UnexpectedMetadataValue
      , UnexpectedRefScriptInOutput
      , UnexpectedTokenDelta
      )
  , ContractAssertion
  , ContractCheck
  , ExpectedActual(ExpectedActual)
  , Label
  , Labeled(Labeled)
  , assertContractExpectedActual
  , assertContract
  , assertContractMaybe
  , assertLovelaceDeltaAtAddress
  , assertOutputHasDatum
  , assertOutputHasRefScript
  , assertTxHasMetadata
  , assertValueDeltaAtAddress
  , assertionToCheck
  , checkExUnitsNotExceed
  , checkGainAtAddress
  , checkGainAtAddress'
  , checkLossAtAddress
  , checkLossAtAddress'
  , checkNewUtxosAtAddress
  , checkTokenDeltaAtAddress
  , checkTokenGainAtAddress
  , checkTokenGainAtAddress'
  , checkTokenLossAtAddress
  , checkTokenLossAtAddress'
  , collectAssertionFailures
  , label
  , noLabel
  , runChecks
  , tellFailure
  , unlabel
  , printLabeled
  , printExpectedActual
  , printContractAssertionFailure
  , printContractAssertionFailures
  ) where

import Prelude

import Contract.Address (Address)
import Contract.Monad (Contract)
import Contract.PlutusData (OutputDatum)
import Contract.Prelude (Effect)
import Contract.Transaction
  ( ScriptRef
  , TransactionHash
  , TransactionOutputWithRefScript
  , getTxMetadata
  )
import Contract.Utxos (utxosAt)
import Contract.Value (CurrencySymbol, TokenName, Value, valueOf, valueToCoin')
import Control.Monad.Error.Class (liftEither, throwError)
import Control.Monad.Error.Class as E
import Control.Monad.Reader (ReaderT, ask, local, mapReaderT, runReaderT)
import Control.Monad.Trans.Class (lift)
import Ctl.Internal.Cardano.Types.Transaction
  ( ExUnits
  , Transaction
  , _redeemers
  , _witnessSet
  )
import Ctl.Internal.Contract.Monad (ContractEnv)
import Ctl.Internal.Metadata.FromMetadata (fromMetadata)
import Ctl.Internal.Metadata.MetadataType (class MetadataType, metadataLabel)
import Ctl.Internal.Plutus.Types.Transaction
  ( _amount
  , _datum
  , _output
  , _scriptRef
  )
import Ctl.Internal.Types.ByteArray (byteArrayToHex)
import Data.Array (foldr)
import Data.Array (fromFoldable, length, mapWithIndex, partition) as Array
import Data.BigInt (BigInt)
import Data.Either (Either, either, hush)
import Data.Foldable (foldMap, null, sum)
import Data.Generic.Rep (class Generic)
import Data.Lens (non, to, traversed, view, (%~), (^.), (^..))
import Data.Lens.Record (prop)
import Data.List (List(Cons, Nil))
import Data.Map (filterKeys, lookup, values) as Map
import Data.Maybe (Maybe(Just, Nothing), maybe)
import Data.Newtype (unwrap)
import Data.Show.Generic (genericShow)
import Data.String (trim) as String
import Data.String.Common (joinWith) as String
import Data.Tuple.Nested (type (/\), (/\))
import Effect.Class (liftEffect)
import Effect.Exception (Error, error, throw, try)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Type.Proxy (Proxy(Proxy))

-- | Monad allowing for accumulation of assertion failures.
type ContractAssertion (a :: Type) =
  ReaderT (Ref (List ContractAssertionFailure)) Contract a

--------------------------------------------------------------------------------
-- Data types and functions for building assertion failures
--------------------------------------------------------------------------------

data ContractAssertionFailure
  = CouldNotGetTxByHash TransactionHash
  | CouldNotParseMetadata Label
  | TransactionHasNoMetadata TransactionHash (Maybe Label)
  | UnexpectedDatumInOutput (Labeled TransactionOutputWithRefScript)
      (ExpectedActual OutputDatum)
  | UnexpectedLovelaceDelta (Labeled Address) (ExpectedActual BigInt)
  | UnexpectedMetadataValue Label (ExpectedActual String)
  | UnexpectedRefScriptInOutput (Labeled TransactionOutputWithRefScript)
      (ExpectedActual (Maybe ScriptRef))
  | UnexpectedTokenDelta (Labeled Address) TokenName (ExpectedActual BigInt)
  | MaxExUnitsExceeded (ExpectedActual ExUnits)
  | CustomFailure String
  | SkippedTest String

derive instance Eq ContractAssertionFailure
derive instance Generic ContractAssertionFailure _

instance Show ContractAssertionFailure where
  show = genericShow

-- | A pretty-printing function that produces a human-readable report on failures.
printContractAssertionFailures :: Array ContractAssertionFailure -> String
printContractAssertionFailures failures =
  String.trim $ errorText <> warningText
  where
  isWarning :: ContractAssertionFailure -> Boolean
  isWarning = case _ of
    SkippedTest _ -> true
    _ -> false

  { yes: warnings, no: errors } = Array.partition isWarning failures

  listFailures = String.joinWith "\n\n    "
    <<< Array.mapWithIndex
      ( \ix elem -> show (ix + one) <> ". " <> printContractAssertionFailure
          elem
      )
  errorText =
    if Array.length errors > 0 then
      "The following `Contract` assertions have failed: \n    "
        <> listFailures errors
        <> "\n\n"
    else ""
  warningText =
    if Array.length warnings > 0 then
      "The following `Contract` checks have been skipped due to an exception: \n\n    "
        <>
          listFailures warnings
    else ""

-- | Pretty printing function that produces a human readable report for a
-- | single `ContractAssertionFailure`
printContractAssertionFailure :: ContractAssertionFailure -> String
printContractAssertionFailure = case _ of
  CouldNotGetTxByHash txHash ->
    "Could not get tx by hash " <> showTxHash txHash

  CouldNotParseMetadata mdLabel ->
    "Could not parse " <> mdLabel <> " metadata"

  TransactionHasNoMetadata txHash mdLabel ->
    "Tx with id " <> showTxHash txHash <> " does not hold "
      <> (maybe "" (_ <> " ") mdLabel <> "metadata")

  UnexpectedDatumInOutput txOutput expectedActual ->
    "Unexpected datum in output " <> printLabeled txOutput <> " " <>
      printExpectedActual expectedActual

  UnexpectedLovelaceDelta addr expectedActual ->
    "Unexpected lovelace delta at address "
      <> (printLabeled addr <> printExpectedActual expectedActual)

  UnexpectedMetadataValue mdLabel expectedActual ->
    "Unexpected " <> mdLabel <> " metadata value" <> printExpectedActual
      expectedActual

  UnexpectedRefScriptInOutput txOutput expectedActual ->
    "Unexpected reference script in output "
      <> (printLabeled txOutput <> printExpectedActual expectedActual)

  UnexpectedTokenDelta addr tn expectedActual ->
    "Unexpected token delta " <> show tn <> " at address "
      <> (printLabeled addr <> printExpectedActual expectedActual)

  MaxExUnitsExceeded expectedActual ->
    "ExUnits limit exceeded: " <> printExpectedActual expectedActual

  CustomFailure msg -> msg
  SkippedTest msg -> msg

showTxHash :: TransactionHash -> String
showTxHash = byteArrayToHex <<< unwrap

type Label = String

data Labeled (a :: Type) = Labeled a (Maybe Label)

derive instance Eq a => Eq (Labeled a)
derive instance Ord a => Ord (Labeled a)
derive instance Generic (Labeled a) _

instance Show a => Show (Labeled a) where
  show = genericShow

label :: forall (a :: Type). a -> Label -> Labeled a
label x l = Labeled x (Just l)

unlabel :: forall (a :: Type). Labeled a -> a
unlabel (Labeled x _) = x

noLabel :: forall (a :: Type). a -> Labeled a
noLabel = flip Labeled Nothing

printLabeled :: forall (a :: Type). Show a => Labeled a -> String
printLabeled (Labeled _ (Just l)) = l
printLabeled (Labeled x Nothing) = show x

data ExpectedActual (a :: Type) = ExpectedActual a a

derive instance Eq a => Eq (ExpectedActual a)
derive instance Ord a => Ord (ExpectedActual a)
derive instance Generic (ExpectedActual a) _

instance Show a => Show (ExpectedActual a) where
  show = genericShow

derive instance Functor ExpectedActual

printExpectedActual :: forall (a :: Type). Show a => ExpectedActual a -> String
printExpectedActual (ExpectedActual expected actual) =
  " (Expected: " <> show expected <> ", Actual: " <> show actual <> ")"

--------------------------------------------------------------------------------
-- Different types of assertions, Assertion composition, Basic functions
--------------------------------------------------------------------------------

-- | A check that can run some initialization code before the `Contract` is run
-- | and check the results afterwards. It is used to implement assertions that
-- | require state monitoring, e.g. checking gains at address.
type ContractCheck a =
  ContractAssertion a
  -> ContractAssertion (ContractAssertion a /\ ContractAssertion Unit)

-- | Create a check that simply asserts something about a `Contract` result.
-- |
-- | If a `Contract` throws an exception, the assertion is never checked,
-- | because the result is never computed.
assertionToCheck
  :: forall (a :: Type)
   . String
  -> (a -> ContractAssertion Unit)
  -> ContractCheck a
assertionToCheck description f contract = do
  putRef /\ getRef <- tieRef
  let
    run = do
      res <- contract
      putRef res
    finalize = do
      getRef >>= case _ of
        Nothing -> tellFailure $ SkippedTest description
        Just res -> f res
  pure $ run /\ finalize

assertContract
  :: ContractAssertionFailure
  -> Boolean
  -> ContractAssertion Unit
assertContract failure cond = unless cond $ tellFailure failure

assertContractMaybe
  :: forall (a :: Type)
   . ContractAssertionFailure
  -> Maybe a
  -> ContractAssertion a
assertContractMaybe msg =
  maybe (liftEffect $ throw $ printContractAssertionFailure msg) pure

assertContractExpectedActual
  :: forall (a :: Type)
   . Eq a
  => (ExpectedActual a -> ContractAssertionFailure)
  -> a
  -> a
  -> ContractAssertion Unit
assertContractExpectedActual mkAssertionFailure expected actual =
  assertContract (mkAssertionFailure $ ExpectedActual expected actual)
    (expected == actual)

-- | Like `runChecks`, but does not throw a user-readable report, collecting
-- | the exceptions instead.
collectAssertionFailures
  :: forall (a :: Type)
   . Array (ContractCheck a)
  -> ContractAssertion a
  -> Contract (Either Error a /\ Array ContractAssertionFailure)
collectAssertionFailures assertions contract = do
  ref <- liftEffect $ Ref.new Nil
  eiResult <- E.try $ flip runReaderT ref wrappedContract
  failures <- liftEffect $ Ref.read ref
  pure (eiResult /\ Array.fromFoldable failures)
  where
  wrapAssertion :: ContractCheck a -> ContractAssertion a -> ContractAssertion a
  wrapAssertion assertion acc = do
    run /\ finalize <- assertion acc
    E.try run >>= \res -> finalize *> liftEither res

  wrappedContract :: ContractAssertion a
  wrappedContract = foldr wrapAssertion contract assertions

-- | Accepts an array of checks and interprets them into a `Contract`.
runChecks
  :: forall (a :: Type)
   . Array (ContractCheck a)
  -> ContractAssertion a
  -> Contract a
runChecks assertions contract = do
  eiResult /\ failures <- collectAssertionFailures assertions contract
  if null failures then either
    (liftEffect <<< throwError <<< error <<< reportException)
    pure
    eiResult
  else do
    let
      errorStr = either reportException (const "") eiResult
      errorReport =
        String.trim
          ( errorStr <> "\n\n" <>
              printContractAssertionFailures (Array.fromFoldable failures)
          ) <> "\n"
    -- error trace from the exception itself will be appended here
    liftEffect $ throwError $ error errorReport
  where
  reportException :: Error -> String
  reportException error = "\n\nAn exception has been thrown: \n\n" <> show error

tellFailure
  :: ContractAssertionFailure -> ContractAssertion Unit
tellFailure failure = do
  ask >>= liftEffect <<< Ref.modify_ (Cons failure)

checkNewUtxosAtAddress
  :: forall (a :: Type)
   . Labeled Address
  -> TransactionHash
  -> (Array TransactionOutputWithRefScript -> ContractAssertion a)
  -> ContractAssertion a
checkNewUtxosAtAddress addr txHash check =
  lift (utxosAt $ unlabel addr) >>= \utxos ->
    check $ Array.fromFoldable $ Map.values $
      Map.filterKeys (\oref -> (unwrap oref).transactionId == txHash) utxos

-- | Sets a limit on `ExUnits` budget. All ExUnits values of all submitted transactions are combined. Transactions that are constructed, but not submitted, are not considered.
-- | The execution of the `Contract` will not be interrupted in case the `ExUnits` limit is reached.
checkExUnitsNotExceed
  :: forall (a :: Type)
   . ExUnits
  -> ContractCheck a
checkExUnitsNotExceed maxExUnits contract = do
  (ref :: Ref ExUnits) <- liftEffect $ Ref.new { mem: zero, steps: zero }
  let
    submitHook :: Transaction -> Effect Unit
    submitHook tx = do
      let
        (newExUnits :: ExUnits) = sum $ tx ^..
          _witnessSet
            <<< _redeemers
            <<< non []
            <<< traversed
            <<< to (unwrap >>> _.exUnits)
      Ref.modify_ (add newExUnits) ref

    setSubmitHook :: ContractEnv -> ContractEnv
    setSubmitHook =
      prop (Proxy :: Proxy "hooks") <<< prop (Proxy :: Proxy "onSubmit")
        -- Extend a hook action if it exists, or set it to `Just submitHook`
        %~ maybe (Just submitHook)
          \oldHook -> Just \tx -> do
            -- ignore possible exception from the old hook
            void $ try $ oldHook tx
            submitHook tx

    finalize :: ContractAssertion Unit
    finalize = do
      exUnits <- liftEffect $ Ref.read ref
      assertContract (MaxExUnitsExceeded (ExpectedActual maxExUnits exUnits))
        (maxExUnits.mem >= exUnits.mem && maxExUnits.steps >= exUnits.steps)

  pure (mapReaderT (local setSubmitHook) contract /\ finalize)

valueAtAddress'
  :: Labeled Address
  -> ContractAssertion Value
valueAtAddress' = map (foldMap (view (_output <<< _amount))) <<< lift
  <<< utxosAt
  <<< unlabel

-- | Arguments are:
-- |
-- | - a labeled address
-- | - a callback that implements the assertion, accepting `Contract` execution
-- |   result, and values (before and after). The value may not be computed due
-- |   to an exception, hence it's wrapped in `Maybe`.
assertValueDeltaAtAddress
  :: forall (a :: Type)
   . Labeled Address
  -> (Maybe a -> Value -> Value -> ContractAssertion Unit)
  -> ContractCheck a
assertValueDeltaAtAddress addr check contract = do
  valueBefore <- valueAtAddress' addr
  ref <- liftEffect $ Ref.new Nothing
  let
    finalize = do
      valueAfter <- valueAtAddress' addr
      liftEffect (Ref.read ref) >>= \res -> check res valueBefore valueAfter
    run = do
      res <- contract
      liftEffect $ Ref.write (Just res) ref
      pure res
  pure (run /\ finalize)

assertLovelaceDeltaAtAddress
  :: forall (a :: Type)
   . Labeled Address
  -> (Maybe a -> Contract BigInt)
  -> (BigInt -> BigInt -> Boolean)
  -> ContractCheck a
assertLovelaceDeltaAtAddress addr getExpected comp contract = do
  assertValueDeltaAtAddress addr check contract
  where
  check :: Maybe a -> Value -> Value -> ContractAssertion Unit
  check result valueBefore valueAfter = do
    expected <- lift $ getExpected result
    let
      actual :: BigInt
      actual = valueToCoin' valueAfter - valueToCoin' valueBefore

      unexpectedLovelaceDelta :: ContractAssertionFailure
      unexpectedLovelaceDelta =
        UnexpectedLovelaceDelta addr (ExpectedActual expected actual)

    assertContract unexpectedLovelaceDelta (comp actual expected)

-- | Requires that the computed amount of lovelace was gained at the address
-- | by calling the contract.
checkGainAtAddress
  :: forall (a :: Type)
   . Labeled Address
  -> (Maybe a -> Contract BigInt)
  -> ContractCheck a
checkGainAtAddress addr getMinGain =
  assertLovelaceDeltaAtAddress addr getMinGain eq

-- | Requires that the passed amount of lovelace was gained at the address
-- | by calling the contract.
checkGainAtAddress'
  :: forall (a :: Type)
   . Labeled Address
  -> BigInt
  -> ContractCheck a
checkGainAtAddress' addr minGain =
  checkGainAtAddress addr (const $ pure minGain)

-- | Requires that the computed amount of lovelace was lost at the address
-- | by calling the contract.
checkLossAtAddress
  :: forall (a :: Type)
   . Labeled Address
  -> (Maybe a -> Contract BigInt)
  -> ContractCheck a
checkLossAtAddress addr getMinLoss =
  assertLovelaceDeltaAtAddress addr (map negate <<< getMinLoss) eq

-- | Requires that the passed amount of lovelace was lost at the address
-- | by calling the contract.
checkLossAtAddress'
  :: forall (a :: Type)
   . Labeled Address
  -> BigInt
  -> ContractCheck a
checkLossAtAddress' addr minLoss =
  checkLossAtAddress addr (const $ pure minLoss)

checkTokenDeltaAtAddress
  :: forall (a :: Type)
   . Labeled Address
  -> (CurrencySymbol /\ TokenName)
  -> (Maybe a -> Contract BigInt)
  -> (BigInt -> BigInt -> Boolean)
  -> ContractCheck a
checkTokenDeltaAtAddress addr (cs /\ tn) getExpected comp contract =
  assertValueDeltaAtAddress addr check contract
  where
  check :: Maybe a -> Value -> Value -> ContractAssertion Unit
  check result valueBefore valueAfter = do
    expected <- lift $ getExpected result
    let
      actual :: BigInt
      actual = valueOf valueAfter cs tn - valueOf valueBefore cs tn

      unexpectedTokenDelta :: ContractAssertionFailure
      unexpectedTokenDelta =
        UnexpectedTokenDelta addr tn (ExpectedActual expected actual)

    assertContract unexpectedTokenDelta (comp actual expected)

-- | Requires that the computed number of tokens was gained at the address
-- | by calling the contract.
checkTokenGainAtAddress
  :: forall (a :: Type)
   . Labeled Address
  -> (CurrencySymbol /\ TokenName)
  -> (Maybe a -> Contract BigInt)
  -> ContractCheck a
checkTokenGainAtAddress addr token getMinGain =
  checkTokenDeltaAtAddress addr token getMinGain eq

-- | Requires that the passed number of tokens was gained at the address
-- | by calling the contract.
checkTokenGainAtAddress'
  :: forall (a :: Type)
   . Labeled Address
  -> (CurrencySymbol /\ TokenName /\ BigInt)
  -> ContractCheck a
checkTokenGainAtAddress' addr (cs /\ tn /\ minGain) =
  checkTokenGainAtAddress addr (cs /\ tn) (const $ pure minGain)

-- | Requires that the computed number of tokens was lost at the address
-- | by calling the contract.
checkTokenLossAtAddress
  :: forall (a :: Type)
   . Labeled Address
  -> (CurrencySymbol /\ TokenName)
  -> (Maybe a -> Contract BigInt)
  -> ContractCheck a
checkTokenLossAtAddress addr token getMinLoss =
  checkTokenDeltaAtAddress addr token (map negate <<< getMinLoss) eq

-- | Requires that the passed number of tokens was lost at the address
-- | by calling the contract.
checkTokenLossAtAddress'
  :: forall (a :: Type)
   . Labeled Address
  -> (CurrencySymbol /\ TokenName /\ BigInt)
  -> ContractCheck a
checkTokenLossAtAddress' addr (cs /\ tn /\ minLoss) =
  checkTokenLossAtAddress addr (cs /\ tn) (const $ pure minLoss)

-- | Requires that the transaction output contains the specified datum or
-- | datum hash.
assertOutputHasDatum
  :: OutputDatum
  -> Labeled TransactionOutputWithRefScript
  -> ContractAssertion Unit
assertOutputHasDatum expectedDatum txOutput = do
  let actualDatum = unlabel txOutput ^. _output <<< _datum
  assertContractExpectedActual (UnexpectedDatumInOutput txOutput)
    expectedDatum
    actualDatum

-- | Requires that the transaction output contains the specified reference
-- | script.
assertOutputHasRefScript
  :: ScriptRef
  -> Labeled TransactionOutputWithRefScript
  -> ContractAssertion Unit
assertOutputHasRefScript expectedRefScript txOutput = do
  let actualRefScript = unlabel txOutput ^. _scriptRef
  assertContractExpectedActual (UnexpectedRefScriptInOutput txOutput)
    (Just expectedRefScript)
    actualRefScript

tieRef
  :: forall (a :: Type)
   . ContractAssertion
       ((a -> ContractAssertion a) /\ ContractAssertion (Maybe a))
tieRef = do
  ref <- liftEffect $ Ref.new Nothing
  let
    putResult result = do
      liftEffect $ Ref.write (Just result) ref
      pure result
    getResult = liftEffect (Ref.read ref)
  pure (putResult /\ getResult)

assertTxHasMetadata
  :: forall (metadata :: Type) (a :: Type)
   . MetadataType metadata
  => Eq metadata
  => Show metadata
  => Label
  -> TransactionHash
  -> metadata
  -> ContractAssertion Unit
assertTxHasMetadata mdLabel txHash expectedMetadata = do
  generalMetadata <-
    assertContractMaybe (TransactionHasNoMetadata txHash Nothing)
      =<< lift (hush <$> getTxMetadata txHash)

  rawMetadata <-
    assertContractMaybe (TransactionHasNoMetadata txHash (Just mdLabel))
      ( Map.lookup (metadataLabel (Proxy :: Proxy metadata))
          (unwrap generalMetadata)
      )

  (metadata :: metadata) <-
    assertContractMaybe (CouldNotParseMetadata mdLabel)
      (fromMetadata rawMetadata)

  let expectedActual = show <$> ExpectedActual expectedMetadata metadata
  assertContract (UnexpectedMetadataValue mdLabel expectedActual)
    (metadata == expectedMetadata)
