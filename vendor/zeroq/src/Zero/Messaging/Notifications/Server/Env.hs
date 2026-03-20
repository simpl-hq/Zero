{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}

module Zero.Messaging.Notifications.Server.Env
  ( NtfServerConfig (..),
    NtfEnv (..),
    NtfSubscriber (..),
    SMPSubscriberVar,
    SMPSubscriber (..),
    NtfPushServer (..),
    PushClientVar,
    PushWorker (..),
    PushWorkerVar,
    NtfRequest (..),
    NtfServerClient (..),
    defaultInactiveClientExpiration,
    newNtfServerEnv,
    newNtfSubscriber,
    newNtfPushServer,
    getPushClient,
    newNtfServerClient,
  ) where

import Control.Concurrent (ThreadId)
import qualified Control.Exception as E
import Control.Logger.Simple
import Control.Monad
import Control.Monad.Except
import Control.Monad.Trans.Except
import Crypto.Random
import Data.Functor (($>))
import Data.Int (Int64)
import Zero.Messaging.Agent.RetryInterval
import Data.List.NonEmpty (NonEmpty)
import qualified Data.Text as T
import Data.Time.Clock (getCurrentTime)
import Data.Time.Clock.System (SystemTime)
import qualified Data.X509.Validation as XV
import Network.Socket
import qualified Network.TLS as TLS
import Numeric.Natural
import Zero.Messaging.Client (ProtocolClientError (..), SMPClientError)
import Zero.Messaging.Client.Agent
import qualified Zero.Messaging.Crypto as C
import Zero.Messaging.Notifications.Protocol
import Zero.Messaging.Notifications.Server.Push.APNS
import Zero.Messaging.Notifications.Server.Stats
import Zero.Messaging.Notifications.Server.Store.Postgres
import Zero.Messaging.Notifications.Server.Store.Types
import Zero.Messaging.Notifications.Transport (NTFVersion, VersionRangeNTF)
import Zero.Messaging.Protocol (BasicAuth, CorrId, Party (..), SMPServer, SParty (..), ServiceId, Transmission)
import Zero.Messaging.Server.Env.STM (StartOptions (..))
import Zero.Messaging.Server.Expiration
import Zero.Messaging.Server.QueueStore.Postgres.Config (PostgresStoreCfg (..))
import Zero.Messaging.Session
import Zero.Messaging.TMap (TMap)
import qualified Zero.Messaging.TMap as TM
import Zero.Messaging.Transport (ASrvTransport, SMPServiceRole (..), ServiceCredentials (..), THandleParams, TransportPeer (..))
import Zero.Messaging.Transport.Credentials (genCredentials, tlsCredentials)
import Zero.Messaging.Transport.Server (AddHTTP, ServerCredentials, TransportServerConfig, loadFingerprint, loadServerCredential)
import Zero.Messaging.Util (liftEitherWith, tshow)
import Zero.Messaging.Util ()
import System.Exit (exitFailure)
import System.Mem.Weak (Weak)
import UnliftIO.STM

data NtfServerConfig = NtfServerConfig
  { transports :: [(ServiceName, ASrvTransport, AddHTTP)],
    controlPort :: Maybe ServiceName,
    controlPortUserAuth :: Maybe BasicAuth,
    controlPortAdminAuth :: Maybe BasicAuth,
    subIdBytes :: Int,
    regCodeBytes :: Int,
    clientQSize :: Natural,
    pushQSize :: Natural,
    smpAgentCfg :: SMPClientAgentConfig,
    apnsConfig :: APNSPushClientConfig,
    allowTestPushProvider :: Bool,
    subsBatchSize :: Int,
    inactiveClientExpiration :: Maybe ExpirationConfig,
    dbStoreConfig :: PostgresStoreCfg,
    ntfCredentials :: ServerCredentials,
    useServiceCreds :: Bool,
    periodicNtfsInterval :: Int,
    logStatsInterval :: Maybe Int64,
    logStatsStartTime :: Int64,
    serverStatsLogFile :: FilePath,
    serverStatsBackupFile :: Maybe FilePath,
    prometheusInterval :: Maybe Int,
    prometheusMetricsFile :: FilePath,
    ntfServerVRange :: VersionRangeNTF,
    transportConfig :: TransportServerConfig,
    startOptions :: StartOptions
  }

