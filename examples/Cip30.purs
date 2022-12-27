-- | This module demonstrates the use of the CIP-30 functions
-- | using an external wallet.
module Ctl.Examples.Cip30
  ( main
  , example
  , contract
  ) where

import Contract.Prelude

import Contract.Config (ContractParams, testnetNamiConfig)
import Contract.Log (logInfo')
import Contract.Monad (Contract, launchAff_, liftContractAffM, runContract)
import Contract.Prim.ByteArray (rawBytesFromAscii)
import Contract.Wallet
  ( WalletExtension
  , apiVersion
  , getChangeAddress
  , getRewardAddresses
  , getUnusedAddresses
  , getWallet
  , icon
  , isEnabled
  , isWalletAvailable
  , name
  , signData
  , walletToWalletExtension
  )
import Control.Monad.Error.Class (liftMaybe)
import Data.Array (head)
import Effect.Exception (error)

main :: Effect Unit
main = example testnetNamiConfig

example :: ContractParams -> Effect Unit
example cfg = launchAff_ do
  mWallet <- runContract cfg getWallet
  let mSupportWallet = walletToWalletExtension =<< mWallet
  _ <- traverse nonConfigFunctions mSupportWallet
  runContract cfg contract

nonConfigFunctions :: WalletExtension -> Aff Unit
nonConfigFunctions extensionWallet = do
  log "Functions that don't depend on `Contract`"
  performAndLog "isWalletAvailable" (liftEffect <<< isWalletAvailable)
  performAndLog "isEnabled" isEnabled
  performAndLog "apiVersion" apiVersion
  performAndLog "name" name
  performAndLog "icon" icon
  where
  performAndLog
    :: forall (a :: Type)
     . Show a
    => String
    -> (WalletExtension -> Aff a)
    -> Aff Unit
  performAndLog msg f = do
    result <- f extensionWallet
    log $ msg <> ":" <> (show result)

contract :: Contract Unit
contract = do
  logInfo' "Running Examples.Cip30"
  logInfo' "Funtions that depend on `Contract`"
  _ <- performAndLog "getUnusedAddresses" getUnusedAddresses
  dataBytes <- liftContractAffM
    ("can't convert : " <> msg <> " to RawBytes")
    (pure mDataBytes)
  mRewardAddress <- performAndLog "getRewardAddresses" getRewardAddresses
  rewardAddr <- liftMaybe (error "can't get reward address")
    $ head mRewardAddress
  mChangeAddress <- performAndLog "getChangeAddress" getChangeAddress
  changeAddress <- liftMaybe (error "can't get change address") mChangeAddress
  _ <- performAndLog "signData changeAddress" $ signData changeAddress dataBytes
  void $ performAndLog "signData rewardAddress" $ signData rewardAddr dataBytes
  where
  msg = "hello world!"
  mDataBytes = rawBytesFromAscii msg

  performAndLog
    :: forall (a :: Type)
     . Show a
    => String
    -> Contract a
    -> Contract a
  performAndLog logMsg cont = do
    result <- cont
    logInfo' $ logMsg <> ": " <> show result
    pure result
