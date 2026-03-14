{-# LANGUAGE CPP #-}

module Zero.Chat.Options.DB

#if defined(dbPostgres)
  ( module Zero.Chat.Options.Postgres,
    FromField (..),
    ToField (..),
  )
  where
import Zero.Chat.Options.Postgres
import Database.PostgreSQL.Simple.FromField (FromField (..))
import Database.PostgreSQL.Simple.ToField (ToField (..))

#else
  ( module Zero.Chat.Options.SQLite,
    FromField (..),
    ToField (..),
  )
  where
import Zero.Chat.Options.SQLite
import Database.SQLite.Simple.FromField (FromField (..))
import Database.SQLite.Simple.ToField (ToField (..))

#endif
