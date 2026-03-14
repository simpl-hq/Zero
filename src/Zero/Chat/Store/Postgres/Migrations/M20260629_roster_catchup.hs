{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Zero.Chat.Store.Postgres.Migrations.M20260629_roster_catchup where

import Data.Text (Text)
import Text.RawString.QQ (r)

m20260629_roster_catchup :: Text
m20260629_roster_catchup =
  [r|
ALTER TABLE group_members ADD COLUMN roster_served_version BIGINT;
ALTER TABLE groups ADD COLUMN stored_roster_version BIGINT;
ALTER TABLE groups ADD COLUMN applied_complete_roster_version BIGINT;
UPDATE groups SET stored_roster_version = roster_version, applied_complete_roster_version = roster_version WHERE roster_version IS NOT NULL;
|]

down_m20260629_roster_catchup :: Text
down_m20260629_roster_catchup =
  [r|
ALTER TABLE group_members DROP COLUMN roster_served_version;
ALTER TABLE groups DROP COLUMN stored_roster_version;
ALTER TABLE groups DROP COLUMN applied_complete_roster_version;
|]