defaultInactiveClientExpiration :: ExpirationConfig
defaultInactiveClientExpiration =
  ExpirationConfig
    { ttl = 43200,
      checkInterval = 3600
    }

data NtfEnv = NtfEnv
  { config :: NtfServerConfig,
    subscriber :: NtfSubscriber,
    pushServer :: NtfPushServer,
    store :: NtfPostgresStore,
    random :: TVar ChaChaDRG,
    tlsServerCreds :: TLS.Credential,
    serverIdentity :: C.KeyHash,
    serverStats :: NtfServerStats
  }

newNtfServerEnv :: NtfServerConfig -> IO NtfEnv
newNtfServerEnv config@NtfServerConfig {pushQSize, smpAgentCfg, apnsConfig, dbStoreConfig, ntfCredentials, useServiceCreds} = do
  random <- C.newRandom
  store <- newNtfDbStore dbStoreConfig
  tlsServerCreds <- loadServerCredential ntfCredentials
  XV.Fingerprint fp <- loadFingerprint ntfCredentials
  let dbService = if useServiceCreds then Just $ mkDbService random store else Nothing
  subscriber <- newNtfSubscriber smpAgentCfg dbService random
  pushServer <- newNtfPushServer pushQSize apnsConfig
  serverStats <- newNtfServerStats =<< getCurrentTime
  pure NtfEnv {config, subscriber, pushServer, store, random, tlsServerCreds, serverIdentity = C.KeyHash fp, serverStats}
  where
    mkDbService g st = DBService {getCredentials, updateServiceId}
      where
        getCredentials :: SMPServer -> IO (Either SMPClientError ServiceCredentials)
        getCredentials srv = runExceptT $ do
          ExceptT (withClientDB "" st $ \db -> getNtfServiceCredentials db srv >>= mapM (mkServiceCreds db)) >>= \case
            Just (C.KeyHash kh, serviceCreds) -> do
              serviceSignKey <- liftEitherWith PCEIOError $ C.x509ToPrivate' $ snd serviceCreds
              pure ServiceCredentials {serviceRole = SRNotifier, serviceCreds, serviceCertHash = XV.Fingerprint kh, serviceSignKey}
            Nothing -> throwE PCEServiceUnavailable
        mkServiceCreds db = \case
          (_, Just tlsCreds) -> pure tlsCreds
          (srvId, Nothing) -> do
            cred <- genCredentials g Nothing (25, 24 * 999999) "zero"
            let tlsCreds = tlsCredentials [cred]
            setNtfServiceCredentials db srvId tlsCreds
            pure tlsCreds
        updateServiceId :: SMPServer -> Maybe ServiceId -> IO (Either SMPClientError ())
        updateServiceId srv serviceId_ = withClientDB "" st $ \db -> updateNtfServiceId db srv serviceId_

data NtfSubscriber = NtfSubscriber
  { smpSubscribers :: TMap SMPServer SMPSubscriberVar,
    subscriberSeq :: TVar Int,
    smpAgent :: SMPClientAgent 'NotifierService
  }

type SMPSubscriberVar = SessionVar SMPSubscriber

newNtfSubscriber :: SMPClientAgentConfig -> Maybe DBService -> TVar ChaChaDRG -> IO NtfSubscriber
newNtfSubscriber smpAgentCfg dbService random = do
  smpSubscribers <- TM.emptyIO
  subscriberSeq <- newTVarIO 0
  smpAgent <- newSMPClientAgent SNotifierService smpAgentCfg dbService random
  pure NtfSubscriber {smpSubscribers, subscriberSeq, smpAgent}

data SMPSubscriber = SMPSubscriber
  { smpServer :: SMPServer,
    smpServerId :: Int64,
    subscriberSubQ :: TQueue ServerNtfSub,
    subThreadId :: Weak ThreadId
  }

