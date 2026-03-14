{-# LANGUAGE QuasiQuotes #-}

module Zero.Chat.Store.Postgres.Migrations.M20251117_member_relations_vector where

import Data.Text (Text)
import qualified Data.Text as T
import Text.RawString.QQ (r)

m20251117_member_relations_vector :: Text
m20251117_member_relations_vector =
  T.pack
    [r|
CREATE FUNCTION set_member_vector_new_relation(v BYTEA, idx BIGINT, direction INT, status INT)
RETURNS BYTEA AS $$
DECLARE
  new_len INT;
  result BYTEA;
  byte_val INT;
  old_byte INT;
BEGIN
  IF idx < 0 THEN
    RETURN v;
  END IF;
  IF idx < length(v) THEN
    old_byte := get_byte(v, idx::INT);
  ELSE
    old_byte := 0;
  END IF;
  byte_val := (old_byte & x'F0'::INT) | (direction * 8) | status;
  new_len := GREATEST(length(v), idx + 1);
  IF new_len > length(v) THEN
    result := v || (SELECT string_agg('\x00'::BYTEA, ''::BYTEA) FROM generate_series(1, new_len - length(v)));
  ELSE
    result := v;
  END IF;
  result := set_byte(result, idx::INT, byte_val);
  RETURN result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE FUNCTION migrate_relations_vector_step(state BYTEA, idx BIGINT, direction INT, intro_status TEXT)
RETURNS BYTEA AS $$
DECLARE
  new_len INT;
  result BYTEA;
  status INT;
  byte_val INT;
BEGIN
  IF idx < 0 THEN
    RETURN state;
  END IF;
  IF intro_status = 're-con' THEN
    IF direction = 0 THEN status := 2; ELSE status := 3; END IF;
  ELSIF intro_status = 'to-con' THEN
    IF direction = 0 THEN status := 3; ELSE status := 2; END IF;
  ELSIF intro_status = 'con' THEN
    status := 4;
  ELSE
    status := 1;
  END IF;
  byte_val := (direction * 8) + status;
  new_len := GREATEST(length(state), idx + 1);
  IF new_len > length(state) THEN
    result := state || (SELECT string_agg('\x00'::BYTEA, ''::BYTEA) FROM generate_series(1, new_len - length(state)));
  ELSE
    result := state;
  END IF;
  result := set_byte(result, idx::INT, byte_val);
  RETURN result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE AGGREGATE migrate_relations_vector(BIGINT, INT, TEXT) (
  SFUNC = migrate_relations_vector_step,
  STYPE = BYTEA,
  INITCOND = ''
);

ALTER TABLE group_members ADD COLUMN index_in_group BIGINT NOT NULL DEFAULT 0;

ALTER TABLE groups ADD COLUMN member_index BIGINT NOT NULL DEFAULT 0;

ALTER TABLE group_members ADD COLUMN member_relations_vector BYTEA;

CREATE INDEX tmp_idx_group_members_group_id_group_member_id ON group_members(group_id, group_member_id);

CREATE TEMPORARY TABLE tmp_members_indexed AS
SELECT
  group_member_id,
  ROW_NUMBER() OVER (
    PARTITION BY group_id
    ORDER BY group_member_id ASC
  ) - 1 AS idx_in_group
FROM group_members;

CREATE INDEX tmp_idx_members_indexed ON tmp_members_indexed(group_member_id);

UPDATE group_members AS gm
SET index_in_group = tmi.idx_in_group
FROM tmp_members_indexed tmi
WHERE tmi.group_member_id = gm.group_member_id;

DROP INDEX tmp_idx_group_members_group_id_group_member_id;
DROP INDEX tmp_idx_members_indexed;
DROP TABLE tmp_members_indexed;

CREATE UNIQUE INDEX idx_group_members_group_id_index_in_group ON group_members(group_id, index_in_group);

UPDATE groups g
SET member_index = COALESCE((
  SELECT MAX(index_in_group) + 1
  FROM group_members
  WHERE group_members.group_id = g.group_id
), 0);

UPDATE group_members
SET member_relations_vector = ''::BYTEA
WHERE group_id IN (
  SELECT mu.group_id
  FROM group_members mu
  WHERE mu.member_category = 'user'
    AND (
      mu.member_role NOT IN ('admin', 'owner')
      OR mu.member_status IN ('removed', 'left', 'deleted')
    )
);
|]

down_m20251117_member_relations_vector :: Text
down_m20251117_member_relations_vector =
  T.pack
    [r|
DROP AGGREGATE migrate_relations_vector(BIGINT, INT, TEXT);
DROP FUNCTION migrate_relations_vector_step(BYTEA, BIGINT, INT, TEXT);
DROP FUNCTION set_member_vector_new_relation(BYTEA, BIGINT, INT, INT);

DROP INDEX idx_group_members_group_id_index_in_group;

ALTER TABLE group_members DROP COLUMN index_in_group;

ALTER TABLE groups DROP COLUMN member_index;

ALTER TABLE group_members DROP COLUMN member_relations_vector;
|]
