{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Zero.Chat.Store.Postgres.Migrations.M20251230_strict_tables where

import Data.Text (Text)
import Text.RawString.QQ (r)
import Zero.Messaging.Agent.Store.Postgres.Migrations.M20251230_strict_tables (isValidText)

m20251230_strict_tables :: Text
m20251230_strict_tables =
  isValidText
    <> [r|
DELETE FROM calls
WHERE NOT zero_is_valid_text(call_state);

ALTER TABLE calls ALTER COLUMN call_state TYPE TEXT USING call_state::TEXT;

DROP FUNCTION zero_is_valid_text(BYTEA);
|]

down_m20251230_strict_tables :: Text
down_m20251230_strict_tables =
  [r|
ALTER TABLE calls ALTER COLUMN call_state TYPE BYTEA USING call_state::BYTEA;
|]
