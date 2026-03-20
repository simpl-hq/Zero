{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

module Zero.Messaging.Transport
  (
    SMPVersion,
    VersionSMP,
    VersionRangeSMP,
    THandleSMP,
    alpnSupportedSMPHandshakes,
    supportedClientSMPRelayVRange,
    supportedServerSMPRelayVRange,
    supportedProxyClientSMPRelayVRange,
    proxiedSMPRelayVRange,
    minClientSMPRelayVersion,
    minServerSMPRelayVersion,
    currentClientSMPRelayVersion,
    currentServerSMPRelayVersion,
    authCmdsSMPVersion,
    sendingProxySMPVersion,
    sndAuthKeySMPVersion,
    deletedEventSMPVersion,
    encryptedBlockSMPVersion,
    blockedEntitySMPVersion,
    shortLinksSMPVersion,
    serviceCertsSMPVersion,
    newNtfCredsSMPVersion,
    clientNoticesSMPVersion,
    rcvServiceSMPVersion,
    namesSMPVersion,
    zeroQVersion,
    smpBlockSize,
    TransportConfig (..),

    Transport (..),
    TProxy (..),
    ATransport (..),
    ASrvTransport,
    TransportPeer (..),
    STransportPeer (..),
    TransportPeerI (..),
    getServerVerifyKey,

    TLS (..),
    SessionId,
    ServiceId,
    EntityId (..),
    pattern NoEntity,
    ALPN,
    connectTLS,
    closeTLS,
    defaultSupportedParams,
    defaultSupportedParamsHTTPS,
    withTlsUnique,

    THandle (..),
    THandleParams (..),
    THandleAuth (..),
    CertChainPubKey (..),
    ServiceCredentials (..),
    THClientService' (..),
    THClientService,
    THPeerClientService,
    SMPServiceRole (..),
    TSbChainKeys (..),
    TransportError (..),
    HandshakeError (..),
    smpServerHandshake,
    smpClientHandshake,
    tPutBlock,
    tGetBlock,
    sendHandshake,
    getHandshake,
    smpTHParamsSetVersion,
  )
where

import Control.Applicative (optional)
import Control.Concurrent.STM
import Control.Monad
import Control.Monad.Except
import Control.Monad.IO.Class
import Control.Monad.Trans.Except (throwE)
import qualified Data.Aeson.TH as J
import Data.Attoparsec.ByteString.Char8 (Parser)
import qualified Data.Attoparsec.ByteString.Char8 as A
import Data.Bifunctor (first)
import Data.Bitraversable (bimapM)
import Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy.Char8 as LB
import Data.Default (def)
import Data.Functor (($>))
import Data.Kind (Type)
import Data.Tuple (swap)
import Data.Typeable (Typeable)
import Data.Version (showVersion)
import Data.Word (Word16)
import qualified Data.X509 as X
import qualified Data.X509.Validation as XV
import GHC.IO.Handle.Internals (ioe_EOF)
import Network.Socket
import qualified Network.TLS as T
import qualified Network.TLS.Extra as TE
import qualified Paths_zeroq as SMQ
import qualified Zero.Messaging.Crypto as C
import Zero.Messaging.Encoding
import Zero.Messaging.Encoding.String
import Zero.Messaging.Parsers (dropPrefix, parseRead1, sumTypeJSON)
import Zero.Messaging.Transport.Buffer
import Zero.Messaging.Transport.Shared
import Zero.Messaging.Util (bshow, catchAll, catchAll_, liftEitherWith)
import Zero.Messaging.Version
import Zero.Messaging.Version.Internal
import System.IO.Error (isEOFError)
import UnliftIO.Exception (Exception)
import qualified UnliftIO.Exception as E

smpBlockSize :: Int
smpBlockSize = 16384

data SMPVersion

instance VersionScope SMPVersion

type VersionSMP = Version SMPVersion

type VersionRangeSMP = VersionRange SMPVersion

pattern VersionSMP :: Word16 -> VersionSMP
pattern VersionSMP v = Version v

_subModeSMPVersion :: VersionSMP
_subModeSMPVersion = VersionSMP 6

authCmdsSMPVersion :: VersionSMP
authCmdsSMPVersion = VersionSMP 7

sendingProxySMPVersion :: VersionSMP
sendingProxySMPVersion = VersionSMP 8

sndAuthKeySMPVersion :: VersionSMP
sndAuthKeySMPVersion = VersionSMP 9

deletedEventSMPVersion :: VersionSMP
deletedEventSMPVersion = VersionSMP 10

encryptedBlockSMPVersion :: VersionSMP
encryptedBlockSMPVersion = VersionSMP 11

blockedEntitySMPVersion :: VersionSMP
blockedEntitySMPVersion = VersionSMP 12

proxyServerHandshakeSMPVersion :: VersionSMP
proxyServerHandshakeSMPVersion = VersionSMP 14

shortLinksSMPVersion :: VersionSMP
shortLinksSMPVersion = VersionSMP 15

serviceCertsSMPVersion :: VersionSMP
serviceCertsSMPVersion = VersionSMP 16

newNtfCredsSMPVersion :: VersionSMP
newNtfCredsSMPVersion = VersionSMP 17

clientNoticesSMPVersion :: VersionSMP
clientNoticesSMPVersion = VersionSMP 18

rcvServiceSMPVersion :: VersionSMP
rcvServiceSMPVersion = VersionSMP 19

namesSMPVersion :: VersionSMP
namesSMPVersion = VersionSMP 20

minClientSMPRelayVersion :: VersionSMP
minClientSMPRelayVersion = VersionSMP 6

minServerSMPRelayVersion :: VersionSMP
minServerSMPRelayVersion = VersionSMP 6

currentClientSMPRelayVersion :: VersionSMP
currentClientSMPRelayVersion = VersionSMP 20

legacyServerSMPRelayVersion :: VersionSMP
legacyServerSMPRelayVersion = VersionSMP 6

currentServerSMPRelayVersion :: VersionSMP
currentServerSMPRelayVersion = VersionSMP 20

proxiedSMPRelayVersion :: VersionSMP
proxiedSMPRelayVersion = VersionSMP 20

supportedClientSMPRelayVRange :: VersionRangeSMP
supportedClientSMPRelayVRange = mkVersionRange minClientSMPRelayVersion currentClientSMPRelayVersion

legacyServerSMPRelayVRange :: VersionRangeSMP
legacyServerSMPRelayVRange = mkVersionRange minServerSMPRelayVersion legacyServerSMPRelayVersion

supportedServerSMPRelayVRange :: VersionRangeSMP
supportedServerSMPRelayVRange = mkVersionRange minServerSMPRelayVersion currentServerSMPRelayVersion

supportedProxyClientSMPRelayVRange :: VersionRangeSMP
supportedProxyClientSMPRelayVRange = mkVersionRange minServerSMPRelayVersion currentServerSMPRelayVersion

proxiedSMPRelayVRange :: VersionRangeSMP
proxiedSMPRelayVRange = mkVersionRange sendingProxySMPVersion proxiedSMPRelayVersion

alpnSupportedSMPHandshakes :: [ALPN]
alpnSupportedSMPHandshakes = ["smp/1"]

zeroQVersion :: String
zeroQVersion = showVersion SMQ.version

data TransportConfig = TransportConfig
  { logTLSErrors :: Bool,
    transportTimeout :: Maybe Int
  }

class Typeable c => Transport (c :: TransportPeer -> Type) where
  transport :: forall p. ATransport p
  transport = ATransport (TProxy @c @p)

  transportName :: TProxy c p -> String

  transportConfig :: c p -> TransportConfig

  getTransportConnection :: TransportPeerI p => TransportConfig -> Bool -> X.CertificateChain -> T.Context -> IO (c p)

  certificateSent :: c p -> Bool

  getPeerCertChain :: c p -> X.CertificateChain

  tlsUnique :: c p -> SessionId

  getSessionALPN :: c p -> Maybe ALPN

  closeConnection :: c p -> IO ()

  cGet :: c p -> Int -> IO ByteString

  cPut :: c p -> ByteString -> IO ()

  getLn :: c p -> IO ByteString

  putLn :: c p -> ByteString -> IO ()
  putLn c = cPut c . (<> "\r\n")

data TransportPeer = TClient | TServer
  deriving (Eq, Show)

data STransportPeer (p :: TransportPeer) where
  STClient :: STransportPeer 'TClient
  STServer :: STransportPeer 'TServer

class TransportPeerI p where sTransportPeer :: STransportPeer p

instance TransportPeerI 'TClient where sTransportPeer = STClient

instance TransportPeerI 'TServer where sTransportPeer = STServer

data TProxy (c :: TransportPeer -> Type) (p :: TransportPeer) = TProxy

data ATransport p = forall c. Transport c => ATransport (TProxy c p)

type ASrvTransport = ATransport 'TServer

getServerVerifyKey :: Transport c => c 'TClient -> Either String C.APublicVerifyKey
getServerVerifyKey c =
  case getPeerCertChain c of
    X.CertificateChain (server : _ca) -> getCertVerifyKey server
    _ -> Left "no certificate chain"

getCertVerifyKey :: X.SignedCertificate -> Either String C.APublicVerifyKey
getCertVerifyKey cert = C.x509ToPublic' $ X.certPubKey $ X.signedObject $ X.getSigned cert

data TLS (p :: TransportPeer) = TLS
  { tlsContext :: T.Context,
    tlsUniq :: ByteString,
    tlsBuffer :: TBuffer,
    tlsALPN :: Maybe ALPN,
    tlsCertSent :: Bool,
    tlsPeerCert :: X.CertificateChain,
    tlsTransportConfig :: TransportConfig
  }

type ALPN = ByteString

connectTLS :: T.TLSParams p => Maybe HostName -> TransportConfig -> p -> Socket -> IO T.Context
connectTLS host_ TransportConfig {logTLSErrors} params sock =
  E.bracketOnError (T.contextNew sock params) closeTLS $ \ctx ->
    logHandshakeErrors (T.handshake ctx) $> ctx
  where
    logHandshakeErrors = if logTLSErrors then (`catchAll` logThrow) else id
    logThrow e = putStrLn ("TLS error" <> host <> ": " <> show e) >> E.throwIO e
    host = maybe "" (\h -> " (" <> h <> ")") host_

getTLS :: forall p. TransportPeerI p => TransportConfig -> Bool -> X.CertificateChain -> T.Context -> IO (TLS p)
getTLS cfg tlsCertSent tlsPeerCert cxt = withTlsUnique @TLS @p cxt newTLS
  where
    newTLS tlsUniq = do
      tlsBuffer <- newTBuffer
      tlsALPN <- T.getNegotiatedProtocol cxt
      pure TLS {tlsContext = cxt, tlsALPN, tlsTransportConfig = cfg, tlsCertSent, tlsPeerCert, tlsUniq, tlsBuffer}

withTlsUnique :: forall c p. TransportPeerI p => T.Context -> (ByteString -> IO (c p)) -> IO (c p)
withTlsUnique cxt f =
  cxtFinished cxt
    >>= maybe (closeTLS cxt >> ioe_EOF) f
  where
    cxtFinished = case sTransportPeer @p of
      STServer -> T.getPeerFinished
      STClient -> T.getFinished

closeTLS :: T.Context -> IO ()
closeTLS ctx =
  T.bye ctx
    `E.finally` T.contextClose ctx
    `catchAll_` pure ()

defaultSupportedParams :: T.Supported
defaultSupportedParams =
  def
    { T.supportedVersions = [T.TLS13, T.TLS12],
      T.supportedCiphers =
        [ TE.cipher_TLS13_CHACHA20POLY1305_SHA256,
          TE.cipher_ECDHE_ECDSA_CHACHA20POLY1305_SHA256
        ],
      T.supportedHashSignatures = [(T.HashIntrinsic, T.SignatureEd448), (T.HashIntrinsic, T.SignatureEd25519)],
      T.supportedGroups = [T.X448, T.X25519],
      T.supportedSecureRenegotiation = False
    }

defaultSupportedParamsHTTPS :: T.Supported
defaultSupportedParamsHTTPS =
  defaultSupportedParams
    { T.supportedCiphers = TE.ciphersuite_strong,
      T.supportedGroups = [T.X25519, T.X448, T.FFDHE4096, T.FFDHE6144, T.FFDHE8192, T.P521],
      T.supportedHashSignatures =
        [ (T.HashIntrinsic, T.SignatureEd448),
          (T.HashIntrinsic, T.SignatureEd25519),
          (T.HashSHA256, T.SignatureECDSA),
          (T.HashSHA384, T.SignatureECDSA),
          (T.HashSHA512, T.SignatureECDSA),
          (T.HashIntrinsic, T.SignatureRSApssRSAeSHA512),
          (T.HashIntrinsic, T.SignatureRSApssRSAeSHA384),
          (T.HashIntrinsic, T.SignatureRSApssRSAeSHA256),
          (T.HashSHA512, T.SignatureRSA),
          (T.HashSHA384, T.SignatureRSA),
          (T.HashSHA256, T.SignatureRSA)
        ]
    }

instance Transport TLS where
  transportName _ = "TLS"
  {-# INLINE transportName #-}
  transportConfig = tlsTransportConfig
  {-# INLINE transportConfig #-}
  getTransportConnection = getTLS
  {-# INLINE getTransportConnection #-}
  certificateSent = tlsCertSent
  {-# INLINE certificateSent #-}
  getPeerCertChain = tlsPeerCert
  {-# INLINE getPeerCertChain #-}
  getSessionALPN = tlsALPN
  {-# INLINE getSessionALPN #-}
  tlsUnique = tlsUniq
  {-# INLINE tlsUnique #-}
  closeConnection tls = closeTLS $ tlsContext tls
  {-# INLINE closeConnection #-}

  cGet :: TLS p -> Int -> IO ByteString
  cGet TLS {tlsContext, tlsBuffer, tlsTransportConfig = TransportConfig {transportTimeout = t_}} n =
    getBuffered tlsBuffer n t_ (T.recvData tlsContext)

  cPut :: TLS p -> ByteString -> IO ()
  cPut TLS {tlsContext, tlsTransportConfig = TransportConfig {transportTimeout = t_}} =
    withTimedErr t_ . T.sendData tlsContext . LB.fromStrict

  getLn :: TLS p -> IO ByteString
  getLn TLS {tlsContext, tlsBuffer} = do
    getLnBuffered tlsBuffer (T.recvData tlsContext) `E.catches` [E.Handler handleTlsEOF, E.Handler handleEOF]
    where
      handleTlsEOF = \case
        T.PostHandshake T.Error_EOF -> E.throwIO TEBadBlock
        e -> E.throwIO e
      handleEOF e = if isEOFError e then E.throwIO TEBadBlock else E.throwIO e

data THandle v c p = THandle
  { connection :: c p,
    params :: THandleParams v p
  }

type THandleSMP c p = THandle SMPVersion c p

data THandleParams v p = THandleParams
  { sessionId :: SessionId,
    blockSize :: Int,
    thServerVRange :: VersionRange v,
    thVersion :: Version v,
    thAuth :: Maybe (THandleAuth p),
    implySessId :: Bool,
    encryptBlock :: Maybe TSbChainKeys,
    batch :: Bool,
    serviceAuth :: Bool
  }

data THandleAuth (p :: TransportPeer) where
  THAuthClient ::
    { peerServerPubKey :: C.PublicKeyX25519,
      peerServerCertKey :: CertChainPubKey,
      clientService :: Maybe THClientService,
      sessSecret :: Maybe C.DhSecretX25519
    } ->
    THandleAuth 'TClient
  THAuthServer ::
    { serverPrivKey :: C.PrivateKeyX25519,
      peerClientService :: Maybe THPeerClientService,
      sessSecret' :: Maybe C.DhSecretX25519
    } ->
    THandleAuth 'TServer

type THClientService = THClientService' C.PrivateKeyEd25519

type THPeerClientService = THClientService' C.PublicKeyEd25519

data THClientService' k = THClientService
  { serviceId :: ServiceId,
    serviceRole :: SMPServiceRole,
    serviceCertHash :: XV.Fingerprint,
    serviceKey :: k
  }

data TSbChainKeys = TSbChainKeys
  { sndKey :: TVar C.SbChainKey,
    rcvKey :: TVar C.SbChainKey
  }

type SessionId = ByteString

type ServiceId = EntityId

newtype EntityId = EntityId {unEntityId :: ByteString}
  deriving (Eq, Ord, Show)
  deriving newtype (Encoding, StrEncoding)

pattern NoEntity :: EntityId
pattern NoEntity = EntityId ""

data SMPServerHandshake = SMPServerHandshake
  { smpVersionRange :: VersionRangeSMP,
    sessionId :: SessionId,
    authPubKey :: Maybe CertChainPubKey
  }

data SMPServerHandshakeResponse
  = SMPServerHandshakeResponse {serviceId :: ServiceId}
  | SMPServerHandshakeError {handshakeError :: TransportError}

data SMPClientHandshake = SMPClientHandshake
  {
    smpVersion :: VersionSMP,
    keyHash :: C.KeyHash,
    authPubKey :: Maybe C.PublicKeyX25519,
    proxyServer :: Bool,
    clientService :: Maybe SMPClientHandshakeService
  }

data SMPClientHandshakeService = SMPClientHandshakeService
  { serviceRole :: SMPServiceRole,
    serviceCertKey :: CertChainPubKey
  }

data ServiceCredentials = ServiceCredentials
  { serviceRole :: SMPServiceRole,
    serviceCreds :: T.Credential,
    serviceCertHash :: XV.Fingerprint,
    serviceSignKey :: C.APrivateSignKey
  }

data SMPServiceRole = SRMessaging | SRNotifier | SRProxy deriving (Eq, Show)

instance Encoding SMPClientHandshake where
  smpEncode SMPClientHandshake {smpVersion = v, keyHash, authPubKey, proxyServer, clientService} =
    smpEncode (v, keyHash)
      <> encodeAuthEncryptCmds v authPubKey
      <> ifHasProxy v (smpEncode proxyServer) ""
      <> ifHasService v (smpEncode clientService) ""
  smpP = do
    (v, keyHash) <- smpP
    authPubKey <- authEncryptCmdsP v smpP
    proxyServer <- ifHasProxy v smpP (pure False)
    clientService <- ifHasService v smpP (pure Nothing)
    pure SMPClientHandshake {smpVersion = v, keyHash, authPubKey, proxyServer, clientService}

instance Encoding SMPClientHandshakeService where
  smpEncode SMPClientHandshakeService {serviceRole, serviceCertKey} =
    smpEncode (serviceRole, serviceCertKey)
  smpP = do
    (serviceRole, serviceCertKey) <- smpP
    pure SMPClientHandshakeService {serviceRole, serviceCertKey}

instance Encoding SMPServiceRole where
  smpEncode = \case
    SRMessaging -> "M"
    SRNotifier -> "N"
    SRProxy -> "P"
  smpP =
    A.anyChar >>= \case
      'M' -> pure SRMessaging
      'N' -> pure SRNotifier
      'P' -> pure SRProxy
      _ -> fail "bad SMPServiceRole"

ifHasProxy :: VersionSMP -> a -> a -> a
ifHasProxy v a b = if v >= proxyServerHandshakeSMPVersion then a else b

ifHasService :: VersionSMP -> a -> a -> a
ifHasService v a b = if v >= serviceCertsSMPVersion then a else b

instance Encoding SMPServerHandshake where
  smpEncode SMPServerHandshake {smpVersionRange, sessionId, authPubKey} =
    smpEncode (smpVersionRange, sessionId) <> auth
    where
      auth = encodeAuthEncryptCmds (maxVersion smpVersionRange) authPubKey
  smpP = do
    (smpVersionRange, sessionId) <- smpP
    authPubKey <- authEncryptCmdsP (maxVersion smpVersionRange) smpP
    pure SMPServerHandshake {smpVersionRange, sessionId, authPubKey}

data CertChainPubKey = CertChainPubKey
  { certChain :: X.CertificateChain,
    signedPubKey :: X.SignedExact X.PubKey
  }
  deriving (Eq, Show)

instance Encoding CertChainPubKey where
  smpEncode CertChainPubKey {certChain, signedPubKey} = smpEncode (C.encodeCertChain certChain, C.SignedObject signedPubKey)
  smpP = do
    certChain <- C.certChainP
    C.SignedObject signedPubKey <- smpP
    pure CertChainPubKey {certChain, signedPubKey}

encodeAuthEncryptCmds :: Encoding a => VersionSMP -> Maybe a -> ByteString
encodeAuthEncryptCmds v k
  | v >= authCmdsSMPVersion = maybe "" smpEncode k
  | otherwise = ""

authEncryptCmdsP :: VersionSMP -> Parser a -> Parser (Maybe a)
authEncryptCmdsP v p = if v >= authCmdsSMPVersion then optional p else pure Nothing

instance Encoding SMPServerHandshakeResponse where
  smpEncode = \case
    SMPServerHandshakeResponse serviceId -> smpEncode ('R', serviceId)
    SMPServerHandshakeError handshakeError -> smpEncode ('E', handshakeError)
  smpP =
    A.anyChar >>= \case
      'R' -> SMPServerHandshakeResponse <$> smpP
      'E' -> SMPServerHandshakeError <$> smpP
      _ -> fail "bad SMPServerHandshakeResponse"

data TransportError
  =
    TEBadBlock
  |
    TEVersion
  |
    TELargeMsg
  |
    TEBadSession
  |
    TENoServerAuth
  |
    TEHandshake {handshakeErr :: HandshakeError}
  deriving (Eq, Read, Show, Exception)

data HandshakeError
  =
    PARSE
  |
    IDENTITY
  |
    BAD_AUTH
  |
    BAD_SERVICE
  deriving (Eq, Read, Show, Exception)

instance Encoding TransportError where
  smpP =
    A.takeTill (== ' ') >>= \case
      "BLOCK" -> pure TEBadBlock
      "VERSION" -> pure TEVersion
      "LARGE_MSG" -> pure TELargeMsg
      "SESSION" -> pure TEBadSession
      "NO_AUTH" -> pure TENoServerAuth
      "HANDSHAKE" -> TEHandshake <$> (A.space *> parseRead1)
      _ -> fail "bad TransportError"
  smpEncode = \case
    TEBadBlock -> "BLOCK"
    TEVersion -> "VERSION"
    TELargeMsg -> "LARGE_MSG"
    TEBadSession -> "SESSION"
    TENoServerAuth -> "NO_AUTH"
    TEHandshake e -> "HANDSHAKE " <> bshow e

tPutBlock :: Transport c => THandle v c p -> ByteString -> IO (Either TransportError ())
tPutBlock THandle {connection = c, params = THandleParams {blockSize, encryptBlock}} block = do
  block_ <- case encryptBlock of
    Just TSbChainKeys {sndKey} -> do
      (sk, nonce) <- atomically $ stateTVar sndKey C.sbcHkdf
      pure $ C.sbEncrypt sk nonce block (blockSize - 16)
    Nothing -> pure $ C.pad block blockSize
  bimapM (const $ pure TELargeMsg) (cPut c) block_

tGetBlock :: Transport c => THandle v c p -> IO (Either TransportError ByteString)
tGetBlock THandle {connection = c, params = THandleParams {blockSize, encryptBlock}} = do
  msg <- cGet c blockSize
  if B.length msg == blockSize
    then
      first (const TELargeMsg) <$>
        case encryptBlock of
          Just TSbChainKeys {rcvKey} -> do
            (sk, nonce) <- atomically $ stateTVar rcvKey C.sbcHkdf
            pure $ C.sbDecrypt sk nonce msg
          Nothing -> pure $ C.unPad msg
    else ioe_EOF

smpServerHandshake ::
  forall c. Transport c =>
  X.CertificateChain ->
  C.APrivateSignKey ->
  c 'TServer ->
  C.KeyPairX25519 ->
  C.KeyHash ->
  VersionRangeSMP ->
  (SMPServiceRole -> X.CertificateChain -> XV.Fingerprint -> ExceptT TransportError IO ServiceId) ->
  ExceptT TransportError IO (THandleSMP c 'TServer)
smpServerHandshake srvCert srvSignKey c (k, pk) kh smpVRange getService = do
  let sk = C.signX509 srvSignKey $ C.publicToX509 k
      smpVersionRange = maybe legacyServerSMPRelayVRange (const smpVRange) $ getSessionALPN c
  sendHandshake th $ SMPServerHandshake {sessionId, smpVersionRange, authPubKey = Just (CertChainPubKey srvCert sk)}
  SMPClientHandshake {smpVersion = v, keyHash, authPubKey = k', proxyServer, clientService} <- getHandshake th
  when (keyHash /= kh) $ throwE $ TEHandshake IDENTITY
  case compatibleVRange' smpVersionRange v of
    Just (Compatible vr) -> do
      service <- mapM getClientService clientService
      liftIO $ smpTHandleServer th v vr pk k' proxyServer service
    Nothing -> throwE TEVersion
  where
    th@THandle {params = THandleParams {sessionId}} = smpTHandle c
    getClientService :: SMPClientHandshakeService -> ExceptT TransportError IO THPeerClientService
    getClientService SMPClientHandshakeService {serviceRole, serviceCertKey = CertChainPubKey cc exact} = handleError sendErr $ do
      unless (getPeerCertChain c == cc) $ throwE $ TEHandshake BAD_AUTH
      (idCert, serviceKey) <- liftEitherWith (const $ TEHandshake BAD_AUTH) $ do
        (leafCert, idCert) <- case chainIdCaCerts cc of
          CCSelf cert -> pure (cert, cert)
          CCValid {leafCert, idCert} -> pure (leafCert, idCert)
          _ -> throwError "bad certificate"
        serviceCertKey <- getCertVerifyKey leafCert
        (idCert,) <$> (C.x509ToPublic' =<< C.verifyX509 serviceCertKey exact)
      let fp = XV.getFingerprint idCert X.HashSHA256
      serviceId <- getService serviceRole cc fp
      sendHandshake th $ SMPServerHandshakeResponse {serviceId}
      pure THClientService {serviceId, serviceRole, serviceCertHash = fp, serviceKey}
    sendErr err = do
      sendHandshake th $ SMPServerHandshakeError {handshakeError = err}
      throwError err

smpClientHandshake :: forall c. Transport c => c 'TClient -> Maybe C.KeyPairX25519 -> C.KeyHash -> VersionRangeSMP -> Bool -> Maybe (ServiceCredentials, C.KeyPairEd25519) -> ExceptT TransportError IO (THandleSMP c 'TClient)
smpClientHandshake c ks_ keyHash@(C.KeyHash kh) vRange proxyServer serviceKeys_ = do
  SMPServerHandshake {sessionId = sessId, smpVersionRange, authPubKey} <- getHandshake th
  when (sessionId /= sessId) $ throwE TEBadSession
  let smpVRange =
        if proxyServer && maxVersion smpVersionRange < proxyServerHandshakeSMPVersion
          then vRange {maxVersion = max (minVersion vRange) deletedEventSMPVersion}
          else vRange
  case smpVersionRange `compatibleVRange` smpVRange of
    Just (Compatible vr) -> do
      ck_ <- forM authPubKey $ \certKey@(CertChainPubKey chain exact) ->
        liftEitherWith (const $ TEHandshake BAD_AUTH) $ do
          case chainIdCaCerts chain of
            CCValid {idCert} | XV.Fingerprint kh == XV.getFingerprint idCert X.HashSHA256 -> pure ()
            _ -> throwError "bad certificate"
          serverKey <- getServerVerifyKey c
          (,certKey) <$> (C.x509ToPublic' =<< C.verifyX509 serverKey exact)
      let v = maxVersion vr
          serviceVersion ServiceCredentials {serviceRole} = if serviceRole == SRMessaging then rcvServiceSMPVersion else serviceCertsSMPVersion
          serviceKeys = case serviceKeys_ of
            Just sks | v >= serviceVersion (fst sks) && certificateSent c -> Just sks
            _ -> Nothing
          clientService = mkClientService <$> serviceKeys
          hs = SMPClientHandshake {smpVersion = v, keyHash, authPubKey = fst <$> ks_, proxyServer, clientService}
      sendHandshake th hs
      service <- mapM getClientService serviceKeys
      liftIO $ smpTHandleClient th v vr (snd <$> ks_) ck_ proxyServer service
    Nothing -> throwE TEVersion
  where
    th@THandle {params = THandleParams {sessionId}} = smpTHandle c
    mkClientService :: (ServiceCredentials, C.KeyPairEd25519) -> SMPClientHandshakeService
    mkClientService (ServiceCredentials {serviceRole, serviceCreds, serviceSignKey}, (k, _)) =
      let sk = C.signX509 serviceSignKey $ C.publicToX509 k
       in SMPClientHandshakeService {serviceRole, serviceCertKey = CertChainPubKey (fst serviceCreds) sk}
    getClientService :: (ServiceCredentials, C.KeyPairEd25519) -> ExceptT TransportError IO THClientService
    getClientService (ServiceCredentials {serviceRole, serviceCertHash}, (_, pk)) =
      getHandshake th >>= \case
        SMPServerHandshakeResponse {serviceId} -> pure THClientService {serviceId, serviceRole, serviceCertHash, serviceKey = pk}
        SMPServerHandshakeError {handshakeError} -> throwE handshakeError

smpTHandleServer :: forall c. THandleSMP c 'TServer -> VersionSMP -> VersionRangeSMP -> C.PrivateKeyX25519 -> Maybe C.PublicKeyX25519 -> Bool -> Maybe THPeerClientService -> IO (THandleSMP c 'TServer)
smpTHandleServer th v vr pk k_ proxyServer peerClientService = do
  let thAuth = Just THAuthServer {serverPrivKey = pk, peerClientService, sessSecret' = (`C.dh'` pk) <$!> k_}
  be <- blockEncryption th v proxyServer thAuth
  pure $ smpTHandle_ th v vr thAuth $ uncurry TSbChainKeys <$> be

smpTHandleClient :: forall c. THandleSMP c 'TClient -> VersionSMP -> VersionRangeSMP -> Maybe C.PrivateKeyX25519 -> Maybe (C.PublicKeyX25519, CertChainPubKey) -> Bool -> Maybe THClientService -> IO (THandleSMP c 'TClient)
smpTHandleClient th v vr pk_ ck_ proxyServer clientService = do
  let thAuth = clientTHParams <$!> ck_
  be <- blockEncryption th v proxyServer thAuth
  pure $ smpTHandle_ th v vr thAuth $ uncurry TSbChainKeys . swap <$> be
  where
    clientTHParams (k, ck) =
      THAuthClient
        { peerServerPubKey = k,
          peerServerCertKey = forceCertChain ck,
          clientService,
          sessSecret = C.dh' k <$!> pk_
        }

blockEncryption :: THandleSMP c p -> VersionSMP -> Bool -> Maybe (THandleAuth p) -> IO (Maybe (TVar C.SbChainKey, TVar C.SbChainKey))
blockEncryption THandle {params = THandleParams {sessionId}} v proxyServer = \case
  Just thAuth | not proxyServer && v >= encryptedBlockSMPVersion -> case thAuth of
    THAuthClient {sessSecret} -> be sessSecret
    THAuthServer {sessSecret'} -> be sessSecret'
  _ -> pure Nothing
  where
    be :: Maybe C.DhSecretX25519 -> IO (Maybe (TVar C.SbChainKey, TVar C.SbChainKey))
    be = mapM $ \(C.DhSecretX25519 secret) -> bimapM newTVarIO newTVarIO $ C.sbcInit sessionId secret

smpTHandle_ :: forall c p. THandleSMP c p -> VersionSMP -> VersionRangeSMP -> Maybe (THandleAuth p) -> Maybe TSbChainKeys -> THandleSMP c p
smpTHandle_ th@THandle {params} v vr thAuth encryptBlock =
  let params' =
        params
          { thVersion = v,
            thServerVRange = vr,
            thAuth,
            implySessId = v >= authCmdsSMPVersion,
            encryptBlock,
            serviceAuth = v >= serviceCertsSMPVersion
          }
   in (th :: THandleSMP c p) {params = params'}

forceCertChain :: CertChainPubKey -> CertChainPubKey
forceCertChain cert@(CertChainPubKey (X.CertificateChain cc) signedKey) = length (show cc) `seq` show signedKey `seq` cert
{-# INLINE forceCertChain #-}

smpTHParamsSetVersion :: VersionSMP -> THandleParams SMPVersion p -> THandleParams SMPVersion p
smpTHParamsSetVersion v params =
  params
    { thVersion = v,
      serviceAuth = v >= serviceCertsSMPVersion
    }
{-# INLINE smpTHParamsSetVersion #-}

sendHandshake :: (Transport c, Encoding smp) => THandle v c p -> smp -> ExceptT TransportError IO ()
sendHandshake th = ExceptT . tPutBlock th . smpEncode

getHandshake :: (Transport c, Encoding smp) => THandle v c p -> ExceptT TransportError IO smp
getHandshake th = ExceptT $ (first (\_ -> TEHandshake PARSE) . A.parseOnly smpP =<<) <$> tGetBlock th

smpTHandle :: Transport c => c p -> THandleSMP c p
smpTHandle c = THandle {connection = c, params}
  where
    v = VersionSMP 0
    params =
      THandleParams
        { sessionId = tlsUnique c,
          blockSize = smpBlockSize,
          thServerVRange = versionToRange v,
          thVersion = v,
          thAuth = Nothing,
          implySessId = False,
          encryptBlock = Nothing,
          batch = True,
          serviceAuth = False
        }

$(J.deriveJSON (sumTypeJSON id) ''HandshakeError)

$(J.deriveJSON (sumTypeJSON $ dropPrefix "TE") ''TransportError)
