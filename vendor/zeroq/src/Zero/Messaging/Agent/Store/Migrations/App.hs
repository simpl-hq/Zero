{-# LANGUAGE CPP #-}

module Zero.Messaging.Agent.Store.Migrations.App
#if defined(dbPostgres)
  ( module Zero.Messaging.Agent.Store.Postgres.Migrations.App,
  )
  where
import Zero.Messaging.Agent.Store.Postgres.Migrations.App
#else
  ( module Zero.Messaging.Agent.Store.SQLite.Migrations.App,
  )
  where
import Zero.Messaging.Agent.Store.SQLite.Migrations.App
#endif
