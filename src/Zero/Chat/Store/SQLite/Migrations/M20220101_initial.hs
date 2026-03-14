{-# LANGUAGE QuasiQuotes #-}

module Zero.Chat.Store.SQLite.Migrations.M20220101_initial where

import Database.SQLite.Simple (Query)
import Database.SQLite.Simple.QQ (sql)

m20220101_initial :: Query
m20220101_initial =
  [sql|
CREATE TABLE contact_profiles (
  contact_profile_id INTEGER PRIMARY KEY,
  display_name TEXT NOT NULL,
  full_name TEXT NOT NULL,
  properties TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX contact_profiles_index ON contact_profiles (display_name, full_name);

CREATE TABLE users (
  user_id INTEGER PRIMARY KEY,
  contact_id INTEGER NOT NULL UNIQUE REFERENCES contacts ON DELETE CASCADE
    DEFERRABLE INITIALLY DEFERRED,
  local_display_name TEXT NOT NULL UNIQUE,
  active_user INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (user_id, local_display_name)
    REFERENCES display_names (user_id, local_display_name)
    ON DELETE CASCADE
    ON UPDATE CASCADE
    DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE display_names (
  user_id INTEGER NOT NULL REFERENCES users ON DELETE CASCADE,
  local_display_name TEXT NOT NULL,
  ldn_base TEXT NOT NULL,
  ldn_suffix INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, local_display_name) ON CONFLICT FAIL,
  UNIQUE (user_id, ldn_base, ldn_suffix) ON CONFLICT FAIL
) WITHOUT ROWID;

CREATE TABLE contacts (
  contact_id INTEGER PRIMARY KEY,
  contact_profile_id INTEGER REFERENCES contact_profiles ON DELETE SET NULL,
  user_id INTEGER NOT NULL REFERENCES users ON DELETE CASCADE,
  local_display_name TEXT NOT NULL,
  is_user INTEGER NOT NULL DEFAULT 0,
  via_group INTEGER REFERENCES groups (group_id) ON DELETE SET NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id, local_display_name)
    REFERENCES display_names (user_id, local_display_name)
    ON DELETE CASCADE
    ON UPDATE CASCADE,
  UNIQUE (user_id, local_display_name),
  UNIQUE (user_id, contact_profile_id)
);

CREATE TABLE sent_probes (
  sent_probe_id INTEGER PRIMARY KEY,
  contact_id INTEGER NOT NULL UNIQUE REFERENCES contacts ON DELETE CASCADE,
  probe BLOB NOT NULL,
  user_id INTEGER NOT NULL REFERENCES users ON DELETE CASCADE,
  UNIQUE (user_id, probe)
);

CREATE TABLE sent_probe_hashes (
  sent_probe_hash_id INTEGER PRIMARY KEY,
  sent_probe_id INTEGER NOT NULL REFERENCES sent_probes ON DELETE CASCADE,
  contact_id INTEGER NOT NULL REFERENCES contacts ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users ON DELETE CASCADE,
  UNIQUE (sent_probe_id, contact_id)
);

CREATE TABLE received_probes (
  received_probe_id INTEGER PRIMARY KEY,
  contact_id INTEGER NOT NULL REFERENCES contacts ON DELETE CASCADE,
  probe BLOB,
  probe_hash BLOB NOT NULL,
  user_id INTEGER NOT NULL REFERENCES users ON DELETE CASCADE
);

CREATE TABLE known_servers(
  server_id INTEGER PRIMARY KEY,
  host TEXT NOT NULL,
  port TEXT NOT NULL,
  key_hash BLOB,
  user_id INTEGER NOT NULL REFERENCES users ON DELETE CASCADE,
  UNIQUE (user_id, host, port)
) WITHOUT ROWID;

CREATE TABLE group_profiles (
  group_profile_id INTEGER PRIMARY KEY,
  display_name TEXT NOT NULL,
  full_name TEXT NOT NULL,
  properties TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE groups (
  group_id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users ON DELETE CASCADE,
  local_display_name TEXT NOT NULL,
  group_profile_id INTEGER REFERENCES group_profiles ON DELETE SET NULL,
  inv_queue_info BLOB,
  FOREIGN KEY (user_id, local_display_name)
    REFERENCES display_names (user_id, local_display_name)
    ON DELETE CASCADE
    ON UPDATE CASCADE,
  UNIQUE (user_id, local_display_name),
  UNIQUE (user_id, group_profile_id)
);

CREATE INDEX idx_groups_inv_queue_info ON groups (inv_queue_info);

CREATE TABLE group_members (
  group_member_id INTEGER PRIMARY KEY,
  group_id INTEGER NOT NULL REFERENCES groups ON DELETE CASCADE,
  member_id BLOB NOT NULL,
  member_role TEXT NOT NULL,
  member_category TEXT NOT NULL,
  member_status TEXT NOT NULL,
  invited_by INTEGER REFERENCES contacts (contact_id) ON DELETE SET NULL,
  sent_inv_queue_info BLOB,
  group_queue_info BLOB,
  direct_queue_info BLOB,
  user_id INTEGER NOT NULL REFERENCES users ON DELETE CASCADE,
  local_display_name TEXT NOT NULL,
  contact_profile_id INTEGER NOT NULL REFERENCES contact_profiles ON DELETE CASCADE,
  contact_id INTEGER REFERENCES contacts ON DELETE CASCADE,
  FOREIGN KEY (user_id, local_display_name)
    REFERENCES display_names (user_id, local_display_name)
    ON DELETE CASCADE
    ON UPDATE CASCADE,
  UNIQUE (group_id, member_id)
);

CREATE TABLE group_member_intros (
  group_member_intro_id INTEGER PRIMARY KEY,
  re_group_member_id INTEGER NOT NULL REFERENCES group_members (group_member_id) ON DELETE CASCADE,
  to_group_member_id INTEGER NOT NULL REFERENCES group_members (group_member_id) ON DELETE CASCADE,
  group_queue_info BLOB,
  direct_queue_info BLOB,
  intro_status TEXT NOT NULL,
  UNIQUE (re_group_member_id, to_group_member_id)
);

CREATE TABLE files (
  file_id INTEGER PRIMARY KEY,
  contact_id INTEGER REFERENCES contacts ON DELETE CASCADE,
  group_id INTEGER REFERENCES groups ON DELETE CASCADE,
  file_name TEXT NOT NULL,
  file_path TEXT,
  file_size INTEGER NOT NULL,
  chunk_size INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  user_id INTEGER NOT NULL REFERENCES users ON DELETE CASCADE
);

CREATE TABLE snd_files (
  file_id INTEGER NOT NULL REFERENCES files ON DELETE CASCADE,
  connection_id INTEGER NOT NULL REFERENCES connections ON DELETE CASCADE,
  file_status TEXT NOT NULL,
  group_member_id INTEGER REFERENCES group_members ON DELETE CASCADE,
  PRIMARY KEY (file_id, connection_id)
) WITHOUT ROWID;

CREATE TABLE rcv_files (
  file_id INTEGER PRIMARY KEY REFERENCES files ON DELETE CASCADE,
  file_status TEXT NOT NULL,
  group_member_id INTEGER REFERENCES group_members ON DELETE CASCADE,
  file_queue_info BLOB
);

CREATE TABLE snd_file_chunks (
  file_id INTEGER NOT NULL,
  connection_id INTEGER NOT NULL,
  chunk_number INTEGER NOT NULL,
  chunk_agent_msg_id INTEGER,
  chunk_sent INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (file_id, connection_id) REFERENCES snd_files ON DELETE CASCADE,
  PRIMARY KEY (file_id, connection_id, chunk_number)
) WITHOUT ROWID;

CREATE TABLE rcv_file_chunks (
  file_id INTEGER NOT NULL REFERENCES rcv_files ON DELETE CASCADE,
  chunk_number INTEGER NOT NULL,
  chunk_agent_msg_id INTEGER NOT NULL,
  chunk_stored INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (file_id, chunk_number)
) WITHOUT ROWID;

CREATE TABLE connections (
  connection_id INTEGER PRIMARY KEY,
  agent_conn_id BLOB NOT NULL UNIQUE,
  conn_level INTEGER NOT NULL DEFAULT 0,
  via_contact INTEGER REFERENCES contacts (contact_id) ON DELETE SET NULL,
  conn_status TEXT NOT NULL,
  conn_type TEXT NOT NULL,
  user_contact_link_id INTEGER REFERENCES user_contact_links ON DELETE CASCADE,
  contact_id INTEGER REFERENCES contacts ON DELETE CASCADE,
  group_member_id INTEGER REFERENCES group_members ON DELETE CASCADE,
  snd_file_id INTEGER,
  rcv_file_id INTEGER REFERENCES rcv_files (file_id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  user_id INTEGER NOT NULL REFERENCES users ON DELETE CASCADE,
  FOREIGN KEY (snd_file_id, connection_id)
    REFERENCES snd_files (file_id, connection_id)
    ON DELETE CASCADE
    DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE user_contact_links (
  user_contact_link_id INTEGER PRIMARY KEY,
  conn_req_contact BLOB NOT NULL,
  local_display_name TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  user_id INTEGER NOT NULL REFERENCES users ON DELETE CASCADE,
  UNIQUE (user_id, local_display_name)
);

CREATE TABLE contact_requests (
  contact_request_id INTEGER PRIMARY KEY,
  user_contact_link_id INTEGER NOT NULL REFERENCES user_contact_links
    ON UPDATE CASCADE ON DELETE CASCADE,
  agent_invitation_id  BLOB NOT NULL,
  contact_profile_id INTEGER REFERENCES contact_profiles
    ON DELETE SET NULL
    DEFERRABLE INITIALLY DEFERRED,
  local_display_name TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  user_id INTEGER NOT NULL REFERENCES users ON DELETE CASCADE,
  FOREIGN KEY (user_id, local_display_name)
    REFERENCES display_names (user_id, local_display_name)
    ON UPDATE CASCADE
    ON DELETE CASCADE
    DEFERRABLE INITIALLY DEFERRED,
  UNIQUE (user_id, local_display_name),
  UNIQUE (user_id, contact_profile_id)
);

CREATE TABLE messages (
  message_id INTEGER PRIMARY KEY,
  msg_sent INTEGER NOT NULL,
  chat_msg_event TEXT NOT NULL,
  msg_body BLOB,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE msg_deliveries (
  msg_delivery_id INTEGER PRIMARY KEY,
  message_id INTEGER NOT NULL REFERENCES messages ON DELETE CASCADE,
  connection_id INTEGER NOT NULL REFERENCES connections ON DELETE CASCADE,
  agent_msg_id INTEGER,
  agent_msg_meta TEXT,
  chat_ts TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (connection_id, agent_msg_id)
);

CREATE TABLE msg_delivery_events (
  msg_delivery_event_id INTEGER PRIMARY KEY,
  msg_delivery_id INTEGER NOT NULL REFERENCES msg_deliveries ON DELETE CASCADE,
  delivery_status TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (msg_delivery_id, delivery_status)
);
|]
