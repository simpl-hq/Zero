{-# LANGUAGE CPP #-}

module Zero.Messaging.Agent.Store.Interface
#if defined(dbPostgres)
  ( module Zero.Messaging.Agent.Store.Postgres,
  )
  where
import Zero.Messaging.Agent.Store.Postgres
#else
  ( module Zero.Messaging.Agent.Store.SQLite,
  )
  where
import Zero.Messaging.Agent.Store.SQLite
#endif
