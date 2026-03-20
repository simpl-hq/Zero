{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fno-warn-ambiguous-fields #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Zero.Messaging.Agent.Store.SQLite
  ( DBOpts (..),
    Migrations.getCurrentMigrations,
    migrateDBSchema,
    createDBStore,
    closeDBStore,
    reopenDBStore,
    execSQL,
    sqlString,
    keyString,
    storeKey,
    connectSQLiteStore,
    openSQLiteStore,
  )
where

import Control.Concurrent.MVar
import Control.Concurrent.STM
import Control.Exception (bracketOnError, onException, throwIO)
import Control.Monad
import Data.Bits (xor)
import Data.ByteArray (ScrubbedBytes)
import qualified Data.ByteArray as BA
import Data.ByteString (ByteString)
import qualified Data.ByteString as B
import Data.Functor (($>))
import Data.IORef
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Database.SQLite.Simple (Query (..))
import qualified Database.SQLite.Simple as SQL
import Database.SQLite.Simple.QQ (sql)
import qualified Database.SQLite3 as SQLite3
import Database.SQLite3.Bindings
import Foreign.C.Types
import Foreign.Ptr
import Zero.Messaging.Agent.Store.Migrations (DBMigrate (..), sharedMigrateSchema)
import qualified Zero.Messaging.Agent.Store.SQLite.Migrations as Migrations
import Zero.Messaging.Agent.Store.SQLite.Common
import qualified Zero.Messaging.Agent.Store.SQLite.DB as DB
import Zero.Messaging.Agent.Store.SQLite.Util
import Zero.Messaging.Agent.Store.Shared (Migration (..), MigrationConfig (..), MigrationError (..))
import qualified Zero.Messaging.Crypto as C
import Zero.Messaging.Util (ifM, packZipWith, safeDecodeUtf8)
import System.Directory (copyFile, createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeDirectory, takeFileName, (</>))

createDBStore :: DBOpts -> [Migration] -> MigrationConfig -> IO (Either MigrationError DBStore)
createDBStore opts@DBOpts {dbFilePath} migrations migrationConfig = do
  let dbDir = takeDirectory dbFilePath
  createDirectoryIfMissing True dbDir
  st <- connectSQLiteStore opts
  r <- migrateDBSchema st opts Nothing migrations migrationConfig `onException` closeDBStore st
  case r of
    Right () -> pure $ Right st
    Left e -> closeDBStore st $> Left e
  where

migrateDBSchema :: DBStore -> DBOpts -> Maybe Query -> [Migration] -> MigrationConfig -> IO (Either MigrationError ())
migrateDBSchema st DBOpts {dbFilePath, vacuum} migrationsTable migrations MigrationConfig {confirm, backupPath} =
  let initialize = Migrations.initialize st migrationsTable
      getCurrent = withTransaction st $ Migrations.getCurrentMigrations migrationsTable
      run = Migrations.run st migrationsTable vacuum
      backup = mkBackup <$> backupPath
      mkBackup bp =
        let f = if null bp then dbFilePath else bp </> takeFileName dbFilePath
          in copyFile dbFilePath $ f <> ".bak"
      dbm = DBMigrate {initialize, getCurrent, run, backup}
   in sharedMigrateSchema dbm (dbNew st) migrations confirm

connectSQLiteStore :: DBOpts -> IO DBStore
connectSQLiteStore DBOpts {dbFilePath, dbFunctions, dbKey = key, keepKey, track} = do
  dbNew <- not <$> doesFileExist dbFilePath
  dbConn <- dbBusyLoop $ connectDB dbFilePath dbFunctions key track
  dbConnection <- newMVar dbConn
  dbKey <- newTVarIO $! storeKey key keepKey
  dbClosed <- newTVarIO False
  dbSem <- newTVarIO 0
  pure DBStore {dbFilePath, dbFunctions, dbKey, dbSem, dbConnection, dbNew, dbClosed}

connectDB :: FilePath -> [SQLiteFuncDef] -> ScrubbedBytes -> DB.TrackQueries -> IO DB.Connection
connectDB path functions key track = do
  db <- DB.open path track
  prepare db `onException` DB.close db
  pure db
  where
    prepare db = do
      unless (BA.null key) . SQLite3.exec db' $ "PRAGMA key = " <> keyString key <> ";"
      SQLite3.exec db' . fromQuery $
        [sql|
          PRAGMA busy_timeout = 100;
          PRAGMA foreign_keys = ON;
          PRAGMA secure_delete = ON;
          PRAGMA auto_vacuum = FULL;
        |]
      mapM_ addFunction functions'
      where
        db' = SQL.connectionHandle $ DB.conn db
        functions' = SQLiteFuncDef "zero_xor_md5_combine" 2 (SQLiteFuncPtr True sqliteXorMd5CombinePtr) : functions
        addFunction SQLiteFuncDef {funcName, argCount, funcPtrs} =
          either (throwIO . userError . show) pure =<< case funcPtrs of
            SQLiteFuncPtr isDet funcPtr -> createStaticFunction db' funcName argCount isDet funcPtr
            SQLiteAggrPtrs stepPtr finalPtr -> createStaticAggregate db' funcName argCount stepPtr finalPtr

foreign export ccall "zero_xor_md5_combine" sqliteXorMd5Combine :: SQLiteFunc

foreign import ccall "&zero_xor_md5_combine" sqliteXorMd5CombinePtr :: FunPtr SQLiteFunc

sqliteXorMd5Combine :: SQLiteFunc
sqliteXorMd5Combine = mkSQLiteFunc $ \cxt args -> do
  idsHash <- SQLite3.funcArgBlob args 0
  rId <- SQLite3.funcArgBlob args 1
  SQLite3.funcResultBlob cxt $ xorMd5Combine idsHash rId

xorMd5Combine :: ByteString -> ByteString -> ByteString
xorMd5Combine idsHash rId = packZipWith xor idsHash $ C.md5Hash rId
{-# INLINE xorMd5Combine #-}

closeDBStore :: DBStore -> IO ()
closeDBStore st@DBStore {dbClosed} =
  ifM (readTVarIO dbClosed) (putStrLn "closeDBStore: already closed") $
    withConnection st $ \conn -> do
      DB.close conn
      atomically $ writeTVar dbClosed True

openSQLiteStore :: DBStore -> ScrubbedBytes -> Bool -> IO ()
openSQLiteStore st@DBStore {dbClosed} key keepKey =
  ifM (readTVarIO dbClosed) (openSQLiteStore_ st key keepKey) (putStrLn "openSQLiteStore: already opened")

openSQLiteStore_ :: DBStore -> ScrubbedBytes -> Bool -> IO ()
openSQLiteStore_ DBStore {dbConnection, dbFilePath, dbFunctions, dbKey, dbClosed} key keepKey =
  bracketOnError
    (takeMVar dbConnection)
    (tryPutMVar dbConnection)
    $ \DB.Connection {slow, track} -> do
      DB.Connection {conn} <- connectDB dbFilePath dbFunctions key track
      atomically $ do
        writeTVar dbClosed False
        writeTVar dbKey $! storeKey key keepKey
      putMVar dbConnection DB.Connection {conn, slow, track}

reopenDBStore :: DBStore -> IO ()
reopenDBStore st@DBStore {dbKey, dbClosed} =
  ifM (readTVarIO dbClosed) open (putStrLn "reopenDBStore: already opened")
  where
    open =
      readTVarIO dbKey >>= \case
        Just key -> openSQLiteStore_ st key True
        Nothing -> fail "reopenDBStore: no key"

keyString :: ScrubbedBytes -> Text
keyString = sqlString . safeDecodeUtf8 . BA.convert

sqlString :: Text -> Text
sqlString s = quote <> T.replace quote "''" s <> quote
  where
    quote = "'"

execSQL :: DB.Connection -> Text -> IO [Text]
execSQL db query = do
  rs <- newIORef []
  SQLite3.execWithCallback (SQL.connectionHandle $ DB.conn db) query (addSQLResultRow rs)
  reverse <$> readIORef rs

addSQLResultRow :: IORef [Text] -> SQLite3.ColumnIndex -> [Text] -> [Maybe Text] -> IO ()
addSQLResultRow rs _count names values = modifyIORef' rs $ \case
  [] -> [showValues values, T.intercalate "|" names]
  rs' -> showValues values : rs'
  where
    showValues = T.intercalate "|" . map (fromMaybe "")
