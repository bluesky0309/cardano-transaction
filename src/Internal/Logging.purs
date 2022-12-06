module Ctl.Internal.Logging
  ( setupLogs
  , mkLogger
  , Logger
  ) where

import Prelude

import Ctl.Internal.Helpers (logString)
import Data.JSDate (now)
import Data.List (List(Cons, Nil))
import Data.List as List
import Data.Log.Level (LogLevel)
import Data.Log.Message (Message)
import Data.Map as Map
import Data.Maybe (Maybe(Just, Nothing))
import Data.Traversable (for_)
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Effect.Ref as Ref

type Logger = LogLevel -> String -> Effect Unit

mkLogger
  :: LogLevel
  -> Maybe (LogLevel -> Message -> Aff Unit)
  -> Logger
mkLogger logLevel mbCustomLogger level message =
  case mbCustomLogger of
    Nothing -> logString logLevel level message
    Just logger -> liftEffect do
      timestamp <- now
      launchAff_ $ logger logLevel
        { level, message, tags: Map.empty, timestamp }

-- | Setup internal machinery for log suppression.
setupLogs
  :: LogLevel
  -> Maybe (LogLevel -> Message -> Aff Unit)
  -> Effect
       { addLogEntry :: LogLevel -> Message -> Effect Unit
       , logger :: LogLevel -> String -> Effect Unit
       , printLogs :: Effect Unit
       , clearLogs :: Effect Unit
       , suppressedLogger :: LogLevel -> String -> Effect Unit
       }
setupLogs logLevel customLogger = do
  -- Keep track of logs to show them only on error if `suppressLogs: true`
  logsRef <- liftEffect $ Ref.new Nil
  let
    -- Logger that stores a message in the queue
    addLogEntry :: LogLevel -> Message -> Effect Unit
    addLogEntry lgl msg = when (msg.level >= lgl) do
      Ref.modify_ (Cons msg) logsRef

    -- Logger that is used to actually print messages
    logger :: Logger
    logger = mkLogger logLevel customLogger

    -- Logger that adds message to the queue, respecting LogLevel
    suppressedLogger :: Logger
    suppressedLogger = mkLogger logLevel
      (Just $ map liftEffect <<< addLogEntry)

    -- Clear the suppressed logs without printing
    clearLogs :: Effect Unit
    clearLogs = do
      Ref.write Nil logsRef

    -- Print suppressed logs
    printLogs :: Effect Unit
    printLogs = do
      logs <- List.reverse <$> Ref.read logsRef
      clearLogs
      for_ logs \logEntry -> do
        logger logEntry.level logEntry.message

  pure { addLogEntry, logger, printLogs, clearLogs, suppressedLogger }
