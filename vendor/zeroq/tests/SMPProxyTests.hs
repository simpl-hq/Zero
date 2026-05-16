{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module SMPProxyTests where

import AgentTests.EqInstances ()
import AgentTests.FunctionalAPITests
import Control.Concurrent (ThreadId, threadDelay)
import Control.Logger.Simple
import Control.Monad (forM, forM_, forever, replicateM_)
import Control.Monad.Trans.Except (ExceptT, runExceptT)
import Data.ByteString.Char8 (ByteString)
import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as L
import Data.Time.Clock (getCurrentTime)
import SMPAgentClient
import SMPClient
import ServerTests (decryptMsgV3, sendRecv)
import Zero.Messaging.Agent hiding (createConnection, joinConnection, sendMessage)
import qualified Zero.Messaging.Agent as A
import Zero.Messaging.Agent.Env.SQLite (AgentConfig (..), InitialAgentServers (..))
import Zero.Messaging.Agent.Protocol hiding (CON, CONF, INFO, REQ)
import qualified Zero.Messaging.Agent.Protocol as A
import Zero.Messaging.Client
import qualified Zero.Messaging.Crypto as C
import Zero.Messaging.Crypto.Ratchet (pattern PQSupportOn)
import qualified Zero.Messaging.Crypto.Ratchet as CR
import Zero.Messaging.Protocol (EncRcvMsgBody (..), MsgBody, QueueReqData (..), RcvMessage (..), SubscriptionMode (..), maxMessageLength, noMsgFlags)
import qualified Zero.Messaging.Protocol as SMP
import Zero.Messaging.Server.Env.STM (AStoreType (..), ServerConfig (..))
import Zero.Messaging.Server.MsgStore.Types (SQSType (..))
import Zero.Messaging.Transport
import Zero.Messaging.Util (bshow, tshow)
import Zero.Messaging.Version (mkVersionRange)
import System.FilePath (splitExtensions)
import System.Random (randomRIO)
import Test.Hspec hiding (fit, it)
import UnliftIO
import Util
#if defined(dbPostgres)
import Fixtures
import Zero.Messaging.Agent.Store.Postgres.Util (dropAllSchemasExceptSystem)
#endif

smpProxyTests :: SpecWith AStoreType
smpProxyTests = do
  describe "server configuration" $ do
    it "refuses proxy handshake unless enabled" testNoProxy
    it "checks basic auth in proxy requests" testProxyAuth
  describe "relay reconnection" $ do
    it "recovers when unresponsive relay restarts (control, no disconnect)" $ \_ ->
      testProxyRecoversWithoutDisconnect
    it "reconnects to relay after sender disconnects mid-connection" $ \_ ->
      testProxyReconnectAfterRelayRestart
  describe "agent client reconnection" $ do
    it "reconnects after a connect is cancelled mid-flight" $ \_ ->
      testAgentClientReconnectAfterCancel
  describe "proxy requests" $ do
    describe "bad relay URIs" $ do
      xit "host not resolved" todo
      xit "when SMP port blackholed" todo
      xit "no SMP service at host/port" todo
      xit "bad SMP fingerprint" todo
    xit "batching proxy requests" todo
  describe "deliver message via SMP proxy" $ do
    let srv1 = SMPServer testHost testPort testKeyHash
        srv2 = SMPServer testHost2 testPort2 testKeyHash
    describe "client API" $ do
      let maxLen = maxMessageLength encryptedBlockSMPVersion
      describe "one server" $ do
        it "deliver via proxy" . oneServer $ do
          deliverMessageViaProxy srv1 srv1 C.SEd448 "hello 1" "hello 2"
      describe "two servers" $ do
        let proxyServ = srv1
            relayServ = srv2
        (msg1, msg2) <- runIO $ do
          g <- C.newRandom
          atomically $ (,) <$> C.randomBytes maxLen g <*> C.randomBytes maxLen g
        it "deliver via proxy" . twoServersFirstProxy $
          deliverMessageViaProxy proxyServ relayServ C.SEd448 "hello 1" "hello 2"
        it "max message size, Ed448 keys" . twoServersFirstProxy $
          deliverMessageViaProxy proxyServ relayServ C.SEd448 msg1 msg2
        it "max message size, Ed25519 keys" . twoServersFirstProxy $
          deliverMessageViaProxy proxyServ relayServ C.SEd25519 msg1 msg2
        it "max message size, X25519 keys" . twoServersFirstProxy $
          deliverMessageViaProxy proxyServ relayServ C.SX25519 msg1 msg2
      describe "stress test 1k" $ do
        let deliver n = deliverMessagesViaProxy srv1 srv2 C.SEd448 [] (map bshow [1 :: Int .. n])
        it "1x1000" . twoServersFirstProxy $ deliver 1000
        it "5x200" . twoServersFirstProxy $ 5 `inParrallel` deliver 200
        it "10x100" . twoServersFirstProxy $ 10 `inParrallel` deliver 100
      describe "stress test - no host" $ do
        it "1x1000, no delay" . oneServer $ proxyConnectDeadRelay 1000 0 srv1
        xit "1x1000, 100ms" . oneServer $ proxyConnectDeadRelay 1000 100000 srv1
        xit "100x1000, 100ms" . oneServer $ 100 `inParrallel` (randomRIO (0, 1000000) >>= threadDelay >> proxyConnectDeadRelay 1000 100000 srv1)
      xdescribe "stress test 10k" $ do
        let deliver n = deliverMessagesViaProxy srv1 srv2 C.SEd448 [] (map bshow [1 :: Int .. n])
        it "1x10000" . twoServersFirstProxy $ deliver 10000
        it "5x2000" . twoServersFirstProxy $ 5 `inParrallel` deliver 2000
        it "10x1000" . twoServersFirstProxy $ 10 `inParrallel` deliver 1000
        it "100x100 N1" . twoServersFirstProxy $ withNumCapabilities 1 $ 100 `inParrallel` deliver 100
        it "100x100 N4 C1" . twoServersNoConc $ withNumCapabilities 4 $ 100 `inParrallel` deliver 100
        it "100x100 N4 C2" . twoServersFirstProxy $ withNumCapabilities 4 $ 100 `inParrallel` deliver 100
        it "100x100 N4 C16" . twoServersMoreConc $ withNumCapabilities 4 $ 100 `inParrallel` deliver 100
        it "100x100 N" . twoServersFirstProxy $ withNCPUCapabilities $ 100 `inParrallel` deliver 100
        it "500x20" . twoServersFirstProxy $ 500 `inParrallel` deliver 20
#if defined(dbPostgres)
    after_ (dropAllSchemasExceptSystem testDBConnectInfo) . describe "agent API" $ do
#else
    describe "agent API" $ do
#endif
      describe "one server" $ do
        it "always via proxy" . oneServer $
          agentDeliverMessageViaProxy ([srv1], SPMAlways, True) ([srv1], SPMAlways, True) C.SEd448 "hello 1" "hello 2" 1
        it "without proxy" . oneServer $
          agentDeliverMessageViaProxy ([srv1], SPMNever, False) ([srv1], SPMNever, False) C.SEd448 "hello 1" "hello 2" 1
      describe "two servers" $ do
        it "always via proxy" $ \msType -> twoServers
          (agentDeliverMessageViaProxy ([srv1], SPMAlways, True) ([srv2], SPMAlways, True) C.SEd448 "hello 1" "hello 2" 1)
          msType
        it "both via proxy" . twoServers $
          agentDeliverMessageViaProxy ([srv1], SPMUnknown, True) ([srv2], SPMUnknown, True) C.SEd448 "hello 1" "hello 2" 1
        it "first via proxy" . twoServers $
          agentDeliverMessageViaProxy ([srv1], SPMUnknown, True) ([srv2], SPMNever, False) C.SEd448 "hello 1" "hello 2" 1
        it "without proxy" . twoServers $
          agentDeliverMessageViaProxy ([srv1], SPMNever, False) ([srv2], SPMNever, False) C.SEd448 "hello 1" "hello 2" 1
        it "first via proxy for unknown" . twoServers $
          agentDeliverMessageViaProxy ([srv1], SPMUnknown, True) ([srv1, srv2], SPMUnknown, False) C.SEd448 "hello 1" "hello 2" 1
        it "without proxy with fallback" . twoServers_ proxyCfg cfgV7 $
          agentDeliverMessageViaProxy ([srv1], SPMUnknown, False) ([srv2], SPMUnknown, False) C.SEd448 "hello 1" "hello 2" 3
        it "fails when fallback is prohibited" . twoServers_ proxyCfg cfgV7 $
          agentViaProxyVersionError
        it "retries sending when destination or proxy relay is offline" $ \_ ->
          agentViaProxyRetryOffline
        it "retries sending when destination relay session disconnects in proxy" $ \_ ->
          agentViaProxyRetryNoSession
      describe "stress test 1k" $ do
        let deliver nAgents nMsgs = agentDeliverMessagesViaProxyConc (replicate nAgents [srv1]) (map bshow [1 :: Int .. nMsgs])
        it "2 agents, 250 messages" . oneServer $ deliver 2 250
        it "5 agents, 10 pairs, 50 messages, N1" . oneServer . withNumCapabilities 1 $ deliver 5 50
        it "5 agents, 10 pairs, 50 messages. N4" . oneServer . withNumCapabilities 4 $ deliver 5 50
      xdescribe "stress test 10k" $ do
        let deliver nAgents nMsgs = agentDeliverMessagesViaProxyConc (replicate nAgents [srv1]) (map bshow [1 :: Int .. nMsgs])
        it "25 agents, 300 pairs, 17 messages" . oneServer . withNumCapabilities 4 $ deliver 25 17
  where
    oneServer test msType = withSmpServerConfigOn (transport @TLS) (updateCfg (proxyCfgMS msType) $ \cfg_ -> cfg_ {msgQueueQuota = 128, maxJournalMsgCount = 256}) testPort $ const test
    twoServers test msType = twoServers_ (proxyCfgMS msType) (proxyCfgMS msType) test msType
    twoServersFirstProxy test msType = twoServers_ (proxyCfgMS msType) (updateCfg (cfgMS msType) $ \cfg_ -> cfg_ {msgQueueQuota = 128, maxJournalMsgCount = 256}) test msType
    twoServersMoreConc test msType = twoServers_ (updateCfg (proxyCfgMS msType) $ \cfg_ -> cfg_ {serverClientConcurrency = 128}) (updateCfg (cfgMS msType) $ \cfg_ -> cfg_ {msgQueueQuota = 128, maxJournalMsgCount = 256}) test msType
    twoServersNoConc test msType = twoServers_ (updateCfg (proxyCfgMS msType) $ \cfg_ -> cfg_ {serverClientConcurrency = 1}) (updateCfg (cfgMS msType) $ \cfg_ -> cfg_ {msgQueueQuota = 128, maxJournalMsgCount = 256}) test msType
    twoServers_ :: AServerConfig -> AServerConfig -> IO () -> AStoreType -> IO ()
    twoServers_ cfg1 cfg2 runTest (ASType qsType _) =
      withSmpServerConfigOn (transport @TLS) cfg1 testPort $ \_ ->
        let cfg2' = case qsType of
              SQSMemory -> journalCfg cfg2 testStoreLogFile2 testStoreMsgsDir2
              SQSPostgres -> journalCfgDB cfg2 testStoreDBOpts2 testStoreMsgsDir2
         in withSmpServerConfigOn (transport @TLS) cfg2' testPort2 $ const runTest

deliverMessageViaProxy :: (C.AlgorithmI a, C.AuthAlgorithm a) => SMPServer -> SMPServer -> C.SAlgorithm a -> ByteString -> ByteString -> IO ()
deliverMessageViaProxy proxyServ relayServ alg msg msg' = deliverMessagesViaProxy proxyServ relayServ alg [msg] [msg']

