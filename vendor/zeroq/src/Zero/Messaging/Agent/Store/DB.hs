{-# LANGUAGE CPP #-}

module Zero.Messaging.Agent.Store.DB
#if defined(dbPostgres)
  ( module Zero.Messaging.Agent.Store.Postgres.DB,
    FromField (..),
    ToField (..),
  )
  where
import Zero.Messaging.Agent.Store.Postgres.DB
#else
  ( module Zero.Messaging.Agent.Store.SQLite.DB,
    FromField (..),
    ToField (..),
  )
  where
import Zero.Messaging.Agent.Store.SQLite.DB
#endif
