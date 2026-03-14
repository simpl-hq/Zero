{-# LANGUAGE QuasiQuotes #-}

module Zero.Chat.Store.SQLite.Migrations.M20221130_delete_item_deleted where

import Database.SQLite.Simple (Query)
import Database.SQLite.Simple.QQ (sql)

m20221130_delete_item_deleted :: Query
m20221130_delete_item_deleted =
  [sql|
DELETE FROM chat_items WHERE item_deleted = 1;
|]