deliverMessagesViaProxy :: (C.AlgorithmI a, C.AuthAlgorithm a) => SMPServer -> SMPServer -> C.SAlgorithm a -> [ByteString] -> [ByteString] -> IO ()
deliverMessagesViaProxy proxyServ relayServ alg unsecuredMsgs securedMsgs = do
  g <- C.newRandom
  ts <- getCurrentTime
  pc' <- getProtocolClient g NRMInteractive (1, proxyServ, Nothing) defaultSMPClientConfig {serverVRange = mkVersionRange minServerSMPRelayVersion currentClientSMPRelayVersion} [] Nothing ts (\_ -> pure ())
  pc <- either (fail . show) pure pc'
  THAuthClient {} <- maybe (fail "getProtocolClient returned no thAuth") pure $ thAuth $ thParams pc
  msgQ <- newTBQueueIO 1024
  rc' <- getProtocolClient g NRMInteractive (2, relayServ, Nothing) defaultSMPClientConfig {serverVRange = mkVersionRange minServerSMPRelayVersion currentClientSMPRelayVersion} [] (Just msgQ) ts (\_ -> pure ())
  rc <- either (fail . show) pure rc'
  (rPub, rPriv) <- atomically $ C.generateAuthKeyPair alg g
  (rdhPub, rdhPriv :: C.PrivateKeyX25519) <- atomically $ C.generateKeyPair g
  SMP.QIK {rcvId, sndId, rcvPublicDhKey = srvDh} <- runExceptT' $ createSMPQueue rc NRMInteractive Nothing (rPub, rPriv) rdhPub (Just "correct") SMSubscribe (QRMessaging Nothing) Nothing
  let dec = decryptMsgV3 $ C.dh' srvDh rdhPriv
  sess0 <- runExceptT' $ connectSMPProxiedRelay pc NRMInteractive relayServ (Just "correct")
  sess <- runExceptT' $ connectSMPProxiedRelay pc NRMInteractive relayServ (Just "correct")
  sess0 `shouldBe` sess
  forM_ unsecuredMsgs $ \msg -> do
    runExceptT' (proxySMPMessage pc NRMInteractive sess Nothing sndId noMsgFlags msg) `shouldReturn` Right ()
    runExceptT' (proxySMPMessage pc NRMInteractive sess {prSessionId = "bad session"} Nothing sndId noMsgFlags msg) `shouldReturn` Left (ProxyProtocolError $ SMP.PROXY SMP.NO_SESSION)
    (_tSess, _, [(_entId, STEvent (Right (SMP.MSG RcvMessage {msgId, msgBody = EncRcvMsgBody encBody})))]) <- atomically $ readTBQueue msgQ
    dec msgId encBody `shouldBe` Right msg
    runExceptT' $ ackSMPMessage rc rPriv rcvId msgId
  (sPub, sPriv) <- atomically $ C.generateAuthKeyPair alg g
  runExceptT' $ secureSMPQueue rc NRMInteractive rPriv rcvId sPub
  waitSendRecv
    ( forM_ securedMsgs $ \msg' ->
        runExceptT' (proxySMPMessage pc NRMInteractive sess (Just sPriv) sndId noMsgFlags msg') `shouldReturn` Right ()
    )
    ( forM_ securedMsgs $ \msg' -> do
        (_tSess, _, [(_entId, STEvent (Right (SMP.MSG RcvMessage {msgId = msgId', msgBody = EncRcvMsgBody encBody'})))]) <- atomically $ readTBQueue msgQ
        dec msgId' encBody' `shouldBe` Right msg'
        runExceptT' $ ackSMPMessage rc rPriv rcvId msgId'
    )

