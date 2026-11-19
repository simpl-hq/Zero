{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fno-warn-ambiguous-fields #-}
{-# OPTIONS_GHC -fno-warn-unticked-promoted-constructors #-}

module Zero.Messaging.Agent.Protocol
  (
    VersionSMPA,
    VersionRangeSMPA,
    pattern VersionSMPA,
    duplexHandshakeSMPAgentVersion,
    ratchetSyncSMPAgentVersion,
    deliveryRcptsSMPAgentVersion,
    pqdrSMPAgentVersion,
    sndAuthKeySMPAgentVersion,
    ratchetOnConfSMPAgentVersion,
    currentSMPAgentVersion,
    supportedSMPAgentVRange,
    e2eEncConnInfoLength,
    e2eEncAgentMsgLength,

    ConnInfo,
    SndQueueSecured,
    AEntityId,
    ACommand (..),
    AEvent (..),
    AEvt (..),
    ACommandTag (..),
    AEventTag (..),
    AEvtTag (..),
    aCommandTag,
    aEventTag,
    AEntity (..),
    SAEntity (..),
    AEntityI (..),
    MsgHash,
    MsgMeta (..),
    RcvQueueInfo (..),
    SndQueueInfo (..),
    SubscriptionStatus (..),
    ConnectionStats (..),
    SwitchPhase (..),
    RcvSwitchStatus (..),
    SndSwitchStatus (..),
    QueueDirection (..),
    RatchetSyncState (..),
    SMPConfirmation (..),
    AgentMsgEnvelope (..),
    AgentMessage (..),
    AgentMessageType (..),
    APrivHeader (..),
    AMessage (..),
    AMessageReceipt (..),
    MsgReceipt (..),
    MsgReceiptInfo,
    MsgReceiptStatus (..),
    SndQAddr,
    SMPServer,
    pattern SMPServer,
    pattern ProtoServerWithAuth,
    SMPServerWithAuth,
    SrvLoc (..),
    SMPQueue (..),
    qAddress,
    sameQueue,
    sameQAddress,
    noAuthSrv,
    SMPQueueUri (..),
    SMPQueueInfo (..),
    SMPQueueAddress (..),
    ConnectionMode (..),
    SConnectionMode (..),
    AConnectionMode (..),
    ConnectionModeI (..),
    ConnectionRequestUri (..),
    AConnectionRequestUri (..),
    ShortLinkCreds (..),
    ConnReqUriData (..),
    CRClientData,
    ServiceScheme,
    FixedLinkData (..),
    AConnLinkData (..),
    ConnLinkData (..),
    AUserConnLinkData (..),
    UserConnLinkData (..),
    UserContactData (..),
    UserLinkData (..),
    OwnerAuth (..),
    OwnerId,
    ConnectionLink (..),
    AConnectionLink (..),
    ZeroNameInfo (..),
    ZeroDomain (..),
    ZeroTLD (..),
    ZeroNameType (..),
    ConnShortLink (..),
    AConnShortLink (..),
    CreatedConnLink (..),
    ACreatedConnLink (..),
    ContactConnType (..),
    ShortLinkScheme (..),
    LinkKey (..),
    PreparedLinkParams (..),
    validateOwners,
    validateLinkOwners,
    sameConnReqContact,
    sameConnShortLink,
    sameShortLinkContact,
    sameShortLinkInv,
    zeroChat,
    connReqUriP',
    zeroConnReqUri,
    zeroShortLink,
    fullDomainName,
    shortNameInfoStr,
    AgentErrorType (..),
    CommandErrorType (..),
    ConnectionErrorType (..),
    BrokerErrorType (..),
    SMPAgentError (..),
    DroppedMsg (..),
    AgentCryptoError (..),
    cryptoErrToSyncState,
    ATransmission,
    ConnId,
    ConfirmationId,
    InvitationId,
    MsgIntegrity (..),
    MsgErrorType (..),
    QueueStatus (..),
    UserId,
    ACorrId,
    AgentMsgId,
    NotificationsMode (..),
    NotificationInfo (..),
    ConnMsgReq (..),

    serializeCommand,
    connMode,
    connMode',
    dbCommandP,
    connModeT,
    serializeQueueStatus,
    queueStatusT,
    agentMessageType,
    aMessageType,
    extraSMPServerHosts,
    updateSMPServerHosts,
    shortenShortLink,
    restoreShortLink,
    isPresetServer,
    linkUserData,
    linkUserData',
  )
where

import Control.Applicative (optional, (<|>))
import Control.Exception (BlockedIndefinitelyOnMVar (..), BlockedIndefinitelyOnSTM (..), fromException)
import Data.Aeson (FromJSON (..), ToJSON (..), Value (..), (.:), (.:?))
import qualified Data.Aeson as J'
import qualified Data.Aeson.Encoding as JE
import qualified Data.Aeson.TH as J
import qualified Data.Aeson.Types as JT
import Data.Attoparsec.ByteString.Char8 (Parser)
import qualified Data.Attoparsec.ByteString.Char8 as A
import qualified Data.ByteString.Base64.URL as B64
import Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as B
import Data.Char (toLower, toUpper)
import Data.Foldable (find)
import Data.Functor (($>))
import Data.Int (Int64)
import Data.Kind (Type)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as L
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (decodeLatin1, encodeUtf8)
import Data.Time.Clock (UTCTime)
import Data.Time.Clock.System (SystemTime)
import Data.Type.Equality
import Data.Typeable (Typeable)
import Data.Word (Word16, Word32)
import Zero.FileTransfer.Description
import Zero.FileTransfer.Protocol (FileParty (..))
import Zero.FileTransfer.Transport (XFTPErrorType)
import Zero.FileTransfer.Types (FileErrorType)
import Zero.Messaging.Agent.QueryString
import Zero.Messaging.Agent.Store.DB (Binary (..), FromField (..), ToField (..), blobFieldDecoder, fromTextField_)
import Zero.Messaging.Client (ProxyClientError)
import qualified Zero.Messaging.Crypto as C
import Zero.Messaging.Crypto.Ratchet
  ( InitialKeys (..),
    PQEncryption (..),
    PQSupport,
    RcvE2ERatchetParams,
    RcvE2ERatchetParamsUri,
    SndE2ERatchetParams,
    pattern PQSupportOff,
    pattern PQSupportOn,
  )
import Zero.Messaging.Encoding
import Zero.Messaging.Encoding.String
import Zero.Messaging.ZeroName (ZeroDomain (..), ZeroNameInfo (..), ZeroNameType (..), ZeroTLD (..), fullDomainName, shortNameInfoStr)
import Zero.Messaging.Parsers
import Zero.Messaging.Protocol
  ( AProtocolType,
    BrokerErrorType (..),
    ErrorType,
    MsgBody,
    MsgFlags,
    MsgId,
    NMsgMeta,
    ProtocolServer (..),
    QueueMode (..),
    SMPClientVersion,
    SMPServer,
    SMPServerWithAuth,
    ServiceSub,
    ServiceSubResult,
    SndPublicAuthKey,
    SubscriptionMode,
    VersionRangeSMPC,
    VersionSMPC,
    initialSMPClientVersion,
    legacyEncodeServer,
    legacyServerP,
    legacyStrEncodeServer,
    noAuthSrv,
    sameSrvAddr,
    senderCanSecure,
    shortLinksSMPClientVersion,
    sndAuthKeySMPClientVersion,
    srvHostnamesSMPClientVersion,
    pattern ProtoServerWithAuth,
    pattern SMPServer,
  )
import qualified Zero.Messaging.Protocol as SMP
import Zero.Messaging.ServiceScheme
import Zero.Messaging.Transport.Client (TransportHost, TransportHosts_ (..))
import Zero.Messaging.Util
import Zero.Messaging.Version
import Zero.Messaging.Version.Internal
import Zero.RemoteControl.Types
import UnliftIO.Exception (Exception)

data SMPAgentVersion

instance VersionScope SMPAgentVersion

type VersionSMPA = Version SMPAgentVersion

type VersionRangeSMPA = VersionRange SMPAgentVersion

pattern VersionSMPA :: Word16 -> VersionSMPA
pattern VersionSMPA v = Version v

duplexHandshakeSMPAgentVersion :: VersionSMPA
duplexHandshakeSMPAgentVersion = VersionSMPA 2

ratchetSyncSMPAgentVersion :: VersionSMPA
ratchetSyncSMPAgentVersion = VersionSMPA 3

deliveryRcptsSMPAgentVersion :: VersionSMPA
deliveryRcptsSMPAgentVersion = VersionSMPA 4

pqdrSMPAgentVersion :: VersionSMPA
pqdrSMPAgentVersion = VersionSMPA 5

sndAuthKeySMPAgentVersion :: VersionSMPA
sndAuthKeySMPAgentVersion = VersionSMPA 6

ratchetOnConfSMPAgentVersion :: VersionSMPA
ratchetOnConfSMPAgentVersion = VersionSMPA 7

minSupportedSMPAgentVersion :: VersionSMPA
minSupportedSMPAgentVersion = duplexHandshakeSMPAgentVersion

currentSMPAgentVersion :: VersionSMPA
currentSMPAgentVersion = VersionSMPA 7

supportedSMPAgentVRange :: VersionRangeSMPA
supportedSMPAgentVRange = mkVersionRange minSupportedSMPAgentVersion currentSMPAgentVersion

e2eEncConnInfoLength :: VersionSMPA -> PQSupport -> Int
e2eEncConnInfoLength v = \case
  PQSupportOn | v >= pqdrSMPAgentVersion -> 11106
  _ -> 14832

e2eEncAgentMsgLength :: VersionSMPA -> PQSupport -> Int
e2eEncAgentMsgLength v = \case
  PQSupportOn | v >= pqdrSMPAgentVersion -> 13618
  _ -> 15840

type ATransmission = (ACorrId, AEntityId, AEvt)

type UserId = Int64

type AEntityId = ByteString

type ACorrId = ByteString

data AEntity = AEConn | AERcvFile | AESndFile | AENone
  deriving (Eq, Show)

data SAEntity :: AEntity -> Type where
  SAEConn :: SAEntity AEConn
  SAERcvFile :: SAEntity AERcvFile
  SAESndFile :: SAEntity AESndFile
  SAENone :: SAEntity AENone

deriving instance Show (SAEntity e)

instance TestEquality SAEntity where
  testEquality SAEConn SAEConn = Just Refl
  testEquality SAERcvFile SAERcvFile = Just Refl
  testEquality SAESndFile SAESndFile = Just Refl
  testEquality SAENone SAENone = Just Refl
  testEquality _ _ = Nothing

class AEntityI (e :: AEntity) where sAEntity :: SAEntity e

instance AEntityI AEConn where sAEntity = SAEConn

instance AEntityI AERcvFile where sAEntity = SAERcvFile

instance AEntityI AESndFile where sAEntity = SAESndFile

instance AEntityI AENone where sAEntity = SAENone

data AEvt = forall e. AEntityI e => AEvt (SAEntity e) (AEvent e)

instance Eq AEvt where
  AEvt e evt == AEvt e' evt' = case testEquality e e' of
    Just Refl -> evt == evt'
    Nothing -> False

deriving instance Show AEvt

type ConnInfo = ByteString

type SndQueueSecured = Bool

data AEvent (e :: AEntity) where
  INV :: AConnectionRequestUri -> AEvent AEConn
  LINK :: ConnShortLink 'CMContact -> UserConnLinkData 'CMContact -> AEvent AEConn
  LDATA :: FixedLinkData 'CMContact -> ConnLinkData 'CMContact -> AEvent AEConn
  CONF :: ConfirmationId -> PQSupport -> [SMPServer] -> ConnInfo -> AEvent AEConn
  REQ :: InvitationId -> PQSupport -> NonEmpty SMPServer -> ConnInfo -> AEvent AEConn
  INFO :: PQSupport -> ConnInfo -> AEvent AEConn
  CON :: PQEncryption -> AEvent AEConn
  END :: AEvent AEConn
  DELD :: AEvent AEConn
  CONNECT :: AProtocolType -> TransportHost -> AEvent AENone
  DISCONNECT :: AProtocolType -> TransportHost -> AEvent AENone
  DOWN :: SMPServer -> [ConnId] -> AEvent AENone
  UP :: SMPServer -> [ConnId] -> AEvent AENone
  SERVICE_ALL :: SMPServer -> AEvent AENone
  SERVICE_DOWN :: SMPServer -> ServiceSub -> AEvent AENone
  SERVICE_UP :: SMPServer -> ServiceSubResult -> AEvent AENone
  SERVICE_END :: SMPServer -> ServiceSub -> AEvent AENone
  SWITCH :: QueueDirection -> SwitchPhase -> ConnectionStats -> AEvent AEConn
  RSYNC :: RatchetSyncState -> Maybe AgentCryptoError -> ConnectionStats -> AEvent AEConn
  SENT :: AgentMsgId -> Maybe SMPServer -> AEvent AEConn
  MWARN :: AgentMsgId -> AgentErrorType -> AEvent AEConn
  MERR :: AgentMsgId -> AgentErrorType -> AEvent AEConn
  MERRS :: NonEmpty AgentMsgId -> AgentErrorType -> AEvent AEConn
  MSG :: MsgMeta -> MsgFlags -> MsgBody -> AEvent AEConn
  MSGNTF :: MsgId -> Maybe UTCTime -> AEvent AEConn
  RCVD :: MsgMeta -> NonEmpty MsgReceipt -> AEvent AEConn
  QCONT :: AEvent AEConn
  DEL_RCVQS :: NonEmpty (ConnId, SMPServer, SMP.RecipientId, Maybe AgentErrorType) -> AEvent AEConn
  DEL_CONNS :: NonEmpty ConnId -> AEvent AEConn
  DEL_USER :: Int64 -> AEvent AENone
  STAT :: ConnectionStats -> AEvent AEConn
  OK :: AEvent AEConn
  JOINED :: SndQueueSecured -> AEvent AEConn
  ERR :: AgentErrorType -> AEvent AEConn
  ERRS :: NonEmpty (ConnId, AgentErrorType) -> AEvent AENone
  SUSPENDED :: AEvent AENone
  RFPROG :: Int64 -> Int64 -> AEvent AERcvFile
  RFDONE :: FilePath -> AEvent AERcvFile
  RFERR :: AgentErrorType -> AEvent AERcvFile
  RFWARN :: AgentErrorType -> AEvent AERcvFile
  SFPROG :: Int64 -> Int64 -> AEvent AESndFile
  SFDONE :: ValidFileDescription 'FSender -> [ValidFileDescription 'FRecipient] -> AEvent AESndFile
  SFERR :: AgentErrorType -> AEvent AESndFile
  SFWARN :: AgentErrorType -> AEvent AESndFile

deriving instance Eq (AEvent e)

deriving instance Show (AEvent e)

data AEvtTag = forall e. AEntityI e => AEvtTag (SAEntity e) (AEventTag e)

instance Eq AEvtTag where
  AEvtTag e evt == AEvtTag e' evt' = case testEquality e e' of
    Just Refl -> evt == evt'
    Nothing -> False

deriving instance Show AEvtTag

data ACommand
  = NEW Bool AConnectionMode InitialKeys SubscriptionMode
  | LSET (UserConnLinkData 'CMContact) (Maybe CRClientData)
  | LGET (ConnShortLink 'CMContact)
  | JOIN Bool AConnectionRequestUri PQSupport SubscriptionMode ConnInfo
  | LET ConfirmationId ConnInfo
  | ACK AgentMsgId (Maybe MsgReceiptInfo)
  | SWCH
  | DEL
  deriving (Eq, Show)

data ACommandTag
  = NEW_
  | LSET_
  | LGET_
  | JOIN_
  | LET_
  | ACK_
  | SWCH_
  | DEL_
  deriving (Show)

data AEventTag (e :: AEntity) where
  INV_ :: AEventTag AEConn
  LINK_ :: AEventTag AEConn
  LDATA_ :: AEventTag AEConn
  CONF_ :: AEventTag AEConn
  REQ_ :: AEventTag AEConn
  INFO_ :: AEventTag AEConn
  CON_ :: AEventTag AEConn
  END_ :: AEventTag AEConn
  DELD_ :: AEventTag AEConn
  CONNECT_ :: AEventTag AENone
  DISCONNECT_ :: AEventTag AENone
  DOWN_ :: AEventTag AENone
  UP_ :: AEventTag AENone
  SERVICE_ALL_ :: AEventTag AENone
  SERVICE_DOWN_ :: AEventTag AENone
  SERVICE_UP_ :: AEventTag AENone
  SERVICE_END_ :: AEventTag AENone
  SWITCH_ :: AEventTag AEConn
  RSYNC_ :: AEventTag AEConn
  SENT_ :: AEventTag AEConn
  MWARN_ :: AEventTag AEConn
  MERR_ :: AEventTag AEConn
  MERRS_ :: AEventTag AEConn
  MSG_ :: AEventTag AEConn
  MSGNTF_ :: AEventTag AEConn
  RCVD_ :: AEventTag AEConn
  QCONT_ :: AEventTag AEConn
  DEL_RCVQS_ :: AEventTag AEConn
  DEL_CONNS_ :: AEventTag AEConn
  DEL_USER_ :: AEventTag AENone
  STAT_ :: AEventTag AEConn
  OK_ :: AEventTag AEConn
  JOINED_ :: AEventTag AEConn
  ERR_ :: AEventTag AEConn
  ERRS_ :: AEventTag AENone
  SUSPENDED_ :: AEventTag AENone
  RFDONE_ :: AEventTag AERcvFile
  RFPROG_ :: AEventTag AERcvFile
  RFERR_ :: AEventTag AERcvFile
  RFWARN_ :: AEventTag AERcvFile
  SFPROG_ :: AEventTag AESndFile
  SFDONE_ :: AEventTag AESndFile
  SFERR_ :: AEventTag AESndFile
  SFWARN_ :: AEventTag AESndFile

deriving instance Eq (AEventTag e)

deriving instance Show (AEventTag e)

aCommandTag :: ACommand -> ACommandTag
aCommandTag = \case
  NEW {} -> NEW_
  LSET {} -> LSET_
  LGET _ -> LGET_
  JOIN {} -> JOIN_
  LET {} -> LET_
  ACK {} -> ACK_
  SWCH -> SWCH_
  DEL -> DEL_

aEventTag :: AEvent e -> AEventTag e
aEventTag = \case
  INV {} -> INV_
  LINK {} -> LINK_
  LDATA {} -> LDATA_
  CONF {} -> CONF_
  REQ {} -> REQ_
  INFO {} -> INFO_
  CON _ -> CON_
  END -> END_
  DELD -> DELD_
  CONNECT {} -> CONNECT_
  DISCONNECT {} -> DISCONNECT_
  DOWN {} -> DOWN_
  UP {} -> UP_
  SERVICE_ALL _ -> SERVICE_ALL_
  SERVICE_DOWN {} -> SERVICE_DOWN_
  SERVICE_UP {} -> SERVICE_UP_
  SERVICE_END {} -> SERVICE_END_
  SWITCH {} -> SWITCH_
  RSYNC {} -> RSYNC_
  SENT {} -> SENT_
  MWARN {} -> MWARN_
  MERR {} -> MERR_
  MERRS {} -> MERRS_
  MSG {} -> MSG_
  MSGNTF {} -> MSGNTF_
  RCVD {} -> RCVD_
  QCONT -> QCONT_
  DEL_RCVQS _ -> DEL_RCVQS_
  DEL_CONNS _ -> DEL_CONNS_
  DEL_USER _ -> DEL_USER_
  STAT _ -> STAT_
  OK -> OK_
  JOINED {} -> JOINED_
  ERR _ -> ERR_
  ERRS _ -> ERRS_
  SUSPENDED -> SUSPENDED_
  RFPROG {} -> RFPROG_
  RFDONE {} -> RFDONE_
  RFERR {} -> RFERR_
  RFWARN {} -> RFWARN_
  SFPROG {} -> SFPROG_
  SFDONE {} -> SFDONE_
  SFERR {} -> SFERR_
  SFWARN {} -> SFWARN_

data QueueDirection = QDRcv | QDSnd
  deriving (Eq, Show)

data SwitchPhase = SPStarted | SPConfirmed | SPSecured | SPCompleted
  deriving (Eq, Show)

data RcvSwitchStatus
  = RSSwitchStarted
  | RSSendingQADD
  | RSSendingQUSE
  | RSReceivedMessage
  deriving (Eq, Show)

instance StrEncoding RcvSwitchStatus where
  strEncode = \case
    RSSwitchStarted -> "switch_started"
    RSSendingQADD -> "sending_qadd"
    RSSendingQUSE -> "sending_quse"
    RSReceivedMessage -> "received_message"
  strP =
    A.takeTill (== ' ') >>= \case
      "switch_started" -> pure RSSwitchStarted
      "sending_qadd" -> pure RSSendingQADD
      "sending_quse" -> pure RSSendingQUSE
      "received_message" -> pure RSReceivedMessage
      _ -> fail "bad RcvSwitchStatus"

instance ToField RcvSwitchStatus where toField = toField . decodeLatin1 . strEncode

instance FromField RcvSwitchStatus where fromField = fromTextField_ $ eitherToMaybe . strDecode . encodeUtf8

instance ToJSON RcvSwitchStatus where
  toEncoding = strToJEncoding
  toJSON = strToJSON

instance FromJSON RcvSwitchStatus where
  parseJSON = strParseJSON "RcvSwitchStatus"

data SndSwitchStatus
  = SSSendingQKEY
  | SSSendingQTEST
  deriving (Eq, Show)

instance StrEncoding SndSwitchStatus where
  strEncode = \case
    SSSendingQKEY -> "sending_qkey"
    SSSendingQTEST -> "sending_qtest"
  strP =
    A.takeTill (== ' ') >>= \case
      "sending_qkey" -> pure SSSendingQKEY
      "sending_qtest" -> pure SSSendingQTEST
      _ -> fail "bad SndSwitchStatus"

instance ToField SndSwitchStatus where toField = toField . decodeLatin1 . strEncode

instance FromField SndSwitchStatus where fromField = fromTextField_ $ eitherToMaybe . strDecode . encodeUtf8

instance ToJSON SndSwitchStatus where
  toEncoding = strToJEncoding
  toJSON = strToJSON

instance FromJSON SndSwitchStatus where
  parseJSON = strParseJSON "SndSwitchStatus"

data RatchetSyncState
  = RSOk
  | RSAllowed
  | RSRequired
  | RSStarted
  | RSAgreed
  deriving (Eq, Show)

instance StrEncoding RatchetSyncState where
  strEncode = \case
    RSOk -> "ok"
    RSAllowed -> "allowed"
    RSRequired -> "required"
    RSStarted -> "started"
    RSAgreed -> "agreed"
  strP =
    A.takeTill (== ' ') >>= \case
      "ok" -> pure RSOk
      "allowed" -> pure RSAllowed
      "required" -> pure RSRequired
      "started" -> pure RSStarted
      "agreed" -> pure RSAgreed
      _ -> fail "bad RatchetSyncState"

instance FromField RatchetSyncState where fromField = fromTextField_ $ eitherToMaybe . strDecode . encodeUtf8

instance ToField RatchetSyncState where toField = toField . decodeLatin1 . strEncode

instance ToJSON RatchetSyncState where
  toEncoding = strToJEncoding
  toJSON = strToJSON

instance FromJSON RatchetSyncState where
  parseJSON = strParseJSON "RatchetSyncState"

data RcvQueueInfo = RcvQueueInfo
  { rcvServer :: SMPServer,
    status :: QueueStatus,
    rcvSwitchStatus :: Maybe RcvSwitchStatus,
    canAbortSwitch :: Bool,
    subStatus :: SubscriptionStatus
  }
  deriving (Eq, Show)

data SndQueueInfo = SndQueueInfo
  { sndServer :: SMPServer,
    status :: QueueStatus,
    sndSwitchStatus :: Maybe SndSwitchStatus
  }
  deriving (Eq, Show)

data SubscriptionStatus
  = SSActive
  | SSPending
  | SSRemoved {subError :: String}
  | SSNoSub
  deriving (Eq, Ord, Show)

data ConnectionStats = ConnectionStats
  { connAgentVersion :: VersionSMPA,
    rcvQueuesInfo :: [RcvQueueInfo],
    sndQueuesInfo :: [SndQueueInfo],
    ratchetSyncState :: RatchetSyncState,
    ratchetSyncSupported :: Bool,
    subStatus :: Maybe SubscriptionStatus
  }
  deriving (Eq, Show)

data NotificationsMode = NMPeriodic | NMInstant
  deriving (Eq, Show)

instance StrEncoding NotificationsMode where
  strEncode = \case
    NMPeriodic -> "PERIODIC"
    NMInstant -> "INSTANT"
  strP =
    A.takeTill (== ' ') >>= \case
      "PERIODIC" -> pure NMPeriodic
      "INSTANT" -> pure NMInstant
      _ -> fail "bad NotificationsMode"

instance ToJSON NotificationsMode where
  toEncoding = strToJEncoding
  toJSON = strToJSON

instance FromJSON NotificationsMode where
  parseJSON = strParseJSON "NotificationsMode"

instance ToField NotificationsMode where toField = toField . decodeLatin1 . strEncode

instance FromField NotificationsMode where fromField = fromTextField_ $ eitherToMaybe . strDecode . encodeUtf8

data NotificationInfo = NotificationInfo
  { ntfConnId :: ConnId,
    ntfDbQueueId :: Int64,
    ntfTs :: SystemTime,
    ntfMsgMeta :: Maybe NMsgMeta
  }
  deriving (Show)

data ConnMsgReq = ConnMsgReq
  { msgConnId :: ConnId,
    msgDbQueueId :: Int64,
    msgTs :: Maybe UTCTime
  }
  deriving (Show)

data ConnectionMode = CMInvitation | CMContact
  deriving (Eq, Show)

data SConnectionMode (m :: ConnectionMode) where
  SCMInvitation :: SConnectionMode CMInvitation
  SCMContact :: SConnectionMode CMContact

deriving instance Eq (SConnectionMode m)

deriving instance Show (SConnectionMode m)

instance TestEquality SConnectionMode where
  testEquality SCMInvitation SCMInvitation = Just Refl
  testEquality SCMContact SCMContact = Just Refl
  testEquality _ _ = Nothing

data AConnectionMode = forall m. ConnectionModeI m => ACM (SConnectionMode m)

instance Eq AConnectionMode where
  ACM m == ACM m' = isJust $ testEquality m m'

deriving instance Show AConnectionMode

connMode :: SConnectionMode m -> ConnectionMode
connMode SCMInvitation = CMInvitation
connMode SCMContact = CMContact
{-# INLINE connMode #-}

connMode' :: ConnectionMode -> AConnectionMode
connMode' CMInvitation = ACM SCMInvitation
connMode' CMContact = ACM SCMContact
{-# INLINE connMode' #-}

class ConnectionModeI (m :: ConnectionMode) where sConnectionMode :: SConnectionMode m

instance ConnectionModeI CMInvitation where sConnectionMode = SCMInvitation

instance ConnectionModeI CMContact where sConnectionMode = SCMContact

type MsgHash = ByteString

data MsgMeta = MsgMeta
  { integrity :: MsgIntegrity,
    recipient :: (AgentMsgId, UTCTime),
    broker :: (MsgId, UTCTime),
    sndMsgId :: AgentMsgId,
    pqEncryption :: PQEncryption
  }
  deriving (Eq, Show)

data DroppedMsg = DroppedMsg
  { brokerTs :: UTCTime,
    attempts :: Int
  }
  deriving (Eq, Show)

data SMPConfirmation = SMPConfirmation
  {
    senderKey :: Maybe SndPublicAuthKey,
    e2ePubKey :: C.PublicKeyX25519,
    connInfo :: ConnInfo,
    smpReplyQueues :: [SMPQueueInfo],
    smpClientVersion :: VersionSMPC
  }
  deriving (Show)

data AgentMsgEnvelope
  = AgentConfirmation
      { agentVersion :: VersionSMPA,
        e2eEncryption_ :: Maybe (SndE2ERatchetParams 'C.X448),
        encConnInfo :: ByteString
      }
  | AgentMsgEnvelope
      { agentVersion :: VersionSMPA,
        encAgentMessage :: ByteString
      }
  | AgentInvitation
      { agentVersion :: VersionSMPA,
        connReq :: ConnectionRequestUri 'CMInvitation,
        connInfo :: ByteString
      }
  | AgentRatchetKey
      { agentVersion :: VersionSMPA,
        e2eEncryption :: RcvE2ERatchetParams 'C.X448,
        info :: ByteString
      }
  deriving (Show)

instance Encoding AgentMsgEnvelope where
  smpEncode = \case
    AgentConfirmation {agentVersion, e2eEncryption_, encConnInfo} ->
      smpEncode (agentVersion, 'C', e2eEncryption_, Tail encConnInfo)
    AgentMsgEnvelope {agentVersion, encAgentMessage} ->
      smpEncode (agentVersion, 'M', Tail encAgentMessage)
    AgentInvitation {agentVersion, connReq, connInfo} ->
      smpEncode (agentVersion, 'I', Large $ strEncode connReq, Tail connInfo)
    AgentRatchetKey {agentVersion, e2eEncryption, info} ->
      smpEncode (agentVersion, 'R', e2eEncryption, Tail info)
  smpP = do
    agentVersion <- smpP
    smpP >>= \case
      'C' -> do
        (e2eEncryption_, Tail encConnInfo) <- smpP
        pure AgentConfirmation {agentVersion, e2eEncryption_, encConnInfo}
      'M' -> do
        Tail encAgentMessage <- smpP
        pure AgentMsgEnvelope {agentVersion, encAgentMessage}
      'I' -> do
        connReq <- strDecode . unLarge <$?> smpP
        Tail connInfo <- smpP
        pure AgentInvitation {agentVersion, connReq, connInfo}
      'R' -> do
        e2eEncryption <- smpP
        Tail info <- smpP
        pure AgentRatchetKey {agentVersion, e2eEncryption, info}
      _ -> fail "bad AgentMsgEnvelope"

data AgentMessage
  =
    AgentConnInfo ConnInfo
  |
    AgentConnInfoReply (NonEmpty SMPQueueInfo) ConnInfo
  | AgentRatchetInfo ByteString
  | AgentMessage APrivHeader AMessage
  deriving (Show)

instance Encoding AgentMessage where
  smpEncode = \case
    AgentConnInfo cInfo -> smpEncode ('I', Tail cInfo)
    AgentConnInfoReply smpQueues cInfo -> smpEncode ('D', smpQueues, Tail cInfo)
    AgentRatchetInfo info -> smpEncode ('R', Tail info)
    AgentMessage hdr aMsg -> smpEncode ('M', hdr, aMsg)
  smpP =
    smpP >>= \case
      'I' -> AgentConnInfo . unTail <$> smpP
      'D' -> AgentConnInfoReply <$> smpP <*> (unTail <$> smpP)
      'R' -> AgentRatchetInfo . unTail <$> smpP
      'M' -> AgentMessage <$> smpP <*> smpP
      _ -> fail "bad AgentMessage"

data AgentMessageType
  = AM_CONN_INFO
  | AM_CONN_INFO_REPLY
  | AM_RATCHET_INFO
  | AM_HELLO_
  | AM_A_MSG_
  | AM_A_RCVD_
  | AM_QCONT_
  | AM_QADD_
  | AM_QKEY_
  | AM_QUSE_
  | AM_QTEST_
  | AM_EREADY_
  deriving (Eq, Show)

instance Encoding AgentMessageType where
  smpEncode = \case
    AM_CONN_INFO -> "C"
    AM_CONN_INFO_REPLY -> "D"
    AM_RATCHET_INFO -> "S"
    AM_HELLO_ -> "H"
    AM_A_MSG_ -> "M"
    AM_A_RCVD_ -> "V"
    AM_QCONT_ -> "QC"
    AM_QADD_ -> "QA"
    AM_QKEY_ -> "QK"
    AM_QUSE_ -> "QU"
    AM_QTEST_ -> "QT"
    AM_EREADY_ -> "E"
  smpP =
    A.anyChar >>= \case
      'C' -> pure AM_CONN_INFO
      'D' -> pure AM_CONN_INFO_REPLY
      'S' -> pure AM_RATCHET_INFO
      'H' -> pure AM_HELLO_
      'M' -> pure AM_A_MSG_
      'V' -> pure AM_A_RCVD_
      'Q' ->
        A.anyChar >>= \case
          'C' -> pure AM_QCONT_
          'A' -> pure AM_QADD_
          'K' -> pure AM_QKEY_
          'U' -> pure AM_QUSE_
          'T' -> pure AM_QTEST_
          _ -> fail "bad AgentMessageType"
      'E' -> pure AM_EREADY_
      _ -> fail "bad AgentMessageType"

agentMessageType :: AgentMessage -> AgentMessageType
agentMessageType = \case
  AgentConnInfo _ -> AM_CONN_INFO
  AgentConnInfoReply {} -> AM_CONN_INFO_REPLY
  AgentRatchetInfo _ -> AM_RATCHET_INFO
  AgentMessage _ aMsg -> aMessageType aMsg

data APrivHeader = APrivHeader
  {
    sndMsgId :: AgentMsgId,
    prevMsgHash :: MsgHash
  }
  deriving (Show)

instance Encoding APrivHeader where
  smpEncode APrivHeader {sndMsgId, prevMsgHash} =
    smpEncode (sndMsgId, prevMsgHash)
  smpP = APrivHeader <$> smpP <*> smpP

data AMsgType
  = HELLO_
  | A_MSG_
  | A_RCVD_
  | A_QCONT_
  | QADD_
  | QKEY_
  | QUSE_
  | QTEST_
  | EREADY_
  deriving (Eq)

instance Encoding AMsgType where
  smpEncode = \case
    HELLO_ -> "H"
    A_MSG_ -> "M"
    A_RCVD_ -> "V"
    A_QCONT_ -> "QC"
    QADD_ -> "QA"
    QKEY_ -> "QK"
    QUSE_ -> "QU"
    QTEST_ -> "QT"
    EREADY_ -> "E"
  smpP =
    A.anyChar >>= \case
      'H' -> pure HELLO_
      'M' -> pure A_MSG_
      'V' -> pure A_RCVD_
      'Q' ->
        A.anyChar >>= \case
          'C' -> pure A_QCONT_
          'A' -> pure QADD_
          'K' -> pure QKEY_
          'U' -> pure QUSE_
          'T' -> pure QTEST_
          _ -> fail "bad AMsgType"
      'E' -> pure EREADY_
      _ -> fail "bad AMsgType"

data AMessage
  =
    HELLO
  |
    A_MSG MsgBody
  |
    A_RCVD (NonEmpty AMessageReceipt)
  |
    A_QCONT SndQAddr
  |
    QADD (NonEmpty (SMPQueueUri, Maybe SndQAddr))
  |
    QKEY (NonEmpty (SMPQueueInfo, SndPublicAuthKey))
  |
    QUSE (NonEmpty (SndQAddr, Bool))
  |
    QTEST (NonEmpty SndQAddr)
  |
    EREADY AgentMsgId
  deriving (Show)

aMessageType :: AMessage -> AgentMessageType
aMessageType = \case
  HELLO -> AM_HELLO_
  A_MSG _ -> AM_A_MSG_
  A_RCVD {} -> AM_A_RCVD_
  A_QCONT _ -> AM_QCONT_
  QADD _ -> AM_QADD_
  QKEY _ -> AM_QKEY_
  QUSE _ -> AM_QUSE_
  QTEST _ -> AM_QTEST_
  EREADY _ -> AM_EREADY_

data AMessageReceipt = AMessageReceipt
  { agentMsgId :: AgentMsgId,
    msgHash :: MsgHash,
    rcptInfo :: MsgReceiptInfo
  }
  deriving (Show)

data MsgReceipt = MsgReceipt
  { agentMsgId :: AgentMsgId,
    msgRcptStatus :: MsgReceiptStatus
  }
  deriving (Eq, Show)

data MsgReceiptStatus = MROk | MRBadMsgHash
  deriving (Eq, Show)

instance StrEncoding MsgReceiptStatus where
  strEncode = \case
    MROk -> "ok"
    MRBadMsgHash -> "badMsgHash"
  strP =
    A.takeWhile1 (/= ' ') >>= \case
      "ok" -> pure MROk
      "badMsgHash" -> pure MRBadMsgHash
      _ -> fail "bad MsgReceiptStatus"

instance ToJSON MsgReceiptStatus where
  toJSON = strToJSON
  toEncoding = strToJEncoding

instance FromJSON MsgReceiptStatus where
  parseJSON = strParseJSON "MsgReceiptStatus"

type MsgReceiptInfo = ByteString

type SndQAddr = (SMPServer, SMP.SenderId)

instance Encoding AMessage where
  smpEncode = \case
    HELLO -> smpEncode HELLO_
    A_MSG body -> smpEncode (A_MSG_, Tail body)
    A_RCVD mrs -> smpEncode (A_RCVD_, mrs)
    A_QCONT addr -> smpEncode (A_QCONT_, addr)
    QADD qs -> smpEncode (QADD_, qs)
    QKEY qs -> smpEncode (QKEY_, qs)
    QUSE qs -> smpEncode (QUSE_, qs)
    QTEST qs -> smpEncode (QTEST_, qs)
    EREADY lastDecryptedMsgId -> smpEncode (EREADY_, lastDecryptedMsgId)
  smpP =
    smpP
      >>= \case
        HELLO_ -> pure HELLO
        A_MSG_ -> A_MSG . unTail <$> smpP
        A_RCVD_ -> A_RCVD <$> smpP
        A_QCONT_ -> A_QCONT <$> smpP
        QADD_ -> QADD <$> smpP
        QKEY_ -> QKEY <$> smpP
        QUSE_ -> QUSE <$> smpP
        QTEST_ -> QTEST <$> smpP
        EREADY_ -> EREADY <$> smpP

instance ToField AMessage where toField = toField . Binary . smpEncode

instance FromField AMessage where fromField = blobFieldDecoder smpDecode

instance Encoding AMessageReceipt where
  smpEncode AMessageReceipt {agentMsgId, msgHash, rcptInfo} =
    smpEncode (agentMsgId, msgHash, Large rcptInfo)
  smpP = do
    (agentMsgId, msgHash, Large rcptInfo) <- smpP
    pure AMessageReceipt {agentMsgId, msgHash, rcptInfo}

instance ConnectionModeI m => StrEncoding (ConnectionRequestUri m) where
  strEncode = \case
    CRInvitationUri crData e2eParams -> crEncode "invitation" crData (Just e2eParams)
    CRContactUri crData -> crEncode "contact" crData Nothing
    where
      crEncode :: ByteString -> ConnReqUriData -> Maybe (RcvE2ERatchetParamsUri 'C.X448) -> ByteString
      crEncode crMode ConnReqUriData {crScheme, crAgentVRange, crSmpQueues, crClientData} e2eParams =
        strEncode crScheme <> "/" <> crMode <> "#/?" <> queryStr
        where
          queryStr =
            strEncode . QSP QEscape $
              [("v", strEncode crAgentVRange), ("smp", B.intercalate ";" $ map strEncode $ L.toList crSmpQueues)]
                <> maybe [] (\e2e -> [("e2e", strEncode e2e)]) e2eParams
                <> maybe [] (\cd -> [("data", encodeUtf8 cd)]) crClientData
  strP = connReqUriP' (Just SSZero)

instance ConnectionModeI m => Encoding (ConnectionRequestUri m) where
  smpEncode = \case
    CRInvitationUri crData e2eParams -> smpEncode (CMInvitation, crData, e2eParams)
    CRContactUri crData -> smpEncode (CMContact, crData)
  smpP = (\(ACR _ cr) -> checkConnMode cr) <$?> smpP
  {-# INLINE smpP #-}

instance Encoding AConnectionRequestUri where
  smpEncode (ACR _ cr) = smpEncode cr
  {-# INLINE smpEncode #-}
  smpP =
    smpP >>= \case
      CMInvitation -> ACR SCMInvitation <$> (CRInvitationUri <$> smpP <*> smpP)
      CMContact -> ACR SCMContact . CRContactUri <$> smpP

instance Encoding ConnReqUriData where
  smpEncode ConnReqUriData {crAgentVRange, crSmpQueues, crClientData} =
    smpEncode (crAgentVRange, crSmpQueues, Large . encodeUtf8 <$> crClientData)
  smpP = do
    (crAgentVRange, smpQueues, clientData) <- smpP
    let crSmpQueues = L.map patchQueueMode smpQueues
    pure ConnReqUriData {crScheme = SSZero, crAgentVRange, crSmpQueues, crClientData = safeDecodeUtf8 . unLarge <$> clientData}
    where
      patchQueueMode q@SMPQueueUri {queueAddress = a} = case a of
        SMPQueueAddress {queueMode = Nothing} -> q {queueAddress = a {queueMode = Just QMContact}} :: SMPQueueUri
        _ -> q

connReqUriP' :: forall m. ConnectionModeI m => Maybe ServiceScheme -> Parser (ConnectionRequestUri m)
connReqUriP' overrideScheme = do
  ACR m cr <- connReqUriP overrideScheme
  case testEquality m $ sConnectionMode @m of
    Just Refl -> pure cr
    _ -> fail "bad connection request mode"

instance StrEncoding AConnectionRequestUri where
  strEncode (ACR _ cr) = strEncode cr
  strP = connReqUriP (Just SSZero)

connReqUriP :: Maybe ServiceScheme -> Parser AConnectionRequestUri
connReqUriP overrideScheme = do
  crScheme <- (`fromMaybe` overrideScheme) <$> strP
  crMode <- A.char '/' *> crModeP <* optional (A.char '/') <* "#/?"
  query <- strP
  aVRange <- queryParam "v" query
  crSmpQueues <- queryParamParser queuesP "smp" query
  let crClientData = safeDecodeUtf8 <$> queryParamStr "data" query
      crData = ConnReqUriData {crScheme, crAgentVRange = aVRange, crSmpQueues, crClientData}
  case crMode of
    CMInvitation -> do
      crE2eParams <- queryParam "e2e" query
      pure . ACR SCMInvitation $ CRInvitationUri crData crE2eParams
    CMContact -> pure . ACR SCMContact $ CRContactUri crData {crAgentVRange = adjustAgentVRange aVRange}
  where
    crModeP = "invitation" $> CMInvitation <|> "contact" $> CMContact
    queuesP = L.fromList <$> (strDecode <$?> A.takeTill (== ';')) `A.sepBy1'` A.char ';'
    adjustAgentVRange vr =
      let v = max minSupportedSMPAgentVersion $ minVersion vr
       in fromMaybe vr $ safeVersionRange v (max v $ maxVersion vr)

instance ConnectionModeI m => FromJSON (ConnectionRequestUri m) where
  parseJSON = strParseJSON "ConnectionRequestUri"
  {-# INLINE parseJSON #-}

instance ConnectionModeI m => ToJSON (ConnectionRequestUri m) where
  toJSON = strToJSON
  {-# INLINE toJSON #-}
  toEncoding = strToJEncoding
  {-# INLINE toEncoding #-}

instance FromJSON AConnectionRequestUri where
  parseJSON = strParseJSON "ConnectionRequestUri"
  {-# INLINE parseJSON #-}

instance ToJSON AConnectionRequestUri where
  toJSON = strToJSON
  {-# INLINE toJSON #-}
  toEncoding = strToJEncoding
  {-# INLINE toEncoding #-}

instance ConnectionModeI m => FromJSON (ConnShortLink m) where
  parseJSON = strParseJSON "ConnShortLink"
  {-# INLINE parseJSON #-}

instance ConnectionModeI m => ToJSON (ConnShortLink m) where
  toJSON = strToJSON
  {-# INLINE toJSON #-}
  toEncoding = strToJEncoding
  {-# INLINE toEncoding #-}

instance FromJSON AConnShortLink where
  parseJSON = strParseJSON "AConnShortLink"
  {-# INLINE parseJSON #-}

instance ToJSON AConnShortLink where
  toJSON = strToJSON
  toEncoding = strToJEncoding

instance StrEncoding ConnectionMode where
  strEncode = \case
    CMInvitation -> "INV"
    CMContact -> "CON"
  strP = "INV" $> CMInvitation <|> "CON" $> CMContact

instance StrEncoding AConnectionMode where
  strEncode (ACM cMode) = strEncode $ connMode cMode
  strP = connMode' <$> strP

instance Encoding ConnectionMode where
  smpEncode = \case
    CMInvitation -> "I"
    CMContact -> "C"
  smpP =
    A.anyChar >>= \case
      'I' -> pure CMInvitation
      'C' -> pure CMContact
      _ -> fail "bad connection mode"

instance ToJSON ConnectionMode where
  toJSON = J'.String . T.toLower . decodeLatin1 . strEncode
  {-# INLINE toJSON #-}
  toEncoding = JE.text . T.toLower . decodeLatin1 . strEncode
  {-# INLINE toEncoding #-}

instance FromJSON ConnectionMode where
  parseJSON = J'.withText "ConnectionMode" $ either fail pure . parseAll strP . encodeUtf8 . T.toUpper
  {-# INLINE parseJSON #-}

connModeT :: Text -> Maybe ConnectionMode
connModeT = \case
  "INV" -> Just CMInvitation
  "CON" -> Just CMContact
  _ -> Nothing

type ConnId = ByteString

type ConfirmationId = ByteString

type InvitationId = ByteString

extraSMPServerHosts :: Map TransportHost TransportHost
extraSMPServerHosts =
  M.fromList
    [ ("smp4.simpl.global", "o5vmywmrnaxalvz6wi3zicyftgio6psuvyniis6gco6bp6ekl4cqj4id.onion"),
      ("smp5.simpl.global", "jjbyvoemxysm7qxap7m5d5m35jzv5qq6gnlv7s4rsn7tdwwmuqciwpid.onion"),
      ("smp6.simpl.global", "bylepyau3ty4czmn77q4fglvperknl4bi2eb2fdy2bh4jxtf32kf73yd.onion"),
      ("smp8.simpl.global", "beccx4yfxxbvyhqypaavemqurytl6hozr47wfc7uuecacjqdvwpw2xid.onion"),
      ("smp9.simpl.global", "jssqzccmrcws6bhmn77vgmhfjmhwlyr3u7puw4erkyoosywgl67slqqd.onion"),
      ("smp10.simpl.global", "rb2pbttocvnbrngnwziclp2f4ckjq65kebafws6g4hy22cdaiv5dwjqd.onion")
    ]

updateSMPServerHosts :: SMPServer -> SMPServer
updateSMPServerHosts srv@ProtocolServer {host} = case host of
  h :| [] -> case M.lookup h extraSMPServerHosts of
    Just h' -> srv {host = [h, h']}
    _ -> srv
  _ -> srv

class SMPQueue q where
  qServer :: q -> SMPServer
  queueId :: q -> SMP.QueueId

qAddress :: SMPQueue q => q -> (SMPServer, SMP.QueueId)
qAddress q = (qServer q, queueId q)
{-# INLINE qAddress #-}

sameQueue :: SMPQueue q => (SMPServer, SMP.QueueId) -> q -> Bool
sameQueue addr q = sameQAddress addr (qAddress q)
{-# INLINE sameQueue #-}

data SMPQueueInfo = SMPQueueInfo {clientVersion :: VersionSMPC, queueAddress :: SMPQueueAddress}
  deriving (Eq, Show)

instance Encoding SMPQueueInfo where
  smpEncode (SMPQueueInfo clientVersion SMPQueueAddress {smpServer, senderId, dhPublicKey, queueMode})
    | clientVersion >= shortLinksSMPClientVersion = addrEnc <> maybe "" smpEncode queueMode
    | clientVersion >= sndAuthKeySMPClientVersion && sndSecure = addrEnc <> smpEncode sndSecure
    | clientVersion > initialSMPClientVersion = addrEnc
    | otherwise = smpEncode clientVersion <> legacyEncodeServer smpServer <> smpEncode (senderId, dhPublicKey)
    where
      addrEnc = smpEncode (clientVersion, smpServer, senderId, dhPublicKey)
      sndSecure = senderCanSecure queueMode
  smpP = do
    clientVersion <- smpP
    smpServer <- if clientVersion > initialSMPClientVersion then smpP else updateSMPServerHosts <$> legacyServerP
    (senderId, dhPublicKey) <- smpP
    queueMode <- queueModeP
    pure $ SMPQueueInfo clientVersion SMPQueueAddress {smpServer, senderId, dhPublicKey, queueMode}

instance VersionI SMPClientVersion SMPQueueInfo where
  type VersionRangeT SMPClientVersion SMPQueueInfo = SMPQueueUri
  version = clientVersion
  toVersionRangeT (SMPQueueInfo _v addr) vr = SMPQueueUri vr addr

instance VersionRangeI SMPClientVersion SMPQueueUri where
  type VersionT SMPClientVersion SMPQueueUri = SMPQueueInfo
  versionRange = clientVRange
  toVersionT (SMPQueueUri _vr addr) v = SMPQueueInfo v addr
  toVersionRange (SMPQueueUri _vr addr) vr = SMPQueueUri vr addr

data SMPQueueUri = SMPQueueUri {clientVRange :: VersionRangeSMPC, queueAddress :: SMPQueueAddress}
  deriving (Eq, Show)

data SMPQueueAddress = SMPQueueAddress
  { smpServer :: SMPServer,
    senderId :: SMP.SenderId,
    dhPublicKey :: C.PublicKeyX25519,
    queueMode :: Maybe QueueMode
  }
  deriving (Eq, Show)

instance SMPQueue SMPQueueUri where
  qServer SMPQueueUri {queueAddress} = qServer queueAddress
  {-# INLINE qServer #-}
  queueId SMPQueueUri {queueAddress} = queueId queueAddress
  {-# INLINE queueId #-}

instance SMPQueue SMPQueueInfo where
  qServer SMPQueueInfo {queueAddress} = qServer queueAddress
  {-# INLINE qServer #-}
  queueId SMPQueueInfo {queueAddress} = queueId queueAddress
  {-# INLINE queueId #-}

instance SMPQueue SMPQueueAddress where
  qServer SMPQueueAddress {smpServer} = smpServer
  {-# INLINE qServer #-}
  queueId SMPQueueAddress {senderId} = senderId
  {-# INLINE queueId #-}

sameQAddress :: (SMPServer, SMP.QueueId) -> (SMPServer, SMP.QueueId) -> Bool
sameQAddress (srv, qId) (srv', qId') = sameSrvAddr srv srv' && qId == qId'
{-# INLINE sameQAddress #-}

instance StrEncoding SMPQueueUri where
  strEncode (SMPQueueUri vr SMPQueueAddress {smpServer = srv, senderId = qId, dhPublicKey, queueMode})
    | minVersion vr >= srvHostnamesSMPClientVersion = strEncode srv <> "/" <> strEncode qId <> "#/?" <> query queryParams
    | otherwise = legacyStrEncodeServer srv <> "/" <> strEncode qId <> "#/?" <> query (queryParams <> srvParam)
    where
      query = strEncode . QSP QEscape
      queryParams = [("v", strEncode vr), ("dh", strEncode dhPublicKey)] <> queueModeParam <> sndSecureParam
        where
          queueModeParam = case queueMode of
            Just QMMessaging -> [("q", "m")]
            Just QMContact -> [("q", "c")]
            Nothing -> []
          sndSecureParam = [("k", "s") | senderCanSecure queueMode && minVersion vr < shortLinksSMPClientVersion]
      srvParam = [("srv", strEncode $ TransportHosts_ hs) | not (null hs)]
      hs = L.tail $ host srv
  strP = do
    srv@ProtocolServer {host = h :| host} <- strP <* A.char '/'
    senderId <- strP <* optional (A.char '/') <* A.char '#'
    (vr, hs, dhPublicKey, queueMode) <- versioned <|> unversioned
    let srv' = srv {host = h :| host <> hs}
        smpServer = if maxVersion vr < srvHostnamesSMPClientVersion then updateSMPServerHosts srv' else srv'
    pure $ SMPQueueUri vr SMPQueueAddress {smpServer, senderId, dhPublicKey, queueMode}
    where
      unversioned = (versionToRange initialSMPClientVersion,[],,Nothing) <$> strP <* A.endOfInput
      versioned = do
        dhKey_ <- optional strP
        query <- optional (A.char '/') *> A.char '?' *> strP
        vr <- queryParam "v" query
        dhKey <- maybe (queryParam "dh" query) pure dhKey_
        hs_ <- queryParam_ "srv" query
        let queueMode = case queryParamStr "q" query of
              Just "m" -> Just QMMessaging
              Just "c" -> Just QMContact
              _ | queryParamStr "k" query == Just "s" -> Just QMMessaging
              _ -> Nothing
        pure (vr, maybe [] thList_ hs_, dhKey, queueMode)

instance Encoding SMPQueueUri where
  smpEncode (SMPQueueUri clientVRange@(VersionRange minV maxV) SMPQueueAddress {smpServer, senderId, dhPublicKey, queueMode})
    | minV >= shortLinksSMPClientVersion = addrEnc <> maybe "" smpEncode queueMode
    | minV >= sndAuthKeySMPClientVersion || (maxV >= sndAuthKeySMPClientVersion && sndSecure) = addrEnc <> smpEncode sndSecure
    | otherwise = addrEnc
    where
      addrEnc = smpEncode (clientVRange, smpServer, senderId, dhPublicKey)
      sndSecure = senderCanSecure queueMode
  smpP = do
    (clientVRange, smpServer, senderId, dhPublicKey) <- smpP
    queueMode <- queueModeP
    pure $ SMPQueueUri clientVRange SMPQueueAddress {smpServer, senderId, dhPublicKey, queueMode}

queueModeP :: Parser (Maybe QueueMode)
queueModeP = Just <$> smpP <|> optional ((\case True -> QMMessaging; _ -> QMContact) <$> smpP)

data ConnectionRequestUri (m :: ConnectionMode) where
  CRInvitationUri :: ConnReqUriData -> RcvE2ERatchetParamsUri 'C.X448 -> ConnectionRequestUri CMInvitation
  CRContactUri :: ConnReqUriData -> ConnectionRequestUri CMContact

zeroConnReqUri :: ConnectionRequestUri m -> ConnectionRequestUri m
zeroConnReqUri = \case
  CRInvitationUri crData e2eParams -> CRInvitationUri crData {crScheme = SSZero} e2eParams
  CRContactUri crData -> CRContactUri crData {crScheme = SSZero}

deriving instance Eq (ConnectionRequestUri m)

deriving instance Show (ConnectionRequestUri m)

data AConnectionRequestUri = forall m. ConnectionModeI m => ACR (SConnectionMode m) (ConnectionRequestUri m)

instance Eq AConnectionRequestUri where
  ACR m cr == ACR m' cr' = case testEquality m m' of
    Just Refl -> cr == cr'
    _ -> False

deriving instance Show AConnectionRequestUri

data ShortLinkCreds = ShortLinkCreds
  { shortLinkId :: SMP.LinkId,
    shortLinkKey :: LinkKey,
    linkPrivSigKey :: C.PrivateKeyEd25519,
    linkRootSigKey :: Maybe C.PublicKeyEd25519,
    linkEncFixedData :: SMP.EncFixedDataBytes
  }
  deriving (Show)

data ShortLinkScheme = SLSZero | SLSServer deriving (Eq, Show)

data ConnShortLink (m :: ConnectionMode) where
  CSLInvitation :: ShortLinkScheme -> SMPServer -> SMP.LinkId -> LinkKey -> ConnShortLink 'CMInvitation
  CSLContact :: ShortLinkScheme -> ContactConnType -> SMPServer -> LinkKey -> ConnShortLink 'CMContact

deriving instance Eq (ConnShortLink m)

deriving instance Show (ConnShortLink m)

zeroShortLink :: ConnShortLink m -> ConnShortLink m
zeroShortLink = \case
  CSLInvitation _ srv lnkId k -> CSLInvitation SLSZero srv lnkId k
  CSLContact _ ct srv k -> CSLContact SLSZero ct srv k

newtype LinkKey = LinkKey ByteString
  deriving (Eq, Show)
  deriving newtype (FromField, StrEncoding)

instance ToField LinkKey where toField (LinkKey s) = toField $ Binary s

data PreparedLinkParams = PreparedLinkParams
  {
    plpNonce :: C.CbNonce,
    plpQueueE2EKeys :: C.KeyPairX25519,
    plpLinkKey :: LinkKey,
    plpRootPrivKey :: C.PrivateKeyEd25519,
    plpSignedFixedData :: ByteString,
    plpSrvWithAuth :: SMPServerWithAuth
  }
  deriving (Show)

instance ConnectionModeI c => ToField (ConnectionLink c) where toField = toField . Binary . strEncode

instance (Typeable c, ConnectionModeI c) => FromField (ConnectionLink c) where fromField = blobFieldDecoder strDecode

instance ConnectionModeI c => ToField (ConnShortLink c) where toField = toField . Binary . strEncode

instance (Typeable c, ConnectionModeI c) => FromField (ConnShortLink c) where fromField = blobFieldDecoder strDecode

data ContactConnType = CCTContact | CCTChannel | CCTGroup | CCTRelay deriving (Eq, Show)

data AConnShortLink = forall m. ConnectionModeI m => ACSL (SConnectionMode m) (ConnShortLink m)

instance Eq AConnShortLink where
  ACSL m sl == ACSL m' sl' = case testEquality m m' of
    Just Refl -> sl == sl'
    Nothing -> False

deriving instance Show AConnShortLink

instance ToField AConnShortLink where toField = toField . Binary . strEncode

instance FromField AConnShortLink where fromField = blobFieldDecoder strDecode

data ConnectionLink m = CLFull (ConnectionRequestUri m) | CLShort (ConnShortLink m)
  deriving (Eq, Show)

data CreatedConnLink m = CCLink {connFullLink :: ConnectionRequestUri m, connShortLink :: Maybe (ConnShortLink m)}
  deriving (Eq, Show)

data ACreatedConnLink = forall m. ConnectionModeI m => ACCL (SConnectionMode m) (CreatedConnLink m)

instance Eq ACreatedConnLink where
  ACCL m l == ACCL m' l' = case testEquality m m' of
    Just Refl -> l == l'
    _ -> False

deriving instance Show ACreatedConnLink

data AConnectionLink = forall m. ConnectionModeI m => ACL (SConnectionMode m) (ConnectionLink m)

instance Eq AConnectionLink where
  ACL m cl == ACL m' cl' = case testEquality m m' of
    Just Refl -> cl == cl'
    _ -> False

deriving instance Show AConnectionLink

instance ConnectionModeI m => StrEncoding (ConnectionLink m) where
  strEncode = \case
    CLFull cr -> strEncode cr
    CLShort sl -> strEncode sl
  strP = (\(ACL _ cl) -> checkConnMode cl) <$?> strP
  {-# INLINE strP #-}

instance StrEncoding AConnectionLink where
  strEncode (ACL _ cl) = strEncode cl
  {-# INLINE strEncode #-}
  strP =
    (\(ACR m cr) -> ACL m (CLFull cr)) <$> strP
      <|> (\(ACSL m sl) -> ACL m (CLShort sl)) <$> strP

instance ConnectionModeI m => ToJSON (ConnectionLink m) where
  toEncoding = strToJEncoding
  toJSON = strToJSON

instance ConnectionModeI m => FromJSON (ConnectionLink m) where
  parseJSON = strParseJSON "ConnectionLink"

instance ToJSON AConnectionLink where
  toEncoding = strToJEncoding
  toJSON = strToJSON

instance FromJSON AConnectionLink where
  parseJSON = strParseJSON "AConnectionLink"

instance ConnectionModeI m => StrEncoding (ConnShortLink m) where
  strEncode = \case
    CSLInvitation sch srv (SMP.EntityId lnkId) (LinkKey k) -> slEncode sch srv 'i' lnkId k
    CSLContact sch ct srv (LinkKey k) -> slEncode sch srv (toLower $ ctTypeChar ct) "" k
    where
      slEncode sch (SMPServer (h :| hs) port (C.KeyHash kh)) linkType lnkId k =
        B.concat [authority, "/", B.singleton linkType, "#", lnkIdStr, B64.encodeUnpadded k, queryStr]
        where
          (authority, paramHosts) = case sch of
            SLSZero -> ("zero:", h : hs)
            SLSServer -> ("https://" <> strEncode h, hs)
          lnkIdStr = if B.null lnkId then "" else B64.encodeUnpadded lnkId <> "/"
          queryStr = if B.null query then "" else "?" <> query
          query =
            strEncode . QSP QEscape $
              [("h", strEncode (TransportHosts_ paramHosts)) | not (null paramHosts)]
                <> [("p", B.pack port) | not (null port)]
                <> [("c", B64.encodeUnpadded kh) | not (B.null kh)]
  strP = (\(ACSL _ l) -> checkConnMode l) <$?> strP
  {-# INLINE strP #-}

instance StrEncoding AConnShortLink where
  strEncode (ACSL _ l) = strEncode l
  {-# INLINE strEncode #-}
  strP = do
    (sch, h_) <- authorityP <* A.char '/'
    ct_ <- contactTypeP <* optional (A.char '/') <* A.char '#'
    case ct_ of
      Nothing -> do
        lnkId <- strP <* A.char '/'
        k <- strP
        srv <- serverQueryP h_
        pure $ ACSL SCMInvitation $ CSLInvitation sch srv (SMP.EntityId lnkId) (LinkKey k)
      Just ct -> do
        k <- strP
        srv <- serverQueryP h_
        pure $ ACSL SCMContact $ CSLContact sch ct srv (LinkKey k)
    where
      authorityP =
        "zero:" $> (SLSZero, Nothing)
          <|> "https://" *> ((SLSServer,) . Just <$> strP)
          <|> fail "bad short link scheme"
      contactTypeP = do
        Just <$> (A.anyChar >>= ctTypeP . toUpper)
          <|> A.char 'i' $> Nothing
          <|> fail "unknown short link type"
      serverQueryP h_ =
        optional (A.char '?' *> strP) >>= \case
          Nothing -> maybe noServer (pure . SMPServerOnlyHost) h_
          Just query -> do
            hs <- maybe noServer pure . L.nonEmpty . maybe id (:) h_ . maybe [] thList_ =<< queryParam_ "h" query
            p <- maybe "" show <$> queryParam_ @Word16 "p" query
            kh <- fromMaybe (C.KeyHash "") <$> queryParam_ "c" query
            pure $ SMPServer hs p kh
      noServer = fail "short link without server"

instance ConnectionModeI m => Encoding (ConnShortLink m) where
  smpEncode = \case
    CSLInvitation _ srv lnkId (LinkKey k) -> smpEncode (CMInvitation, srv, lnkId, k)
    CSLContact _ ct srv (LinkKey k) -> smpEncode (CMContact, ctTypeChar ct, srv, k)
  smpP = (\(ACSL _ l) -> checkConnMode l) <$?> smpP
  {-# INLINE smpP #-}

instance Encoding AConnShortLink where
  smpEncode (ACSL _ l) = smpEncode l
  {-# INLINE smpEncode #-}
  smpP =
    smpP >>= \case
      CMInvitation -> do
        (srv, lnkId, k) <- smpP
        pure $ ACSL SCMInvitation $ CSLInvitation SLSServer srv lnkId (LinkKey k)
      CMContact -> do
        ct <- ctTypeP =<< A.anyChar
        (srv, k) <- smpP
        pure $ ACSL SCMContact $ CSLContact SLSServer ct srv (LinkKey k)

ctTypeP :: Char -> Parser ContactConnType
ctTypeP = \case
  'A' -> pure CCTContact
  'C' -> pure CCTChannel
  'G' -> pure CCTGroup
  'R' -> pure CCTRelay
  _ -> fail "unknown contact address type"
{-# INLINE ctTypeP #-}

ctTypeChar :: ContactConnType -> Char
ctTypeChar = \case
  CCTContact -> 'A'
  CCTChannel -> 'C'
  CCTGroup -> 'G'
  CCTRelay -> 'R'
{-# INLINE ctTypeChar #-}

instance StrEncoding ContactConnType where
  strEncode = B.singleton . ctTypeChar
  strP = A.anyChar >>= ctTypeP

shortenShortLink :: NonEmpty SMPServer -> ConnShortLink m -> ConnShortLink m
shortenShortLink presetSrvs = \case
  CSLInvitation sch srv lnkId linkKey -> CSLInvitation sch (shortServer srv) lnkId linkKey
  CSLContact sch ct srv linkKey -> CSLContact sch ct (shortServer srv) linkKey
  where
    shortServer srv@(SMPServer (h :| _) _ _) =
      if isPresetServer srv presetSrvs then SMPServerOnlyHost h else srv

isPresetServer :: Foldable t => SMPServer -> t SMPServer -> Bool
isPresetServer srv@(SMPServer hs p kh) presetSrvs = case findPresetServer srv presetSrvs of
  Just (SMPServer hs' p' kh') ->
    all (`elem` hs') hs
      && (p == p' || (null p' && (p == "443" || p == "5223")))
      && kh == kh'
  Nothing -> False

pattern SMPServerOnlyHost :: TransportHost -> SMPServer
pattern SMPServerOnlyHost h <- SMPServer [h] "" (C.KeyHash "")
  where
    SMPServerOnlyHost h = SMPServer [h] "" (C.KeyHash "")

restoreShortLink :: NonEmpty SMPServer -> ConnShortLink m -> ConnShortLink m
restoreShortLink presetSrvs = \case
  CSLInvitation sch srv lnkId linkKey -> CSLInvitation sch (fullServer srv) lnkId linkKey
  CSLContact sch ct srv linkKey -> CSLContact sch ct (fullServer srv) linkKey
  where
    fullServer = \case
      s@(SMPServerOnlyHost _) -> fromMaybe s $ findPresetServer s presetSrvs
      s -> s

findPresetServer :: Foldable t => SMPServer -> t SMPServer -> Maybe SMPServer
findPresetServer ProtocolServer {host = h :| _} = find (\ProtocolServer {host = h' :| _} -> h == h')
{-# INLINE findPresetServer #-}

sameConnReqContact :: ConnectionRequestUri 'CMContact -> ConnectionRequestUri 'CMContact -> Bool
sameConnReqContact (CRContactUri ConnReqUriData {crSmpQueues = qs}) (CRContactUri ConnReqUriData {crSmpQueues = qs'}) =
  L.length qs == L.length qs' && all same (L.zip qs qs')
  where
    same (q, q') = sameQAddress (qAddress q) (qAddress q')

sameConnShortLink :: AConnShortLink -> AConnShortLink -> Bool
sameConnShortLink (ACSL m sl) (ACSL m' sl') = case testEquality m m' of
  Just Refl -> case sl of
    CSLContact {} -> sameShortLinkContact sl sl'
    CSLInvitation {} -> sameShortLinkInv sl sl'
  Nothing -> False

sameShortLinkContact :: ConnShortLink 'CMContact -> ConnShortLink 'CMContact -> Bool
sameShortLinkContact (CSLContact _ ct srv k) (CSLContact _ ct' srv' k') =
  ct == ct' && sameSrvAddr srv srv' && k == k'

sameShortLinkInv :: ConnShortLink 'CMInvitation -> ConnShortLink 'CMInvitation -> Bool
sameShortLinkInv (CSLInvitation _ srv lnkId k) (CSLInvitation _ srv' lnkId' k') =
  sameSrvAddr srv srv' && lnkId == lnkId' && k == k'

checkConnMode :: forall t m m'. (ConnectionModeI m, ConnectionModeI m') => t m' -> Either String (t m)
checkConnMode c = case testEquality (sConnectionMode @m) (sConnectionMode @m') of
  Just Refl -> Right c
  Nothing -> Left "bad connection mode"
{-# INLINE checkConnMode #-}

data ConnReqUriData = ConnReqUriData
  { crScheme :: ServiceScheme,
    crAgentVRange :: VersionRangeSMPA,
    crSmpQueues :: NonEmpty SMPQueueUri,
    crClientData :: Maybe CRClientData
  }
  deriving (Eq, Show)

type CRClientData = Text

data FixedLinkData c = FixedLinkData
  { agentVRange :: VersionRangeSMPA,
    rootKey :: C.PublicKeyEd25519,
    linkConnReq :: ConnectionRequestUri c,
    linkEntityId :: Maybe ByteString
  }
  deriving (Eq, Show)

data ConnLinkData c where
  InvitationLinkData :: VersionRangeSMPA -> UserLinkData -> ConnLinkData 'CMInvitation
  ContactLinkData :: VersionRangeSMPA -> UserContactData -> ConnLinkData 'CMContact

deriving instance Eq (ConnLinkData c)

deriving instance Show (ConnLinkData c)

data UserContactData = UserContactData
  {
    direct :: Bool,
    owners :: [OwnerAuth],
    relays :: [ConnShortLink 'CMContact],
    userData :: UserLinkData
  }
  deriving (Eq, Show)

newtype UserLinkData = UserLinkData ByteString
  deriving (Eq, Show)

data AConnLinkData = forall m. ConnectionModeI m => ACLD (SConnectionMode m) (ConnLinkData m)

data UserConnLinkData c where
  UserInvLinkData :: UserLinkData -> UserConnLinkData 'CMInvitation
  UserContactLinkData :: UserContactData -> UserConnLinkData 'CMContact

deriving instance Eq (UserConnLinkData m)

deriving instance Show (UserConnLinkData m)

data AUserConnLinkData = forall m. ConnectionModeI m => AULD (SConnectionMode m) (UserConnLinkData m)

linkUserData :: ConnLinkData c -> UserLinkData
linkUserData = \case
  InvitationLinkData _ d -> d
  ContactLinkData _ UserContactData {userData} -> userData
{-# INLINE linkUserData #-}

linkUserData' :: ConnLinkData c -> ByteString
linkUserData' d = let UserLinkData s = linkUserData d in s
{-# INLINE linkUserData' #-}

type OwnerId = ByteString

data OwnerAuth = OwnerAuth
  { ownerId :: OwnerId,
    ownerKey :: C.PublicKeyEd25519,
    authOwnerSig :: C.Signature 'C.Ed25519
  }
  deriving (Eq, Show)

instance Encoding OwnerAuth where
  smpEncode OwnerAuth {ownerId, ownerKey, authOwnerSig} =
    smpEncode $ smpEncode (ownerId, ownerKey, C.signatureBytes authOwnerSig)
  smpP = do
    (ownerId, ownerKey, authOwnerSig) <- A.parseOnly smpP <$?> smpP
    pure OwnerAuth {ownerId, ownerKey, authOwnerSig}

validateOwners :: Maybe ShortLinkCreds -> UserContactData -> Either String ()
validateOwners shortLink_ UserContactData {owners} = case shortLink_ of
  Nothing
    | null owners -> Right ()
    | otherwise -> Left "no link credentials with additional owners"
  Just ShortLinkCreds {linkPrivSigKey, linkRootSigKey}
    | hasOwner -> validateLinkOwners (fromMaybe k linkRootSigKey) owners
    | otherwise -> Left "no current owner in link data"
    where
      hasOwner = isNothing linkRootSigKey || any ((k ==) . ownerKey) owners
      k = C.publicKey linkPrivSigKey

validateLinkOwners :: C.PublicKeyEd25519 -> [OwnerAuth] -> Either String ()
validateLinkOwners rootKey = go []
  where
    go _ [] = Right ()
    go prev (o : os) = validOwner o >> go (o : prev) os
      where
        validOwner OwnerAuth {ownerId = oId, ownerKey = k, authOwnerSig = sig}
          | k == rootKey = Left $ "owner key for ID " <> idStr <> " matches root key"
          | any duplicate prev = Left $ "duplicate owner key or ID " <> idStr
          | signedBy rootKey || any (signedBy . ownerKey) prev = Right ()
          | otherwise = Left $ "invalid authorization of owner ID " <> idStr
          where
            duplicate OwnerAuth {ownerId, ownerKey} = oId == ownerId || k == ownerKey
            idStr = B.unpack $ B64.encodeUnpadded oId
            signedBy k' = C.verify' k' sig (oId <> C.encodePubKey k)

instance ConnectionModeI c => Encoding (FixedLinkData c) where
  smpEncode FixedLinkData {agentVRange, rootKey, linkConnReq, linkEntityId} =
    smpEncode (agentVRange, rootKey, linkConnReq) <> maybe "" smpEncode linkEntityId
  smpP = do
    (agentVRange, rootKey, linkConnReq) <- smpP
    linkEntityId <- optional smpP <* A.takeByteString
    pure FixedLinkData {agentVRange, rootKey, linkConnReq, linkEntityId}

instance ConnectionModeI c => Encoding (ConnLinkData c) where
  smpEncode = \case
    InvitationLinkData vr userData -> smpEncode (CMInvitation, vr, userData)
    ContactLinkData vr cd -> smpEncode (CMContact, vr, cd)
  smpP = (\(ACLD _ d) -> checkConnMode d) <$?> smpP
  {-# INLINE smpP #-}

instance Encoding AConnLinkData where
  smpEncode (ACLD _ d) = smpEncode d
  {-# INLINE smpEncode #-}
  smpP =
    smpP >>= \case
      CMInvitation -> do
        (vr, userData) <- smpP <* A.takeByteString
        pure $ ACLD SCMInvitation $ InvitationLinkData vr userData
      CMContact -> do
        (vr, cd) <- smpP
        pure $ ACLD SCMContact $ ContactLinkData vr cd

instance ConnectionModeI c => Encoding (UserConnLinkData c) where
  smpEncode = \case
    UserInvLinkData userData -> smpEncode (CMInvitation, userData)
    UserContactLinkData cd -> smpEncode (CMContact, cd)
  smpP = (\(AULD _ d) -> checkConnMode d) <$?> smpP
  {-# INLINE smpP #-}

instance Encoding AUserConnLinkData where
  smpEncode (AULD _ d) = smpEncode d
  {-# INLINE smpEncode #-}
  smpP =
    smpP >>= \case
      CMInvitation -> do
        userData <- smpP <* A.takeByteString
        pure $ AULD SCMInvitation $ UserInvLinkData userData
      CMContact ->
        AULD SCMContact . UserContactLinkData <$> smpP

instance ConnectionModeI c => StrEncoding (UserConnLinkData c) where
  strEncode = smpEncode
  {-# INLINE strEncode #-}
  strP = smpP
  {-# INLINE strP #-}

instance Encoding UserContactData where
  smpEncode UserContactData {direct, owners, relays, userData} =
    B.concat [smpEncode direct, smpEncodeList owners, smpEncodeList relays, smpEncode userData]
  smpP = do
    direct <- smpP
    owners <- smpListP
    relays <- smpListP
    userData <- smpP <* A.takeByteString
    pure UserContactData {direct, owners, relays, userData}

instance Encoding UserLinkData where
  smpEncode (UserLinkData s) = if B.length s <= 254 then smpEncode s else smpEncode ('\255', Large s)
  {-# INLINE smpEncode #-}
  smpP = UserLinkData <$> ((A.char '\255' *> (unLarge <$> smpP)) <|> smpP)
  {-# INLINE smpP #-}

data QueueStatus
  =
    New
  |
    Confirmed
  |
    Secured
  |
    Active
  |
    Disabled
  deriving (Eq, Show, Read)

serializeQueueStatus :: QueueStatus -> Text
serializeQueueStatus = \case
  New -> "new"
  Confirmed -> "confirmed"
  Secured -> "secured"
  Active -> "active"
  Disabled -> "disabled"

queueStatusT :: Text -> Maybe QueueStatus
queueStatusT = \case
  "new" -> Just New
  "confirmed" -> Just Confirmed
  "secured" -> Just Secured
  "active" -> Just Active
  "disabled" -> Just Disabled
  _ -> Nothing

type AgentMsgId = Int64

data MsgIntegrity = MsgOk | MsgError {errorInfo :: MsgErrorType}
  deriving (Eq, Show)

instance StrEncoding MsgIntegrity where
  strP = "OK" $> MsgOk <|> "ERR " *> (MsgError <$> strP)
  strEncode = \case
    MsgOk -> "OK"
    MsgError e -> "ERR " <> strEncode e

data MsgErrorType
  = MsgSkipped {fromMsgId :: AgentMsgId, toMsgId :: AgentMsgId}
  | MsgBadId {msgId :: AgentMsgId}
  | MsgBadHash
  | MsgDuplicate
  deriving (Eq, Show)

instance StrEncoding MsgErrorType where
  strP =
    "ID " *> (MsgBadId <$> A.decimal)
      <|> "NO_ID " *> (MsgSkipped <$> A.decimal <* A.space <*> A.decimal)
      <|> "HASH" $> MsgBadHash
      <|> "DUPLICATE" $> MsgDuplicate
  strEncode = \case
    MsgSkipped fromMsgId toMsgId ->
      B.unwords ["NO_ID", bshow fromMsgId, bshow toMsgId]
    MsgBadId aMsgId -> "ID " <> bshow aMsgId
    MsgBadHash -> "HASH"
    MsgDuplicate -> "DUPLICATE"

data AgentErrorType
  =
    CMD {cmdErr :: CommandErrorType, errContext :: String}
  |
    CONN {connErr :: ConnectionErrorType, errContext :: String}
  |
    NO_USER
  |
    SMP {serverAddress :: String, smpErr :: ErrorType}
  |
    NTF {serverAddress :: String, ntfErr :: ErrorType}
  |
    XFTP {serverAddress :: String, xftpErr :: XFTPErrorType}
  |
    FILE {fileErr :: FileErrorType}
  |
    NO_NAME_SERVERS
  |
    PROXY {proxyServer :: String, relayServer :: String, proxyErr :: ProxyClientError}
  |
    RCP {rcpErr :: RCErrorType}
  |
    BROKER {brokerAddress :: String, brokerErr :: BrokerErrorType}
  |
    AGENT {agentErr :: SMPAgentError}
  |
    NOTICE {server :: Text, preset :: Bool, expiresAt :: Maybe UTCTime}
  |
    INTERNAL {internalErr :: String}
  |
    CRITICAL {offerRestart :: Bool, criticalErr :: String}
  |
    INACTIVE
  deriving (Eq, Show, Exception)

instance AnyError AgentErrorType where
  fromSomeException e = case fromException e of
    Just BlockedIndefinitelyOnSTM -> CRITICAL True "Thread blocked indefinitely in STM transaction"
    _ -> case fromException e of
      Just BlockedIndefinitelyOnMVar -> CRITICAL True "Thread blocked indefinitely on MVar"
      _ -> INTERNAL $ show e
  {-# INLINE fromSomeException #-}

data CommandErrorType
  =
    PROHIBITED
  |
    SYNTAX
  |
    NO_CONN
  |
    SIZE
  |
    LARGE
  deriving (Eq, Read, Show, Exception)

data ConnectionErrorType
  =
    NOT_FOUND
  |
    DUPLICATE
  |
    ZERO
  |
    NOT_ACCEPTED
  |
    NOT_AVAILABLE
  deriving (Eq, Read, Show, Exception)

data SMPAgentError
  =
    A_MESSAGE
  |
    A_PROHIBITED {prohibitedErr :: String}
  |
    A_VERSION
  |
    A_LINK {linkErr :: String}
  |
    A_CRYPTO {cryptoErr :: AgentCryptoError}
  |
    A_DUPLICATE {droppedMsg_ :: Maybe DroppedMsg}
  |
    A_QUEUE {queueErr :: String}
  deriving (Eq, Show, Exception)

data AgentCryptoError
  =
    DECRYPT_AES
  |
    DECRYPT_CB
  |
    RATCHET_HEADER
  |
    RATCHET_EARLIER Word32
  |
    RATCHET_SKIPPED Word32
  |
    RATCHET_SYNC
  deriving (Eq, Read, Show, Exception)

cryptoErrToSyncState :: AgentCryptoError -> RatchetSyncState
cryptoErrToSyncState = \case
  DECRYPT_AES -> RSAllowed
  DECRYPT_CB -> RSAllowed
  RATCHET_HEADER -> RSRequired
  RATCHET_EARLIER _ -> RSAllowed
  RATCHET_SKIPPED _ -> RSRequired
  RATCHET_SYNC -> RSRequired

dbCommandP :: Parser ACommand
dbCommandP = commandP $ A.take =<< (A.decimal <* "\n")

instance StrEncoding ACommandTag where
  strP =
    A.takeTill (== ' ') >>= \case
      "NEW" -> pure NEW_
      "LSET" -> pure LSET_
      "LGET" -> pure LGET_
      "JOIN" -> pure JOIN_
      "LET" -> pure LET_
      "ACK" -> pure ACK_
      "SWCH" -> pure SWCH_
      "DEL" -> pure DEL_
      _ -> fail "bad ACommandTag"
  strEncode = \case
    NEW_ -> "NEW"
    LSET_ -> "LSET"
    LGET_ -> "LGET"
    JOIN_ -> "JOIN"
    LET_ -> "LET"
    ACK_ -> "ACK"
    SWCH_ -> "SWCH"
    DEL_ -> "DEL"

commandP :: Parser ByteString -> Parser ACommand
commandP binaryP =
  strP
    >>= \case
      NEW_ -> s (NEW <$> strP_ <*> strP_ <*> pqIKP <*> (strP <|> pure SMP.SMSubscribe))
      LSET_ -> s (LSET <$> strP <*> optional (A.space *> strP))
      LGET_ -> s (LGET <$> strP)
      JOIN_ -> s (JOIN <$> strP_ <*> strP_ <*> pqSupP <*> (strP_ <|> pure SMP.SMSubscribe) <*> binaryP)
      LET_ -> s (LET <$> A.takeTill (== ' ') <* A.space <*> binaryP)
      ACK_ -> s (ACK <$> A.decimal <*> optional (A.space *> binaryP))
      SWCH_ -> pure SWCH
      DEL_ -> pure DEL
  where
    s :: Parser a -> Parser a
    s p = A.space *> p
    pqIKP :: Parser InitialKeys
    pqIKP = strP_ <|> pure (IKLinkPQ PQSupportOff)
    pqSupP :: Parser PQSupport
    pqSupP = strP_ <|> pure PQSupportOff

serializeCommand :: ACommand -> ByteString
serializeCommand = \case
  NEW ntfs cMode pqIK subMode -> s (NEW_, ntfs, cMode, pqIK, subMode)
  LSET uld cd_ -> s (LSET_, uld) <> maybe "" (B.cons ' ' . s) cd_
  LGET sl -> s (LGET_, sl)
  JOIN ntfs cReq pqSup subMode cInfo -> s (JOIN_, ntfs, cReq, pqSup, subMode, Str $ serializeBinary cInfo)
  LET confId cInfo -> B.unwords [s LET_, confId, serializeBinary cInfo]
  ACK mId rcptInfo_ -> s (ACK_, mId) <> maybe "" (B.cons ' ' . serializeBinary) rcptInfo_
  SWCH -> s SWCH_
  DEL -> s DEL_
  where
    s :: StrEncoding a => a -> ByteString
    s = strEncode

serializeBinary :: ByteString -> ByteString
serializeBinary body = bshow (B.length body) <> "\n" <> body

$(J.deriveJSON (enumJSON fstToLower) ''QueueStatus)

$(J.deriveJSON (sumTypeJSON $ dropPrefix "SS") ''SubscriptionStatus)

$(J.deriveJSON defaultJSON ''RcvQueueInfo)

$(J.deriveJSON defaultJSON ''SndQueueInfo)

$(J.deriveJSON defaultJSON ''ConnectionStats)

$(J.deriveJSON (sumTypeJSON fstToLower) ''MsgErrorType)

$(J.deriveJSON (sumTypeJSON fstToLower) ''MsgIntegrity)

$(J.deriveJSON (sumTypeJSON id) ''CommandErrorType)

$(J.deriveJSON (sumTypeJSON id) ''ConnectionErrorType)

$(J.deriveJSON (sumTypeJSON id) ''AgentCryptoError)

$(J.deriveJSON defaultJSON ''DroppedMsg)

$(J.deriveJSON (sumTypeJSON id) ''SMPAgentError)

$(J.deriveJSON (sumTypeJSON id) ''AgentErrorType)

$(J.deriveJSON (enumJSON $ dropPrefix "QD") ''QueueDirection)

$(J.deriveJSON (enumJSON $ dropPrefix "SP") ''SwitchPhase)

instance ConnectionModeI m => FromJSON (CreatedConnLink m) where
  parseJSON = $(J.mkParseJSON defaultJSON ''CreatedConnLink)

instance ConnectionModeI m => ToJSON (CreatedConnLink m) where
  toEncoding = $(J.mkToEncoding defaultJSON ''CreatedConnLink)
  toJSON = $(J.mkToJSON defaultJSON ''CreatedConnLink)

instance FromJSON ACreatedConnLink where
  parseJSON (Object v) = do
    ACR m cReq <- v .: "connFullLink"
    shortLink <- v .:? "connShortLink"
    pure $ ACCL m $ CCLink cReq shortLink
  parseJSON invalid =
    JT.prependFailure "bad ACreatedConnLink, " (JT.typeMismatch "Object" invalid)

instance ToJSON ACreatedConnLink where
  toEncoding (ACCL _ ccLink) = toEncoding ccLink
  toJSON (ACCL _ ccLink) = toJSON ccLink

