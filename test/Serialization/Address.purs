module Test.Ctl.Serialization.Address (suite) where

import Prelude

import Cardano.Serialization.Lib (fromBytes, toBytes)
import Contract.Address (addressWithNetworkTagFromBech32)
import Ctl.Internal.Serialization.Address
  ( NetworkId(MainnetId, TestnetId)
  , addressBech32
  , addressFromBech32
  , addressNetworkId
  , baseAddressDelegationCred
  , baseAddressFromAddress
  , baseAddressPaymentCred
  , baseAddressToAddress
  , enterpriseAddress
  , enterpriseAddressFromAddress
  , enterpriseAddressPaymentCred
  , enterpriseAddressToAddress
  , keyHashCredential
  , paymentKeyHashStakeKeyHashAddress
  , pointerAddress
  , pointerAddressFromAddress
  , pointerAddressPaymentCred
  , pointerAddressStakePointer
  , pointerAddressToAddress
  , rewardAddress
  , rewardAddressFromAddress
  , rewardAddressPaymentCred
  , rewardAddressToAddress
  , scriptHashCredential
  , stakeCredentialToKeyHash
  , stakeCredentialToScriptHash
  )
import Ctl.Internal.Serialization.Hash
  ( Ed25519KeyHash
  , ScriptHash
  , ed25519KeyHashFromBech32
  , scriptHashFromBytes
  )
import Ctl.Internal.Test.TestPlanM (TestPlanM)
import Ctl.Internal.Types.Aliases (Bech32String)
import Ctl.Internal.Types.BigNum (fromInt, fromStringUnsafe) as BigNum
import Data.ByteArray (hexToByteArrayUnsafe)
import Data.Maybe (Maybe(Nothing))
import Data.Newtype (unwrap, wrap)
import Effect.Aff (Aff)
import Effect.Class.Console (log)
import Mote (group, test)
import Test.Ctl.Fixtures (ed25519KeyHashFixture1)
import Test.Ctl.Utils (errMaybe)
import Test.Spec.Assertions (shouldEqual)

doesNotThrow
  :: forall (f :: Type -> Type) (a :: Type). Applicative f => a -> f a
doesNotThrow = pure

pkhBech32 :: Bech32String
pkhBech32 = "addr_vkh1zuctrdcq6ctd29242w8g84nlz0q38t2lnv3zzfcrfqktx0c9tzp"

scriptHashHex :: String
scriptHashHex = "463e9264962cea64efafa576d44c8d2821d09c0c7495c253d4101a9a"

mPkh :: Maybe Ed25519KeyHash
mPkh = ed25519KeyHashFromBech32 pkhBech32

mScriptHash :: Maybe ScriptHash
mScriptHash = scriptHashFromBytes $ hexToByteArrayUnsafe scriptHashHex

addressFunctionsTest :: TestPlanM (Aff Unit) Unit
addressFunctionsTest = test "Address tests" $ do
  let
    bechstr =
      "addr1qyc0kwu98x23ufhsxjgs5k3h7gktn8v5682qna5amwh2juguztcrc8hjay66es67ctn0jmr9plfmlw37je2s2px4xdssgvxerq"
    testnetBech =
      "addr_test1qqm0z9quxyefwwq902p5f9t4s35smhegjthhhqpeclnpx2rzhuq2p6jahnky7qqua9nz9tcw6nlgy6cpjvmlaaye4apqzc6ppq"
  addr1 <- errMaybe "addressFromBech32 failed on valid bech32" $
    addressFromBech32 bechstr
  bechstr `shouldEqual` addressBech32 addr1
  addressFromBech32 "randomstuff" `shouldEqual` Nothing
  let addrBts = toBytes $ unwrap addr1
  addr2 <- map wrap $ errMaybe "addressFromBech32 failed on valid bech32" $
    fromBytes addrBts
  addr2 `shouldEqual` addr1
  addressNetworkId addr2 `shouldEqual` MainnetId
  testnetAddr <-
    errMaybe "addressWithNetworkTagFromBech32 failed on valid bech32" $
      addressWithNetworkTagFromBech32 testnetBech
  mainnetAddr <-
    errMaybe "addressWithNetworkTagFromBech32 failed on valid bech32" $
      addressWithNetworkTagFromBech32 bechstr
  _.networkId (unwrap testnetAddr) `shouldEqual` TestnetId
  _.networkId (unwrap mainnetAddr) `shouldEqual` MainnetId

