{-# LANGUAGE CPP #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
#if __GLASGOW_HASKELL__ == 810
{-# LANGUAGE UndecidableInstances #-}
#endif
{-# OPTIONS_GHC -fno-warn-ambiguous-fields #-}

module Zero.Messaging.Server.Env.STM
  ( ServerConfig (..),
    ServerStoreCfg (..),
    SupportedStore,
    StorePaths (..),
    StartOptions (..),
    Env (..),
    Server (..),
    ServerSubscribers (..),
    SubscribedClients,
    ProxyAgent (..),
    Client (..),
    ClientId,
    ClientSub (..),
    Sub (..),
    ServerSub (..),
    SubscriptionThread (..),
    MsgStoreType,
    MsgStore (..),
    AStoreType (..),
    VerifiedTransmission,
    ResponseAndMessage,
    newEnv,
    mkJournalStoreConfig,
    msgStore,
    fromMsgStore,
    newClient,
    getServerClients,
    getServerClient,
    insertServerClient,
    deleteServerClient,
    getSubscribedClients,
    getSubscribedClient,
    upsertSubscribedClient,
    lookupSubscribedClient,
    lookupDeleteSubscribedClient,
    deleteSubcribedClient,
    sameClientId,
    sameClient,
    newSubscription,
    newProhibitedSub,
    defaultMsgQueueQuota,
    defMsgExpirationDays,
    defNtfExpirationHours,
    defaultMessageExpiration,
    defaultNtfExpiration,
    defaultInactiveClientExpiration,
    defaultProxyClientConcurrency,
    defaultNameResolverConcurrency,
    defaultMaxJournalMsgCount,
    defaultMaxJournalStateLines,
    defaultIdleQueueInterval,
    journalMsgStoreDepth,
    readWriteQueueStore,
    noPostgresExitStr,
    noPostgresExit,
    dbStoreCfg,
    storeLogFile',
  )
where

import Control.Concurrent (ThreadId)
import Control.Logger.Simple
import Control.Monad
import qualified Crypto.PubKey.RSA as RSA
import Crypto.Random
import Data.Int (Int64)
import Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IM
import Data.IntSet (IntSet)
import qualified Data.IntSet as IS
import Data.Kind (Constraint)
import Data.List (intercalate)
import Data.List.NonEmpty (NonEmpty)
import Data.Map.Strict (Map)
import Data.Maybe (isJust)
import qualified Data.Text as T
import Data.Time.Clock (getCurrentTime, nominalDay)
import Data.Time.Clock.System (SystemTime)
import qualified Data.X509 as X
import Data.X509.Validation (Fingerprint (..))
import GHC.TypeLits (TypeError)
import qualified GHC.TypeLits as TE
import Network.Socket (ServiceName)
import qualified Network.TLS as T
import Numeric.Natural
import Zero.Messaging.Agent.Lock
import Zero.Messaging.Agent.Store.Shared (MigrationConfirmation (..))
import Zero.Messaging.Client.Agent (SMPClientAgent, SMPClientAgentConfig, newSMPClientAgent)
import Zero.Messaging.Crypto (KeyHash (..))
import qualified Zero.Messaging.Crypto as C
import Zero.Messaging.Protocol
import Zero.Messaging.Server.Expiration
import Zero.Messaging.Server.Information
import Zero.Messaging.Server.MsgStore.Journal
import Zero.Messaging.Server.MsgStore.STM
import Zero.Messaging.Server.MsgStore.Types
import Zero.Messaging.Server.Names (NamesConfig (..), NamesEnv, newNamesEnv, pingEndpoint)
import Zero.Messaging.Server.NtfStore
import Zero.Messaging.Server.QueueStore
import Zero.Messaging.Server.QueueStore.Postgres.Config
import Zero.Messaging.Server.QueueStore.STM (STMQueueStore, setStoreLog)
import Zero.Messaging.Server.QueueStore.Types
import Zero.Messaging.Server.Stats
import Zero.Messaging.Server.StoreLog
import Zero.Messaging.Server.StoreLog.ReadWrite
import Zero.Messaging.SystemTime
import Zero.Messaging.TMap (TMap)
import qualified Zero.Messaging.TMap as TM
import Zero.Messaging.Transport (ASrvTransport, SMPVersion, THandleParams, TransportPeer (..), VersionRangeSMP)
import Zero.Messaging.Transport.Server
import Zero.Messaging.Util (ifM, tshow, whenM, ($>>=))
import System.Directory (doesFileExist)
import System.Exit (exitFailure)
import System.IO (IOMode (..))
import System.Mem.Weak (Weak)
import UnliftIO.STM

#if defined(dbServerPostgres)
import Zero.Messaging.Server.MsgStore.Postgres
#endif

data ServerConfig s = ServerConfig
  { transports :: [(ServiceName, ASrvTransport, AddHTTP)],
    smpHandshakeTimeout :: Int,
    tbqSize :: Natural,
    msgQueueQuota :: Int,
    maxJournalMsgCount :: Int,
    maxJournalStateLines :: Int,
    queueIdBytes :: Int,
    msgIdBytes :: Int,
    serverStoreCfg :: ServerStoreCfg s,
    storeNtfsFile :: Maybe FilePath,
    allowNewQueues :: Bool,
    newQueueBasicAuth :: Maybe BasicAuth,
    controlPortUserAuth :: Maybe BasicAuth,
    controlPortAdminAuth :: Maybe BasicAuth,
    dailyBlockQueueQuota :: Int,
    messageExpiration :: Maybe ExpirationConfig,
    expireMessagesOnStart :: Bool,
    expireMessagesOnSend :: Bool,
    idleQueueInterval :: Int64,
    notificationExpiration :: ExpirationConfig,
    inactiveClientExpiration :: Maybe ExpirationConfig,
    logStatsInterval :: Maybe Int64,
    logStatsStartTime :: Int64,
    serverStatsLogFile :: FilePath,
    serverStatsBackupFile :: Maybe FilePath,
    prometheusInterval :: Maybe Int,
    prometheusMetricsFile :: FilePath,
    ntfDeliveryInterval :: Int,
    pendingENDInterval :: Int,
    smpCredentials :: ServerCredentials,
    httpCredentials :: Maybe ServerCredentials,
    smpServerVRange :: VersionRangeSMP,
    transportConfig :: TransportServerConfig,
    controlPort :: Maybe ServiceName,
    smpAgentCfg :: SMPClientAgentConfig,
    allowSMPProxy :: Bool,
    serverClientConcurrency :: Int,
    serverResolverConcurrency :: Int,
    namesConfig :: Maybe NamesConfig,
    information :: Maybe ServerPublicInfo,
    startOptions :: StartOptions
  }

data StartOptions = StartOptions
  { maintenance :: Bool,
    compactLog :: Bool,
    logLevel :: LogLevel,
    skipWarnings :: Bool,
    confirmMigrations :: MigrationConfirmation
  }

defMsgExpirationDays :: Int64
defMsgExpirationDays = 21

defaultMessageExpiration :: ExpirationConfig
defaultMessageExpiration =
  ExpirationConfig
    { ttl = defMsgExpirationDays * 86400,
      checkInterval = 7200
    }

defaultIdleQueueInterval :: Int64
defaultIdleQueueInterval = 14400

defNtfExpirationHours :: Int64
defNtfExpirationHours = 24

defaultNtfExpiration :: ExpirationConfig
defaultNtfExpiration =
  ExpirationConfig
    { ttl = defNtfExpirationHours * 3600,
      checkInterval = 3600
    }

defaultInactiveClientExpiration :: ExpirationConfig
defaultInactiveClientExpiration =
  ExpirationConfig
    { ttl = 21600,
      checkInterval = 3600
    }

defaultProxyClientConcurrency :: Int
defaultProxyClientConcurrency = 32

defaultNameResolverConcurrency :: Int
defaultNameResolverConcurrency = 1000

journalMsgStoreDepth :: Int
journalMsgStoreDepth = 5

defaultMaxJournalStateLines :: Int
defaultMaxJournalStateLines = 16

defaultMaxJournalMsgCount :: Int
defaultMaxJournalMsgCount = 256

defaultMsgQueueQuota :: Int
defaultMsgQueueQuota = 128

defaultStateTailSize :: Int
defaultStateTailSize = 512

data Env s = Env
  { config :: ServerConfig s,
    serverActive :: TVar Bool,
    serverInfo :: ServerInformation,
    server :: Server s,
    serverIdentity :: KeyHash,
    msgStore_ :: MsgStore s,
    ntfStore :: NtfStore,
    random :: TVar ChaChaDRG,
    tlsServerCreds :: T.Credential,
    httpServerCreds :: Maybe T.Credential,
    serverStats :: ServerStats,
    sockets :: TVar [(ServiceName, SocketState)],
    clientSeq :: TVar ClientId,
    proxyAgent :: ProxyAgent,
    namesEnv :: Maybe NamesEnv
  }

msgStore :: Env s -> s
msgStore = fromMsgStore . msgStore_
{-# INLINE msgStore #-}

fromMsgStore :: MsgStore s -> s
fromMsgStore = \case
  StoreMemory s -> s
  StoreJournal s -> s
#if defined(dbServerPostgres)
  StoreDatabase s -> s
#endif
{-# INLINE fromMsgStore #-}

type family SupportedStore (qs :: QSType) (ms :: MSType) :: Constraint where
  SupportedStore 'QSMemory 'MSMemory = ()
  SupportedStore 'QSMemory 'MSJournal = ()
  SupportedStore 'QSMemory 'MSPostgres =
    (Int ~ Bool, TypeError ('TE.Text "Storing messages in Postgres DB with queues in memory is not supported"))
  SupportedStore 'QSPostgres 'MSMemory =
    (Int ~ Bool, TypeError ('TE.Text "Storing messages in memory with queues in Postgres DB is not supported"))
  SupportedStore 'QSPostgres 'MSJournal = ()
#if defined(dbServerPostgres)
  SupportedStore 'QSPostgres 'MSPostgres = ()
#else
  SupportedStore 'QSPostgres 'MSPostgres =
    (Int ~ Bool, TypeError ('TE.Text "Server compiled without server_postgres flag"))
#endif

data AStoreType =
  forall qs ms. (SupportedStore qs ms, MsgStoreClass (MsgStoreType qs ms)) =>
  ASType (SQSType qs) (SMSType ms)

data ServerStoreCfg s where
  SSCMemory :: Maybe StorePaths -> ServerStoreCfg STMMsgStore
  SSCMemoryJournal :: {storeLogFile :: FilePath, storeMsgsPath :: FilePath} -> ServerStoreCfg (JournalMsgStore 'QSMemory)
  SSCDatabaseJournal :: {storeCfg :: PostgresStoreCfg, storeMsgsPath' :: FilePath} -> ServerStoreCfg (JournalMsgStore 'QSPostgres)
#if defined(dbServerPostgres)
  SSCDatabase :: PostgresStoreCfg -> ServerStoreCfg PostgresMsgStore
#endif

dbStoreCfg :: ServerStoreCfg s -> Maybe PostgresStoreCfg
dbStoreCfg = \case
  SSCMemory _ -> Nothing
  SSCMemoryJournal {} -> Nothing
  SSCDatabaseJournal {storeCfg} -> Just storeCfg
#if defined(dbServerPostgres)
  SSCDatabase cfg -> Just cfg
#endif

storeLogFile' :: ServerStoreCfg s -> Maybe FilePath
storeLogFile' = \case
  SSCMemory sp_ -> (\StorePaths {storeLogFile} -> storeLogFile) <$> sp_
  SSCMemoryJournal {storeLogFile} -> Just storeLogFile
  SSCDatabaseJournal {storeCfg = PostgresStoreCfg {dbStoreLogPath}} -> dbStoreLogPath
#if defined(dbServerPostgres)
  SSCDatabase (PostgresStoreCfg {dbStoreLogPath}) -> dbStoreLogPath
#endif

data StorePaths = StorePaths {storeLogFile :: FilePath, storeMsgsFile :: Maybe FilePath}

type family MsgStoreType (qs :: QSType) (ms :: MSType) where
  MsgStoreType 'QSMemory 'MSMemory = STMMsgStore
  MsgStoreType qs 'MSJournal = JournalMsgStore qs
#if defined(dbServerPostgres)
  MsgStoreType 'QSPostgres 'MSPostgres = PostgresMsgStore
#endif

data MsgStore s where
  StoreMemory :: STMMsgStore -> MsgStore STMMsgStore
  StoreJournal :: JournalMsgStore qs -> MsgStore (JournalMsgStore qs)
#if defined(dbServerPostgres)
  StoreDatabase :: PostgresMsgStore -> MsgStore PostgresMsgStore
#endif

data Server s = Server
  { clients :: ServerClients s,
    subscribers :: ServerSubscribers s,
    ntfSubscribers :: ServerSubscribers s,
    savingLock :: Lock
  }

newtype ServerClients s = ServerClients {serverClients :: TVar (IntMap (Client s))}

data ServerSubscribers s = ServerSubscribers
  { subQ :: TQueue (ClientSub, ClientId),
    queueSubscribers :: SubscribedClients s,
    serviceSubscribers :: SubscribedClients s,
    totalServiceSubs :: TVar (Int64, IdsHash),
    subClients :: TVar IntSet,
    pendingEvents :: TVar (IntMap (NonEmpty (EntityId, BrokerMsg)))
  }

data SubscribedClients s = SubscribedClients (TMap EntityId (TVar (Maybe (Client s))))

getSubscribedClients :: SubscribedClients s -> IO (Map EntityId (TVar (Maybe (Client s))))
getSubscribedClients (SubscribedClients cs) = readTVarIO cs

getSubscribedClient :: EntityId -> SubscribedClients s -> IO (Maybe (TVar (Maybe (Client s))))
getSubscribedClient entId (SubscribedClients cs) = TM.lookupIO entId cs
{-# INLINE getSubscribedClient #-}

upsertSubscribedClient :: EntityId -> Client s -> SubscribedClients s -> STM (Maybe (Client s))
upsertSubscribedClient entId c (SubscribedClients cs) =
  TM.lookup entId cs >>= \case
    Nothing -> Nothing <$ TM.insertM entId (newTVar (Just c)) cs
    Just cv ->
      readTVar cv >>= \case
        Just c' | sameClientId c c' -> pure Nothing
        c_ -> c_ <$ writeTVar cv (Just c)

lookupSubscribedClient :: EntityId -> SubscribedClients s -> STM (Maybe (Client s))
lookupSubscribedClient entId (SubscribedClients cs) = TM.lookup entId cs $>>= readTVar
{-# INLINE lookupSubscribedClient #-}

lookupDeleteSubscribedClient :: EntityId -> SubscribedClients s -> STM (Maybe (Client s))
lookupDeleteSubscribedClient entId (SubscribedClients cs) =
  TM.lookupDelete entId cs $>>= (`swapTVar` Nothing)
{-# INLINE lookupDeleteSubscribedClient #-}

deleteSubcribedClient :: EntityId -> Client s -> SubscribedClients s -> IO ()
deleteSubcribedClient entId c (SubscribedClients cs) =
  TM.lookupIO entId cs >>= mapM_ (\cv -> atomically $ whenM (sameClient c cv) $ delete cv)
  where
    delete cv = do
      writeTVar cv Nothing
      TM.delete entId cs

sameClientId :: Client s -> (Client s) -> Bool
sameClientId c c' = clientId c == clientId c'
{-# INLINE sameClientId #-}

sameClient :: Client s -> TVar (Maybe (Client s)) -> STM Bool
sameClient c cv = maybe False (sameClientId c) <$> readTVar cv
{-# INLINE sameClient #-}

data ClientSub
  = CSClient QueueId (Maybe ServiceId) (Maybe ServiceId)
  | CSDeleted QueueId (Maybe ServiceId)
  | CSService ServiceId (Int64, IdsHash)

newtype ProxyAgent = ProxyAgent
  { smpAgent :: SMPClientAgent 'Sender
  }

type ClientId = Int

data Client s = Client
  { clientId :: ClientId,
    subscriptions :: TMap RecipientId Sub,
    ntfSubscriptions :: TMap NotifierId (),
    serviceSubscribed :: TVar Bool,
    ntfServiceSubscribed :: TVar Bool,
    serviceSubsCount :: TVar (Int64, IdsHash),
    ntfServiceSubsCount :: TVar (Int64, IdsHash),
    rcvQ :: TBQueue (NonEmpty (VerifiedTransmission s)),
    sndQ :: TBQueue (NonEmpty (Transmission BrokerMsg), [Transmission BrokerMsg]),
    msgQ :: TBQueue (NonEmpty (Transmission BrokerMsg)),
    procThreads :: TVar Int,
    endThreads :: TVar (IntMap (Weak ThreadId)),
    endThreadSeq :: TVar Int,
    clientTHParams :: THandleParams SMPVersion 'TServer,
    connected :: TVar Bool,
    createdAt :: SystemTime,
    rcvActiveAt :: TVar SystemTime,
    sndActiveAt :: TVar SystemTime
  }

type VerifiedTransmission s = (Maybe (StoreQueue s, QueueRec), Transmission Cmd)

type ResponseAndMessage = (Transmission BrokerMsg, Maybe (Transmission BrokerMsg))

data ServerSub = ServerSub (TVar SubscriptionThread) | ProhibitSub

data SubscriptionThread = NoSub | SubPending | SubThread (Weak ThreadId)

data Sub = Sub
  { subThread :: ServerSub,
    delivered :: TVar (Maybe (MsgId, SystemSeconds))
  }

newServer :: IO (Server s)
newServer = do
  clients <- ServerClients <$> newTVarIO mempty
  subscribers <- newServerSubscribers
  ntfSubscribers <- newServerSubscribers
  savingLock <- createLockIO
  return Server {clients, subscribers, ntfSubscribers, savingLock}

getServerClients :: Server s -> IO (IntMap (Client s))
getServerClients = readTVarIO . serverClients . clients
{-# INLINE getServerClients #-}

getServerClient :: ClientId -> Server s -> IO (Maybe (Client s))
getServerClient cId s = IM.lookup cId <$> getServerClients s
{-# INLINE getServerClient #-}

insertServerClient :: Client s -> Server s -> IO Bool
insertServerClient c@Client {clientId, connected} Server {clients} =
  atomically $
    ifM
      (readTVar connected)
      (True <$ modifyTVar' (serverClients clients) (IM.insert clientId c))
      (pure False)
{-# INLINE insertServerClient #-}

deleteServerClient :: ClientId -> Server s -> IO ()
deleteServerClient cId Server {clients} = atomically $ modifyTVar' (serverClients clients) $ IM.delete cId
{-# INLINE deleteServerClient #-}

newServerSubscribers :: IO (ServerSubscribers s)
newServerSubscribers = do
  subQ <- newTQueueIO
  queueSubscribers <- SubscribedClients <$> TM.emptyIO
  serviceSubscribers <- SubscribedClients <$> TM.emptyIO
  totalServiceSubs <- newTVarIO (0, mempty)
  subClients <- newTVarIO IS.empty
  pendingEvents <- newTVarIO IM.empty
  pure ServerSubscribers {subQ, queueSubscribers, serviceSubscribers, totalServiceSubs, subClients, pendingEvents}

newClient :: ClientId -> Natural -> THandleParams SMPVersion 'TServer -> SystemTime -> IO (Client s)
newClient clientId qSize clientTHParams createdAt = do
  subscriptions <- TM.emptyIO
  ntfSubscriptions <- TM.emptyIO
  serviceSubscribed <- newTVarIO False
  ntfServiceSubscribed <- newTVarIO False
  serviceSubsCount <- newTVarIO (0, mempty)
  ntfServiceSubsCount <- newTVarIO (0, mempty)
  rcvQ <- newTBQueueIO qSize
  sndQ <- newTBQueueIO qSize
  msgQ <- newTBQueueIO qSize
  procThreads <- newTVarIO 0
  endThreads <- newTVarIO IM.empty
  endThreadSeq <- newTVarIO 0
  connected <- newTVarIO True
  rcvActiveAt <- newTVarIO createdAt
  sndActiveAt <- newTVarIO createdAt
  return
    Client
      { clientId,
        subscriptions,
        ntfSubscriptions,
        serviceSubscribed,
        ntfServiceSubscribed,
        serviceSubsCount,
        ntfServiceSubsCount,
        rcvQ,
        sndQ,
        msgQ,
        procThreads,
        endThreads,
        endThreadSeq,
        clientTHParams,
        connected,
        createdAt,
        rcvActiveAt,
        sndActiveAt
      }

newSubscription :: SubscriptionThread -> STM Sub
newSubscription st = do
  delivered <- newTVar Nothing
  subThread <- ServerSub <$> newTVar st
  return Sub {subThread, delivered}

newProhibitedSub :: STM Sub
newProhibitedSub = do
  delivered <- newTVar Nothing
  return Sub {subThread = ProhibitSub, delivered}

newEnv :: ServerConfig s -> IO (Env s)
newEnv config@ServerConfig {smpCredentials, httpCredentials, serverStoreCfg, smpAgentCfg, information, messageExpiration, idleQueueInterval, msgQueueQuota, maxJournalMsgCount, maxJournalStateLines, namesConfig} = do
  serverActive <- newTVarIO True
  server <- newServer
  msgStore_ <- case serverStoreCfg of
    SSCMemory storePaths_ -> do
      let storePath = storeMsgsFile =<< storePaths_
      ms <- newMsgStore STMStoreConfig {storePath, quota = msgQueueQuota}
      forM_ storePaths_ $ \StorePaths {storeLogFile = f} -> loadStoreLog (mkQueue ms True) f $ queueStore ms
      pure $ StoreMemory ms
    SSCMemoryJournal {storeLogFile, storeMsgsPath} -> do
      logWarn $
        "Journal message store is deprecated and will be removed soon.\n"
          <> "Please migrate to in-memory storage using `journal export` command.\n"
          <> "After that you can migrate to PostgreSQL using `database import` command."
      let qsCfg = MQStoreCfg
          cfg = mkJournalStoreConfig qsCfg storeMsgsPath msgQueueQuota maxJournalMsgCount maxJournalStateLines idleQueueInterval
      ms <- newMsgStore cfg
      loadStoreLog (mkQueue ms True) storeLogFile $ stmQueueStore ms
      pure $ StoreJournal ms
#if defined(dbServerPostgres)
    SSCDatabaseJournal {storeCfg, storeMsgsPath'} -> do
      let StartOptions {compactLog, confirmMigrations} = startOptions config
          qsCfg = PQStoreCfg (storeCfg {confirmMigrations} :: PostgresStoreCfg)
          cfg = mkJournalStoreConfig qsCfg storeMsgsPath' msgQueueQuota maxJournalMsgCount maxJournalStateLines idleQueueInterval
      when compactLog $ compactDbStoreLog $ dbStoreLogPath storeCfg
      StoreJournal <$> newMsgStore cfg
    SSCDatabase storeCfg -> do
      let StartOptions {compactLog, confirmMigrations} = startOptions config
          cfg = PostgresMsgStoreCfg storeCfg {confirmMigrations} msgQueueQuota
      when compactLog $ compactDbStoreLog $ dbStoreLogPath storeCfg
      StoreDatabase <$> newMsgStore cfg
#else
    SSCDatabaseJournal {} -> noPostgresExit
#endif
  ntfStore <- NtfStore <$> TM.emptyIO
  random <- C.newRandom
  tlsServerCreds <- getCredentials "SMP" smpCredentials
  httpServerCreds <- mapM (getCredentials "HTTPS") httpCredentials
  mapM_ checkHTTPSCredentials httpServerCreds
  Fingerprint fp <- loadFingerprint smpCredentials
  let serverIdentity = KeyHash fp
  serverStats <- newServerStats =<< getCurrentTime
  sockets <- newTVarIO []
  clientSeq <- newTVarIO 0
  proxyAgent <- newSMPProxyAgent smpAgentCfg random
  namesEnv <- forM namesConfig $ \nc -> do
    logInfo $ "[NAMES] resolver enabled, endpoint=" <> T.pack (resolverEndpoint nc)
    env <- newNamesEnv nc
    pingEndpoint env >>= \case
      Right _ -> logInfo "[NAMES] endpoint probe ok"
      Left e -> logWarn $ "[NAMES] endpoint probe failed (server will still start, RSLV will return ERR (NAME ...) until reachable): " <> tshow e
    pure env
  pure
    Env
      { serverActive,
        config,
        serverInfo,
        server,
        serverIdentity,
        msgStore_,
        ntfStore,
        random,
        tlsServerCreds,
        httpServerCreds,
        serverStats,
        sockets,
        clientSeq,
        proxyAgent,
        namesEnv
      }
  where
    loadStoreLog :: StoreQueueClass q => (RecipientId -> QueueRec -> IO q) -> FilePath -> STMQueueStore q -> IO ()
    loadStoreLog mkQ f st = do
      logNote $ "restoring queues from file " <> T.pack f
      sl <- readWriteQueueStore False mkQ f st
      setStoreLog st sl
#if defined(dbServerPostgres)
    compactDbStoreLog = \case
      Just f -> do
        logNote $ "compacting queues in file " <> T.pack f
        st <- newMsgStore STMStoreConfig {storePath = Nothing, quota = msgQueueQuota}
        sl <- readWriteQueueStore False (mkQueue st False) f (queueStore st)
        setStoreLog (queueStore st) sl
        closeMsgStore st
      Nothing -> do
        logError "Error: `--compact-log` used without `db_store_log` INI option"
        exitFailure
#endif
    getCredentials protocol creds = do
      files <- missingCreds
      unless (null files) $ do
        putStrLn $ "----------\nError: no " <> protocol <> " credentials: " <> intercalate ", " files
        when (protocol == "HTTPS") $ do
          putStrLn "Server should serve static pages to show connection links in the browser."
          putStrLn letsEncrypt
        exitFailure
      loadServerCredential creds
      where
        missingfile f = (\y -> [f | not y]) <$> doesFileExist f
        missingCreds = do
          let files = maybe id (:) (caCertificateFile creds) [certificateFile creds, privateKeyFile creds]
           in concat <$> mapM missingfile files
    checkHTTPSCredentials (X.CertificateChain cc, _k) =
      case map (X.signedObject . X.getSigned) cc of
        X.Certificate {X.certPubKey = X.PubKeyRSA rsa} : _ca | RSA.public_size rsa >= 512 -> pure ()
        _ -> do
          putStrLn $ "Error: unsupported HTTPS credentials, required 4096-bit RSA\n" <> letsEncrypt
          exitFailure
    letsEncrypt = "Use Let's Encrypt to generate: certbot certonly --standalone -d yourdomainname --key-type rsa --rsa-key-size 4096\n----------"
    serverInfo =
      ServerInformation
        { information,
          config =
            ServerPublicConfig
              { persistence,
                messageExpiration = ttl <$> messageExpiration,
                statsEnabled = isJust $ logStatsInterval config,
                newQueuesAllowed = allowNewQueues config,
                basicAuthEnabled = isJust $ newQueueBasicAuth config
              }
        }
      where
        persistence = case serverStoreCfg of
          SSCMemory sp_ -> case sp_ of
            Nothing -> SPMMemoryOnly
            Just StorePaths {storeMsgsFile = Just _} -> SPMMessages
            _ -> SPMQueues
          _ -> SPMMessages

noPostgresExit :: IO a
noPostgresExit = putStrLn noPostgresExitStr >> exitFailure

noPostgresExitStr :: String
noPostgresExitStr =
  "Error: server binary is compiled without support for PostgreSQL database.\n"
    <> "Please download `smp-server-postgres` or re-compile with `cabal build -fserver_postgres`."

mkJournalStoreConfig :: QStoreCfg s -> FilePath -> Int -> Int -> Int -> Int64 -> JournalStoreConfig s
mkJournalStoreConfig queueStoreCfg storePath msgQueueQuota maxJournalMsgCount maxJournalStateLines idleQueueInterval =
  JournalStoreConfig
    { storePath,
      quota = msgQueueQuota,
      pathParts = journalMsgStoreDepth,
      queueStoreCfg,
      maxMsgCount = maxJournalMsgCount,
      maxStateLines = maxJournalStateLines,
      stateTailSize = defaultStateTailSize,
      idleInterval = idleQueueInterval,
      expireBackupsAfter = 14 * nominalDay,
      keepMinBackups = 2
    }

newSMPProxyAgent :: SMPClientAgentConfig -> TVar ChaChaDRG -> IO ProxyAgent
newSMPProxyAgent smpAgentCfg random = do
  smpAgent <- newSMPClientAgent SSender smpAgentCfg Nothing random
  pure ProxyAgent {smpAgent}

readWriteQueueStore :: forall q. StoreQueueClass q => Bool -> (RecipientId -> QueueRec -> IO q) -> FilePath -> STMQueueStore q -> IO (StoreLog 'WriteMode)
readWriteQueueStore tty mkQ = readWriteStoreLog (readQueueStore tty mkQ) (writeQueueStore @q)
