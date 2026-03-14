{-# LANGUAGE CPP #-}

module Zero.Chat.Store
  ( DBStore,
    StoreError (..),
    ChatLockEntity (..),
    UserMsgReceiptSettings (..),
    UserContactLink (..),
    GroupLinkInfo (..),
    AddressSettings (..),
    AutoAccept (..),
    createChatStore,
    migrations,
    withTransaction,
  )
where

import Zero.Chat.Store.Profiles
import Zero.Chat.Store.Shared
import Zero.Messaging.Agent.Store.Common (DBStore (..), withTransaction)
import Zero.Messaging.Agent.Store.Interface (DBOpts, createDBStore)
import Zero.Messaging.Agent.Store.Shared (MigrationConfig, MigrationError)
#if defined(dbPostgres)
import Zero.Chat.Store.Postgres.Migrations
#else
import Zero.Chat.Store.SQLite.Migrations
#endif

createChatStore :: DBOpts -> MigrationConfig -> IO (Either MigrationError DBStore)
createChatStore dbCreateOpts = createDBStore dbCreateOpts migrations
