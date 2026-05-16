{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module AgentTests.SchemaDump where

import Control.DeepSeq
import Control.Monad (unless, void)
import Data.List (dropWhileEnd)
import Data.Maybe (fromJust, isJust)
import Data.Text (Text)
import Database.SQLite.Simple (Only (..))
import qualified Database.SQLite.Simple as SQL
import Zero.Messaging.Agent.Store.Migrations.App (appMigrations)
import Zero.Messaging.Agent.Store.SQLite
import Zero.Messaging.Agent.Store.SQLite.Common (withTransaction')
import Zero.Messaging.Agent.Store.SQLite.DB (TrackQueries (..))
import qualified Zero.Messaging.Agent.Store.SQLite.Migrations as Migrations
import Zero.Messaging.Agent.Store.Shared (Migration (..), MigrationConfig (..), MigrationConfirmation (..), MigrationsToRun (..), toDownMigration)
import Zero.Messaging.Util (ifM)
import System.Directory (doesFileExist, removeFile)
import System.Process (readCreateProcess, shell)
import Test.Hspec hiding (fit, it)
import Util

testDB :: FilePath
testDB = "tests/tmp/test_agent_schema.db"

appSchema :: FilePath
appSchema = "src/Zero/Messaging/Agent/Store/SQLite/Migrations/agent_schema.sql"

appLint :: FilePath
appLint = "src/Zero/Messaging/Agent/Store/SQLite/Migrations/agent_lint.sql"

testSchema :: FilePath
testSchema = "tests/tmp/test_agent_schema.sql"

schemaDumpTest :: Spec
schemaDumpTest = do
  it "verify and overwrite schema dump" testVerifySchemaDump
  it "verify .lint fkey-indexes" testVerifyLintFKeyIndexes
  it "verify schema down migrations" testSchemaMigrations
  it "verify strict tables" testVerifyStrict
  it "should NOT create user record for new database" testUsersMigrationNew
  it "should create user record for old database" testUsersMigrationOld

testVerifySchemaDump :: IO ()
testVerifySchemaDump = do
  savedSchema <- ifM (doesFileExist appSchema) (readFile appSchema) (pure "")
  savedSchema `deepseq` pure ()
  void $ createDBStore (DBOpts testDB [] "" False True TQOff) appMigrations (MigrationConfig MCConsole Nothing)
  getSchema testDB appSchema `shouldReturn` savedSchema
  removeFile testDB

testVerifyLintFKeyIndexes :: IO ()
testVerifyLintFKeyIndexes = do
  savedLint <- ifM (doesFileExist appLint) (readFile appLint) (pure "")
  savedLint `deepseq` pure ()
  void $ createDBStore (DBOpts testDB [] "" False True TQOff) appMigrations (MigrationConfig MCConsole Nothing)
  getLintFKeyIndexes testDB "tests/tmp/agent_lint.sql" `shouldReturn` savedLint
  removeFile testDB

testSchemaMigrations :: IO ()
testSchemaMigrations = do
  let noDownMigrations = dropWhileEnd (\Migration {down} -> isJust down) appMigrations
  Right st <- createDBStore (DBOpts testDB [] "" False True TQOff) noDownMigrations (MigrationConfig MCError Nothing)
  mapM_ (testDownMigration st) $ drop (length noDownMigrations) appMigrations
  closeDBStore st
  removeFile testDB
  removeFile testSchema
  where
    testDownMigration st m = do
      putStrLn $ "down migration " <> name m
      let downMigr = fromJust $ toDownMigration m
      schema <- getSchema testDB testSchema
      Migrations.run st Nothing True $ MTRUp [m]
      schema' <- getSchema testDB testSchema
      schema' `shouldNotBe` schema
      Migrations.run st Nothing True $ MTRDown [downMigr]
      unless (name m `elem` skipComparisonForDownMigrations) $ do
        schema'' <- getSchema testDB testSchema
        schema'' `shouldBe` schema
      Migrations.run st Nothing True $ MTRUp [m]
      schema''' <- getSchema testDB testSchema
      schema''' `shouldBe` schema'

testVerifyStrict :: IO ()
testVerifyStrict = do
  Right st <- createDBStore (DBOpts testDB [] "" False True TQOff) appMigrations (MigrationConfig MCConsole Nothing)
  withTransaction' st (`SQL.query_` "SELECT name FROM sqlite_master WHERE type = 'table' AND name != 'sqlite_sequence' AND sql NOT LIKE '% STRICT'")
    `shouldReturn` ([] :: [Only Text])

testUsersMigrationNew :: IO ()
testUsersMigrationNew = do
  Right st <- createDBStore (DBOpts testDB [] "" False True TQOff) appMigrations (MigrationConfig MCError Nothing)
  withTransaction' st (`SQL.query_` "SELECT user_id FROM users;")
    `shouldReturn` ([] :: [Only Int])
  closeDBStore st

testUsersMigrationOld :: IO ()
testUsersMigrationOld = do
  let beforeUsers = takeWhile (("m20230110_users" /=) . name) appMigrations
  Right st <- createDBStore (DBOpts testDB [] "" False True TQOff) beforeUsers (MigrationConfig MCError Nothing)
  withTransaction' st (`SQL.query_` "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'users';")
    `shouldReturn` ([] :: [Only String])
  closeDBStore st
  Right st' <- createDBStore (DBOpts testDB [] "" False True TQOff) appMigrations (MigrationConfig MCYesUp Nothing)
  withTransaction' st' (`SQL.query_` "SELECT user_id FROM users;")
    `shouldReturn` ([Only (1 :: Int)])
  closeDBStore st'

skipComparisonForDownMigrations :: [String]
skipComparisonForDownMigrations =
  [
    "m20230814_indexes",
    "m20250322_short_links"
  ]

getSchema :: FilePath -> FilePath -> IO String
getSchema dbPath schemaPath = do
  void $ readCreateProcess (shell $ "sqlite3 " <> dbPath <> " '.schema --indent' > " <> schemaPath) ""
  sch <- readFile schemaPath
  sch `deepseq` pure sch

getLintFKeyIndexes :: FilePath -> FilePath -> IO String
getLintFKeyIndexes dbPath lintPath = do
  void $ readCreateProcess (shell $ "sqlite3 " <> dbPath <> " '.lint fkey-indexes' > " <> lintPath) ""
  lint <- readFile lintPath
  lint `deepseq` pure lint
