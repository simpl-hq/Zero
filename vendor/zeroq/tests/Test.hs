{-# LANGUAGE CPP #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE TypeApplications #-}

import AgentTests (agentCoreTests, agentTests)
import CLITests
import Control.Concurrent (threadDelay)
import qualified Control.Exception as E
import Control.Logger.Simple
import CoreTests.BatchingTests
import CoreTests.CryptoFileTests
import CoreTests.CryptoTests
import CoreTests.EncodingTests
import CoreTests.MsgStoreTests
import CoreTests.RetryIntervalTests
import CoreTests.SOCKSSettings
import CoreTests.StoreLogTests
import CoreTests.TSessionSubs
import CoreTests.UtilTests
import CoreTests.VersionRangeTests
import FileDescriptionTests (fileDescriptionTests)
import GHC.IO.Exception (IOException (..))
import qualified GHC.IO.Exception as IOException
import RSLVTests (rslvTests)
import RemoteControl (remoteControlTests)
import SMPNamesTests (smpNamesTests)
import SMPProxyTests (smpProxyTests)
import ServerTests
import Zero.Messaging.Server.Env.STM (AStoreType (..))
import Zero.Messaging.Server.MsgStore.Types (SMSType (..), SQSType (..))
import Zero.Messaging.Transport (TLS, Transport (..))
import System.Directory (createDirectoryIfMissing, removeDirectoryRecursive)
import System.Environment (setEnv)
import Test.Hspec hiding (fit, it)
import Util
import XFTPAgent
import XFTPCLI (xftpCLIFileTests)
import Zero.FileTransfer.Server.Env (AFStoreType (..))
import Zero.FileTransfer.Server.Store (SFSType (..))
import XFTPServerTests (xftpServerTests)
import WebTests (webTests)
import XFTPWebTests (xftpWebTests)

#if defined(dbPostgres)
import Fixtures
import SMPAgentClient (testDB)
import Zero.Messaging.Agent.Store.Postgres.Migrations.App
import Zero.Messaging.Agent.Store.Postgres.Util (dropAllSchemasExceptSystem)
#else
import AgentTests.SchemaDump (schemaDumpTest)
#endif

#if defined(dbServerPostgres)
import CoreTests.XFTPStoreTests (xftpStoreTests, xftpMigrationTests)
import NtfServerTests (ntfServerTests)
import NtfClient (ntfTestServerDBConnectInfo, ntfTestStoreDBOpts)
import SMPClient (testServerDBConnectInfo, testStoreDBOpts)
import Zero.Messaging.Notifications.Server.Store.Migrations (ntfServerMigrations)
import Zero.Messaging.Server.QueueStore.Postgres.Migrations (serverMigrations)
import XFTPClient (testXFTPDBConnectInfo)
#endif

#if defined(dbPostgres) || defined(dbServerPostgres)
import PostgresSchemaDump (postgresSchemaDumpTest)
import SMPClient (postgressBracket)
#endif

logCfg :: LogConfig
logCfg = LogConfig {lc_file = Nothing, lc_stderr = True}

main :: IO ()
main = do
  setLogLevel testLogLevel
  withGlobalLogging logCfg $ do
    setEnv "APNS_KEY_ID" "H82WD9K9AQ"
    setEnv "APNS_KEY_FILE" "./tests/fixtures/AuthKey_H82WD9K9AQ.p8"
    hspec
#if defined(dbPostgres)
      . aroundAll_ (postgressBracket testDBConnectInfo)
#endif
      . before_ (createDirectoryIfMissing False "tests/tmp")
      . after_ (eventuallyRemove "tests/tmp" 3)
      $ do
        describe "Core tests" $ do
          describe "Batching tests" batchingTests
          describe "Encoding tests" encodingTests
          describe "Version range" versionRangeTests
          describe "Encryption tests" cryptoTests
          describe "Encrypted files tests" cryptoFileTests
          describe "Message store tests" msgStoreTests
          describe "Retry interval tests" retryIntervalTests
          describe "SOCKS settings tests" socksSettingsTests
#if defined(dbServerPostgres)
          around_ (postgressBracket testServerDBConnectInfo) $
            describe "Store log tests" storeLogTests
#else
          describe "Store log tests" storeLogTests
#endif
          describe "TSessionSubs tests" tSessionSubsTests
          describe "Util tests" utilTests
          describe "Names resolver tests" smpNamesTests
          describe "RSLV functional API tests" rslvTests
          describe "Agent core tests" agentCoreTests
#if defined(dbServerPostgres)
        around_ (postgressBracket testServerDBConnectInfo) $
          describe "SMP server schema dump" $
            postgresSchemaDumpTest
              serverMigrations
              [ "20250320_short_links"
              ]
              testStoreDBOpts
              "src/Zero/Messaging/Server/QueueStore/Postgres/server_schema.sql"
        around_ (postgressBracket testServerDBConnectInfo) $ do
          describe "SMP server via TLS, postgres-only message store" $
            before (pure (transport @TLS, ASType SQSPostgres SMSPostgres)) serverTests
#endif
        describe "SMP server via TLS, jornal message store" $ do
          describe "SMP syntax" $ serverSyntaxTests (transport @TLS)
          before (pure (transport @TLS, ASType SQSMemory SMSJournal)) serverTests
        describe "SMP server via TLS, memory message store" $
          before (pure (transport @TLS, ASType SQSMemory SMSMemory)) serverTests
#if defined(dbServerPostgres)
        around_ (postgressBracket ntfTestServerDBConnectInfo) $
          describe "Ntf server schema dump" $
            postgresSchemaDumpTest
              ntfServerMigrations
              []
              ntfTestStoreDBOpts
              "src/Zero/Messaging/Notifications/Server/Store/ntf_server_schema.sql"
        around_ (postgressBracket ntfTestServerDBConnectInfo) $ do
          describe "Notifications server (SMP server: memory store)" $
            ntfServerTests (transport @TLS, ASType SQSMemory SMSMemory)
          around_ (postgressBracket testServerDBConnectInfo) $ do
            describe "Notifications server (SMP server: postgres-only store)" $
              ntfServerTests (transport @TLS, ASType SQSPostgres SMSPostgres)
        around_ (postgressBracket testServerDBConnectInfo) $ do
          describe "SMP client agent, server postgres-only message store" $ agentTests (transport @TLS, ASType SQSPostgres SMSPostgres)
          describe "SMP proxy, postgres-only message store" $
            before (pure $ ASType SQSPostgres SMSPostgres) smpProxyTests
#endif
        describe "SMP client agent, server memory message store" $ agentTests (transport @TLS, ASType SQSMemory SMSMemory)
        describe "SMP proxy, jornal message store" $
          before (pure $ ASType SQSMemory SMSJournal) smpProxyTests
        describe "XFTP" $ do
          describe "XFTP server" $
            before (pure $ AFSType SFSMemory) xftpServerTests
          describe "XFTP file description" fileDescriptionTests
          describe "XFTP CLI (memory)" $
            before (pure $ AFSType SFSMemory) xftpCLIFileTests
          describe "XFTP agent" $
            before (pure $ AFSType SFSMemory) xftpAgentTests
#if defined(dbServerPostgres)
        around_ (postgressBracket testXFTPDBConnectInfo) $ do
          describe "XFTP Postgres store operations" xftpStoreTests
          describe "XFTP migration round-trip" xftpMigrationTests
          describe "XFTP server (PostgreSQL)" $
            before (pure $ AFSType SFSPostgres) xftpServerTests
          describe "XFTP agent (PostgreSQL)" $
            before (pure $ AFSType SFSPostgres) xftpAgentTests
          describe "XFTP CLI (PostgreSQL)" $
            before (pure $ AFSType SFSPostgres) xftpCLIFileTests
#endif
#if defined(dbPostgres)
        describe "XFTP Web Client" $ xftpWebTests (dropAllSchemasExceptSystem testDBConnectInfo)
#else
        describe "XFTP Web Client" $ xftpWebTests (pure ())
#endif
        describe "XRCP" remoteControlTests
        describe "Web" webTests
        describe "Server CLIs" cliTests
#if defined(dbPostgres)
        around_ (postgressBracket testDBConnectInfo) $
          describe "Agent PostgreSQL schema dump" $
            postgresSchemaDumpTest
              appMigrations
              ["20250322_short_links"]
              (testDBOpts testDB)
              "src/Zero/Messaging/Agent/Store/Postgres/Migrations/agent_postgres_schema.sql"
#else
        describe "Agent SQLite schema dump" schemaDumpTest
#endif

eventuallyRemove :: FilePath -> Int -> IO ()
eventuallyRemove path retries = case retries of
  0 -> action
  n ->
    action `E.catch` \ioe@IOError {ioe_type, ioe_filename} -> case ioe_type of
      IOException.UnsatisfiedConstraints | ioe_filename == Just path -> threadDelay 1000000 >> eventuallyRemove path (n - 1)
      _ -> E.throwIO ioe
  where
    action = removeDirectoryRecursive path