stakeCredentialTests :: TestPlanM (Aff Unit) Unit
stakeCredentialTests = test "StakeCredential tests" $ do
  pkh <- errMaybe "Error ed25519KeyHashFromBech32:" mPkh
  scrh <- errMaybe "Error scriptHashFromBech32:" mScriptHash

  let
    pkhCred = keyHashCredential $ pkh
    schCred = scriptHashCredential $ scrh
    pkhCredBytes = toBytes $ unwrap pkhCred
    schCredBytes = toBytes $ unwrap schCred

  pkhCred2 <- map wrap
    $ errMaybe "StakeCredential FromBytes failed on valid bytes"
    $
      fromBytes pkhCredBytes
  pkh2 <- errMaybe "stakeCredentialToKeyHash failed" $ stakeCredentialToKeyHash
    pkhCred2
  pkh2 `shouldEqual` pkh
  stakeCredentialToScriptHash pkhCred2 `shouldEqual` Nothing

  schCred2 <- map wrap
    $ errMaybe "StakeCredential FromBytes failed on valid bytes"
    $
      fromBytes schCredBytes
  sch2 <- errMaybe "stakeCredentialToScriptHash failed" $
    stakeCredentialToScriptHash schCred2
  sch2 `shouldEqual` scrh
  stakeCredentialToKeyHash schCred2 `shouldEqual` Nothing

baseAddressFunctionsTest :: TestPlanM (Aff Unit) Unit
baseAddressFunctionsTest = test "BaseAddress tests" $ do
  pkh <- errMaybe "Error ed25519KeyHashFromBech32:" mPkh
  baddr <- doesNotThrow $
    paymentKeyHashStakeKeyHashAddress MainnetId pkh ed25519KeyHashFixture1
  addr <- doesNotThrow $ baseAddressToAddress baddr
  baddr2 <- errMaybe "baseAddressFromAddress failed on valid base address" $
    baseAddressFromAddress
      addr
  baddr2 `shouldEqual` baddr
  baseAddressDelegationCred baddr `shouldEqual` keyHashCredential
    ed25519KeyHashFixture1
  baseAddressPaymentCred baddr `shouldEqual` keyHashCredential pkh

rewardAddressFunctionsTest :: TestPlanM (Aff Unit) Unit
rewardAddressFunctionsTest = test "RewardAddress tests" $ do
  pkh <- errMaybe "Error ed25519KeyHashFromBech32:" mPkh
  raddr <- doesNotThrow $ rewardAddress
    { network: TestnetId, paymentCred: keyHashCredential pkh }
  addr <- doesNotThrow $ rewardAddressToAddress raddr
  raddr2 <- errMaybe "rewardAddressFromAddress failed on valid reward address" $
    rewardAddressFromAddress addr
  raddr2 `shouldEqual` raddr
  rewardAddressPaymentCred raddr `shouldEqual` keyHashCredential pkh

enterpriseAddressFunctionsTest :: TestPlanM (Aff Unit) Unit
enterpriseAddressFunctionsTest = test "EnterpriseAddress tests" $ do
  pkh <- errMaybe "Error ed25519KeyHashFromBech32:" mPkh
  eaddr <- doesNotThrow $ enterpriseAddress
    { network: MainnetId, paymentCred: keyHashCredential pkh }
  addr <- doesNotThrow $ enterpriseAddressToAddress eaddr
  eaddr2 <-
    errMaybe "enterpriseAddressFromAddress failed on valid enterprise address" $
      enterpriseAddressFromAddress addr
  eaddr2 `shouldEqual` eaddr
  enterpriseAddressPaymentCred eaddr `shouldEqual` keyHashCredential pkh

pointerAddressFunctionsTest :: TestPlanM (Aff Unit) Unit
pointerAddressFunctionsTest = test "PointerAddress tests" $ do
  pkh <- errMaybe "Error ed25519KeyHashFromBech32:" mPkh
  let
    pointer =
      { slot: wrap (BigNum.fromStringUnsafe "2147483648")
      , certIx: wrap (BigNum.fromInt 20)
      , txIx: wrap (BigNum.fromInt 120)
      }
  paddr <- doesNotThrow $ pointerAddress
    { network: MainnetId
    , paymentCred: keyHashCredential pkh
    , stakePointer: pointer
    }
  addr <- doesNotThrow $ pointerAddressToAddress paddr
  paddr2 <- errMaybe "pointerAddressFromAddress failed on valid pointer address"
    $
      pointerAddressFromAddress addr
  paddr2 `shouldEqual` paddr
  pointerAddressPaymentCred paddr `shouldEqual` keyHashCredential pkh
  pointerAddressStakePointer paddr `shouldEqual` pointer

byronAddressFunctionsTest :: TestPlanM (Aff Unit) Unit
byronAddressFunctionsTest = test "ByronAddress tests" $ log
  "ByronAddress tests todo"

suite :: TestPlanM (Aff Unit) Unit
suite = group "Address test suite" $ do
  addressFunctionsTest
  stakeCredentialTests
  baseAddressFunctionsTest
  rewardAddressFunctionsTest
  enterpriseAddressFunctionsTest
  pointerAddressFunctionsTest
  byronAddressFunctionsTest
