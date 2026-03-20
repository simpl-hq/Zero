{-# LANGUAGE QuasiQuotes #-}

module Zero.Messaging.Agent.Store.SQLite.Migrations.M20220322_notifications where

import Database.SQLite.Simple (Query)
import Database.SQLite.Simple.QQ (sql)

m20220322_notifications :: Query
m20220322_notifications =
  [sql|
CREATE TABLE ntf_servers (
  ntf_host TEXT NOT NULL,
  ntf_port TEXT NOT NULL,
  ntf_key_hash BLOB NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (ntf_host, ntf_port)
) WITHOUT ROWID;

CREATE TABLE ntf_tokens (
  provider TEXT NOT NULL,
  device_token TEXT NOT NULL,
  ntf_host TEXT NOT NULL,
  ntf_port TEXT NOT NULL,
  tkn_id BLOB,
  tkn_pub_key BLOB NOT NULL,
  tkn_priv_key BLOB NOT NULL,
  tkn_pub_dh_key BLOB NOT NULL,
  tkn_priv_dh_key BLOB NOT NULL,
  tkn_dh_secret BLOB,
  tkn_status TEXT NOT NULL,
  tkn_action BLOB,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (provider, device_token, ntf_host, ntf_port),
  FOREIGN KEY (ntf_host, ntf_port) REFERENCES ntf_servers
    ON DELETE RESTRICT ON UPDATE CASCADE
) WITHOUT ROWID;
|]
