module Ctl.Internal.Contract.WaitUntilSlot
  ( waitUntilSlot
  , waitNSlots
  , currentSlot
  , currentTime
  ) where

import Prelude

import Ctl.Internal.Contract.Monad(Contract)
import Control.Monad.Reader.Class (asks)

import Contract.Log (logTrace')
import Ctl.Internal.Helpers (liftEither, liftM)
-- import Ctl.Internal.QueryM.EraSummaries (getEraSummaries)
import Ctl.Internal.QueryM.Ogmios (EraSummaries, SystemStart, RelativeTime, SlotLength)
-- import Ctl.Internal.QueryM.SystemStart (getSystemStart)
import Ctl.Internal.Serialization.Address (Slot(Slot))
import Ctl.Internal.Types.BigNum as BigNum
import Ctl.Internal.Types.Chain as Chain
import Ctl.Internal.Types.Interval
  ( POSIXTime(POSIXTime)
  , findSlotEraSummary
  , getSlotLength
  , slotToPosixTime
  )
import Ctl.Internal.Types.Natural (Natural)
import Ctl.Internal.Types.Natural as Natural
import Data.Bifunctor (lmap)
import Data.BigInt as BigInt
import Data.DateTime.Instant (unInstant)
import Data.Either (hush)
import Data.Int as Int
import Data.Newtype (unwrap, wrap)
import Data.Time.Duration (Milliseconds(Milliseconds), Seconds)
import Effect.Aff (Milliseconds, delay)
import Effect.Aff.Class (liftAff)
import Effect.Class (liftEffect)
import Effect.Exception (error)
import Effect.Now (now)
import Ctl.Internal.Contract (getChainTip)

-- | The returned slot will be no less than the slot provided as argument.
waitUntilSlot :: Slot -> Contract Chain.Tip
waitUntilSlot futureSlot =
  getChainTip >>= case _ of
    tip@(Chain.Tip (Chain.ChainTip { slot }))
      | slot >= futureSlot -> pure tip
      | otherwise -> do
          { systemStart, slotLength, slotReference } <- asks _.ledgerConstants
          let slotLengthMs = unwrap slotLength * 1000.0
          -- slotLengthMs <- map getSlotLength $ liftEither
          --   $ lmap (const $ error "Unable to get current Era summary")
          --   $ findSlotEraSummary eraSummaries slot
          -- `timePadding` in slots
          -- If there are less than `slotPadding` slots remaining, start querying for chainTip
          -- repeatedly, because it's possible that at any given moment Ogmios suddenly
          -- synchronizes with node that is also synchronized with global time.
          getLag slotReference slotLength systemStart slot >>= logLag slotLengthMs
          futureTime <-
            liftEffect (slotToPosixTime slotReference slotLength systemStart futureSlot)
              >>= hush >>> liftM (error "Unable to convert Slot to POSIXTime")
          delayTime <- estimateDelayUntil futureTime
          liftAff $ delay delayTime
          let
            -- Repeatedly check current slot until it's greater than or equal to futureAbsSlot
            fetchRepeatedly :: Contract Chain.Tip
            fetchRepeatedly =
              getChainTip >>= case _ of
                currentTip@(Chain.Tip (Chain.ChainTip { slot: currentSlot_ }))
                  | currentSlot_ >= futureSlot -> pure currentTip
                  | otherwise -> do
                      liftAff $ delay $ Milliseconds slotLengthMs
                      getLag slotReference slotLength systemStart currentSlot_ >>= logLag
                        slotLengthMs
                      fetchRepeatedly
                Chain.TipAtGenesis -> do
                  liftAff $ delay retryDelay
                  fetchRepeatedly
          fetchRepeatedly
    Chain.TipAtGenesis -> do
      -- We just retry until the tip moves from genesis
      liftAff $ delay retryDelay
      waitUntilSlot futureSlot
  where
  retryDelay :: Milliseconds
  retryDelay = wrap 1000.0

  logLag :: Number -> Milliseconds -> Contract Unit
  logLag slotLengthMs (Milliseconds lag) = do
    logTrace' $
      "waitUntilSlot: current lag: " <> show lag <> " ms, "
        <> show (lag / slotLengthMs)
        <> " slots."

-- | Calculate difference between estimated POSIX time of given slot
-- | and current time.
getLag :: { slot :: Slot, time :: RelativeTime } -> SlotLength -> SystemStart -> Slot -> Contract Milliseconds
getLag slotReference slotLength sysStart nowSlot = do
  nowPosixTime <- liftEffect (slotToPosixTime slotReference slotLength sysStart nowSlot) >>=
    hush >>> liftM (error "Unable to convert Slot to POSIXTime")
  nowMs <- unwrap <<< unInstant <$> liftEffect now
  logTrace' $
    "getLag: current slot: " <> BigNum.toString (unwrap nowSlot)
      <> ", slot time: "
      <> BigInt.toString (unwrap nowPosixTime)
      <> ", system time: "
      <> show nowMs
  nowMsBigInt <- liftM (error "Unable to convert Milliseconds to BigInt") $
    BigInt.fromNumber nowMs
  pure $ wrap $ BigInt.toNumber $ nowMsBigInt - unwrap nowPosixTime

-- | Estimate how long we want to wait if we want to wait until `timePadding`
-- | milliseconds before a given `POSIXTime`.
estimateDelayUntil :: POSIXTime -> Contract Milliseconds
estimateDelayUntil futureTimePosix = do
  futureTimeSec <- posixTimeToSeconds futureTimePosix
  nowMs <- unwrap <<< unInstant <$> liftEffect now
  let
    result = wrap $ mul 1000.0 $ nonNegative $
      unwrap futureTimeSec - nowMs / 1000.0
  logTrace' $
    "estimateDelayUntil: target time: " <> show (unwrap futureTimeSec * 1000.0)
      <> ", system time: "
      <> show nowMs
      <> ", delay: "
      <> show (unwrap result)
      <> "ms"
  pure result
  where
  nonNegative :: Number -> Number
  nonNegative n
    | n < 0.0 = 0.0
    | otherwise = n

posixTimeToSeconds :: POSIXTime -> Contract Seconds
posixTimeToSeconds (POSIXTime futureTimeBigInt) = do
  liftM (error "Unable to convert POSIXTIme to Number")
    $ map (wrap <<< Int.toNumber)
    $ BigInt.toInt
    $ futureTimeBigInt / BigInt.fromInt 1000

-- | Wait at least `offset` number of slots.
waitNSlots :: Natural -> Contract Chain.Tip
waitNSlots offset = do
  offsetBigNum <- liftM (error "Unable to convert BigInt to BigNum")
    $ (BigNum.fromBigInt <<< Natural.toBigInt) offset
  if offsetBigNum == BigNum.fromInt 0 then getChainTip
  else do
    slot <- currentSlot
    newSlot <- liftM (error "Unable to advance slot")
      $ wrap <$> BigNum.add (unwrap slot) offsetBigNum
    waitUntilSlot newSlot

currentSlot :: Contract Slot
currentSlot = getChainTip <#> case _ of
  Chain.Tip (Chain.ChainTip { slot }) -> slot
  Chain.TipAtGenesis -> (Slot <<< BigNum.fromInt) 0

-- | Get the latest POSIXTime of the current slot.
-- The plutus implementation relies on `slotToEndPOSIXTime`
-- https://github.com/input-output-hk/plutus-apps/blob/fb8a39645e532841b6e38d42ecb957f1945833a5/plutus-contract/src/Plutus/Contract/Trace.hs
currentTime :: Contract POSIXTime
currentTime = currentSlot >>= slotToEndPOSIXTime

-- | Get the ending 'POSIXTime' of a 'Slot' related to
-- | our `Contract` configuration.
-- see https://github.com/input-output-hk/plutus-apps/blob/fb8a39645e532841b6e38d42ecb957f1945833a5/plutus-ledger/src/Ledger/TimeSlot.hs
slotToEndPOSIXTime :: Slot -> Contract POSIXTime
slotToEndPOSIXTime slot = do
  futureSlot <- liftM (error "Unable to advance slot")
    $ wrap <$> BigNum.add (unwrap slot) (BigNum.fromInt 1)
  { systemStart, slotLength, slotReference } <- asks _.ledgerConstants
  futureTime <- liftEffect $ slotToPosixTime slotReference slotLength systemStart futureSlot
    >>= hush >>> liftM (error "Unable to convert Slot to POSIXTime")
  -- We assume that a slot is 1000 milliseconds here.
  -- TODO Don't
  pure ((wrap <<< BigInt.fromInt $ -1) + futureTime)
