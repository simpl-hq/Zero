{-# LANGUAGE QuasiQuotes #-}

module Zero.Messaging.Agent.Store.SQLite.Migrations.M20220608_v2 where

import Database.SQLite.Simple (Query)
import Database.SQLite.Simple.QQ (sql)

m20220608_v2 :: Query
m20220608_v2 =
  [sql|
ALTER TABLE messages ADD COLUMN msg_flags TEXT NULL;

ALTER TABLE conn_confirmations ADD COLUMN smp_reply_queues BLOB NULL;

ALTER TABLE connections ADD COLUMN duplex_handshake INTEGER NULL DEFAULT 0;

ALTER TABLE rcv_messages ADD COLUMN user_ack INTEGER NULL DEFAULT 0;

ALTER TABLE rcv_queues ADD COLUMN ntf_public_key BLOB;

ALTER TABLE rcv_queues ADD COLUMN ntf_private_key BLOB;

ALTER TABLE rcv_queues ADD COLUMN ntf_id BLOB;

ALTER TABLE rcv_queues ADD COLUMN rcv_ntf_dh_secret BLOB;

CREATE UNIQUE INDEX idx_rcv_queues_ntf ON rcv_queues (host, port, ntf_id);

CREATE TABLE ntf_subscriptions (
  conn_id BLOB NOT NULL,
  smp_host TEXT NULL,
  smp_port TEXT NULL,
  smp_ntf_id BLOB,
  ntf_host TEXT NOT NULL,
  ntf_port TEXT NOT NULL,
  ntf_sub_id BLOB,
  ntf_sub_status TEXT NOT NULL,
  ntf_sub_action TEXT,
  ntf_sub_smp_action TEXT,
  ntf_sub_action_ts TEXT,
  updated_by_supervisor INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (conn_id),
  FOREIGN KEY (smp_host, smp_port) REFERENCES servers (host, port)
    ON DELETE SET NULL ON UPDATE CASCADE,
  FOREIGN KEY (ntf_host, ntf_port) REFERENCES ntf_servers
    ON DELETE RESTRICT ON UPDATE CASCADE
) WITHOUT ROWID;
|]
