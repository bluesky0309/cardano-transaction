module Ctl.Internal.Wallet.Cip30Mock where

import Prelude

import Contract.Monad (Contract, ContractEnv, wrapContract)
import Control.Monad.Error.Class (liftMaybe, try)
import Control.Monad.Reader (ask)
import Control.Monad.Reader.Class (local)
import Control.Promise (Promise, fromAff)
import Ctl.Internal.Cardano.Types.TransactionUnspentOutput
  ( TransactionUnspentOutput(TransactionUnspentOutput)
  )
import Ctl.Internal.Deserialization.Transaction (deserializeTransaction)
import Ctl.Internal.Helpers (liftEither)
import Ctl.Internal.QueryM (QueryM, runQueryMInRuntime)
import Ctl.Internal.QueryM.Utxos (utxosAt)
import Ctl.Internal.Serialization
  ( convertTransactionUnspentOutput
  , convertValue
  , toBytes
  )
import Ctl.Internal.Serialization.Address (NetworkId(TestnetId, MainnetId))
import Ctl.Internal.Serialization.WitnessSet (convertWitnessSet)
import Ctl.Internal.Types.ByteArray (byteArrayToHex, hexToByteArray)
import Ctl.Internal.Types.CborBytes (cborBytesFromByteArray, cborBytesToHex)
import Ctl.Internal.Wallet
  ( Wallet
  , WalletExtension(LodeWallet, NamiWallet, GeroWallet, FlintWallet, NuFiWallet)
  , mkWalletAff
  )
import Ctl.Internal.Wallet.Key
  ( KeyWallet(KeyWallet)
  , PrivatePaymentKey
  , PrivateStakeKey
  , privateKeysToKeyWallet
  )
import Data.Array as Array
import Data.Either (hush)
import Data.Foldable (fold, foldMap)
import Data.Function.Uncurried (Fn2, mkFn2)
import Data.Lens ((.~))
import Data.Lens.Common (simple)
import Data.Lens.Iso.Newtype (_Newtype)
import Data.Lens.Record (prop)
import Data.Map as Map
import Data.Maybe (Maybe(Just))
import Data.Newtype (unwrap, wrap)
import Data.Traversable (traverse)
import Data.Tuple.Nested ((/\))
import Data.UInt as UInt
import Effect (Effect)
import Effect.Aff (Aff)
import Effect.Aff.Class (liftAff)
import Effect.Class (liftEffect)
import Effect.Exception (error)
import Effect.Unsafe (unsafePerformEffect)
import Type.Proxy (Proxy(Proxy))
import Untagged.Union (asOneOf)

data WalletMock = MockFlint | MockGero | MockNami | MockLode | MockNuFi

-- | Construct a CIP-30 wallet mock that exposes `KeyWallet` functionality
-- | behind a CIP-30 interface and uses Ogmios to submit Txs.
-- | The wallet is injected directly to `window.cardano` object, under the
-- | name corresponding to provided `WalletMock`. It works even in NodeJS
-- | (we introduce a global `window` object and delete it afterwards).
-- |
-- | Note that this function will refuse to overwrite existing wallet
-- | with the mock, so the users should disable their browser extensions
-- | before running it in the browser.
-- |
-- | Note that this function implements single-address light wallet logic, so
-- | it will have to be changed a lot to successfully mimic the behavior of
-- | multi-address wallets, like Eternl.
withCip30Mock
  :: forall (r :: Row Type) (a :: Type)
   . KeyWallet
  -> WalletMock
  -> Contract r a
  -> Contract r a
withCip30Mock (KeyWallet keyWallet) mock contract = do
  cip30Mock <- wrapContract $ mkCip30Mock keyWallet.paymentKey
    keyWallet.stakeKey
  deleteMock <- liftEffect $ injectCip30Mock mockString cip30Mock
  wallet <- liftAff mkWalletAff'
  let
    setUpdatedWallet :: ContractEnv r -> ContractEnv r
    setUpdatedWallet =
      simple _Newtype <<< prop (Proxy :: Proxy "runtime") <<< prop
        (Proxy :: Proxy "wallet") .~
        (Just wallet)
  res <- try $ local setUpdatedWallet contract
  liftEffect deleteMock
  liftEither res
  where
  mkWalletAff' :: Aff Wallet
  mkWalletAff' = case mock of
    MockFlint -> mkWalletAff FlintWallet
    MockGero -> mkWalletAff GeroWallet
    MockNami -> mkWalletAff NamiWallet
    MockLode -> mkWalletAff LodeWallet
    MockNuFi -> mkWalletAff NuFiWallet

  mockString :: String
  mockString = case mock of
    MockFlint -> "flint"
    MockGero -> "gerowallet"
    MockNami -> "nami"
    MockLode -> "LodeWallet"
    MockNuFi -> "nufi"

