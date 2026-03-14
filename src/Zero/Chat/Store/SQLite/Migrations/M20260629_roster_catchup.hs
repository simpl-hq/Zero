{-# LANGUAGE QuasiQuotes #-}

module Zero.Chat.Store.SQLite.Migrations.M20260629_roster_catchup where

import Database.SQLite.Simple (Query)
import Database.SQLite.Simple.QQ (sql)

m20260629_roster_catchup :: Query
m20260629_roster_catchup =
  [sql|
ALTER TABLE group_members ADD COLUMN roster_served_version INTEGER;
ALTER TABLE groups ADD COLUMN stored_roster_version INTEGER;
ALTER TABLE groups ADD COLUMN applied_complete_roster_version INTEGER;
UPDATE groups SET stored_roster_version = roster_version, applied_complete_roster_version = roster_version WHERE roster_version IS NOT NULL;
|]

down_m20260629_roster_catchup :: Query
down_m20260629_roster_catchup =
  [sql|
ALTER TABLE group_members DROP COLUMN roster_served_version;
ALTER TABLE groups DROP COLUMN stored_roster_version;
ALTER TABLE groups DROP COLUMN applied_complete_roster_version;
|]
