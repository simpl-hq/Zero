{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Zero.Chat.Store.Postgres.Migrations.M20260529_delivery_job_senders where

import Data.Text (Text)
import Text.RawString.QQ (r)

m20260529_delivery_job_senders :: Text
m20260529_delivery_job_senders =
  [r|
DROP INDEX idx_delivery_jobs_single_sender_group_member_id;

ALTER TABLE delivery_jobs ADD COLUMN sender_group_member_ids TEXT;

UPDATE delivery_jobs
SET sender_group_member_ids = single_sender_group_member_id::text
WHERE single_sender_group_member_id IS NOT NULL;

ALTER TABLE delivery_jobs DROP COLUMN single_sender_group_member_id;
|]

down_m20260529_delivery_job_senders :: Text
down_m20260529_delivery_job_senders =
  [r|
DELETE FROM delivery_jobs
WHERE sender_group_member_ids IS NOT NULL
  AND length(sender_group_member_ids) > 0
  AND position(',' in sender_group_member_ids) = 0
  AND NOT EXISTS (
    SELECT 1 FROM group_members
    WHERE group_member_id = sender_group_member_ids::bigint
  );

ALTER TABLE delivery_jobs ADD COLUMN single_sender_group_member_id BIGINT REFERENCES group_members(group_member_id) ON DELETE CASCADE;

UPDATE delivery_jobs
SET single_sender_group_member_id =
  CASE
    WHEN sender_group_member_ids IS NULL THEN NULL
    WHEN position(',' in sender_group_member_ids) > 0 THEN NULL
    WHEN length(sender_group_member_ids) = 0 THEN NULL
    ELSE sender_group_member_ids::bigint
  END;

ALTER TABLE delivery_jobs DROP COLUMN sender_group_member_ids;

CREATE INDEX idx_delivery_jobs_single_sender_group_member_id ON delivery_jobs(single_sender_group_member_id);
|]
