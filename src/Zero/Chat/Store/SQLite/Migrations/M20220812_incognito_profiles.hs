{-# LANGUAGE QuasiQuotes #-}

module Zero.Chat.Store.SQLite.Migrations.M20220812_incognito_profiles where

import Database.SQLite.Simple (Query)
import Database.SQLite.Simple.QQ (sql)

m20220812_incognito_profiles :: Query
m20220812_incognito_profiles =
  [sql|
ALTER TABLE connections ADD COLUMN custom_user_profile_id INTEGER REFERENCES contact_profiles ON DELETE SET NULL;

ALTER TABLE group_members ADD COLUMN member_profile_id INTEGER REFERENCES contact_profiles ON DELETE SET NULL;

ALTER TABLE contact_profiles ADD COLUMN incognito INTEGER;
|]
