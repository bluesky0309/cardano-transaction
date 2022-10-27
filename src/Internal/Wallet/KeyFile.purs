-- | **NodeJS-only module**
module Ctl.Internal.Wallet.KeyFile
  ( keyFromFile
  , privatePaymentKeyFromFile
  , privatePaymentKeyFromString
  , privatePaymentKeyToFile
  , privateStakeKeyFromFile
  , privateStakeKeyFromString
  , privateStakeKeyToFile
  , formatStakeKey
  , formatPaymentKey
  ) where

import Prelude

import Aeson (encodeAeson)
import Control.Monad.Error.Class (liftMaybe)
import Ctl.Internal.Cardano.TextEnvelope
  ( TextEnvelopeType
      ( PaymentSigningKeyShelleyed25519
      , StakeSigningKeyShelleyed25519
      )
  , textEnvelopeBytes
  )
import Ctl.Internal.Deserialization.Keys (privateKeyFromBytes)
import Ctl.Internal.Helpers (liftM)
import Ctl.Internal.Serialization.Keys (bytesFromPrivateKey)
import Ctl.Internal.Serialization.Types (PrivateKey)
import Ctl.Internal.Types.ByteArray (ByteArray)
import Ctl.Internal.Types.RawBytes (rawBytesToHex)
import Ctl.Internal.Wallet.Key
  ( PrivatePaymentKey(PrivatePaymentKey)
  , PrivateStakeKey(PrivateStakeKey)
  )
import Data.Bifunctor (lmap)
import Data.Either (hush)
import Data.Maybe (Maybe)
import Data.Newtype (wrap)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Exception (error)
import Node.Encoding as Encoding
import Node.FS.Sync (readTextFile, writeTextFile)
import Node.Path (FilePath)

keyFromFile :: FilePath -> TextEnvelopeType -> Aff ByteArray
keyFromFile filePath ty = do
  fileContents <- liftEffect $ readTextFile Encoding.UTF8 filePath
  let errorMsg = error "Error while decoding key"
  liftMaybe errorMsg $ textEnvelopeBytes fileContents ty

privatePaymentKeyFromString :: String -> Maybe PrivatePaymentKey
privatePaymentKeyFromString jsonString = do
  bytes <- textEnvelopeBytes jsonString PaymentSigningKeyShelleyed25519
  PrivatePaymentKey <$> privateKeyFromBytes (wrap bytes)

privateStakeKeyFromString :: String -> Maybe PrivateStakeKey
privateStakeKeyFromString jsonString = do
  bytes <- textEnvelopeBytes jsonString StakeSigningKeyShelleyed25519
  PrivateStakeKey <$> privateKeyFromBytes (wrap bytes)

privatePaymentKeyFromFile :: FilePath -> Aff PrivatePaymentKey
privatePaymentKeyFromFile filePath = do
  bytes <- keyFromFile filePath PaymentSigningKeyShelleyed25519
  liftM (error "Unable to decode private payment key") $
    PrivatePaymentKey <$> privateKeyFromBytes (wrap bytes)

privateStakeKeyFromFile :: FilePath -> Aff PrivateStakeKey
privateStakeKeyFromFile filePath = do
  bytes <- keyFromFile filePath StakeSigningKeyShelleyed25519
  liftM (error "Unable to decode private stake key") $
    PrivateStakeKey <$> privateKeyFromBytes (wrap bytes)

privatePaymentKeyToFile :: FilePath -> PrivatePaymentKey -> Aff Unit
privatePaymentKeyToFile filePath key =
  liftEffect <<< (writeTextFile Encoding.UTF8 filePath) $ formatPaymentKey key

privateStakeKeyToFile :: FilePath -> PrivateStakeKey -> Aff Unit
privateStakeKeyToFile filePath key =
  liftEffect <<< (writeTextFile Encoding.UTF8 filePath) $ formatStakeKey key

formatPaymentKey :: PrivatePaymentKey -> String
formatPaymentKey (PrivatePaymentKey key) = encodeAeson >>> show
  $
    { "type": "PaymentSigningKeyShelley_ed25519"
    , description: "Payment Signing Key"
    , cborHex: keyToCbor key
    }

formatStakeKey :: PrivateStakeKey -> String
formatStakeKey (PrivateStakeKey key) = encodeAeson >>> show
  $
    { "type": "StakeSigningKeyShelley_ed25519"
    , description: "Stake Signing Key"
    , cborHex: keyToCbor key
    }

keyToCbor :: PrivateKey -> String
keyToCbor = (magicPrefix <> _) <<< rawBytesToHex <<< bytesFromPrivateKey

magicPrefix :: String
magicPrefix = "5820"
