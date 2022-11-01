module Test.Ctl.AffInterface (suite) where

import Prelude

import Contract.Chain (ChainTip(ChainTip), Tip(Tip, TipAtGenesis))
import Control.Monad.Except (throwError)
import Ctl.Internal.Address (ogmiosAddressToAddress)
import Ctl.Internal.QueryM
  ( QueryM
  , getChainTip
  , getDatumByHash
  , getDatumsByHashes
  , getDatumsByHashesWithErrors
  , submitTxOgmios
  )
import Ctl.Internal.QueryM.CurrentEpoch (getCurrentEpoch)
import Ctl.Internal.QueryM.EraSummaries (getEraSummaries)
import Ctl.Internal.QueryM.Ogmios (OgmiosAddress)
import Ctl.Internal.QueryM.SystemStart (getSystemStart)
import Ctl.Internal.QueryM.Utxos (utxosAt)
import Ctl.Internal.QueryM.WaitUntilSlot (waitUntilSlot)
import Ctl.Internal.Serialization.Address (Slot(Slot))
import Ctl.Internal.Test.TestPlanM (TestPlanM)
import Ctl.Internal.Types.BigNum (add, fromInt) as BigNum
import Ctl.Internal.Types.ByteArray (hexToByteArrayUnsafe)
import Ctl.Internal.Types.Transaction (DataHash(DataHash))
import Data.Either (Either(Left, Right))
import Data.Maybe (Maybe(Just, Nothing), fromMaybe, isJust)
import Data.Newtype (over, wrap)
import Data.String.CodeUnits (indexOf)
import Data.String.Pattern (Pattern(Pattern))
import Effect.Aff (error, try)
import Mote (group, test)
import Test.Spec.Assertions (shouldSatisfy)

testnet_addr1 :: OgmiosAddress
testnet_addr1 =
  "addr_test1qr7g8nrv76fc7k4ueqwecljxx9jfwvsgawhl55hck3n8uwaz26mpcwu58zdkhpdnc6nuq3fa8vylc8ak9qvns7r2dsysp7ll4d"

addr1 :: OgmiosAddress
addr1 =
  "addr1qyc0kwu98x23ufhsxjgs5k3h7gktn8v5682qna5amwh2juguztcrc8hjay66es67ctn0jmr9plfmlw37je2s2px4xdssgvxerq"

-- note: currently this suite relies on Ogmios being open and running against the
-- testnet, and does not directly test outputs, as this suite is intended to
-- help verify that the Aff interface for websockets itself works,
-- not that the data represents expected values, as that would depend on chain
-- state, and ogmios itself.
suite :: TestPlanM (QueryM Unit) Unit
suite = do
  group "Aff Interface" do
    test "UtxosAt Testnet" $ testUtxosAt testnet_addr1
    test "UtxosAt Mainnet" $ testUtxosAt addr1
    test "Get ChainTip" testGetChainTip
    test "Get waitUntilSlot" testWaitUntilSlot
    test "Get EraSummaries" testGetEraSummaries
    test "Get CurrentEpoch" testGetCurrentEpoch
    test "Get SystemStart" testGetSystemStart
  group "Ogmios error" do
    test "Ogmios fails with user-friendly message" do
      try testSubmitTxFailure >>= case _ of
        Right _ -> do
          void $ throwError $ error $
            "Unexpected success in testSubmitTxFailure"
        Left error -> do
          (Pattern "Server responded with `fault`" `indexOf` show error)
            `shouldSatisfy` isJust
  group "Ogmios datum cache" do
    test "Can process GetDatumByHash" do
      testOgmiosDatumCacheGetDatumByHash
    test "Can process GetDatumsByHashes" do
      testOgmiosDatumCacheGetDatumsByHashes
    test "Can process GetDatumsByHashesWithErrors" do
      testOgmiosDatumCacheGetDatumsByHashesWithErrors

testOgmiosDatumCacheGetDatumByHash :: QueryM Unit
testOgmiosDatumCacheGetDatumByHash = do
  void $ getDatumByHash $ DataHash $ hexToByteArrayUnsafe
    "f7c47c65216f7057569111d962a74de807de57e79f7efa86b4e454d42c875e4e"

testOgmiosDatumCacheGetDatumsByHashes :: QueryM Unit
testOgmiosDatumCacheGetDatumsByHashes = do
  void $ getDatumsByHashes $ pure $ DataHash $ hexToByteArrayUnsafe
    "f7c47c65216f7057569111d962a74de807de57e79f7efa86b4e454d42c875e4e"

testOgmiosDatumCacheGetDatumsByHashesWithErrors :: QueryM Unit
testOgmiosDatumCacheGetDatumsByHashesWithErrors = do
  void $ getDatumsByHashesWithErrors $ pure $ DataHash $ hexToByteArrayUnsafe
    "f7c47c65216f7057569111d962a74de807de57e79f7efa86b4e454d42c875e4e"

testUtxosAt :: OgmiosAddress -> QueryM Unit
testUtxosAt testAddr = case ogmiosAddressToAddress testAddr of
  Nothing -> throwError (error "Failed UtxosAt")
  Just addr -> void $ utxosAt addr

testGetChainTip :: QueryM Unit
testGetChainTip = do
  void getChainTip

testWaitUntilSlot :: QueryM Unit
testWaitUntilSlot = do
  void $ getChainTip >>= case _ of
    TipAtGenesis -> throwError $ error "Tip is at genesis"
    Tip (ChainTip { slot }) -> do
      waitUntilSlot $ over Slot
        (fromMaybe (BigNum.fromInt 0) <<< BigNum.add (BigNum.fromInt 10))
        slot

testGetEraSummaries :: QueryM Unit
testGetEraSummaries = do
  void getEraSummaries

testSubmitTxFailure :: QueryM Unit
testSubmitTxFailure = do
  let bytes = hexToByteArrayUnsafe "00"
  void $ submitTxOgmios bytes (wrap bytes)

testGetCurrentEpoch :: QueryM Unit
testGetCurrentEpoch = do
  void getCurrentEpoch

testGetSystemStart :: QueryM Unit
testGetSystemStart = do
  void getSystemStart