type Cip30Mock =
  { getNetworkId :: Effect (Promise Int)
  , getUtxos :: Effect (Promise (Array String))
  , getCollateral :: Effect (Promise (Array String))
  , getBalance :: Effect (Promise String)
  , getUsedAddresses :: Effect (Promise (Array String))
  , getUnusedAddresses :: Effect (Promise (Array String))
  , getChangeAddress :: Effect (Promise String)
  , getRewardAddresses :: Effect (Promise (Array String))
  , signTx :: String -> Promise String
  , signData ::
      Fn2 String String (Promise { key :: String, signature :: String })
  }

mkCip30Mock
  :: PrivatePaymentKey -> Maybe PrivateStakeKey -> QueryM Cip30Mock
mkCip30Mock pKey mSKey = do
  { config, runtime } <- ask
  let
    getCollateralUtxos utxos = do
      let
        pparams = unwrap $ runtime.pparams
        coinsPerUtxoUnit = pparams.coinsPerUtxoUnit
        maxCollateralInputs = UInt.toInt $
          pparams.maxCollateralInputs
      liftEffect $
        (unwrap keyWallet).selectCollateral coinsPerUtxoUnit
          maxCollateralInputs
          utxos
          <#> fold

  pure $
    { getNetworkId: fromAff $ pure $
        case config.networkId of
          TestnetId -> 0
          MainnetId -> 1
    , getUtxos: fromAff do
        ownAddress <- (unwrap keyWallet).address config.networkId
        utxos <- liftMaybe (error "No UTxOs at address") =<<
          runQueryMInRuntime config runtime (utxosAt ownAddress)
        collateralUtxos <- getCollateralUtxos utxos
        let
          -- filter UTxOs that will be used as collateral
          nonCollateralUtxos =
            Map.filter
              (flip Array.elem (collateralUtxos <#> unwrap >>> _.output))
              utxos
        -- Convert to CSL representation and serialize
        cslUtxos <- traverse (liftEffect <<< convertTransactionUnspentOutput)
          $ Map.toUnfoldable nonCollateralUtxos <#> \(input /\ output) ->
              TransactionUnspentOutput { input, output }
        pure $ (byteArrayToHex <<< toBytes <<< asOneOf) <$> cslUtxos
    , getCollateral: fromAff do
        ownAddress <- (unwrap keyWallet).address config.networkId
        utxos <- liftMaybe (error "No UTxOs at address") =<<
          runQueryMInRuntime config runtime (utxosAt ownAddress)
        collateralUtxos <- getCollateralUtxos utxos
        cslUnspentOutput <- liftEffect $ traverse
          convertTransactionUnspentOutput
          collateralUtxos
        pure $ (byteArrayToHex <<< toBytes <<< asOneOf) <$> cslUnspentOutput
    , getBalance: fromAff do
        ownAddress <- (unwrap keyWallet).address config.networkId
        utxos <- liftMaybe (error "No UTxOs at address") =<<
          runQueryMInRuntime config runtime (utxosAt ownAddress)
        value <- liftEffect $ convertValue $
          (foldMap (_.amount <<< unwrap) <<< Map.values)
            utxos
        pure $ byteArrayToHex $ toBytes $ asOneOf value
    , getUsedAddresses: fromAff do
        (unwrap keyWallet).address config.networkId <#> \address ->
          [ (byteArrayToHex <<< toBytes <<< asOneOf) address ]
    , getUnusedAddresses: fromAff $ pure []
    , getChangeAddress: fromAff do
        (unwrap keyWallet).address config.networkId <#>
          (byteArrayToHex <<< toBytes <<< asOneOf)
    , getRewardAddresses: fromAff do
        (unwrap keyWallet).address config.networkId <#> \address ->
          [ (byteArrayToHex <<< toBytes <<< asOneOf) address ]
    , signTx: \str -> unsafePerformEffect $ fromAff do
        txBytes <- liftMaybe (error "Unable to convert CBOR") $ hexToByteArray
          str
        tx <- liftMaybe (error "Failed to decode Transaction CBOR")
          $ hush
          $ deserializeTransaction
          $ cborBytesFromByteArray txBytes
        witness <- (unwrap keyWallet).signTx tx
        cslWitnessSet <- liftEffect $ convertWitnessSet witness
        pure $ byteArrayToHex $ toBytes $ asOneOf cslWitnessSet
    , signData: mkFn2 \_addr msg -> unsafePerformEffect $ fromAff do
        msgBytes <- liftMaybe (error "Unable to convert CBOR")
          (hexToByteArray msg)
        { key, signature } <- (unwrap keyWallet).signData config.networkId
          (wrap msgBytes)
        pure { key: cborBytesToHex key, signature: cborBytesToHex signature }
    }
  where
  keyWallet = privateKeysToKeyWallet pKey mSKey

-- returns an action that removes the mock.
foreign import injectCip30Mock :: String -> Cip30Mock -> Effect (Effect Unit)
