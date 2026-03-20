{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# OPTIONS_GHC -fno-warn-unticked-promoted-constructors #-}

module Zero.Messaging.Agent.Store
  ( RcvQueue,
    NewRcvQueue,
    StoredRcvQueue (..),
    RcvQueueSub (..),
    ClientNtfCreds (..),
    InvShortLink (..),
    SndQueue,
    NewSndQueue,
    StoredSndQueue (..),
    SMPQueueRec (..),
    SomeRcvQueue (..),
    ConnType (..),
    Connection' (..),
    Connection,
    SConnType (..),
    SomeConn' (..),
    SomeConn,
    SomeConnSub,
    ConnData (..),
    NoticeId,
    PendingCommand (..),
    AgentCmdType (..),
    AgentCommand (..),
    AgentCommandTag (..),
    InternalCommand (..),
    InternalCommandTag (..),
    NewConfirmation (..),
    AcceptedConfirmation (..),
    NewInvitation (..),
    Invitation (..),
    PrevExternalSndId,
    PrevRcvMsgHash,
    PrevSndMsgHash,
    RcvMsgData (..),
    RcvMsg (..),
    SndMsgData (..),
    SndMsgPrepData (..),
    SndMsg (..),
    PendingMsgData (..),
    PendingMsgPrepData (..),
    InternalRcvId (..),
    ExternalSndId,
    ExternalSndTs,
    BrokerId,
    BrokerTs,
    InternalSndId (..),
    MsgBase (..),
    InternalId (..),
    InternalTs,
    AsyncCmdId,
    StoreError (..),
    AnyStoreError (..),
    ServiceAssoc,
    createStore,
    rcvQueueSub,
    rcvSMPQueueAddress,
    canAbortRcvSwitch,
    findQ,
    removeQ,
    removeQP,
    sndAddress,
    findRQ,
    switchingRQ,
    updatedQs,
    toConnData,
    updateConnection,
    connType,
    ratchetSyncAllowed,
    ratchetSyncSendProhibited,
    agentCommandTag,
    internalCmdTag,
  ) where

import Control.Exception (Exception (..))
import qualified Data.Attoparsec.ByteString.Char8 as A
import Data.ByteString.Char8 (ByteString)
import Data.Int (Int64)
import Data.Kind (Type)
import Data.List (find)
import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as L
import Data.Maybe (isJust)
import Data.Time (UTCTime)
import Data.Type.Equality
import Zero.Messaging.Agent.Protocol
import Zero.Messaging.Agent.RetryInterval (RI2State)
import Zero.Messaging.Agent.Store.Common
import Zero.Messaging.Agent.Store.DB (SQLError)
import Zero.Messaging.Agent.Store.Entity
import Zero.Messaging.Agent.Store.Interface (createDBStore)
import Zero.Messaging.Agent.Store.Migrations.App (appMigrations)
import Zero.Messaging.Agent.Store.Shared (MigrationConfig (..), MigrationError (..))
import qualified Zero.Messaging.Crypto as C
import Zero.Messaging.Crypto.Ratchet (MsgEncryptKeyX448, PQEncryption, PQSupport, RatchetX448)
import Zero.Messaging.Encoding.String
import Zero.Messaging.Protocol
  ( MsgBody,
    MsgFlags,
    MsgId,
    NotifierId,
    NtfPrivateAuthKey,
    NtfPublicAuthKey,
    QueueMode,
    RcvDhSecret,
    RcvNtfDhSecret,
    RcvPrivateAuthKey,
    SndPrivateAuthKey,
    VersionSMPC,
  )
import qualified Zero.Messaging.Protocol as SMP
import Zero.Messaging.Util (AnyError (..), bshow)

createStore :: DBOpts -> MigrationConfig -> IO (Either MigrationError DBStore)
createStore dbOpts = createDBStore dbOpts appMigrations

type RcvQueue = StoredRcvQueue 'DBStored

type NewRcvQueue = StoredRcvQueue 'DBNew

data StoredRcvQueue (q :: DBStored) = RcvQueue
  { userId :: UserId,
    connId :: ConnId,
    server :: SMPServer,
    rcvId :: SMP.RecipientId,
    rcvPrivateKey :: RcvPrivateAuthKey,
    rcvDhSecret :: RcvDhSecret,
    e2ePrivKey :: C.PrivateKeyX25519,
    e2eDhSecret :: Maybe C.DhSecretX25519,
    sndId :: SMP.SenderId,
    queueMode :: Maybe QueueMode,
    shortLink :: Maybe ShortLinkCreds,
    rcvServiceAssoc :: ServiceAssoc,
    status :: QueueStatus,
    enableNtfs :: Bool,
    clientNoticeId :: Maybe NoticeId,
    dbQueueId :: DBEntityId' q,
    primary :: Bool,
    dbReplaceQueueId :: Maybe Int64,
    rcvSwchStatus :: Maybe RcvSwitchStatus,
    smpClientVersion :: VersionSMPC,
    clientNtfCreds :: Maybe ClientNtfCreds,
    deleteErrors :: Int
  }
  deriving (Show)

data RcvQueueSub = RcvQueueSub
  { userId :: UserId,
    connId :: ConnId,
    server :: SMPServer,
    rcvId :: SMP.RecipientId,
    rcvPrivateKey :: RcvPrivateAuthKey,
    status :: QueueStatus,
    enableNtfs :: Bool,
    clientNoticeId :: Maybe NoticeId,
    dbQueueId :: Int64,
    primary :: Bool,
    dbReplaceQueueId :: Maybe Int64
  }
  deriving (Show)

rcvQueueSub :: RcvQueue -> RcvQueueSub
rcvQueueSub RcvQueue {userId, connId, server, rcvId, rcvPrivateKey, status, enableNtfs, clientNoticeId, dbQueueId = DBEntityId dbQueueId, primary, dbReplaceQueueId} =
  RcvQueueSub {userId, connId, server, rcvId, rcvPrivateKey, status, enableNtfs, clientNoticeId, dbQueueId, primary, dbReplaceQueueId}

type ServiceAssoc = Bool

rcvSMPQueueAddress :: RcvQueue -> SMPQueueAddress
rcvSMPQueueAddress RcvQueue {server, sndId, e2ePrivKey, queueMode} =
  SMPQueueAddress server sndId (C.publicKey e2ePrivKey) queueMode

canAbortRcvSwitch :: RcvQueue -> Bool
canAbortRcvSwitch = maybe False canAbort . rcvSwchStatus
  where
    canAbort = \case
      RSSwitchStarted -> True
      RSSendingQADD -> True
      RSSendingQUSE -> False
      RSReceivedMessage -> False

data ClientNtfCreds = ClientNtfCreds
  {
    ntfPublicKey :: NtfPublicAuthKey,
    ntfPrivateKey :: NtfPrivateAuthKey,
    notifierId :: NotifierId,
    rcvNtfDhSecret :: RcvNtfDhSecret
  }
  deriving (Show)

data InvShortLink = InvShortLink
  { server :: SMPServer,
    linkId :: SMP.LinkId,
    linkKey :: LinkKey,
    sndPrivateKey :: SndPrivateAuthKey,
    sndId :: Maybe SMP.SenderId
  }
  deriving (Show)

type SndQueue = StoredSndQueue 'DBStored

type NewSndQueue = StoredSndQueue 'DBNew

data StoredSndQueue (q :: DBStored) = SndQueue
  { userId :: UserId,
    connId :: ConnId,
    server :: SMPServer,
    sndId :: SMP.SenderId,
    queueMode :: Maybe QueueMode,
    sndPrivateKey :: SndPrivateAuthKey,
    e2ePubKey :: Maybe C.PublicKeyX25519,
    e2eDhSecret :: C.DhSecretX25519,
    status :: QueueStatus,
    dbQueueId :: DBEntityId' q,
    primary :: Bool,
    dbReplaceQueueId :: Maybe Int64,
    sndSwchStatus :: Maybe SndSwitchStatus,
    smpClientVersion :: VersionSMPC
  }
  deriving (Show)

instance SMPQueue RcvQueue where
  qServer RcvQueue {server} = server
  {-# INLINE qServer #-}
  queueId RcvQueue {rcvId} = rcvId
  {-# INLINE queueId #-}

instance SMPQueue NewRcvQueue where
  qServer RcvQueue {server} = server
  {-# INLINE qServer #-}
  queueId RcvQueue {rcvId} = rcvId
  {-# INLINE queueId #-}

instance SMPQueue RcvQueueSub where
  qServer RcvQueueSub {server} = server
  {-# INLINE qServer #-}
  queueId RcvQueueSub {rcvId} = rcvId
  {-# INLINE queueId #-}

instance SMPQueue SndQueue where
  qServer SndQueue {server} = server
  {-# INLINE qServer #-}
  queueId SndQueue {sndId} = sndId
  {-# INLINE queueId #-}

findQ :: SMPQueue q => (SMPServer, SMP.QueueId) -> NonEmpty q -> Maybe q
findQ = find . sameQueue
{-# INLINE findQ #-}

removeQ :: SMPQueue q => (SMPServer, SMP.QueueId) -> NonEmpty q -> Maybe (q, [q])
removeQ = removeQP . sameQueue
{-# INLINE removeQ #-}

removeQP :: (q -> Bool) -> NonEmpty q -> Maybe (q, [q])
removeQP p qs = case L.break p qs of
  (_, []) -> Nothing
  (qs1, q : qs2) -> Just (q, qs1 <> qs2)

sndAddress :: RcvQueue -> (SMPServer, SMP.SenderId)
sndAddress RcvQueue {server, sndId} = (server, sndId)
{-# INLINE sndAddress #-}

findRQ :: (SMPServer, SMP.SenderId) -> NonEmpty RcvQueue -> Maybe RcvQueue
findRQ sAddr = find $ sameQAddress sAddr . sndAddress
{-# INLINE findRQ #-}

switchingRQ :: NonEmpty RcvQueue -> Maybe RcvQueue
switchingRQ = find $ isJust . rcvSwchStatus
{-# INLINE switchingRQ #-}

updatedQs :: SMPQueueRec q => q -> NonEmpty q -> NonEmpty q
updatedQs q = L.map $ \q' -> if dbQId q == dbQId q' then q else q'
{-# INLINE updatedQs #-}

class SMPQueue q => SMPQueueRec q where
  qUserId :: q -> UserId
  qConnId :: q -> ConnId
  dbQId :: q -> Int64
  qPrimary :: q -> Bool
  dbReplaceQId :: q -> Maybe Int64

instance SMPQueueRec RcvQueue where
  qUserId RcvQueue {userId} = userId
  {-# INLINE qUserId #-}
  qConnId RcvQueue {connId} = connId
  {-# INLINE qConnId #-}
  dbQId RcvQueue {dbQueueId = DBEntityId qId} = qId
  {-# INLINE dbQId #-}
  qPrimary RcvQueue {primary} = primary
  {-# INLINE qPrimary #-}
  dbReplaceQId RcvQueue {dbReplaceQueueId} = dbReplaceQueueId
  {-# INLINE dbReplaceQId #-}

instance SMPQueueRec RcvQueueSub where
  qUserId RcvQueueSub {userId} = userId
  {-# INLINE qUserId #-}
  qConnId RcvQueueSub {connId} = connId
  {-# INLINE qConnId #-}
  dbQId RcvQueueSub {dbQueueId} = dbQueueId
  {-# INLINE dbQId #-}
  qPrimary RcvQueueSub {primary} = primary
  {-# INLINE qPrimary #-}
  dbReplaceQId RcvQueueSub {dbReplaceQueueId} = dbReplaceQueueId
  {-# INLINE dbReplaceQId #-}

instance SMPQueueRec SndQueue where
  qUserId SndQueue {userId} = userId
  {-# INLINE qUserId #-}
  qConnId SndQueue {connId} = connId
  {-# INLINE qConnId #-}
  dbQId SndQueue {dbQueueId = DBEntityId qId} = qId
  {-# INLINE dbQId #-}
  qPrimary SndQueue {primary} = primary
  {-# INLINE qPrimary #-}
  dbReplaceQId SndQueue {dbReplaceQueueId} = dbReplaceQueueId
  {-# INLINE dbReplaceQId #-}

class SMPQueueRec q => SomeRcvQueue q where
  rcvAuthKey :: q -> RcvPrivateAuthKey

instance SomeRcvQueue RcvQueue where
  rcvAuthKey RcvQueue {rcvPrivateKey} = rcvPrivateKey
  {-# INLINE rcvAuthKey #-}

instance SomeRcvQueue RcvQueueSub where
  rcvAuthKey RcvQueueSub {rcvPrivateKey} = rcvPrivateKey
  {-# INLINE rcvAuthKey #-}

data ConnType = CNew | CRcv | CSnd | CDuplex | CContact deriving (Eq, Show)

data Connection' (d :: ConnType) rq sq where
  NewConnection :: ConnData -> Connection' CNew rq sq
  RcvConnection :: ConnData -> rq -> Connection' CRcv rq sq
  SndConnection :: ConnData -> sq -> Connection' CSnd rq sq
  DuplexConnection :: ConnData -> NonEmpty rq -> NonEmpty sq -> Connection' CDuplex rq sq
  ContactConnection :: ConnData -> rq -> Connection' CContact rq sq

deriving instance (Show rq, Show sq) => Show (Connection' d rq sq)

type Connection d = Connection' d RcvQueue SndQueue

toConnData :: Connection' d rq sq -> ConnData
toConnData = \case
  NewConnection cData -> cData
  RcvConnection cData _ -> cData
  SndConnection cData _ -> cData
  DuplexConnection cData _ _ -> cData
  ContactConnection cData _ -> cData

updateConnection :: ConnData -> Connection' d rq sq -> Connection' d rq sq
updateConnection cData = \case
  NewConnection _ -> NewConnection cData
  RcvConnection _ rq -> RcvConnection cData rq
  SndConnection _ sq -> SndConnection cData sq
  DuplexConnection _ rqs sqs -> DuplexConnection cData rqs sqs
  ContactConnection _ rq -> ContactConnection cData rq

data SConnType :: ConnType -> Type where
  SCNew :: SConnType CNew
  SCRcv :: SConnType CRcv
  SCSnd :: SConnType CSnd
  SCDuplex :: SConnType CDuplex
  SCContact :: SConnType CContact

connType :: SConnType c -> ConnType
connType SCNew = CNew
connType SCRcv = CRcv
connType SCSnd = CSnd
connType SCDuplex = CDuplex
connType SCContact = CContact

deriving instance Show (SConnType d)

instance TestEquality SConnType where
  testEquality SCRcv SCRcv = Just Refl
  testEquality SCSnd SCSnd = Just Refl
  testEquality SCDuplex SCDuplex = Just Refl
  testEquality SCContact SCContact = Just Refl
  testEquality _ _ = Nothing

data SomeConn' rq sq = forall d. SomeConn (SConnType d) (Connection' d rq sq)

deriving instance (Show rq, Show sq) => Show (SomeConn' rq sq)

type SomeConn = SomeConn' RcvQueue SndQueue

type SomeConnSub = SomeConn' RcvQueueSub SndQueue

data ConnData = ConnData
  { connId :: ConnId,
    userId :: UserId,
    connAgentVersion :: VersionSMPA,
    enableNtfs :: Bool,
    lastExternalSndId :: PrevExternalSndId,
    deleted :: Bool,
    ratchetSyncState :: RatchetSyncState,
    pqSupport :: PQSupport
  }
  deriving (Eq, Show)

type NoticeId = Int64

ratchetSyncAllowed :: ConnData -> Bool
ratchetSyncAllowed ConnData {ratchetSyncState, connAgentVersion} =
  connAgentVersion >= ratchetSyncSMPAgentVersion && (ratchetSyncState `elem` ([RSAllowed, RSRequired] :: [RatchetSyncState]))

ratchetSyncSendProhibited :: ConnData -> Bool
ratchetSyncSendProhibited ConnData {ratchetSyncState} =
  ratchetSyncState `elem` ([RSRequired, RSStarted, RSAgreed] :: [RatchetSyncState])

data PendingCommand = PendingCommand
  { cmdId :: AsyncCmdId,
    corrId :: ACorrId,
    userId :: UserId,
    connId :: ConnId,
    command :: AgentCommand
  }

data AgentCmdType = ACClient | ACInternal

instance StrEncoding AgentCmdType where
  strEncode = \case
    ACClient -> "CLIENT"
    ACInternal -> "INTERNAL"
  strP =
    A.takeTill (== ' ') >>= \case
      "CLIENT" -> pure ACClient
      "INTERNAL" -> pure ACInternal
      _ -> fail "bad AgentCmdType"

data AgentCommand
  = AClientCommand ACommand
  | AInternalCommand InternalCommand

instance StrEncoding AgentCommand where
  strEncode = \case
    AClientCommand cmd -> strEncode (ACClient, Str $ serializeCommand cmd)
    AInternalCommand cmd -> strEncode (ACInternal, cmd)
  strP =
    strP_ >>= \case
      ACClient -> AClientCommand <$> dbCommandP
      ACInternal -> AInternalCommand <$> strP

data AgentCommandTag
  = AClientCommandTag ACommandTag
  | AInternalCommandTag InternalCommandTag
  deriving (Show)

instance StrEncoding AgentCommandTag where
  strEncode = \case
    AClientCommandTag t -> strEncode (ACClient, t)
    AInternalCommandTag t -> strEncode (ACInternal, t)
  strP =
    strP_ >>= \case
      ACClient -> AClientCommandTag <$> strP
      ACInternal -> AInternalCommandTag <$> strP

data InternalCommand
  = ICAck SMP.RecipientId MsgId
  | ICAckDel SMP.RecipientId MsgId InternalId
  | ICAllowSecure SMP.RecipientId (Maybe SMP.SndPublicAuthKey)
  | ICDuplexSecure SMP.RecipientId SMP.SndPublicAuthKey
  | ICDeleteConn
  | ICDeleteRcvQueue SMP.RecipientId
  | ICQSecure SMP.RecipientId SMP.SndPublicAuthKey
  | ICQDelete SMP.RecipientId

data InternalCommandTag
  = ICAck_
  | ICAckDel_
  | ICAllowSecure_
  | ICDuplexSecure_
  | ICDeleteConn_
  | ICDeleteRcvQueue_
  | ICQSecure_
  | ICQDelete_
  deriving (Show)

instance StrEncoding InternalCommand where
  strEncode = \case
    ICAck rId srvMsgId -> strEncode (ICAck_, rId, srvMsgId)
    ICAckDel rId srvMsgId mId -> strEncode (ICAckDel_, rId, srvMsgId, mId)
    ICAllowSecure rId sndKey -> strEncode (ICAllowSecure_, rId, sndKey)
    ICDuplexSecure rId sndKey -> strEncode (ICDuplexSecure_, rId, sndKey)
    ICDeleteConn -> strEncode ICDeleteConn_
    ICDeleteRcvQueue rId -> strEncode (ICDeleteRcvQueue_, rId)
    ICQSecure rId senderKey -> strEncode (ICQSecure_, rId, senderKey)
    ICQDelete rId -> strEncode (ICQDelete_, rId)
  strP =
    strP >>= \case
      ICAck_ -> ICAck <$> _strP <*> _strP
      ICAckDel_ -> ICAckDel <$> _strP <*> _strP <*> _strP
      ICAllowSecure_ -> ICAllowSecure <$> _strP <*> _strP
      ICDuplexSecure_ -> ICDuplexSecure <$> _strP <*> _strP
      ICDeleteConn_ -> pure ICDeleteConn
      ICDeleteRcvQueue_ -> ICDeleteRcvQueue <$> _strP
      ICQSecure_ -> ICQSecure <$> _strP <*> _strP
      ICQDelete_ -> ICQDelete <$> _strP

instance StrEncoding InternalCommandTag where
  strEncode = \case
    ICAck_ -> "ACK"
    ICAckDel_ -> "ACK_DEL"
    ICAllowSecure_ -> "ALLOW_SECURE"
    ICDuplexSecure_ -> "DUPLEX_SECURE"
    ICDeleteConn_ -> "DELETE_CONN"
    ICDeleteRcvQueue_ -> "DELETE_RCV_QUEUE"
    ICQSecure_ -> "QSECURE"
    ICQDelete_ -> "QDELETE"
  strP =
    A.takeTill (== ' ') >>= \case
      "ACK" -> pure ICAck_
      "ACK_DEL" -> pure ICAckDel_
      "ALLOW_SECURE" -> pure ICAllowSecure_
      "DUPLEX_SECURE" -> pure ICDuplexSecure_
      "DELETE_CONN" -> pure ICDeleteConn_
      "DELETE_RCV_QUEUE" -> pure ICDeleteRcvQueue_
      "QSECURE" -> pure ICQSecure_
      "QDELETE" -> pure ICQDelete_
      _ -> fail "bad InternalCommandTag"

agentCommandTag :: AgentCommand -> AgentCommandTag
agentCommandTag = \case
  AClientCommand cmd -> AClientCommandTag $ aCommandTag cmd
  AInternalCommand cmd -> AInternalCommandTag $ internalCmdTag cmd

internalCmdTag :: InternalCommand -> InternalCommandTag
internalCmdTag = \case
  ICAck {} -> ICAck_
  ICAckDel {} -> ICAckDel_
  ICAllowSecure {} -> ICAllowSecure_
  ICDuplexSecure {} -> ICDuplexSecure_
  ICDeleteConn -> ICDeleteConn_
  ICDeleteRcvQueue {} -> ICDeleteRcvQueue_
  ICQSecure {} -> ICQSecure_
  ICQDelete _ -> ICQDelete_

data NewConfirmation = NewConfirmation
  { connId :: ConnId,
    senderConf :: SMPConfirmation,
    ratchetState :: RatchetX448
  }

data AcceptedConfirmation = AcceptedConfirmation
  { confirmationId :: ConfirmationId,
    connId :: ConnId,
    senderConf :: SMPConfirmation,
    ratchetState :: RatchetX448,
    ownConnInfo :: ConnInfo
  }

data NewInvitation = NewInvitation
  { contactConnId :: ConnId,
    connReq :: ConnectionRequestUri 'CMInvitation,
    recipientConnInfo :: ConnInfo
  }

data Invitation = Invitation
  { invitationId :: InvitationId,
    contactConnId_ :: Maybe ConnId,
    connReq :: ConnectionRequestUri 'CMInvitation,
    recipientConnInfo :: ConnInfo,
    ownConnInfo :: Maybe ConnInfo,
    accepted :: Bool
  }

type PrevExternalSndId = Int64

type PrevRcvMsgHash = MsgHash

type PrevSndMsgHash = MsgHash

data RcvMsgData = RcvMsgData
  { msgMeta :: MsgMeta,
    msgType :: AgentMessageType,
    msgFlags :: MsgFlags,
    msgBody :: MsgBody,
    internalRcvId :: InternalRcvId,
    internalHash :: MsgHash,
    externalPrevSndHash :: MsgHash,
    encryptedMsgHash :: MsgHash
  }

data RcvMsg = RcvMsg
  { internalId :: InternalId,
    msgMeta :: MsgMeta,
    msgType :: AgentMessageType,
    msgBody :: MsgBody,
    internalHash :: MsgHash,
    msgReceipt :: Maybe MsgReceipt,
    userAck :: Bool
  }

data SndMsgData = SndMsgData
  { internalId :: InternalId,
    internalSndId :: InternalSndId,
    internalTs :: InternalTs,
    msgType :: AgentMessageType,
    msgFlags :: MsgFlags,
    msgBody :: MsgBody,
    pqEncryption :: PQEncryption,
    internalHash :: MsgHash,
    prevMsgHash :: MsgHash,
    sndMsgPrepData_ :: Maybe SndMsgPrepData
  }

data SndMsgPrepData = SndMsgPrepData
  { encryptKey :: MsgEncryptKeyX448,
    paddedLen :: Int,
    sndMsgBodyId :: Int64
  }
  deriving (Show)

data SndMsg = SndMsg
  { internalId :: InternalId,
    internalSndId :: InternalSndId,
    msgType :: AgentMessageType,
    internalHash :: MsgHash,
    msgReceipt :: Maybe MsgReceipt
  }

data PendingMsgData = PendingMsgData
  { msgId :: InternalId,
    msgType :: AgentMessageType,
    msgFlags :: MsgFlags,
    msgBody :: MsgBody,
    pqEncryption :: PQEncryption,
    msgRetryState :: Maybe RI2State,
    internalTs :: InternalTs,
    internalSndId :: InternalSndId,
    prevMsgHash :: PrevSndMsgHash,
    pendingMsgPrepData_ :: Maybe PendingMsgPrepData
  }
  deriving (Show)

data PendingMsgPrepData = PendingMsgPrepData
  { encryptKey :: MsgEncryptKeyX448,
    paddedLen :: Int,
    sndMsgBody :: AMessage
  }
  deriving (Show)

newtype InternalRcvId = InternalRcvId {unRcvId :: Int64} deriving (Eq, Show)

type ExternalSndId = Int64

type ExternalSndTs = UTCTime

type BrokerId = MsgId

type BrokerTs = UTCTime

newtype InternalSndId = InternalSndId {unSndId :: Int64} deriving (Eq, Show)

data MsgBase = MsgBase
  { connId :: ConnId,
    internalId :: InternalId,
    internalTs :: InternalTs,
    msgBody :: MsgBody,
    internalHash :: MsgHash
  }
  deriving (Eq, Show)

newtype InternalId = InternalId {unId :: Int64} deriving (Eq, Show)

instance StrEncoding InternalId where
  strEncode = strEncode . unId
  strP = InternalId <$> strP

type InternalTs = UTCTime

type AsyncCmdId = Int64

data StoreError
  =
    SEInternal ByteString
  |
    SEDatabaseBusy ByteString
  |
    SEUniqueID
  |
    SEUserNotFound
  |
    SEConnNotFound
  |
    SEServerNotFound
  |
    SEConnDuplicate
  |
    SESndQueueExists
  |
    SEBadConnType String ConnType
  |
    SEConfirmationNotFound
  |
    SEInvitationNotFound String InvitationId
  |
    SEMsgNotFound String
  |
    SECmdNotFound
  |
    SEBadQueueStatus
  |
    SERatchetNotFound
  |
    SEX3dhKeysNotFound
  |
    SEAgentError AgentErrorType
  |
    SEXFTPServerNotFound
  |
    SEFileNotFound
  |
    SEDeletedSndChunkReplicaNotFound
  |
    SEWorkItemError {errContext :: String}
  |
    SEServersStatsNotFound
  deriving (Eq, Show, Exception)

instance AnyError StoreError where
  fromSomeException e = SEInternal $ case fromException e of
    Just (e' :: SQLError) -> bshow e'
    Nothing -> bshow e

class (Show e, AnyError e) => AnyStoreError e where
  isWorkItemError :: e -> Bool
  mkWorkItemError :: String -> e

instance AnyStoreError StoreError where
  isWorkItemError = \case
    SEWorkItemError {} -> True
    _ -> False
  mkWorkItemError errContext = SEWorkItemError {errContext}
