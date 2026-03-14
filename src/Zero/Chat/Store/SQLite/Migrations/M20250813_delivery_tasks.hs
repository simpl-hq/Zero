{-# LANGUAGE QuasiQuotes #-}

module Zero.Chat.Store.SQLite.Migrations.M20250813_delivery_tasks where

import Database.SQLite.Simple (Query)
import Database.SQLite.Simple.QQ (sql)

m20250813_delivery_tasks :: Query
m20250813_delivery_tasks =
  [sql|
CREATE TABLE delivery_tasks (
  delivery_task_id INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id INTEGER NOT NULL REFERENCES groups ON DELETE CASCADE,
  worker_scope TEXT NOT NULL,
  job_scope_spec_tag TEXT,
  job_scope_include_pending INTEGER,
  job_scope_support_gm_id INTEGER REFERENCES group_members(group_member_id) ON DELETE CASCADE,
  sender_group_member_id INTEGER NOT NULL REFERENCES group_members(group_member_id) ON DELETE CASCADE,
  message_id INTEGER REFERENCES messages ON DELETE CASCADE,
  message_from_channel INTEGER NOT NULL DEFAULT 0,
  task_status TEXT NOT NULL,
  task_err_reason TEXT,
  failed INTEGER DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_delivery_tasks_group_id ON delivery_tasks(group_id);
CREATE INDEX idx_delivery_tasks_job_scope_support_gm_id ON delivery_tasks(job_scope_support_gm_id);
CREATE INDEX idx_delivery_tasks_sender_group_member_id ON delivery_tasks(sender_group_member_id);
CREATE INDEX idx_delivery_tasks_message_id ON delivery_tasks(message_id);

CREATE INDEX idx_delivery_tasks_next ON delivery_tasks(
  group_id,
  worker_scope,
  failed,
  task_status
);
CREATE INDEX idx_delivery_tasks_next_for_job_scope ON delivery_tasks(
  group_id,
  worker_scope,
  job_scope_spec_tag,
  job_scope_include_pending,
  job_scope_support_gm_id,
  failed,
  task_status
);
CREATE INDEX idx_delivery_tasks_next_for_job_scope_sender ON delivery_tasks(
  group_id,
  worker_scope,
  job_scope_spec_tag,
  job_scope_include_pending,
  job_scope_support_gm_id,
  sender_group_member_id,
  failed,
  task_status
);
CREATE INDEX idx_delivery_tasks_created_at ON delivery_tasks(created_at);

CREATE TABLE delivery_jobs (
  delivery_job_id INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id INTEGER NOT NULL REFERENCES groups ON DELETE CASCADE,
  worker_scope TEXT NOT NULL,
  job_scope_spec_tag TEXT,
  job_scope_include_pending INTEGER,
  job_scope_support_gm_id INTEGER REFERENCES group_members(group_member_id) ON DELETE CASCADE,
  single_sender_group_member_id INTEGER REFERENCES group_members(group_member_id) ON DELETE CASCADE,
  body BLOB,
  cursor_group_member_id INTEGER,
  job_status TEXT NOT NULL,
  job_err_reason TEXT,
  failed INTEGER DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_delivery_jobs_group_id ON delivery_jobs(group_id);
CREATE INDEX idx_delivery_jobs_job_scope_support_gm_id ON delivery_jobs(job_scope_support_gm_id);
CREATE INDEX idx_delivery_jobs_single_sender_group_member_id ON delivery_jobs(single_sender_group_member_id);

CREATE INDEX idx_delivery_jobs_next ON delivery_jobs(
  group_id,
  worker_scope,
  failed,
  job_status
);
CREATE INDEX idx_delivery_jobs_created_at ON delivery_jobs(created_at);

ALTER TABLE messages ADD COLUMN broker_ts TEXT;
|]

down_m20250813_delivery_tasks :: Query
down_m20250813_delivery_tasks =
  [sql|
ALTER TABLE messages DROP COLUMN broker_ts;

DROP INDEX idx_delivery_jobs_group_id;
DROP INDEX idx_delivery_jobs_job_scope_support_gm_id;
DROP INDEX idx_delivery_jobs_single_sender_group_member_id;

DROP INDEX idx_delivery_jobs_next;
DROP INDEX idx_delivery_jobs_created_at;

DROP TABLE delivery_jobs;

DROP INDEX idx_delivery_tasks_group_id;
DROP INDEX idx_delivery_tasks_job_scope_support_gm_id;
DROP INDEX idx_delivery_tasks_sender_group_member_id;
DROP INDEX idx_delivery_tasks_message_id;

DROP INDEX idx_delivery_tasks_next;
DROP INDEX idx_delivery_tasks_next_for_job_scope;
DROP INDEX idx_delivery_tasks_next_for_job_scope_sender;
DROP INDEX idx_delivery_tasks_created_at;

DROP TABLE delivery_tasks;
|]
