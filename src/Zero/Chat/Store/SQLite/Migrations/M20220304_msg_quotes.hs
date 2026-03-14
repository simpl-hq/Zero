{-# LANGUAGE QuasiQuotes #-}

module Zero.Chat.Store.SQLite.Migrations.M20220304_msg_quotes where

import Database.SQLite.Simple (Query)
import Database.SQLite.Simple.QQ (sql)

m20220304_msg_quotes :: Query
m20220304_msg_quotes =
  [sql|
    ALTER TABLE messages ADD COLUMN shared_msg_id BLOB;
    ALTER TABLE messages ADD COLUMN shared_msg_id_user INTEGER;
    CREATE INDEX idx_messages_shared_msg_id ON messages (shared_msg_id);
    CREATE UNIQUE INDEX idx_messages_direct_shared_msg_id ON messages (connection_id, shared_msg_id_user, shared_msg_id);
    CREATE UNIQUE INDEX idx_messages_group_shared_msg_id ON messages (group_id, shared_msg_id_user, shared_msg_id);

    ALTER TABLE chat_items ADD COLUMN shared_msg_id BLOB;
    ALTER TABLE chat_items ADD COLUMN quoted_shared_msg_id BLOB;
    ALTER TABLE chat_items ADD COLUMN quoted_sent_at TEXT;
    ALTER TABLE chat_items ADD COLUMN quoted_content TEXT;
    ALTER TABLE chat_items ADD COLUMN quoted_sent INTEGER;
    ALTER TABLE chat_items ADD COLUMN quoted_member_id BLOB;
    CREATE INDEX idx_chat_items_shared_msg_id ON chat_items (shared_msg_id);
|]