data NtfPushServer = NtfPushServer
  { pushWorkers :: TMap (Maybe T.Text, PushProvider) PushWorkerVar,
    pushWorkerSeq :: TVar Int,
    pushQSize :: Natural,
    pushClients :: TMap PushProvider PushClientVar,
    pushClientSeq :: TVar Int,
    apnsConfig :: APNSPushClientConfig
  }

data PushWorker = PushWorker
  { workerQ :: TBQueue (NtfTknRec, PushNotification),
    workerThreadId :: Weak ThreadId
  }

type PushWorkerVar = SessionVar PushWorker

type PushClientVar = SessionVar (Either E.SomeException PushProviderClient)

newNtfPushServer :: Natural -> APNSPushClientConfig -> IO NtfPushServer
newNtfPushServer pushQSize apnsConfig = do
  pushWorkers <- TM.emptyIO
  pushWorkerSeq <- newTVarIO 0
  pushClients <- TM.emptyIO
  pushClientSeq <- newTVarIO 0
  pure NtfPushServer {pushWorkers, pushWorkerSeq, pushQSize, pushClients, pushClientSeq, apnsConfig}

getPushClient :: NtfPushServer -> PushProvider -> IO (PushProviderClient, PushClientVar)
getPushClient s@NtfPushServer {apnsConfig = APNSPushClientConfig {reconnectInterval}} pp =
  withRetryIntervalCount reconnectInterval $ \n _delay loop -> do
    ts <- getCurrentTime
    E.try (atomically (getSessVar (pushClientSeq s) pp (pushClients s) ts) >>= either (newPushClient s pp) waitForPushClient) >>= \case
      Right result -> pure result
      Left e
        | n < 2 -> do
            logError $ "getPushClient error (" <> tshow pp <> "): " <> tshow (e :: E.SomeException)
            loop
        | otherwise -> E.throwIO e

newPushClient :: NtfPushServer -> PushProvider -> PushClientVar -> IO (PushProviderClient, PushClientVar)
newPushClient NtfPushServer {pushClients, apnsConfig} pp v = do
  r <- E.try $ case apnsProviderHost pp of
    Nothing -> pure $ \_ _ -> pure ()
    Just host -> apnsPushProviderClient <$> createAPNSPushClient host apnsConfig
  atomically $ do
    putTMVar (sessionVar v) r
    case r of
      Left _ -> removeSessVar v pp pushClients
      Right _ -> pure ()
  either E.throwIO (\c -> pure (c, v)) r

waitForPushClient :: PushClientVar -> IO (PushProviderClient, PushClientVar)
waitForPushClient v =
  atomically (readTMVar $ sessionVar v) >>= either E.throwIO (\c -> pure (c, v))

data NtfRequest
  = NtfReqNew CorrId ANewNtfEntity
  | forall e. NtfEntityI e => NtfReqCmd (SNtfEntity e) (NtfEntityRec e) (Transmission (NtfCommand e))
  | NtfReqPing CorrId NtfEntityId

data NtfServerClient = NtfServerClient
  { rcvQ :: TBQueue (NonEmpty NtfRequest),
    sndQ :: TBQueue (NonEmpty (Transmission NtfResponse)),
    ntfThParams :: THandleParams NTFVersion 'TServer,
    connected :: TVar Bool,
    rcvActiveAt :: TVar SystemTime,
    sndActiveAt :: TVar SystemTime
  }

newNtfServerClient :: Natural -> THandleParams NTFVersion 'TServer -> SystemTime -> IO NtfServerClient
newNtfServerClient qSize ntfThParams ts = do
  rcvQ <- newTBQueueIO qSize
  sndQ <- newTBQueueIO qSize
  connected <- newTVarIO True
  rcvActiveAt <- newTVarIO ts
  sndActiveAt <- newTVarIO ts
  return NtfServerClient {rcvQ, sndQ, ntfThParams, connected, rcvActiveAt, sndActiveAt}
