module Test.Ctl.OgmiosDatumCache
  ( suite
  ) where

import Prelude

import Aeson (caseAesonArray, decodeAeson, encodeAeson)
import Contract.Address (ByteArray)
import Control.Monad.Error.Class (class MonadThrow)
import Ctl.Internal.Hashing (datumHash)
import Ctl.Internal.QueryM.DatumCacheWsp (GetDatumsByHashesR)
import Ctl.Internal.Test.TestPlanM (TestPlanM)
import Ctl.Internal.Types.Datum (Datum(Datum))
import Ctl.Internal.Types.PlutusData (PlutusData)
import Data.Either (Either(Left, Right))
import Data.Map as Map
import Data.Newtype (unwrap)
import Data.Traversable (for_)
import Data.Tuple.Nested ((/\))
import Effect.Aff (Aff)
import Effect.Class (class MonadEffect)
import Effect.Exception (Error)
import Mote (group, skip, test)
import Test.Ctl.Utils (errEither, readAeson)
import Test.Spec.Assertions (shouldEqual)

suite :: TestPlanM (Aff Unit) Unit
suite = group "Ogmios Datum Cache tests" $ do
  skip $ test
    "Plutus data samples should satisfy the Aeson roundtrip test (FIXME: \
    \https://github.com/mlabs-haskell/purescript-aeson/issues/7)"
    plutusDataToFromAesonTest
  test "Plutus data samples should have a compatible hash" plutusDataHashingTest
  test "GetDatumsByHashesR fixture parses and hashes properly"
    getDatumsByHashesHashingTest

readGetDatumsByHashesSample
  :: forall (m :: Type -> Type)
   . MonadEffect m
  => m GetDatumsByHashesR
readGetDatumsByHashesSample = do
  errEither <<< decodeAeson =<< readAeson
    "./fixtures/test/ogmios-datum-cache/get-datums-by-hashes-samples.json"

getDatumsByHashesHashingTest
  :: forall (m :: Type -> Type)
   . MonadEffect m
  => MonadThrow Error m
  => m Unit
getDatumsByHashesHashingTest = do
  datums <- Map.toUnfoldable <<< unwrap <$> readGetDatumsByHashesSample
  for_ (datums :: Array _) \(hash /\ datum) -> do
    (datumHash <$> datum) `shouldEqual` Right (hash)

readPlutusDataSamples
  :: forall (m :: Type -> Type)
   . MonadEffect m
  => m (Array { hash :: ByteArray, plutusData :: PlutusData })
readPlutusDataSamples = do
  errEither <<< decodeAeson =<< readAeson
    "./fixtures/test/ogmios-datum-cache/plutus-data-samples.json"

plutusDataToFromAesonTest
  :: forall (m :: Type -> Type). MonadEffect m => MonadThrow Error m => m Unit
plutusDataToFromAesonTest = do
  pdsAes <- readAeson
    "./fixtures/test/ogmios-datum-cache/plutus-data-samples.json"
  aess <- errEither <<< caseAesonArray (Left "Expected a Json array") Right $
    pdsAes
  for_ aess \aes -> do
    (sample :: { hash :: ByteArray, plutusData :: PlutusData }) <- errEither $
      decodeAeson aes
    let aes' = encodeAeson sample
    aes `shouldEqual` aes'

plutusDataHashingTest
  :: forall (m :: Type -> Type). MonadEffect m => MonadThrow Error m => m Unit
plutusDataHashingTest = do
  plutusDataSamples <- readPlutusDataSamples
  let elems = plutusDataSamples
  for_ elems \{ hash, plutusData } -> do
    let hash' = datumHash $ Datum plutusData
    hash `shouldEqual` unwrap hash'
