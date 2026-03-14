{-# LANGUAGE QuasiQuotes #-}

module Zero.Chat.Store.SQLite.Migrations.M20231114_remote_control where

import Database.SQLite.Simple (Query)
import Database.SQLite.Simple.QQ (sql)

m20231114_remote_control :: Query
m20231114_remote_control =
  [sql|
CREATE TABLE remote_hosts (
  remote_host_id INTEGER PRIMARY KEY AUTOINCREMENT,
  host_device_name TEXT NOT NULL,
  store_path TEXT NOT NULL,
  ca_key BLOB NOT NULL,
  ca_cert BLOB NOT NULL,
  id_key BLOB NOT NULL,
  host_fingerprint BLOB NOT NULL,
  host_dh_pub BLOB NOT NULL
);

CREATE UNIQUE INDEX idx_remote_hosts_host_fingerprint ON remote_hosts(host_fingerprint);

CREATE TABLE remote_controllers (
  remote_ctrl_id INTEGER PRIMARY KEY AUTOINCREMENT,
  ctrl_device_name TEXT NOT NULL,
  ca_key BLOB NOT NULL,
  ca_cert BLOB NOT NULL,
  ctrl_fingerprint BLOB NOT NULL,
  id_pub BLOB NOT NULL,
  dh_priv_key BLOB NOT NULL,
  prev_dh_priv_key BLOB
);

CREATE UNIQUE INDEX idx_remote_controllers_ctrl_fingerprint ON remote_controllers(ctrl_fingerprint);
|]

down_m20231114_remote_control :: Query
down_m20231114_remote_control =
  [sql|
DROP INDEX idx_remote_hosts_host_fingerprint;
DROP INDEX idx_remote_controllers_ctrl_fingerprint;
DROP TABLE remote_hosts;
DROP TABLE remote_controllers;
|]
