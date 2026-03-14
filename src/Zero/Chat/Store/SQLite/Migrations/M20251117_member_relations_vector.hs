{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Zero.Chat.Store.SQLite.Migrations.M20251117_member_relations_vector where

import qualified Data.ByteString as B
import Database.SQLite.Simple (Query)
import Database.SQLite.Simple.QQ (sql)
import Database.SQLite3 (funcArgBlob, funcArgInt64, funcArgText, funcResultBlob)
import Database.SQLite3.Bindings
import Foreign.C.Types
import Foreign.Ptr
import Zero.Chat.Types.MemberRelations (IntroductionDirection (..), MemberRelation (..), fromIntroDirInt, fromRelationInt, setNewRelation, setNewRelations)
import Zero.Messaging.Agent.Store.SQLite.Util (SQLiteFunc, SQLiteFuncFinal, mkSQLiteAggFinal, mkSQLiteAggStep, mkSQLiteFunc)

foreign export ccall "zero_member_relations_step" sqliteMemberRelationsStep :: SQLiteFunc

foreign import ccall "&zero_member_relations_step" sqliteMemberRelationsStepPtr :: FunPtr SQLiteFunc

foreign export ccall "zero_member_relations_final" sqliteMemberRelationsFinal :: SQLiteFuncFinal

foreign import ccall "&zero_member_relations_final" sqliteMemberRelationsFinalPtr :: FunPtr SQLiteFuncFinal

sqliteMemberRelationsStep :: SQLiteFunc
sqliteMemberRelationsStep = mkSQLiteAggStep [] $ \_ args acc -> do
  idx <- funcArgInt64 args 0
  direction <- fromIntroDirInt . fromIntegral <$> funcArgInt64 args 1
  introStatus <- funcArgText args 2
  let relation = introStatusToRelation direction introStatus
  pure $ (idx, (direction, relation)) : acc
  where
    introStatusToRelation dir status = case status of
      "re-con" -> if dir == IDSubjectIntroduced then MRSubjectConnected else MRReferencedConnected
      "to-con" -> if dir == IDSubjectIntroduced then MRReferencedConnected else MRSubjectConnected
      "con" -> MRConnected
      _ -> MRIntroduced

sqliteMemberRelationsFinal :: SQLiteFuncFinal
sqliteMemberRelationsFinal = mkSQLiteAggFinal [] $ \cxt acc -> funcResultBlob cxt $ setNewRelations acc B.empty

foreign export ccall "zero_set_member_vector_new_relation" sqliteSetMemberVectorNewRelation :: SQLiteFunc

foreign import ccall "&zero_set_member_vector_new_relation" sqliteSetMemberVectorNewRelationPtr :: FunPtr SQLiteFunc

sqliteSetMemberVectorNewRelation :: SQLiteFunc
sqliteSetMemberVectorNewRelation = mkSQLiteFunc $ \cxt args -> do
  v <- funcArgBlob args 0
  idx <- funcArgInt64 args 1
  direction <- fromIntroDirInt . fromIntegral <$> funcArgInt64 args 2
  status <- fromRelationInt . fromIntegral <$> funcArgInt64 args 3
  funcResultBlob cxt $ setNewRelation idx direction status v

m20251117_member_relations_vector :: Query
m20251117_member_relations_vector =
  [sql|
ALTER TABLE group_members ADD COLUMN index_in_group INTEGER NOT NULL DEFAULT 0;

ALTER TABLE groups ADD COLUMN member_index INTEGER NOT NULL DEFAULT 0;

ALTER TABLE group_members ADD COLUMN member_relations_vector BLOB;

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
SET index_in_group = (
  SELECT idx_in_group
  FROM tmp_members_indexed
  WHERE tmp_members_indexed.group_member_id = gm.group_member_id
);

DROP INDEX tmp_idx_group_members_group_id_group_member_id;
DROP INDEX tmp_idx_members_indexed;
DROP TABLE tmp_members_indexed;

CREATE UNIQUE INDEX idx_group_members_group_id_index_in_group ON group_members(group_id, index_in_group);

UPDATE groups AS g
SET member_index = COALESCE((
  SELECT MAX(index_in_group) + 1
  FROM group_members
  WHERE group_members.group_id = g.group_id
), 0);

UPDATE group_members
SET member_relations_vector = x''
WHERE group_id IN (
  SELECT mu.group_id
  FROM group_members mu
  WHERE mu.member_category = 'user'
    AND (
      mu.member_role NOT IN (CAST('admin' AS BLOB), CAST('owner' AS BLOB))
      OR mu.member_status IN ('removed', 'left', 'deleted')
    )
);
|]

down_m20251117_member_relations_vector :: Query
down_m20251117_member_relations_vector =
  [sql|
DROP INDEX idx_group_members_group_id_index_in_group;

ALTER TABLE group_members DROP COLUMN index_in_group;

ALTER TABLE groups DROP COLUMN member_index;

ALTER TABLE group_members DROP COLUMN member_relations_vector;
|]