proxyConnectDeadRelay :: Int -> Int -> SMPServer -> IO ()
proxyConnectDeadRelay n d proxyServ = do
  g <- C.newRandom
  ts <- getCurrentTime
  pc' <- getProtocolClient g NRMInteractive (1, proxyServ, Nothing) defaultSMPClientConfig {serverVRange = mkVersionRange minServerSMPRelayVersion sendingProxySMPVersion} [] Nothing ts (\_ -> pure ())
  pc <- either (fail . show) pure pc'
  THAuthClient {} <- maybe (fail "getProtocolClient returned no thAuth") pure $ thAuth $ thParams pc
  replicateM_ n $ do
    sess0 <- runExceptT $ connectSMPProxiedRelay pc NRMInteractive (SMPServer testHost "45678" testKeyHash) (Just "correct")
    case sess0 of
      Right !_noWay -> error "got unexpected client"
      Left !_err -> threadDelay d

agentDeliverMessageViaProxy :: (C.AlgorithmI a, C.AuthAlgorithm a) => (NonEmpty SMPServer, SMPProxyMode, Bool) -> (NonEmpty SMPServer, SMPProxyMode, Bool) -> C.SAlgorithm a -> ByteString -> ByteString -> AgentMsgId -> IO ()
agentDeliverMessageViaProxy aTestCfg@(aSrvs, _, aViaProxy) bTestCfg@(bSrvs, _, bViaProxy) alg msg1 msg2 baseId =
  withAgent 1 aCfg (servers aTestCfg) testDB $ \alice ->
    withAgent 2 aCfg (servers bTestCfg) testDB2 $ \bob -> runRight_ $ do
      (bobId, CCLink qInfo Nothing) <- A.createConnection alice NRMInteractive 1 True True SCMInvitation Nothing Nothing CR.IKPQOn SMSubscribe
      aliceId <- A.prepareConnectionToJoin bob 1 True qInfo PQSupportOn
      sqSecured <- A.joinConnection bob NRMInteractive 1 aliceId True qInfo "bob's connInfo" PQSupportOn SMSubscribe
      liftIO $ sqSecured `shouldBe` True
      ("", _, A.CONF confId pqSup' _ "bob's connInfo") <- get alice
      liftIO $ pqSup' `shouldBe` PQSupportOn
      allowConnection alice bobId confId "alice's connInfo"
      let pqEnc = CR.PQEncOn
      get alice ##> ("", bobId, A.CON pqEnc)
      get bob ##> ("", aliceId, A.INFO PQSupportOn "alice's connInfo")
      get bob ##> ("", aliceId, A.CON pqEnc)
      let aProxySrv = if aViaProxy then Just $ L.head aSrvs else Nothing
      1 <- msgId <$> A.sendMessage alice bobId pqEnc noMsgFlags msg1
      get alice ##> ("", bobId, A.SENT (baseId + 1) aProxySrv)
      2 <- msgId <$> A.sendMessage alice bobId pqEnc noMsgFlags msg2
      get alice ##> ("", bobId, A.SENT (baseId + 2) aProxySrv)
      get bob =##> \case ("", c, Msg' _ pq msg1') -> c == aliceId && pq == pqEnc && msg1 == msg1'; _ -> False
      ackMessage bob aliceId (baseId + 1) Nothing
      get bob =##> \case ("", c, Msg' _ pq msg2') -> c == aliceId && pq == pqEnc && msg2 == msg2'; _ -> False
      ackMessage bob aliceId (baseId + 2) Nothing
      let bProxySrv = if bViaProxy then Just $ L.head bSrvs else Nothing
      3 <- msgId <$> A.sendMessage bob aliceId pqEnc noMsgFlags msg1
      get bob ##> ("", aliceId, A.SENT (baseId + 3) bProxySrv)
      4 <- msgId <$> A.sendMessage bob aliceId pqEnc noMsgFlags msg2
      get bob ##> ("", aliceId, A.SENT (baseId + 4) bProxySrv)
      get alice =##> \case ("", c, Msg' _ pq msg1') -> c == bobId && pq == pqEnc && msg1 == msg1'; _ -> False
      ackMessage alice bobId (baseId + 3) Nothing
      get alice =##> \case ("", c, Msg' _ pq msg2') -> c == bobId && pq == pqEnc && msg2 == msg2'; _ -> False
      ackMessage alice bobId (baseId + 4) Nothing
  where
    msgId = subtract baseId . fst
    aCfg = agentCfg {sndAuthAlg = C.AuthAlg alg, rcvAuthAlg = C.AuthAlg alg}
    servers (srvs, smpProxyMode, _) = (initAgentServersProxy_ smpProxyMode SPFAllow) {smp = userServers srvs}

agentDeliverMessagesViaProxyConc :: [NonEmpty SMPServer] -> [MsgBody] -> IO ()
agentDeliverMessagesViaProxyConc agentServers msgs =
  withAgents $ \agents -> do
    let pairs = combinations 2 agents
    logNote $ "Pairing " <> tshow (length agents) <> " agents into " <> tshow (length pairs) <> " connections"
    connections <- forM pairs $ \case
      [a, b] -> prePair a b
      _ -> error "agents must be paired"
    logNote "Running..."
    mapConcurrently_ run connections
  where
    withAgents :: ([AgentClient] -> IO ()) -> IO ()
    withAgents action = go [] (zip [1 :: Int ..] agentServers)
      where
        go agents = \case
          [] -> action agents
          (aId, aSrvs) : next -> withAgent aId aCfg (servers aSrvs) (dbPrefix <> show aId <> dbSuffix) $ \a -> (a : agents) `go` next
        (dbPrefix, dbSuffix) = splitExtensions testDB
    prePair alice bob = do
      (bobId, CCLink qInfo Nothing) <- runExceptT' $ A.createConnection alice NRMInteractive 1 True True SCMInvitation Nothing Nothing CR.IKPQOn SMSubscribe
      aliceId <- runExceptT' $ A.prepareConnectionToJoin bob 1 True qInfo PQSupportOn
      sqSecured <- runExceptT' $ A.joinConnection bob NRMInteractive 1 aliceId True qInfo "bob's connInfo" PQSupportOn SMSubscribe
      liftIO $ sqSecured `shouldBe` True
      confId <-
        get alice >>= \case
          ("", _, A.CONF confId pqSup' _ "bob's connInfo") -> do
            pqSup' `shouldBe` PQSupportOn
            pure confId
          huh -> fail $ show huh
      runExceptT' $ allowConnection alice bobId confId "alice's connInfo"
      get alice ##> ("", bobId, A.CON pqEnc)
      get bob ##> ("", aliceId, A.INFO PQSupportOn "alice's connInfo")
      get bob ##> ("", aliceId, A.CON pqEnc)
      pure (alice, bobId, bob, aliceId)
    run (alice, bobId, bob, aliceId) = do
      aSender <- async $ forM_ msgs $ runExceptT' . A.sendMessage alice bobId pqEnc noMsgFlags
      bRecipient <-
        async $
          forever $
            get bob >>= \case
              ("", _, A.SENT _ _) -> pure ()
              ("", _, Msg' mId' _ _) -> runExceptT' $ ackMessage alice bobId mId' Nothing
              huh -> fail (show huh)
      bSender <- async $ forM_ msgs $ runExceptT' . A.sendMessage bob aliceId pqEnc noMsgFlags
      aRecipient <-
        async $
          forever $
            get alice >>= \case
              ("", _, A.SENT _ _) -> pure ()
              ("", _, Msg' mId' _ _) -> runExceptT' $ ackMessage alice bobId mId' Nothing
              huh -> fail (show huh)
      logDebug "run waiting..."
      a2b <- async $ (waitCatch aSender >>= either throwIO pure) `finally` cancel bRecipient
      b2a <- async $ (waitCatch bSender >>= either throwIO pure) `finally` cancel aRecipient
      waitEitherCatch a2b b2a >>= \case
        Right (Right ()) -> wait b2a
        Right (Left e) -> cancel bSender >> throwIO e
        Left (Right ()) -> wait a2b
        Left (Left e) -> cancel aSender >> throwIO e
      logDebug "run finished"
    pqEnc = CR.PQEncOn
    aCfg = agentCfg {sndAuthAlg = C.AuthAlg C.SEd448, rcvAuthAlg = C.AuthAlg C.SEd448}
    servers srvs = (initAgentServersProxy_ SPMAlways SPFAllow) {smp = userServers srvs}

agentViaProxyVersionError :: IO ()
agentViaProxyVersionError =
  withAgent 1 agentCfg (servers [SMPServer testHost testPort testKeyHash]) testDB $ \alice -> do
    Left (A.BROKER _ (TRANSPORT TEVersion)) <-
      withAgent 2 agentCfg (servers [SMPServer testHost2 testPort2 testKeyHash]) testDB2 $ \bob -> runExceptT $ do
        (_bobId, CCLink qInfo Nothing) <- A.createConnection alice NRMInteractive 1 True True SCMInvitation Nothing Nothing CR.IKPQOn SMSubscribe
        aliceId <- A.prepareConnectionToJoin bob 1 True qInfo PQSupportOn
        A.joinConnection bob NRMInteractive 1 aliceId True qInfo "bob's connInfo" PQSupportOn SMSubscribe
    pure ()
  where
    servers srvs = (initAgentServersProxy_ SPMUnknown SPFProhibit) {smp = userServers srvs}

agentViaProxyRetryOffline :: IO ()
agentViaProxyRetryOffline = do
  let srv1 = SMPServer testHost testPort testKeyHash
      srv2 = SMPServer testHost testPort2 testKeyHash
      msg1 = "hello 1"
      msg2 = "hello 2"
      aProxySrv = Just srv1
      bProxySrv = Just srv2
  withAgent 1 aCfg (servers srv1) testDB $ \alice ->
    withAgent 2 aCfg (servers srv2) testDB2 $ \bob -> do
      let pqEnc = CR.PQEncOn
      withServer $ \_ -> do
        (aliceId, bobId) <- withServer2 $ \_ -> runRight $ do
          (bobId, CCLink qInfo Nothing) <- A.createConnection alice NRMInteractive 1 True True SCMInvitation Nothing Nothing CR.IKPQOn SMSubscribe
          aliceId <- A.prepareConnectionToJoin bob 1 True qInfo PQSupportOn
          sqSecured <- A.joinConnection bob NRMInteractive 1 aliceId True qInfo "bob's connInfo" PQSupportOn SMSubscribe
          liftIO $ sqSecured `shouldBe` True
          ("", _, A.CONF confId pqSup' _ "bob's connInfo") <- get alice
          liftIO $ pqSup' `shouldBe` PQSupportOn
          allowConnection alice bobId confId "alice's connInfo"
          get alice ##> ("", bobId, A.CON pqEnc)
          get bob ##> ("", aliceId, A.INFO PQSupportOn "alice's connInfo")
          get bob ##> ("", aliceId, A.CON pqEnc)
          1 <- msgId <$> A.sendMessage alice bobId pqEnc noMsgFlags msg1
          get alice ##> ("", bobId, A.SENT (baseId + 1) aProxySrv)
          get bob =##> \case ("", c, Msg' _ pq msg1') -> c == aliceId && pq == pqEnc && msg1 == msg1'; _ -> False
          ackMessage bob aliceId (baseId + 1) Nothing
          2 <- msgId <$> A.sendMessage bob aliceId pqEnc noMsgFlags msg2
          get bob ##> ("", aliceId, A.SENT (baseId + 2) bProxySrv)
          get alice =##> \case ("", c, Msg' _ pq msg2') -> c == bobId && pq == pqEnc && msg2 == msg2'; _ -> False
          ackMessage alice bobId (baseId + 2) Nothing
          pure (aliceId, bobId)
        runRight_ $ do
          3 <- msgId <$> A.sendMessage alice bobId pqEnc noMsgFlags msg1
          bob `down` aliceId
        withServer2 $ \_ -> runRight_ $ do
          bob `up` aliceId
          get alice ##> ("", bobId, A.SENT (baseId + 3) aProxySrv)
          get bob =##> \case ("", c, Msg' _ pq msg1') -> c == aliceId && pq == pqEnc && msg1 == msg1'; _ -> False
          ackMessage bob aliceId (baseId + 3) Nothing
        runRight_ $ do
          4 <- msgId <$> A.sendMessage bob aliceId pqEnc noMsgFlags msg2
          bob `down` aliceId
        withServer2 $ \_ -> do
          getInAnyOrder
            bob
            [ \case ("", "", AEvt SAENone (UP _ [c])) -> c == aliceId; _ -> False,
              \case ("", c, AEvt SAEConn (A.SENT mId srv)) -> c == aliceId && mId == baseId + 4 && srv == bProxySrv; _ -> False
            ]
          runRight_ $ do
            get alice =##> \case ("", c, Msg' _ pq msg2') -> c == bobId && pq == pqEnc && msg2 == msg2'; _ -> False
            ackMessage alice bobId (baseId + 4) Nothing
  where
    withServer :: (ThreadId -> IO a) -> IO a
    withServer = withServer_ testStoreLogFile testStoreMsgsDir testStoreNtfsFile testPort
    withServer2 :: (ThreadId -> IO a) -> IO a
    withServer2 = withServer_ testStoreLogFile2 testStoreMsgsDir2 testStoreNtfsFile2 testPort2
    withServer_ storeLog storeMsgs storeNtfs =
      let cfg' = updateCfg (journalCfg proxyCfg storeLog storeMsgs) $ \cfg_ -> cfg_ {storeNtfsFile = Just storeNtfs}
       in withSmpServerConfigOn (transport @TLS) cfg'
    a `up` cId = nGet a =##> \case ("", "", UP _ [c]) -> c == cId; _ -> False
    a `down` cId = nGet a =##> \case ("", "", DOWN _ [c]) -> c == cId; _ -> False
    aCfg = agentCfg {messageRetryInterval = fastMessageRetryInterval}
    baseId = 1
    msgId = subtract baseId . fst
    servers srv = initAgentServersProxy {smp = userServers [srv]}

agentViaProxyRetryNoSession :: IO ()
agentViaProxyRetryNoSession = do
  let srv1 = SMPServer testHost testPort testKeyHash
      srv2 = SMPServer testHost testPort2 testKeyHash
  withAgent 1 agentCfg (servers srv1) testDB $ \a ->
    withAgent 2 agentCfg (servers srv2) testDB2 $ \b -> do
      withSmpServerConfigOn (transport @TLS) proxyCfg testPort $ \_ -> do
        (aId, _) <- withServer2 $ \_ -> runRight $ makeConnection a b
        nGet b =##> \case ("", "", DOWN _ [c]) -> c == aId; _ -> False
        withServer2 $ \_ -> do
          nGet b =##> \case ("", "", UP _ [c]) -> c == aId; _ -> False
          _ <- runRight $ makeConnection b a
          pure ()
  where
    withServer2 = withSmpServerConfigOn (transport @TLS) proxyCfgJ2 testPort2
    servers srv = initAgentServersProxy {smp = userServers [srv]}

testNoProxy :: AStoreType -> IO ()
testNoProxy msType = do
  withSmpServerConfigOn (transport @TLS) (cfgMS msType) testPort2 $ \_ -> do
    testSMPClient_ "127.0.0.1" testPort2 proxyVRangeV8 Nothing $ \(th :: THandleSMP TLS 'TClient) -> do
      (_, _, reply) <- sendRecv th (Nothing, "0", NoEntity, SMP.PRXY testSMPServer Nothing)
      reply `shouldBe` Right (SMP.ERR $ SMP.PROXY SMP.BASIC_AUTH)

testProxyAuth :: AStoreType -> IO ()
testProxyAuth msType = do
  withSmpServerConfigOn (transport @TLS) proxyCfgAuth testPort $ \_ -> do
    testSMPClient_ "127.0.0.1" testPort proxyVRangeV8 Nothing $ \(th :: THandleSMP TLS 'TClient) -> do
      (_, _, reply) <- sendRecv th (Nothing, "0", NoEntity, SMP.PRXY testSMPServer2 $ Just "wrong")
      reply `shouldBe` Right (SMP.ERR $ SMP.PROXY SMP.BASIC_AUTH)
  where
    proxyCfgAuth = updateCfg (proxyCfgMS msType) $ \cfg_ -> cfg_ {newQueueBasicAuth = Just "correct"}

requestRelaySession :: IO (Either SMP.ErrorType SMP.BrokerMsg)
requestRelaySession =
  testSMPClient_ "localhost" testPort proxyVRangeV8 Nothing $ \(th :: THandleSMP TLS 'TClient) ->
    (\(_, _, reply) -> reply) <$> sendRecv th (Nothing, "1", NoEntity, SMP.PRXY testSMPServer2 Nothing)

requireProxyReconnect :: IO ()
requireProxyReconnect =
  withSmpServerConfigOn (transport @TLS) proxyCfgJ2 testPort2 $ \_ -> do
    testSMPClient_ "127.0.0.1" testPort2 proxyVRangeV8 Nothing $ \(th :: THandleSMP TLS 'TClient) -> do
      (_, _, reply) <- sendRecv th (Nothing, "0", NoEntity, SMP.PING)
      reply `shouldBe` Right SMP.PONG
    threadDelay 1500000
    requestRelaySession >>= \case
      Right SMP.PKEY {} -> pure ()
      reply -> expectationFailure $ "proxy failed to reach the healthy relay; expected PKEY, got: " <> show reply

testProxyRecoversWithoutDisconnect :: IO ()
testProxyRecoversWithoutDisconnect =
  withSmpServerConfigOn (transport @TLS) proxyCfgShortTimeout testPort $ \_ -> do
    withStallingServerOn testPort2 $
      requestRelaySession >>= \case
        Right (SMP.ERR (SMP.PROXY (SMP.BROKER _))) -> pure ()
        reply -> expectationFailure $ "expected a proxy broker error from the unresponsive relay, got: " <> show reply
    requireProxyReconnect

testProxyReconnectAfterRelayRestart :: IO ()
testProxyReconnectAfterRelayRestart =
  withSmpServerConfigOn (transport @TLS) proxyCfgShortTimeout testPort $ \_ -> do
    withStallingServerOn testPort2 $
      race_ (threadDelay 1000000) requestRelaySession
    requireProxyReconnect

testAgentClientReconnectAfterCancel :: IO ()
testAgentClientReconnectAfterCancel =
  withAgent 1 agentCfg agentServersLeak testDB $ \a -> do
    withStallingServerOn testPort2 $ do
      t <- async $ runExceptT $ A.createConnection a NRMInteractive 1 True True SCMInvitation Nothing Nothing CR.IKPQOn SMSubscribe
      threadDelay 1000000
      cancel t
    withSmpServerConfigOn (transport @TLS) cfgJ2 testPort2 $ \_ -> do
      testSMPClient_ "127.0.0.1" testPort2 proxyVRangeV8 Nothing $ \(th :: THandleSMP TLS 'TClient) -> do
        (_, _, reply) <- sendRecv th (Nothing, "0", NoEntity, SMP.PING)
        reply `shouldBe` Right SMP.PONG
      r <- timeout 8000000 $ runExceptT $ A.createConnection a NRMInteractive 1 True True SCMInvitation Nothing Nothing CR.IKPQOn SMSubscribe
      case r of
        Just (Right _) -> pure ()
        _ -> expectationFailure $ "agent failed to connect after a cancelled connect; got: " <> show r
  where
    agentServersLeak =
      initAgentServers
        { smp = userServers [testSMPServer2],
          netCfg = (netCfg initAgentServers) {tcpConnectTimeout = NetworkTimeout 4000000 4000000}
        }

todo :: AStoreType -> IO ()
todo _ = fail "TODO"

runExceptT' :: Exception e => ExceptT e IO a -> IO a
runExceptT' a = runExceptT a >>= either throwIO pure

waitSendRecv :: IO () -> IO () -> IO ()
waitSendRecv s r = do
  s' <- async s
  r' <- async r
  waitCatch s' >>= either (\e -> cancel r' >> fail (show e)) pure
  waitCatch r' >>= either (\e -> cancel s' >> fail (show e)) pure
