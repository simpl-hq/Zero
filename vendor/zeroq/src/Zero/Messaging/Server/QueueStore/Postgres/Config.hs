module Zero.Messaging.Server.QueueStore.Postgres.Config
  ( PostgresStoreCfg (..),
  ) where

import Data.Int (Int64)
import Zero.Messaging.Agent.Store.Postgres.Options (DBOpts)
import Zero.Messaging.Agent.Store.Shared (MigrationConfirmation)

data PostgresStoreCfg = PostgresStoreCfg
  { dbOpts :: DBOpts,
    dbStoreLogPath :: Maybe FilePath,
    confirmMigrations :: MigrationConfirmation,
    deletedTTL :: Int64
  }
