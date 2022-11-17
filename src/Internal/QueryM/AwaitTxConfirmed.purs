module Ctl.Internal.QueryM.AwaitTxConfirmed
  ( awaitTxConfirmed
  , awaitTxConfirmedWithTimeout
  , awaitTxConfirmedWithTimeoutSlots
  ) where

import Prelude

import Control.Parallel (parOneOf)
import Ctl.Internal.QueryM (QueryM, getChainTip)
import Ctl.Internal.QueryM.Kupo (isTxConfirmed) as Kupo
import Ctl.Internal.QueryM.Ogmios (TxHash)
import Ctl.Internal.QueryM.WaitUntilSlot (waitUntilSlot)
import Ctl.Internal.Serialization.Address (Slot)
import Ctl.Internal.Types.BigNum as BigNum
import Ctl.Internal.Types.Chain as Chain
import Data.Either (either)
import Data.Maybe (maybe)
import Data.Newtype (unwrap, wrap)
import Data.Number (infinity)
import Data.Time.Duration (Milliseconds, Seconds(Seconds), fromDuration)
import Effect.Aff (delay)
import Effect.Aff.Class (liftAff)
import Effect.Class (liftEffect)
import Effect.Exception (throw)

awaitTxConfirmed :: TxHash -> QueryM Unit
awaitTxConfirmed = awaitTxConfirmedWithTimeout (Seconds infinity)

awaitTxConfirmedWithTimeout :: Seconds -> TxHash -> QueryM Unit
awaitTxConfirmedWithTimeout timeoutSeconds txHash =
  -- If timeout is infinity, do not use a timeout at all
  if unwrap timeoutSeconds == infinity then void findTx
  else do
    txFound <- parOneOf [ findTx, waitAndFail ]
    if txFound then pure unit
    else liftEffect $ throw $
      "awaitTxConfirmedWithTimeout: timeout exceeded, Transaction not \
      \confirmed"
  where
  -- Try to find the TX indefinitely, with a waiting period between each
  -- request
  findTx :: QueryM Boolean
  findTx =
    isTxConfirmed txHash >>= \found ->
      if found then pure true else liftAff (delay delayTime) *> findTx

  -- Wait until the timeout elapses and return false
  waitAndFail :: QueryM Boolean
  waitAndFail = do
    liftAff $ delay $ timeout
    pure false

  timeout :: Milliseconds
  timeout = fromDuration timeoutSeconds

  delayTime :: Milliseconds
  delayTime = wrap 1000.0

awaitTxConfirmedWithTimeoutSlots :: Int -> TxHash -> QueryM Unit
awaitTxConfirmedWithTimeoutSlots timeoutSlots txHash =
  getCurrentSlot >>= addSlots timeoutSlots >>= go
  where
  getCurrentSlot :: QueryM Slot
  getCurrentSlot = getChainTip >>= case _ of
    Chain.TipAtGenesis -> do
      liftAff $ delay $ wrap 1000.0
      getCurrentSlot
    Chain.Tip (Chain.ChainTip { slot }) -> pure slot

  addSlots :: Int -> Slot -> QueryM Slot
  addSlots n slot =
    maybe (liftEffect $ throw "Cannot determine next slot") (pure <<< wrap) $
      unwrap slot `BigNum.add` BigNum.fromInt n

  go :: Slot -> QueryM Unit
  go timeout =
    isTxConfirmed txHash >>= \found ->
      unless found do
        slot <- getCurrentSlot
        when (slot >= timeout) do
          liftEffect $ throw $
            "awaitTxConfirmedWithTimeoutSlots: \
            \ timeout exceeded, Transaction not confirmed"
        void $ addSlots 1 slot >>= waitUntilSlot
        go timeout

isTxConfirmed :: TxHash -> QueryM Boolean
isTxConfirmed txHash =
  Kupo.isTxConfirmed (wrap txHash)
    >>= either (liftEffect <<< throw <<< show) pure
