{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeApplications #-}

module Zero.Messaging.Client
  (
    TransportSession,
    SMPTransportSession,
    ProtocolClient (thParams, sessionTs),
    SMPClient,
    ProxiedRelay (..),
    getProtocolClient,
    closeProtocolClient,
    protocolClientServer,
    protocolClientServer',
    transportHost',
    transportSession',
    useWebPort,
    isPresetDomain,

    createSMPQueue,
    subscribeSMPQueue,
    subscribeSMPQueues,
    streamSubscribeSMPQueues,
    getSMPMessage,
    subscribeSMPQueueNotifications,
    subscribeSMPQueuesNtfs,
    subscribeService,
    smpClientService,
    smpClientServiceId,
    secureSMPQueue,
    secureSndSMPQueue,
    proxySecureSndSMPQueue,
    addSMPQueueLink,
    deleteSMPQueueLink,
    secureGetSMPQueueLink,
    proxySecureGetSMPQueueLink,
    getSMPQueueLink,
    proxyGetSMPQueueLink,
    enableSMPQueueNotifications,
    disableSMPQueueNotifications,
    enableSMPQueuesNtfs,
    disableSMPQueuesNtfs,
    sendSMPMessage,
    ackSMPMessage,
    suspendSMPQueue,
    deleteSMPQueue,
    deleteSMPQueues,
    connectSMPProxiedRelay,
    proxySMPMessage,
    proxyResolveName,
    directResolveName,
    forwardSMPTransmission,
    getSMPQueueInfo,
    sendProtocolCommand,
    sendProtocolCommands,

    ProtocolClientError (..),
    SMPClientError,
    ProxyClientError (..),
    Response (..),
    unexpectedResponse,
    ProtocolClientConfig (..),
    NetworkConfig (..),
    NetworkTimeout (..),
    NetworkRequestMode (..),
    pattern NRMInteractive,
    TransportSessionMode (..),
    HostMode (..),
    SocksMode (..),
    SMPProxyMode (..),
    SMPProxyFallback (..),
    SMPWebPortServers (..),
    netTimeoutInt,
    defaultClientConfig,
    defaultSMPClientConfig,
    defaultNetworkConfig,
    transportClientConfig,
    clientSocksCredentials,
    chooseTransportHost,
    temporaryClientError,
    smpClientServiceError,
    smpProxyError,
    smpErrorClientNotice,
    textToHostMode,
    clientHandlers,
    ServerTransmissionBatch,
    ServerTransmission (..),
    ClientCommand,

    PCTransmission,
    mkTransmission,
    authTransmission,
    smpClientStub,

    TBQueueInfo (..),
    getTBQueueInfo,
    getProtocolClientQueuesInfo,
    nonBlockingWriteTBQueue,
  )
where

import Control.Applicative ((<|>))
import Control.Concurrent (ThreadId, forkFinally, forkIO, killThread, mkWeakThreadId)
import Control.Concurrent.Async
import Control.Concurrent.STM
import Control.Exception (Exception, Handler (..), IOException, SomeAsyncException, SomeException)
import qualified Control.Exception as E
import Control.Logger.Simple
import Control.Monad
import Control.Monad.Except
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except
import Crypto.Random (ChaChaDRG)
import qualified Data.Aeson.TH as J
import qualified Data.Attoparsec.ByteString.Char8 as A
import Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Base64 as B64
import Data.Functor (($>))
import Data.Int (Int64)
import Data.List (find, isSuffixOf)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as L
import Data.Maybe (catMaybes, fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime (..), diffUTCTime, getCurrentTime)
import qualified Data.X509 as X
import qualified Data.X509.Validation as XV
import Network.Socket (HostName, ServiceName)
import Network.Socks5 (SocksCredentials (..))
import Numeric.Natural
import qualified Zero.Messaging.Crypto as C
import Zero.Messaging.Encoding
import Zero.Messaging.Encoding.String
import Zero.Messaging.Parsers (defaultJSON, dropPrefix, enumJSON, sumTypeJSON)
import Zero.Messaging.Protocol
import Zero.Messaging.Protocol.Types
import Zero.Messaging.Server.QueueStore.QueueInfo
import Zero.Messaging.ZeroName (ZeroDomain)
import Zero.Messaging.TMap (TMap)
import qualified Zero.Messaging.TMap as TM
import Zero.Messaging.Transport
import Zero.Messaging.Transport.Client (SocksAuth (..), SocksProxyWithAuth (..), TransportClientConfig (..), TransportHost (..), defaultSMPPort, runTransportClient)
import Zero.Messaging.Transport.HTTP2 (httpALPN11)
import Zero.Messaging.Transport.KeepAlive
import Zero.Messaging.Transport.Shared (ChainCertificates (..), chainIdCaCerts, x509validate)
import Zero.Messaging.Util
import Zero.Messaging.Version
import System.Mem.Weak (Weak, deRefWeak)
import System.Timeout (timeout)

data ProtocolClient v err msg = ProtocolClient
  { action :: Maybe (Weak ThreadId),
    thParams :: THandleParams v 'TClient,
    sessionTs :: UTCTime,
    client_ :: PClient v err msg
  }

data PClient v err msg = PClient
  { connected :: TVar Bool,
    transportSession :: TransportSession msg,
    transportHost :: TransportHost,
    tcpConnectTimeout :: NetworkTimeout,
    tcpTimeout :: NetworkTimeout,
    sendPings :: TVar Bool,
    lastReceived :: TVar UTCTime,
    timeoutErrorCount :: TVar Int,
    clientCorrId :: TVar ChaChaDRG,
    sentCommands :: TMap CorrId (Request err msg),
    sndQ :: TBQueue (Maybe (Request err msg), ByteString),
    rcvQ :: TBQueue (NonEmpty (Transmission (Either err msg))),
    msgQ :: Maybe (TBQueue (ServerTransmissionBatch v err msg))
  }

smpClientStub :: TVar ChaChaDRG -> ByteString -> VersionSMP -> Maybe (THandleAuth 'TClient) -> IO SMPClient
smpClientStub g sessionId thVersion thAuth = do
  let ts = UTCTime (read "2024-03-31") 0
  connected <- newTVarIO False
  clientCorrId <- atomically $ C.newRandomDRG g
  sentCommands <- TM.emptyIO
  sendPings <- newTVarIO False
  lastReceived <- newTVarIO ts
  timeoutErrorCount <- newTVarIO 0
  sndQ <- newTBQueueIO 100
  rcvQ <- newTBQueueIO 100
  let NetworkConfig {tcpConnectTimeout, tcpTimeout} = defaultNetworkConfig
  return
    ProtocolClient
      { action = Nothing,
        thParams =
          THandleParams
            { sessionId,
              thVersion,
              thServerVRange = supportedServerSMPRelayVRange,
              thAuth,
              blockSize = smpBlockSize,
              implySessId = thVersion >= authCmdsSMPVersion,
              encryptBlock = Nothing,
              batch = True,
              serviceAuth = thVersion >= serviceCertsSMPVersion
            },
        sessionTs = ts,
        client_ =
          PClient
            { connected,
              transportSession = (1, "smp://LcJUMfVhwD8yxjAiSaDzzGF3-kLG4Uh0Fl_ZIjrRwjI=@localhost:5001", Nothing),
              transportHost = "localhost",
              tcpConnectTimeout,
              tcpTimeout,
              sendPings,
              lastReceived,
              timeoutErrorCount,
              clientCorrId,
              sentCommands,
              sndQ,
              rcvQ,
              msgQ = Nothing
            }
      }

type SMPClient = ProtocolClient SMPVersion ErrorType BrokerMsg

type ClientCommand msg = (EntityId, Maybe C.APrivateAuthKey, ProtoCommand msg)

type ServerTransmissionBatch v err msg = (TransportSession msg, THandleParams v 'TClient, NonEmpty (EntityId, ServerTransmission err msg))

data ServerTransmission err msg
  = STEvent (Either (ProtocolClientError err) msg)
  | STResponse (ProtoCommand msg) (Either (ProtocolClientError err) msg)
  | STUnexpectedError (ProtocolClientError err)

data HostMode
  =
    HMOnionViaSocks
  |
    HMOnion
  |
    HMPublic
  deriving (Eq, Show)

textToHostMode :: Text -> Either String HostMode
textToHostMode = \case
  "public" -> Right HMPublic
  "onion" -> Right HMOnionViaSocks
  s -> Left $ T.unpack $ "Invalid host_mode: " <> s

data SocksMode
  =
    SMAlways
  |
    SMOnion
  deriving (Eq, Show)

instance StrEncoding SocksMode where
  strEncode = \case
    SMAlways -> "always"
    SMOnion -> "onion"
  strP =
    A.takeTill (== ' ') >>= \case
      "always" -> pure SMAlways
      "onion" -> pure SMOnion
      _ -> fail "Invalid Socks mode"

data NetworkConfig = NetworkConfig
  {
    socksProxy :: Maybe SocksProxyWithAuth,
    socksMode :: SocksMode,
    hostMode :: HostMode,
    requiredHostMode :: Bool,
    sessionMode :: TransportSessionMode,
    smpProxyMode :: SMPProxyMode,
    smpProxyFallback :: SMPProxyFallback,
    smpWebPortServers :: SMPWebPortServers,
    tcpConnectTimeout :: NetworkTimeout,
    tcpTimeout :: NetworkTimeout,
    tcpTimeoutPerKb :: Int64,
    rcvConcurrency :: Int,
    tcpKeepAlive :: Maybe KeepAliveOpts,
    smpPingInterval :: Int64,
    smpPingCount :: Int,
    logTLSErrors :: Bool
  }
  deriving (Eq, Show)

data NetworkTimeout = NetworkTimeout {backgroundTimeout :: Int, interactiveTimeout :: Int}
  deriving (Eq, Show)

data NetworkRequestMode
  = NRMBackground
  | NRMInteractive' {retryCount :: Int}

pattern NRMInteractive :: NetworkRequestMode
pattern NRMInteractive = NRMInteractive' 0

netTimeoutInt :: NetworkTimeout -> NetworkRequestMode -> Int
netTimeoutInt NetworkTimeout {backgroundTimeout, interactiveTimeout} = \case
  NRMBackground -> backgroundTimeout
  NRMInteractive' n
    | n <= 0 -> interactiveTimeout
    | otherwise ->
        let (m, d)
              | n == 1 = (3, 2)
              | n == 2 = (9, 4)
              | otherwise = (27, 8)
         in (interactiveTimeout * m) `div` d

data TransportSessionMode = TSMUser | TSMSession | TSMServer | TSMEntity
  deriving (Eq, Show)

data SMPProxyMode
  = SPMAlways
  | SPMUnknown
  | SPMUnprotected
  | SPMNever
  deriving (Eq, Show)

data SMPProxyFallback
  = SPFAllow
  | SPFAllowProtected
  | SPFProhibit
  deriving (Eq, Show)

data SMPWebPortServers
  = SWPAll
  | SWPPreset
  | SWPOff
  deriving (Eq, Show)

instance StrEncoding SMPProxyMode where
  strEncode = \case
    SPMAlways -> "always"
    SPMUnknown -> "unknown"
    SPMUnprotected -> "unprotected"
    SPMNever -> "never"
  strP =
    A.takeTill (== ' ') >>= \case
      "always" -> pure SPMAlways
      "unknown" -> pure SPMUnknown
      "unprotected" -> pure SPMUnprotected
      "never" -> pure SPMNever
      _ -> fail "Invalid SMP proxy mode"

instance StrEncoding SMPProxyFallback where
  strEncode = \case
    SPFAllow -> "yes"
    SPFAllowProtected -> "protected"
    SPFProhibit -> "no"
  strP =
    A.takeTill (== ' ') >>= \case
      "yes" -> pure SPFAllow
      "protected" -> pure SPFAllowProtected
      "no" -> pure SPFProhibit
      _ -> fail "Invalid SMP proxy fallback mode"

instance StrEncoding SMPWebPortServers where
  strEncode = \case
    SWPAll -> "all"
    SWPPreset -> "preset"
    SWPOff -> "off"
  strP =
    A.takeTill (== ' ') >>= \case
      "all" -> pure SWPAll
      "preset" -> pure SWPPreset
      "off" -> pure SWPOff
      _ -> fail "Invalid SMP wep port setting"

defaultNetworkConfig :: NetworkConfig
defaultNetworkConfig =
  NetworkConfig
    { socksProxy = Nothing,
      socksMode = SMAlways,
      hostMode = HMOnionViaSocks,
      requiredHostMode = False,
      sessionMode = TSMSession,
      smpProxyMode = SPMNever,
      smpProxyFallback = SPFAllow,
      smpWebPortServers = SWPPreset,
      tcpConnectTimeout = NetworkTimeout {backgroundTimeout = 45_000000, interactiveTimeout = 15_000000},
      tcpTimeout = NetworkTimeout {backgroundTimeout = 30_000000, interactiveTimeout = 10_000000},
      tcpTimeoutPerKb = 5_000,
      rcvConcurrency = 8,
      tcpKeepAlive = Just defaultKeepAliveOpts,
      smpPingInterval = 600_000_000,
      smpPingCount = 3,
      logTLSErrors = False
    }

transportClientConfig :: NetworkConfig -> NetworkRequestMode -> TransportHost -> Bool -> Maybe [ALPN] -> TransportClientConfig
transportClientConfig NetworkConfig {socksProxy, socksMode, tcpConnectTimeout, tcpKeepAlive, logTLSErrors} nm host useSNI clientALPN =
  TransportClientConfig {socksProxy = useSocksProxy socksMode, tcpConnectTimeout = tOut, tcpKeepAlive, logTLSErrors, clientCredentials = Nothing, clientALPN, useSNI}
  where
    tOut = netTimeoutInt tcpConnectTimeout nm
    socksProxy' = (\(SocksProxyWithAuth _ proxy) -> proxy) <$> socksProxy
    useSocksProxy SMAlways = socksProxy'
    useSocksProxy SMOnion = case host of
      THOnionHost _ -> socksProxy'
      _ -> Nothing

clientSocksCredentials :: ProtocolTypeI (ProtoType msg) => NetworkConfig -> UTCTime -> TransportSession msg -> Maybe SocksCredentials
clientSocksCredentials NetworkConfig {socksProxy, sessionMode} proxySessTs (userId, srv, entityId_) = case socksProxy of
  Just (SocksProxyWithAuth auth _) -> case auth of
    SocksAuthUsername {username, password} -> Just $ SocksCredentials username password
    SocksAuthNull -> Nothing
    SocksIsolateByAuth -> Just $ SocksCredentials sessionUsername ""
  Nothing -> Nothing
  where
    sessionUsername =
      B64.encode $ C.sha256Hash $
        bshow userId <> case sessionMode of
          TSMUser -> ""
          TSMSession -> ":" <> bshow proxySessTs
          TSMServer -> ":" <> bshow proxySessTs <> "@" <> strEncode srv
          TSMEntity -> ":" <> bshow proxySessTs <> "@" <> strEncode srv <> maybe "" ("/" <>) entityId_

data ProtocolClientConfig v = ProtocolClientConfig
  {
    qSize :: Natural,
    defaultTransport :: (ServiceName, ATransport 'TClient),
    networkConfig :: NetworkConfig,
    clientALPN :: Maybe [ALPN],
    serviceCredentials :: Maybe ServiceCredentials,
    serverVRange :: VersionRange v,
    agreeSecret :: Bool,
    proxyServer :: Bool,
    useSNI :: Bool
  }

defaultClientConfig :: Maybe [ALPN] -> Bool -> VersionRange v -> ProtocolClientConfig v
defaultClientConfig clientALPN useSNI serverVRange =
  ProtocolClientConfig
    { qSize = 64,
      defaultTransport = ("443", transport @TLS),
      networkConfig = defaultNetworkConfig,
      clientALPN,
      serviceCredentials = Nothing,
      serverVRange,
      agreeSecret = False,
      proxyServer = False,
      useSNI
    }
{-# INLINE defaultClientConfig #-}

defaultSMPClientConfig :: ProtocolClientConfig SMPVersion
defaultSMPClientConfig =
  (defaultClientConfig (Just alpnSupportedSMPHandshakes) False supportedClientSMPRelayVRange)
    { defaultTransport = (show defaultSMPPort, transport @TLS),
      agreeSecret = True
    }
{-# INLINE defaultSMPClientConfig #-}

data Request err msg = Request
  { corrId :: CorrId,
    entityId :: EntityId,
    command :: ProtoCommand msg,
    pending :: TVar Bool,
    responseVar :: TMVar (Either (ProtocolClientError err) msg)
  }

data Response err msg = Response
  { entityId :: EntityId,
    response :: Either (ProtocolClientError err) msg
  }

chooseTransportHost :: NetworkConfig -> NonEmpty TransportHost -> Either (ProtocolClientError err) TransportHost
chooseTransportHost NetworkConfig {socksProxy, hostMode, requiredHostMode} hosts =
  firstOrError $ case hostMode of
    HMOnionViaSocks -> maybe publicHost (const onionHost) socksProxy
    HMOnion -> onionHost
    HMPublic -> publicHost
  where
    firstOrError
      | requiredHostMode = maybe (Left PCEIncompatibleHost) Right
      | otherwise = Right . fromMaybe (L.head hosts)
    isOnionHost = \case THOnionHost _ -> True; _ -> False
    onionHost = find isOnionHost hosts
    publicHost = find (not . isOnionHost) hosts

protocolClientServer :: ProtocolTypeI (ProtoType msg) => ProtocolClient v err msg -> String
protocolClientServer = B.unpack . strEncode . protocolClientServer'
{-# INLINE protocolClientServer #-}

protocolClientServer' :: ProtocolClient v err msg -> ProtoServer msg
protocolClientServer' = snd3 . transportSession . client_
  where
    snd3 (_, s, _) = s
{-# INLINE protocolClientServer' #-}

transportHost' :: ProtocolClient v err msg -> TransportHost
transportHost' = transportHost . client_
{-# INLINE transportHost' #-}

transportSession' :: ProtocolClient v err msg -> TransportSession msg
transportSession' = transportSession . client_
{-# INLINE transportSession' #-}

type UserId = Int64

type TransportSession msg = (UserId, ProtoServer msg, Maybe ByteString)

type SMPTransportSession = TransportSession BrokerMsg

getProtocolClient :: forall v err msg. Protocol v err msg => TVar ChaChaDRG -> NetworkRequestMode -> TransportSession msg -> ProtocolClientConfig v -> [HostName] -> Maybe (TBQueue (ServerTransmissionBatch v err msg)) -> UTCTime -> (ProtocolClient v err msg -> IO ()) -> IO (Either (ProtocolClientError err) (ProtocolClient v err msg))
getProtocolClient g nm transportSession@(_, srv, _) cfg@ProtocolClientConfig {qSize, networkConfig, clientALPN, serviceCredentials, serverVRange, agreeSecret, proxyServer, useSNI} presetDomains msgQ proxySessTs disconnected = do
  case chooseTransportHost networkConfig (host srv) of
    Right useHost ->
      (getCurrentTime >>= mkProtocolClient useHost >>= runClient useTransport useHost)
        `E.catches` clientHandlers
    Left e -> pure $ Left e
  where
    NetworkConfig {tcpConnectTimeout, tcpTimeout, smpPingInterval} = networkConfig
    mkProtocolClient :: TransportHost -> UTCTime -> IO (PClient v err msg)
    mkProtocolClient transportHost ts = do
      connected <- newTVarIO False
      sendPings <- newTVarIO False
      lastReceived <- newTVarIO ts
      timeoutErrorCount <- newTVarIO 0
      clientCorrId <- atomically $ C.newRandomDRG g
      sentCommands <- TM.emptyIO
      sndQ <- newTBQueueIO qSize
      rcvQ <- newTBQueueIO qSize
      return
        PClient
          { connected,
            transportSession,
            transportHost,
            tcpConnectTimeout,
            tcpTimeout,
            sendPings,
            lastReceived,
            timeoutErrorCount,
            clientCorrId,
            sentCommands,
            sndQ,
            rcvQ,
            msgQ
          }

    runClient :: (ServiceName, ATransport 'TClient) -> TransportHost -> PClient v err msg -> IO (Either (ProtocolClientError err) (ProtocolClient v err msg))
    runClient (port', ATransport t) useHost c = do
      cVar <- newEmptyTMVarIO
      let tcConfig = (transportClientConfig networkConfig nm useHost useSNI useALPN) {clientCredentials = serviceCreds <$> serviceCredentials}
          socksCreds = clientSocksCredentials networkConfig proxySessTs transportSession
      tId <-
        runTransportClient tcConfig socksCreds useHost port' (Just $ keyHash srv) (client t c cVar)
          `forkFinally` \r ->
            let err = either toNetworkError (const NEFailedError) r
             in void $ atomically $ tryPutTMVar cVar $ Left $ PCENetworkError err
      c_ <- netTimeoutInt tcpConnectTimeout nm `timeout` atomically (takeTMVar cVar)
      case c_ of
        Just (Right c') -> mkWeakThreadId tId >>= \tId' -> pure $ Right c' {action = Just tId'}
        Just (Left e) -> pure $ Left e
        Nothing -> killThread tId $> Left (PCENetworkError NETimeoutError)

    useTransport :: (ServiceName, ATransport 'TClient)
    useTransport = case port srv of
      "" -> case protocolTypeI @(ProtoType msg) of
        SPSMP | web -> ("443", transport @TLS)
        _ -> defaultTransport cfg
      p -> (p, transport @TLS)

    useALPN :: Maybe [ALPN]
    useALPN = if web then Just [httpALPN11] else clientALPN

    web = useWebPort networkConfig presetDomains srv

    client :: forall c. Transport c => TProxy c 'TClient -> PClient v err msg -> TMVar (Either (ProtocolClientError err) (ProtocolClient v err msg)) -> c 'TClient -> IO ()
    client _ c cVar h = do
      ks <- if agreeSecret then Just <$> atomically (C.generateKeyPair g) else pure Nothing
      serviceKeys_ <- mapM (\creds -> (creds,) <$> atomically (C.generateKeyPair g)) serviceCredentials
      runExceptT (protocolClientHandshake @v @err @msg h ks (keyHash srv) serverVRange proxyServer serviceKeys_) >>= \case
        Left e -> atomically . putTMVar cVar . Left $ PCETransportError e
        Right th@THandle {params} -> do
          sessionTs <- getCurrentTime
          let c' = ProtocolClient {action = Nothing, client_ = c, thParams = params, sessionTs}
          atomically $ writeTVar (lastReceived c) sessionTs
          atomically $ do
            writeTVar (connected c) True
            putTMVar cVar $ Right c'
          raceAny_ ([send c' th, process c', receive c' th] <> [monitor c' | smpPingInterval > 0])
            `E.finally` disconnected c'

    send :: Transport c => ProtocolClient v err msg -> THandle v c 'TClient -> IO ()
    send ProtocolClient {client_ = PClient {sndQ}} h = forever $ atomically (readTBQueue sndQ) >>= sendPending
      where
        sendPending (r, s) = case r of
          Nothing -> void $ tPutLog h s
          Just Request {pending, responseVar} ->
            whenM (readTVarIO pending) $ tPutLog h s >>= either responseErr pure
            where
              responseErr = atomically . putTMVar responseVar . Left . PCETransportError

    receive :: Transport c => ProtocolClient v err msg -> THandle v c 'TClient -> IO ()
    receive ProtocolClient {client_ = PClient {rcvQ, lastReceived, timeoutErrorCount}} h = forever $ do
      tGetClient h >>= atomically . writeTBQueue rcvQ
      getCurrentTime >>= atomically . writeTVar lastReceived
      atomically $ writeTVar timeoutErrorCount 0

    monitor :: ProtocolClient v err msg -> IO ()
    monitor c@ProtocolClient {client_ = PClient {sendPings, lastReceived, timeoutErrorCount}} = loop smpPingInterval
      where
        loop :: Int64 -> IO ()
        loop delay = do
          threadDelay' delay
          diff <- diffUTCTime <$> getCurrentTime <*> readTVarIO lastReceived
          let idle = diffToMicroseconds diff
              remaining = smpPingInterval - idle
          if remaining > 1_000_000
            then loop remaining
            else do
              whenM (readTVarIO sendPings) $ void . runExceptT $ sendProtocolCommand c NRMBackground Nothing NoEntity (protocolPing @v @err @msg)
              cnt <- readTVarIO timeoutErrorCount
              when (maxCnt == 0 || cnt < maxCnt || diff < recoverWindow) $ loop smpPingInterval
        recoverWindow = 15 * 60
        maxCnt = smpPingCount networkConfig

    process :: ProtocolClient v err msg -> IO ()
    process c = forever $ atomically (readTBQueue $ rcvQ $ client_ c) >>= processMsgs c

    processMsgs :: ProtocolClient v err msg -> NonEmpty (Transmission (Either err msg)) -> IO ()
    processMsgs c ts = do
      ts' <- catMaybes <$> mapM (processMsg c) (L.toList ts)
      forM_ msgQ $ \q ->
        mapM_ (atomically . writeTBQueue q . serverTransmission c) (L.nonEmpty ts')

    processMsg :: ProtocolClient v err msg -> Transmission (Either err msg) -> IO (Maybe (EntityId, ServerTransmission err msg))
    processMsg ProtocolClient {client_ = PClient {sentCommands}} (corrId, entId, respOrErr)
      | B.null $ bs corrId = sendMsg $ STEvent clientResp
      | otherwise =
          TM.lookupIO corrId sentCommands >>= \case
            Nothing -> sendMsg $ STUnexpectedError unexpected
            Just Request {entityId, command, pending, responseVar} -> do
              wasPending <-
                atomically $ do
                  TM.delete corrId sentCommands
                  ifM
                    (swapTVar pending False)
                    (True <$ tryPutTMVar responseVar (if entityId == entId then clientResp else Left unexpected))
                    (pure False)
              if wasPending
                then pure Nothing
                else sendMsg $ if entityId == entId then STResponse command clientResp else STUnexpectedError unexpected
      where
        unexpected = unexpectedResponse respOrErr
        clientResp = case respOrErr of
          Left e -> Left $ PCEResponseError e
          Right r -> case protocolError r of
            Just e -> Left $ PCEProtocolError e
            _ -> Right r
        sendMsg :: ServerTransmission err msg -> IO (Maybe (EntityId, ServerTransmission err msg))
        sendMsg t = case msgQ of
          Just _ -> pure $ Just (entId, t)
          Nothing ->
            Nothing <$ case clientResp of
              Left e -> logError $ "SMP client error: " <> tshow e
              Right _ -> logWarn "SMP client unprocessed event"

clientHandlers :: [Handler (Either (ProtocolClientError e) a)]
clientHandlers =
  [ Handler $ \(e :: IOException) -> pure $ Left $ PCEIOError $ E.displayException e,
    Handler $ \(e :: SomeAsyncException) -> E.throwIO e,
    Handler $ \(e :: SomeException) -> pure $ Left $ PCENetworkError $ toNetworkError e
  ]

useWebPort :: NetworkConfig -> [HostName] -> ProtocolServer p -> Bool
useWebPort cfg presetDomains ProtocolServer {host = h :| _} = case smpWebPortServers cfg of
  SWPAll -> True
  SWPPreset -> isPresetDomain presetDomains h
  SWPOff -> False

isPresetDomain :: [HostName] -> TransportHost -> Bool
isPresetDomain presetDomains = \case
  THDomainName h -> any (`isSuffixOf` h) presetDomains
  _ -> False

unexpectedResponse :: Show r => r -> ProtocolClientError err
unexpectedResponse = PCEUnexpectedResponse . B.pack . take 32 . show

closeProtocolClient :: ProtocolClient v err msg -> IO ()
closeProtocolClient = mapM_ (deRefWeak >=> mapM_ killThread) . action
{-# INLINE closeProtocolClient #-}

data ProtocolClientError err
  =
    PCEProtocolError err
  |
    PCEResponseError err
  |
    PCEUnexpectedResponse ByteString
  |
    PCEResponseTimeout
  |
    PCENetworkError NetworkError
  |
    PCEIncompatibleHost
  |
    PCEServiceUnavailable
  |
    PCETransportError TransportError
  |
    PCECryptoError C.CryptoError
  |
    PCEIOError String
  deriving (Eq, Show, Exception)

type SMPClientError = ProtocolClientError ErrorType

temporaryClientError :: ProtocolClientError err -> Bool
temporaryClientError = \case
  PCENetworkError _ -> True
  PCEResponseTimeout -> True
  PCEIOError _ -> True
  _ -> False
{-# INLINE temporaryClientError #-}

smpClientServiceError :: SMPClientError -> Bool
smpClientServiceError = \case
  PCEServiceUnavailable -> True
  PCEProtocolError SERVICE -> True
  PCEProtocolError (PROXY (BROKER NO_SERVICE)) -> True
  _ -> False

smpProxyError :: SMPClientError -> ErrorType
smpProxyError = \case
  PCEProtocolError e -> PROXY $ PROTOCOL e
  PCEResponseError e -> PROXY $ BROKER $ RESPONSE $ B.unpack $ strEncode e
  PCEUnexpectedResponse e -> PROXY $ BROKER $ UNEXPECTED $ B.unpack e
  PCEResponseTimeout -> PROXY $ BROKER TIMEOUT
  PCENetworkError e -> PROXY $ BROKER $ NETWORK e
  PCEIncompatibleHost -> PROXY $ BROKER HOST
  PCEServiceUnavailable -> PROXY $ BROKER $ NO_SERVICE
  PCETransportError t -> PROXY $ BROKER $ TRANSPORT t
  PCECryptoError _ -> CRYPTO
  PCEIOError _ -> INTERNAL

smpErrorClientNotice :: SMPClientError -> Maybe (Maybe ClientNotice)
smpErrorClientNotice = \case
  PCEProtocolError (BLOCKED BlockingInfo {notice}) -> Just notice
  _ -> Nothing
{-# INLINE smpErrorClientNotice #-}

createSMPQueue ::
  SMPClient ->
  NetworkRequestMode ->
  Maybe C.CbNonce ->
  C.AAuthKeyPair ->
  RcvPublicDhKey ->
  Maybe BasicAuth ->
  SubscriptionMode ->
  QueueReqData ->
  Maybe NewNtfCreds ->
  ExceptT SMPClientError IO QueueIdsKeys
createSMPQueue c nm nonce_ (rKey, rpKey) dhKey auth subMode qrd ntfCreds =
  sendProtocolCommand_ c nm nonce_ Nothing (Just rpKey) NoEntity (Cmd SCreator $ NEW $ NewQueueReq rKey dhKey auth subMode (Just qrd) ntfCreds) >>= \case
    IDS qik -> pure qik
    r -> throwE $ unexpectedResponse r

subscribeSMPQueue :: SMPClient -> RcvPrivateAuthKey -> RecipientId -> ExceptT SMPClientError IO (Maybe ServiceId)
subscribeSMPQueue c rpKey rId = do
  liftIO $ enablePings c
  sendSMPCommand c NRMBackground (Just rpKey) rId SUB >>= liftIO . processSUBResponse_ c rId >>= except

subscribeSMPQueues :: SMPClient -> NonEmpty (RecipientId, RcvPrivateAuthKey) -> IO (NonEmpty (Either SMPClientError (Maybe ServiceId)))
subscribeSMPQueues c qs = do
  liftIO $ enablePings c
  sendProtocolCommands c NRMBackground cs >>= mapM (processSUBResponse c)
  where
    cs = L.map (\(rId, rpKey) -> (rId, Just rpKey, Cmd SRecipient SUB)) qs

streamSubscribeSMPQueues :: SMPClient -> NonEmpty (RecipientId, RcvPrivateAuthKey) -> ([(RecipientId, Either SMPClientError (Maybe ServiceId))] -> IO ()) -> IO ()
streamSubscribeSMPQueues c qs cb = streamProtocolCommands c NRMBackground cs $ mapM process >=> cb
  where
    cs = L.map (\(rId, rpKey) -> (rId, Just rpKey, Cmd SRecipient SUB)) qs
    process r@(Response rId _) = (rId,) <$> processSUBResponse c r

processSUBResponse :: SMPClient -> Response ErrorType BrokerMsg -> IO (Either SMPClientError (Maybe ServiceId))
processSUBResponse c (Response rId r) = pure r $>>= processSUBResponse_ c rId

processSUBResponse_ :: SMPClient -> RecipientId -> BrokerMsg -> IO (Either SMPClientError (Maybe ServiceId))
processSUBResponse_ c rId = \case
  OK -> pure $ Right Nothing
  SOK serviceId_ -> pure $ Right serviceId_
  cmd@MSG {} -> writeSMPMessage c rId cmd $> Right Nothing
  r' -> pure . Left $ unexpectedResponse r'

writeSMPMessage :: SMPClient -> RecipientId -> BrokerMsg -> IO ()
writeSMPMessage c rId msg = atomically $ mapM_ (`writeTBQueue` serverTransmission c [(rId, STEvent (Right msg))]) (msgQ $ client_ c)

serverTransmission :: ProtocolClient v err msg -> NonEmpty (RecipientId, ServerTransmission err msg) -> ServerTransmissionBatch v err msg
serverTransmission ProtocolClient {thParams, client_ = PClient {transportSession}} ts = (transportSession, thParams, ts)

getSMPMessage :: SMPClient -> RcvPrivateAuthKey -> RecipientId -> ExceptT SMPClientError IO (Maybe RcvMessage)
getSMPMessage c rpKey rId =
  sendSMPCommand c NRMInteractive (Just rpKey) rId GET >>= \case
    OK -> pure Nothing
    cmd@(MSG msg) -> liftIO (writeSMPMessage c rId cmd) $> Just msg
    r -> throwE $ unexpectedResponse r
{-# INLINE getSMPMessage #-}

subscribeSMPQueueNotifications :: SMPClient -> NtfPrivateAuthKey -> NotifierId -> ExceptT SMPClientError IO (Maybe ServiceId)
subscribeSMPQueueNotifications c npKey nId = do
  liftIO $ enablePings c
  sendSMPCommand c NRMBackground (Just npKey) nId NSUB >>= except . nsubResponse_

subscribeSMPQueuesNtfs :: SMPClient -> NonEmpty (NotifierId, NtfPrivateAuthKey) -> IO (NonEmpty (Either SMPClientError (Maybe ServiceId)))
subscribeSMPQueuesNtfs c qs = do
  liftIO $ enablePings c
  L.map nsubResponse <$> sendProtocolCommands c NRMBackground cs
  where
    cs = L.map (\(nId, npKey) -> (nId, Just npKey, Cmd SNotifier NSUB)) qs

nsubResponse :: Response ErrorType BrokerMsg -> Either SMPClientError (Maybe ServiceId)
nsubResponse (Response _ r) = r >>= nsubResponse_
{-# INLINE nsubResponse #-}

nsubResponse_ :: BrokerMsg -> Either SMPClientError (Maybe ServiceId)
nsubResponse_ = \case
  OK -> Right Nothing
  SOK serviceId_ -> Right serviceId_
  r' -> Left $ unexpectedResponse r'
{-# INLINE nsubResponse_ #-}

subscribeService :: forall p. (PartyI p, ServiceParty p) => SMPClient -> SParty p -> Int64 -> IdsHash -> ExceptT SMPClientError IO ServiceSub
subscribeService c party n idsHash = case smpClientService c of
  Just THClientService {serviceId, serviceKey} -> do
    liftIO $ enablePings c
    sendSMPCommand c NRMBackground (Just (C.APrivateAuthKey C.SEd25519 serviceKey)) serviceId subCmd >>= \case
      SOKS n' idsHash' -> pure $ ServiceSub serviceId n' idsHash'
      r -> throwE $ unexpectedResponse r
    where
      subCmd :: Command p
      subCmd = case party of
        SRecipientService -> SUBS n idsHash
        SNotifierService -> NSUBS n idsHash
  Nothing -> throwE PCEServiceUnavailable

smpClientService :: SMPClient -> Maybe THClientService
smpClientService = thAuth . thParams >=> clientService
{-# INLINE smpClientService #-}

smpClientServiceId :: SMPClient -> Maybe ServiceId
smpClientServiceId = fmap (\THClientService {serviceId} -> serviceId) . smpClientService
{-# INLINE smpClientServiceId #-}

enablePings :: SMPClient -> IO ()
enablePings ProtocolClient {client_ = PClient {sendPings}} = atomically $ writeTVar sendPings True
{-# INLINE enablePings #-}

secureSMPQueue :: SMPClient -> NetworkRequestMode -> RcvPrivateAuthKey -> RecipientId -> SndPublicAuthKey -> ExceptT SMPClientError IO ()
secureSMPQueue c nm rpKey rId senderKey = okSMPCommand (KEY senderKey) c nm rpKey rId
{-# INLINE secureSMPQueue #-}

secureSndSMPQueue :: SMPClient -> NetworkRequestMode -> SndPrivateAuthKey -> SenderId -> ExceptT SMPClientError IO ()
secureSndSMPQueue c nm spKey sId = okSMPCommand (SKEY $ C.toPublic spKey) c nm spKey sId
{-# INLINE secureSndSMPQueue #-}

proxySecureSndSMPQueue :: SMPClient -> NetworkRequestMode -> ProxiedRelay -> SndPrivateAuthKey -> SenderId -> ExceptT SMPClientError IO (Either ProxyClientError ())
proxySecureSndSMPQueue c nm proxiedRelay spKey sId = proxyOKSMPCommand c nm proxiedRelay (Just spKey) sId (SKEY $ C.toPublic spKey)
{-# INLINE proxySecureSndSMPQueue #-}

addSMPQueueLink :: SMPClient -> NetworkRequestMode -> RcvPrivateAuthKey -> RecipientId -> LinkId -> QueueLinkData -> ExceptT SMPClientError IO ()
addSMPQueueLink c nm rpKey rId lnkId d = okSMPCommand (LSET lnkId d) c nm rpKey rId
{-# INLINE addSMPQueueLink #-}

deleteSMPQueueLink :: SMPClient -> NetworkRequestMode -> RcvPrivateAuthKey -> RecipientId -> ExceptT SMPClientError IO ()
deleteSMPQueueLink = okSMPCommand LDEL
{-# INLINE deleteSMPQueueLink #-}

secureGetSMPQueueLink :: SMPClient -> NetworkRequestMode -> SndPrivateAuthKey -> LinkId -> ExceptT SMPClientError IO (SenderId, QueueLinkData)
secureGetSMPQueueLink c nm spKey lnkId =
  sendSMPCommand c nm (Just spKey) lnkId (LKEY $ C.toPublic spKey) >>= \case
    LNK sId d -> pure (sId, d)
    r -> throwE $ unexpectedResponse r

proxySecureGetSMPQueueLink :: SMPClient -> NetworkRequestMode -> ProxiedRelay -> SndPrivateAuthKey -> LinkId -> ExceptT SMPClientError IO (Either ProxyClientError (SenderId, QueueLinkData))
proxySecureGetSMPQueueLink c nm proxiedRelay spKey lnkId =
  proxySMPCommand  c nm proxiedRelay (Just spKey) lnkId (LKEY $ C.toPublic spKey) >>= \case
    Right (LNK sId d) -> pure $ Right (sId, d)
    Right r -> throwE $ unexpectedResponse r
    Left e -> pure $ Left e

getSMPQueueLink :: SMPClient -> NetworkRequestMode -> LinkId -> ExceptT SMPClientError IO (SenderId, QueueLinkData)
getSMPQueueLink c nm lnkId =
  sendSMPCommand c nm Nothing lnkId LGET >>= \case
    LNK sId d -> pure (sId, d)
    r -> throwE $ unexpectedResponse r

proxyGetSMPQueueLink :: SMPClient -> NetworkRequestMode -> ProxiedRelay -> LinkId -> ExceptT SMPClientError IO (Either ProxyClientError (SenderId, QueueLinkData))
proxyGetSMPQueueLink c nm proxiedRelay lnkId =
  proxySMPCommand c nm proxiedRelay Nothing lnkId LGET >>= \case
    Right (LNK sId d) -> pure $ Right (sId, d)
    Right r -> throwE $ unexpectedResponse r
    Left e -> pure $ Left e

enableSMPQueueNotifications :: SMPClient -> RcvPrivateAuthKey -> RecipientId -> NtfPublicAuthKey -> RcvNtfPublicDhKey -> ExceptT SMPClientError IO (NotifierId, RcvNtfPublicDhKey)
enableSMPQueueNotifications c rpKey rId notifierKey rcvNtfPublicDhKey =
  sendSMPCommand c NRMBackground (Just rpKey) rId (NKEY notifierKey rcvNtfPublicDhKey) >>= \case
    NID nId rcvNtfSrvPublicDhKey -> pure (nId, rcvNtfSrvPublicDhKey)
    r -> throwE $ unexpectedResponse r

enableSMPQueuesNtfs :: SMPClient -> NonEmpty (RecipientId, RcvPrivateAuthKey, NtfPublicAuthKey, RcvNtfPublicDhKey) -> IO (NonEmpty (Either SMPClientError (NotifierId, RcvNtfPublicDhKey)))
enableSMPQueuesNtfs c qs = L.map process <$> sendProtocolCommands c NRMBackground cs
  where
    cs = L.map (\(rId, rpKey, notifierKey, rcvNtfPublicDhKey) -> (rId, Just rpKey, Cmd SRecipient $ NKEY notifierKey rcvNtfPublicDhKey)) qs
    process (Response _ r) = case r of
      Right (NID nId rcvNtfSrvPublicDhKey) -> Right (nId, rcvNtfSrvPublicDhKey)
      Right r' -> Left $ unexpectedResponse r'
      Left e -> Left e

disableSMPQueueNotifications :: SMPClient -> RcvPrivateAuthKey -> RecipientId -> ExceptT SMPClientError IO ()
disableSMPQueueNotifications c = okSMPCommand NDEL c NRMBackground
{-# INLINE disableSMPQueueNotifications #-}

disableSMPQueuesNtfs :: SMPClient -> NonEmpty (RecipientId, RcvPrivateAuthKey) -> IO (NonEmpty (Either SMPClientError ()))
disableSMPQueuesNtfs c = okSMPCommands NDEL c NRMBackground
{-# INLINE disableSMPQueuesNtfs #-}

sendSMPMessage :: SMPClient -> NetworkRequestMode -> Maybe SndPrivateAuthKey -> SenderId -> MsgFlags -> MsgBody -> ExceptT SMPClientError IO ()
sendSMPMessage c nm spKey sId flags msg =
  sendSMPCommand c nm spKey sId (SEND flags msg) >>= \case
    OK -> pure ()
    r -> throwE $ unexpectedResponse r

proxySMPMessage :: SMPClient -> NetworkRequestMode -> ProxiedRelay -> Maybe SndPrivateAuthKey -> SenderId -> MsgFlags -> MsgBody -> ExceptT SMPClientError IO (Either ProxyClientError ())
proxySMPMessage c nm proxiedRelay spKey sId flags msg = proxyOKSMPCommand c nm proxiedRelay spKey sId (SEND flags msg)

proxyResolveName :: SMPClient -> NetworkRequestMode -> ProxiedRelay -> ZeroDomain -> ExceptT SMPClientError IO (Either ProxyClientError NameRecord)
proxyResolveName c nm proxiedRelay name
  | prVersion proxiedRelay >= namesSMPVersion =
      proxySMPCommand c nm proxiedRelay Nothing NoEntity (RSLV name) >>= \case
        Right (RNAME nr) -> pure $ Right nr
        Right r -> throwE $ unexpectedResponse r
        Left e -> pure $ Left e
  | otherwise = throwE $ PCETransportError TEVersion

directResolveName :: SMPClient -> NetworkRequestMode -> ZeroDomain -> ExceptT SMPClientError IO NameRecord
directResolveName c nm name
  | thVersion (thParams c) >= namesSMPVersion =
      sendProtocolCommand c nm Nothing NoEntity (Cmd SResolver (RSLV name)) >>= \case
        RNAME nr -> pure nr
        r -> throwE $ unexpectedResponse r
  | otherwise = throwE $ PCETransportError TEVersion

ackSMPMessage :: SMPClient -> RcvPrivateAuthKey -> QueueId -> MsgId -> ExceptT SMPClientError IO ()
ackSMPMessage c rpKey rId msgId =
  sendSMPCommand c NRMBackground (Just rpKey) rId (ACK msgId) >>= \case
    OK -> return ()
    cmd@MSG {} -> liftIO $ writeSMPMessage c rId cmd
    r -> throwE $ unexpectedResponse r

suspendSMPQueue :: SMPClient -> NetworkRequestMode -> RcvPrivateAuthKey -> QueueId -> ExceptT SMPClientError IO ()
suspendSMPQueue = okSMPCommand OFF
{-# INLINE suspendSMPQueue #-}

deleteSMPQueue :: SMPClient -> NetworkRequestMode -> RcvPrivateAuthKey -> RecipientId -> ExceptT SMPClientError IO ()
deleteSMPQueue = okSMPCommand DEL
{-# INLINE deleteSMPQueue #-}

deleteSMPQueues :: SMPClient -> NetworkRequestMode -> NonEmpty (RecipientId, RcvPrivateAuthKey) -> IO (NonEmpty (Either SMPClientError ()))
deleteSMPQueues = okSMPCommands DEL
{-# INLINE deleteSMPQueues #-}

connectSMPProxiedRelay :: SMPClient -> NetworkRequestMode -> SMPServer -> Maybe BasicAuth -> ExceptT SMPClientError IO ProxiedRelay
connectSMPProxiedRelay c@ProtocolClient {client_ = PClient {tcpConnectTimeout, tcpTimeout}} nm relayServ@ProtocolServer {port = relayPort, keyHash = C.KeyHash kh} proxyAuth
  | thVersion (thParams c) >= sendingProxySMPVersion =
      sendProtocolCommand_ c nm Nothing tOut Nothing NoEntity (Cmd SProxiedClient (PRXY relayServ proxyAuth)) >>= \case
        PKEY sId vr (CertChainPubKey chain key) ->
          case supportedClientSMPRelayVRange `compatibleVersion` vr of
            Nothing -> throwE $ transportErr TEVersion
            Just (Compatible v) -> do
              relayKey <- liftEitherWith (const $ transportErr $ TEHandshake IDENTITY) =<< liftIO (runExceptT $ validateRelay chain key)
              pure $ ProxiedRelay sId v proxyAuth relayKey
        r -> throwE $ unexpectedResponse r
  | otherwise = throwE $ PCETransportError TEVersion
  where
    tOut = Just $ netTimeoutInt tcpConnectTimeout nm + netTimeoutInt tcpTimeout nm
    transportErr = PCEProtocolError . PROXY . BROKER . TRANSPORT
    hostName = B.unpack $ strEncode $ transportHost' c
    validateRelay :: X.CertificateChain -> X.SignedExact X.PubKey -> ExceptT String IO C.PublicKeyX25519
    validateRelay chain exact = case chainIdCaCerts chain of
      CCValid {leafCert, idCert, caCert}
        | XV.Fingerprint kh == XV.getFingerprint idCert X.HashSHA256 -> do
            errs <- liftIO $ x509validate caCert (hostName, B.pack relayPort) chain
            unless (null errs) $ throwError "bad certificate"
            serverKey <- liftEither $ C.x509ToPublic' $ X.certPubKey $ X.signedObject $ X.getSigned leafCert
            liftEither $ C.x509ToPublic' =<< C.verifyX509 serverKey exact
      _ -> throwError "bad certificate"

data ProxiedRelay = ProxiedRelay
  { prSessionId :: SessionId,
    prVersion :: VersionSMP,
    prBasicAuth :: Maybe BasicAuth,
    prServerKey :: C.PublicKeyX25519
  }

data ProxyClientError
  =
    ProxyProtocolError {protocolErr :: ErrorType}
  |
    ProxyUnexpectedResponse {responseStr :: String}
  |
    ProxyResponseError {responseErr :: ErrorType}
  deriving (Eq, Show, Exception)

instance StrEncoding ProxyClientError where
  strEncode = \case
    ProxyProtocolError e -> "PROTOCOL " <> strEncode e
    ProxyUnexpectedResponse s -> "UNEXPECTED " <> B.pack s
    ProxyResponseError e -> "SYNTAX " <> strEncode e
  strP =
    A.takeTill (== ' ') >>= \case
      "PROTOCOL" -> ProxyProtocolError <$> _strP
      "UNEXPECTED" -> ProxyUnexpectedResponse . B.unpack <$> (A.space *> A.takeByteString)
      "SYNTAX" -> ProxyResponseError <$> _strP
      _ -> fail "bad ProxyClientError"

proxyOKSMPCommand :: SMPClient -> NetworkRequestMode -> ProxiedRelay -> Maybe SndPrivateAuthKey -> SenderId -> Command 'Sender -> ExceptT SMPClientError IO (Either ProxyClientError ())
proxyOKSMPCommand c nm proxiedRelay spKey sId command =
  proxySMPCommand  c nm proxiedRelay spKey sId command >>= \case
    Right OK -> pure $ Right ()
    Right r -> throwE $ unexpectedResponse r
    Left e -> pure $ Left e

proxySMPCommand ::
  forall p.
  PartyI p =>
  SMPClient ->
  NetworkRequestMode ->
  ProxiedRelay ->
  Maybe SndPrivateAuthKey ->
  SenderId ->
  Command p ->
  ExceptT SMPClientError IO (Either ProxyClientError BrokerMsg)
proxySMPCommand c@ProtocolClient {thParams = proxyThParams, client_ = PClient {clientCorrId = g, tcpTimeout}} nm (ProxiedRelay sessionId v _ serverKey) spKey sId command = do
  let serverThAuth = (\ta -> ta {peerServerPubKey = serverKey}) <$> thAuth proxyThParams
      serverThParams = smpTHParamsSetVersion v proxyThParams {sessionId, thAuth = serverThAuth}
  (cmdPubKey, cmdPrivKey) <- liftIO . atomically $ C.generateKeyPair @'C.X25519 g
  let cmdSecret = C.dh' serverKey cmdPrivKey
  nonce@(C.CbNonce corrId) <- liftIO . atomically $ C.randomCbNonce g
  let TransmissionForAuth {tForAuth, tToSend} = encodeTransmissionForAuth serverThParams (CorrId corrId, sId, Cmd (sParty @p) command)
  auth <- liftEitherWith PCETransportError $ authTransmission serverThAuth False spKey nonce tForAuth
  b <- case batchTransmissions serverThParams [Right (auth, tToSend)] of
    [] -> throwE $ PCETransportError TELargeMsg
    TBError e _ : _ -> throwE $ PCETransportError e
    TBTransmission s _ : _ -> pure s
    TBTransmissions s _ _ : _ -> pure s
  et <- liftEitherWith PCECryptoError $ EncTransmission <$> C.cbEncrypt cmdSecret nonce b paddedProxiedTLength
  let tOut = Just $ 2 * netTimeoutInt tcpTimeout nm
  tryE (sendProtocolCommand_ c nm (Just nonce) tOut Nothing (EntityId sessionId) (Cmd SProxiedClient (PFWD v cmdPubKey et))) >>= \case
    Right r -> case r of
      PRES (EncResponse er) -> do
        t' <- liftEitherWith PCECryptoError $ C.cbDecrypt cmdSecret (C.reverseNonce nonce) er
        case tParse serverThParams t' of
          t'' :| [] -> case tDecodeClient serverThParams t'' of
            (_, _, cmd) -> case cmd of
              Right (ERR e) -> throwE $ PCEProtocolError e
              Right r' -> pure $ Right r'
              Left e -> throwE $ PCEResponseError e
          _ -> throwE $ PCETransportError TEBadBlock
      ERR e -> pure . Left $ ProxyProtocolError e
      _ -> pure . Left $ ProxyUnexpectedResponse $ take 32 $ show r
    Left e -> case e of
      PCEProtocolError e' -> pure . Left $ ProxyProtocolError e'
      PCEUnexpectedResponse e' -> pure . Left $ ProxyUnexpectedResponse $ B.unpack e'
      PCEResponseError e' -> pure . Left $ ProxyResponseError e'
      _ -> throwE e

forwardSMPTransmission :: SMPClient -> CorrId -> VersionSMP -> C.PublicKeyX25519 -> EncTransmission -> ExceptT SMPClientError IO EncResponse
forwardSMPTransmission c@ProtocolClient {thParams, client_ = PClient {clientCorrId = g}} fwdCorrId fwdVersion fwdKey fwdTransmission = do
  sessSecret <- case thAuth thParams of
    Nothing -> throwE $ PCETransportError TENoServerAuth
    Just THAuthClient {sessSecret} -> maybe (throwE $ PCETransportError TENoServerAuth) pure sessSecret
  nonce <- liftIO . atomically $ C.randomCbNonce g
  let fwdT = FwdTransmission {fwdCorrId, fwdVersion, fwdKey, fwdTransmission}
      eft = EncFwdTransmission $ C.cbEncryptNoPad sessSecret nonce (smpEncode fwdT)
  sendProtocolCommand_ c NRMBackground (Just nonce) Nothing Nothing NoEntity (Cmd SProxyService (RFWD eft)) >>= \case
    RRES (EncFwdResponse efr) -> do
      r' <- liftEitherWith PCECryptoError $ C.cbDecryptNoPad sessSecret (C.reverseNonce nonce) efr
      FwdResponse {fwdCorrId = _, fwdResponse} <- liftEitherWith (const $ PCEResponseError BLOCK) $ smpDecode r'
      pure fwdResponse
    r -> throwE $ unexpectedResponse r

getSMPQueueInfo :: SMPClient -> NetworkRequestMode -> C.APrivateAuthKey -> QueueId -> ExceptT SMPClientError IO QueueInfo
getSMPQueueInfo c nm pKey qId =
  sendSMPCommand c nm (Just pKey) qId QUE >>= \case
    INFO info -> pure info
    r -> throwE $ unexpectedResponse r

okSMPCommand :: PartyI p => Command p -> SMPClient -> NetworkRequestMode -> C.APrivateAuthKey -> QueueId -> ExceptT SMPClientError IO ()
okSMPCommand cmd c nm pKey qId =
  sendSMPCommand c nm (Just pKey) qId cmd >>= \case
    OK -> return ()
    r -> throwE $ unexpectedResponse r

okSMPCommands :: PartyI p => Command p -> SMPClient -> NetworkRequestMode -> NonEmpty (QueueId, C.APrivateAuthKey) -> IO (NonEmpty (Either SMPClientError ()))
okSMPCommands cmd c nm qs = L.map process <$> sendProtocolCommands c nm cs
  where
    aCmd = Cmd sParty cmd
    cs = L.map (\(qId, pKey) -> (qId, Just pKey, aCmd)) qs
    process (Response _ r) = case r of
      Right OK -> Right ()
      Right r' -> Left $ unexpectedResponse r'
      Left e -> Left e

sendSMPCommand :: PartyI p => SMPClient -> NetworkRequestMode -> Maybe C.APrivateAuthKey -> EntityId -> Command p -> ExceptT SMPClientError IO BrokerMsg
sendSMPCommand c nm pKey entId cmd = sendProtocolCommand c nm pKey entId (Cmd sParty cmd)
{-# INLINE sendSMPCommand #-}

type PCTransmission err msg = (Either TransportError SentRawTransmission, Request err msg)

sendProtocolCommands :: forall v err msg. Protocol v err msg => ProtocolClient v err msg -> NetworkRequestMode -> NonEmpty (ClientCommand msg) -> IO (NonEmpty (Response err msg))
sendProtocolCommands c@ProtocolClient {thParams} nm cs = do
  bs <- batchTransmissions' thParams <$> mapM (mkTransmission c) cs
  validate . concat =<< mapM (sendBatch c nm) bs
  where
    validate :: [Response err msg] -> IO (NonEmpty (Response err msg))
    validate rs
      | diff == 0 = pure $ L.fromList rs
      | diff > 0 = do
          putStrLn "send error: fewer responses than expected"
          pure $ L.fromList $ rs <> replicate diff (Response NoEntity $ Left $ PCETransportError TEBadBlock)
      | otherwise = do
          putStrLn "send error: more responses than expected"
          pure $ L.fromList $ take (L.length cs) rs
      where
        diff = L.length cs - length rs

streamProtocolCommands :: forall v err msg. Protocol v err msg => ProtocolClient v err msg -> NetworkRequestMode -> NonEmpty (ClientCommand msg) -> ([Response err msg] -> IO ()) -> IO ()
streamProtocolCommands c@ProtocolClient {thParams} nm cs cb = do
  bs <- batchTransmissions' thParams <$> mapM (mkTransmission c) cs
  mapM_ (cb <=< sendBatch c nm) bs

sendBatch :: ProtocolClient v err msg -> NetworkRequestMode -> TransportBatch (Request err msg) -> IO [Response err msg]
sendBatch c@ProtocolClient {client_ = PClient {sndQ}} nm b = do
  case b of
    TBError e Request {entityId} -> do
      putStrLn "send error: large message"
      pure [Response entityId $ Left $ PCETransportError e]
    TBTransmissions s n rs
      | n > 0 -> do
          nonBlockingWriteTBQueue sndQ (Nothing, s)
          mapConcurrently (getResponse c nm Nothing) rs
      | otherwise -> pure []
    TBTransmission s r -> do
      nonBlockingWriteTBQueue sndQ (Nothing, s)
      (: []) <$> getResponse c nm Nothing r

sendProtocolCommand :: forall v err msg. Protocol v err msg => ProtocolClient v err msg -> NetworkRequestMode -> Maybe C.APrivateAuthKey -> EntityId -> ProtoCommand msg -> ExceptT (ProtocolClientError err) IO msg
sendProtocolCommand c nm = sendProtocolCommand_ c nm Nothing Nothing

sendProtocolCommand_ :: forall v err msg. Protocol v err msg => ProtocolClient v err msg -> NetworkRequestMode -> Maybe C.CbNonce -> Maybe Int -> Maybe C.APrivateAuthKey -> EntityId -> ProtoCommand msg -> ExceptT (ProtocolClientError err) IO msg
sendProtocolCommand_ c@ProtocolClient {client_ = PClient {sndQ}, thParams = THandleParams {batch, blockSize, serviceAuth}} nm nonce_ tOut pKey entId cmd =
  ExceptT $ uncurry sendRecv =<< mkTransmission_ c nonce_ (entId, pKey, cmd)
  where
    sendRecv :: Either TransportError SentRawTransmission -> Request err msg -> IO (Either (ProtocolClientError err) msg)
    sendRecv t_ r = case t_ of
      Left e -> pure . Left $ PCETransportError e
      Right t
        | B.length s > blockSize - 2 -> pure . Left $ PCETransportError TELargeMsg
        | otherwise -> do
            nonBlockingWriteTBQueue sndQ (Just r, s)
            response <$> getResponse c nm tOut r
        where
          s
            | batch = tEncodeBatch1 serviceAuth t
            | otherwise = tEncode serviceAuth t

nonBlockingWriteTBQueue :: TBQueue a -> a -> IO ()
nonBlockingWriteTBQueue q x = do
  sent <- atomically $ tryWriteTBQueue q x
  unless sent $ void $ forkIO $ atomically $ writeTBQueue q x

getResponse :: ProtocolClient v err msg -> NetworkRequestMode -> Maybe Int -> Request err msg -> IO (Response err msg)
getResponse ProtocolClient {client_ = PClient {tcpTimeout, timeoutErrorCount}} nm tOut Request {entityId, pending, responseVar} = do
  r <- fromMaybe (netTimeoutInt tcpTimeout nm) tOut `timeout` atomically (takeTMVar responseVar)
  response <- atomically $ do
    writeTVar pending False
    ((r <|>) <$> tryTakeTMVar responseVar) >>= \case
      Just r' -> writeTVar timeoutErrorCount 0 $> r'
      Nothing -> modifyTVar' timeoutErrorCount (+ 1) $> Left PCEResponseTimeout
  pure Response {entityId, response}

mkTransmission :: Protocol v err msg => ProtocolClient v err msg ->  ClientCommand msg -> IO (PCTransmission err msg)
mkTransmission c = mkTransmission_ c Nothing

mkTransmission_ :: forall v err msg. Protocol v err msg => ProtocolClient v err msg -> Maybe C.CbNonce -> ClientCommand msg -> IO (PCTransmission err msg)
mkTransmission_ ProtocolClient {thParams, client_ = PClient {clientCorrId, sentCommands}} nonce_ (entityId, pKey_, command) = do
  nonce@(C.CbNonce corrId) <- maybe (atomically $ C.randomCbNonce clientCorrId) pure nonce_
  let TransmissionForAuth {tForAuth, tToSend} = encodeTransmissionForAuth thParams (CorrId corrId, entityId, command)
      auth = authTransmission (thAuth thParams) (useServiceAuth command) pKey_ nonce tForAuth
  r <- mkRequest (CorrId corrId)
  pure ((,tToSend) <$> auth, r)
  where
    mkRequest :: CorrId -> IO (Request err msg)
    mkRequest corrId = do
      pending <- newTVarIO True
      responseVar <- newEmptyTMVarIO
      let r =
            Request
              { corrId,
                entityId,
                command,
                pending,
                responseVar
              }
      atomically $ TM.insert corrId r sentCommands
      pure r

authTransmission :: Maybe (THandleAuth 'TClient) -> Bool -> Maybe C.APrivateAuthKey -> C.CbNonce -> ByteString -> Either TransportError (Maybe TAuthorizations)
authTransmission thAuth serviceAuth pKey_ nonce t = traverse authenticate pKey_
  where
    authenticate :: C.APrivateAuthKey -> Either TransportError TAuthorizations
    authenticate (C.APrivateAuthKey a pk) = (,serviceSig) <$> case a of
      C.SX25519 -> case thAuth of
        Just THAuthClient {peerServerPubKey = k} -> Right $ TAAuthenticator $ C.cbAuthenticate k pk nonce t'
        Nothing -> Left TENoServerAuth
      C.SEd25519 -> sign pk
      C.SEd448 -> sign pk
    (t', serviceSig) = case clientService =<< thAuth of
      Just THClientService {serviceCertHash = XV.Fingerprint fp, serviceKey} | serviceAuth ->
        (fp <> t, Just $ C.sign' serviceKey t)
      _ -> (t, Nothing)
    sign :: forall a. (C.AlgorithmI a, C.SignatureAlgorithm a) => C.PrivateKey a -> Either TransportError TransmissionAuth
    sign pk = Right $ TASignature $ C.ASignature (C.sAlgorithm @a) (C.sign' pk t')

data TBQueueInfo = TBQueueInfo
  { qLength :: Int,
    qFull :: Bool
  }
  deriving (Show)

getTBQueueInfo :: TBQueue a -> STM TBQueueInfo
getTBQueueInfo q = do
  qLength <- fromIntegral <$> lengthTBQueue q
  qFull <- isFullTBQueue q
  pure TBQueueInfo {qLength, qFull}

getProtocolClientQueuesInfo :: ProtocolClient v err msg -> IO (TBQueueInfo, TBQueueInfo)
getProtocolClientQueuesInfo ProtocolClient {client_ = PClient {sndQ, rcvQ}} = do
  sndQInfo <- atomically $ getTBQueueInfo sndQ
  rcvQInfo <- atomically $ getTBQueueInfo rcvQ
  pure (sndQInfo, rcvQInfo)

$(J.deriveJSON (enumJSON $ dropPrefix "HM") ''HostMode)

$(J.deriveJSON (enumJSON $ dropPrefix "SM") ''SocksMode)

$(J.deriveJSON (enumJSON $ dropPrefix "TSM") ''TransportSessionMode)

$(J.deriveJSON (enumJSON $ dropPrefix "SPM") ''SMPProxyMode)

$(J.deriveJSON (enumJSON $ dropPrefix "SPF") ''SMPProxyFallback)

$(J.deriveJSON (enumJSON $ dropPrefix "SWP") ''SMPWebPortServers)

$(J.deriveJSON defaultJSON ''NetworkTimeout)

$(J.deriveJSON defaultJSON ''NetworkConfig)

$(J.deriveJSON (sumTypeJSON $ dropPrefix "Proxy") ''ProxyClientError)

$(J.deriveJSON defaultJSON ''TBQueueInfo)
