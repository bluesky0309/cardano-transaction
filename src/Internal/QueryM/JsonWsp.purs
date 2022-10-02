-- | Provides basics types and operations for working with JSON RPC protocol
-- | used by Ogmios and ogmios-datum-cache
module Ctl.Internal.QueryM.JsonWsp
  ( JsonWspRequest
  , JsonWspResponse
  , JsonWspCall
  , mkCallType
  , buildRequest
  , parseJsonWspResponse
  , parseJsonWspResponseId
  ) where

import Prelude

import Aeson
  ( class DecodeAeson
  , class EncodeAeson
  , Aeson
  , JsonDecodeError(TypeMismatch)
  , caseAesonObject
  , caseAesonString
  , decodeAeson
  , encodeAeson
  , getField
  , getFieldOptional
  )
import Ctl.Internal.QueryM.UniqueId (ListenerId, uniqueId)
import Data.Either (Either(Left))
import Data.Maybe (Maybe)
import Data.Traversable (traverse)
import Effect (Effect)
import Foreign.Object (Object)
import Record as Record

-- | Structure of all json wsp websocket requests
-- described in: https://ogmios.dev/getting-started/basics/
type JsonWspRequest (a :: Type) =
  { type :: String
  , version :: String
  , servicename :: String
  , methodname :: String
  , args :: a
  , mirror :: ListenerId
  }

-- | Convenience helper function for creating `JsonWspRequest a` objects
mkJsonWspRequest
  :: forall (a :: Type)
   . { type :: String
     , version :: String
     , servicename :: String
     }
  -> { methodname :: String
     , args :: a
     }
  -> Effect (JsonWspRequest a)
mkJsonWspRequest service method = do
  id <- uniqueId $ method.methodname <> "-"
  pure
    $ Record.merge { mirror: id }
    $
      Record.merge service method

-- | Structure of all json wsp websocket responses
-- described in: https://ogmios.dev/getting-started/basics/
type JsonWspResponse (a :: Type) =
  { type :: String
  , version :: String
  , servicename :: String
  -- methodname is not always present if `fault` is not empty
  , methodname :: Maybe String
  , result :: Maybe a
  , fault :: Maybe Aeson
  , reflection :: ListenerId
  }

-- | A wrapper for tying arguments and response types to request building.
newtype JsonWspCall :: Type -> Type -> Type
newtype JsonWspCall (i :: Type) (o :: Type) = JsonWspCall
  (i -> Effect { body :: Aeson, id :: String })

-- | Creates a "jsonwsp call" which ties together request input and response output types
-- | along with a way to create a request object.
mkCallType
  :: forall (a :: Type) (i :: Type) (o :: Type)
   . EncodeAeson (JsonWspRequest a)
  => { type :: String
     , version :: String
     , servicename :: String
     }
  -> { methodname :: String, args :: i -> a }
  -> JsonWspCall i o
mkCallType service { methodname, args } = JsonWspCall $ \i -> do
  req <- mkJsonWspRequest service { methodname, args: args i }
  pure { body: encodeAeson req, id: req.mirror }

-- | Create a JsonWsp request body and id
buildRequest
  :: forall (i :: Type) (o :: Type)
   . JsonWspCall i o
  -> i
  -> Effect { body :: Aeson, id :: String }
buildRequest (JsonWspCall c) = c

-- | Polymorphic response parser
parseJsonWspResponse
  :: forall (a :: Type)
   . DecodeAeson a
  => Aeson
  -> Either JsonDecodeError (JsonWspResponse a)
parseJsonWspResponse = aesonObject $ \o -> do
  typeField <- getField o "type"
  version <- getField o "version"
  servicename <- getField o "servicename"
  methodname <- getFieldOptional o "methodname"
  result <- traverse decodeAeson =<< getFieldOptional o "result"
  fault <- traverse decodeAeson =<< getFieldOptional o "fault"
  reflection <- parseMirror =<< getField o "reflection"
  pure
    { "type": typeField
    , version
    , servicename
    , methodname
    , result
    , fault
    , reflection
    }

-- | Parse just ID from the response
parseJsonWspResponseId
  :: Aeson
  -> Either JsonDecodeError ListenerId
parseJsonWspResponseId = aesonObject $ \o -> do
  parseMirror =<< getField o "reflection"

-- | Helper for assuming we get an object
aesonObject
  :: forall (a :: Type)
   . (Object Aeson -> Either JsonDecodeError a)
  -> Aeson
  -> Either JsonDecodeError a
aesonObject = caseAesonObject (Left (TypeMismatch "expected object"))

-- parsing json

-- | A parser for the `Mirror` type.
parseMirror :: Aeson -> Either JsonDecodeError ListenerId
parseMirror = caseAesonString (Left (TypeMismatch "expected string")) pure
