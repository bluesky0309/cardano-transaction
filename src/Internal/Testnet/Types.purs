module Ctl.Internal.Testnet.Types
  ( CardanoTestnetStartupParams
  , Era(..)
  , LoggingFormat(..)
  , TestnetPaths
  , Event(..)
  , StartupFailure(..)
  , KupmiosConfig
  , NodeLocation
  , Node
  , GenesisUtxoKeyLocation
  , OptionalStartupParams
  , TestnetRuntime
  , TestnetClusterConfig
  , LogParams
  , defaultOptionalStartupParams
  , defaultStartupParams
  ) where

import Contract.Prelude

import Contract.Config as Config
import Data.Time.Duration (Milliseconds, Seconds)
import Data.UInt (UInt)
import Node.Path (FilePath)
import Record as Record

data Era
  = Byron
  | Shelley
  | Allegra
  | Mary
  | Alonzo
  | Babbage

data StartupFailure
  = SpawnFailed
  | InitializationFailed

derive instance Eq StartupFailure
derive instance Generic StartupFailure _
instance Show StartupFailure where
  show = genericShow

data Event
  = Ready872 -- when cardano-testnet 8.7.2 is ready to go
  | Finished
  | Failed
  | StartupFailed StartupFailure

derive instance Eq Event
derive instance Generic Event _
instance Show Event where
  show = genericShow

instance Show Era where
  show = case _ of
    Byron -> "byron-era"
    Shelley -> "shelley-era"
    Allegra -> "allegra-era"
    Mary -> "mary-era"
    Alonzo -> "alonzo-era"
    Babbage -> "babbage-era"

data LoggingFormat = LogAsJson | LogAsText

instance Show LoggingFormat where
  show = case _ of
    LogAsJson -> "json"
    LogAsText -> "text"

type OptionalStartupParams r =
  ( numPoolNodes :: Maybe Int
  , era :: Maybe Era
  , epochLength :: Maybe Milliseconds
  , slotLength :: Maybe Seconds
  , activeSlotsCoeff :: Maybe Number
  , enableP2p :: Maybe Boolean
  , nodeLoggingFormat :: Maybe LoggingFormat
  | r
  )

-- | Command line params for the cardano-testnet executable
type CardanoTestnetStartupParams r =
  ( testnetMagic :: Int
  | OptionalStartupParams r
  )

defaultStartupParams
  :: { testnetMagic :: Int } -> Record (CardanoTestnetStartupParams ())
defaultStartupParams necessaryParams =
  defaultOptionalStartupParams `Record.union` necessaryParams

defaultOptionalStartupParams :: Record (OptionalStartupParams ())
defaultOptionalStartupParams =
  { numPoolNodes: Nothing
  , era: Just Babbage
  , epochLength: Nothing
  , slotLength: Nothing
  , activeSlotsCoeff: Nothing
  , enableP2p: Nothing
  , nodeLoggingFormat: Nothing
  }

type TestnetPaths =
  { testnetDirectory :: FilePath
  , genesisKeys :: Array { | GenesisUtxoKeyLocation () }
  , nodeConfigPath :: FilePath
  , nodeSocketPath :: FilePath
  , nodeDirs :: Array { | NodeLocation () }
  }

type Node r =
  ( socket :: FilePath
  , port :: UInt
  | NodeLocation r
  )

type NodeLocation r =
  ( idx :: Int
  , name :: String
  , workdir :: FilePath
  | r
  )

type GenesisUtxoKeyLocation r =
  ( path :: FilePath
  , idx :: Int
  | r
  )

type TestnetClusterConfig r =
  ( hooks :: Config.Hooks
  | KupmiosConfig (LogParams r)
  )

type LogParams r =
  ( logLevel :: LogLevel
  , customLogger :: Maybe (LogLevel -> Config.Message -> Aff Unit)
  , suppressLogs :: Boolean
  | r
  )

type KupmiosConfig r =
  ( kupoConfig :: Config.ServerConfig
  , ogmiosConfig :: Config.ServerConfig
  | r
  )

type TestnetRuntime r =
  ( nodes :: Array { | Node () }
  | r
  )
