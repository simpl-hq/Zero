{-# LANGUAGE CPP #-}

module Zero.Messaging.Agent.Store.Common
#if defined(dbPostgres)
  ( module Zero.Messaging.Agent.Store.Postgres.Common,
  )
  where
import Zero.Messaging.Agent.Store.Postgres.Common
#else
  ( module Zero.Messaging.Agent.Store.SQLite.Common,
  )
  where
import Zero.Messaging.Agent.Store.SQLite.Common
#endif
