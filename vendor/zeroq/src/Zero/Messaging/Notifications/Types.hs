{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Zero.Messaging.Notifications.Types
  ( NtfTknAction (..),
    NtfToken (..),
    NtfSubAction (..),
    NtfActionTs,
    NtfSubNTFAction (..),
    NtfSubSMPAction (..),
    NtfAgentSubStatus (..),
    NtfSubscription (..),
    newNtfToken,
    isDeleteNtfSubAction,
    newNtfSubscription,
  ) where

import qualified Data.Attoparsec.ByteString.Char8 as A
import Data.Text.Encoding (decodeLatin1, encodeUtf8)
import Data.Time (UTCTime)
import Zero.Messaging.Agent.Protocol (ConnId, NotificationsMode (..), UserId)
import Zero.Messaging.Agent.Store.DB (Binary (..), FromField (..), ToField (..), blobFieldDecoder, fromTextField_)
import qualified Zero.Messaging.Crypto as C
import Zero.Messaging.Encoding
import Zero.Messaging.Encoding.String
import Zero.Messaging.Notifications.Protocol
import Zero.Messaging.Protocol (NotifierId, NtfServer, SMPServer)
import Zero.Messaging.Util (eitherToMaybe)

data NtfTknAction
  = NTARegister
  | NTAVerify NtfRegCode
  | NTACheck
  | NTADelete
  deriving (Show)

instance Encoding NtfTknAction where
  smpEncode = \case
    NTARegister -> "R"
    NTAVerify code -> smpEncode ('V', code)
    NTACheck -> "C"
    NTADelete -> "D"
  smpP =
    A.anyChar >>= \case
      'R' -> pure NTARegister
      'V' -> NTAVerify <$> smpP
      'C' -> pure NTACheck
      'D' -> pure NTADelete
      _ -> fail "bad NtfTknAction"

instance FromField NtfTknAction where fromField = blobFieldDecoder smpDecode

instance ToField NtfTknAction where toField = toField . Binary . smpEncode

data NtfToken = NtfToken
  { deviceToken :: DeviceToken,
    ntfServer :: NtfServer,
    ntfTokenId :: Maybe NtfTokenId,

    ntfPubKey :: C.APublicAuthKey,
    ntfPrivKey :: C.APrivateAuthKey,
    ntfDhKeys :: C.KeyPairX25519,
    ntfDhSecret :: Maybe C.DhSecretX25519,
    ntfTknStatus :: NtfTknStatus,
    ntfTknAction :: Maybe NtfTknAction,
    ntfMode :: NotificationsMode
  }
  deriving (Show)

newNtfToken :: DeviceToken -> NtfServer -> C.AAuthKeyPair -> C.KeyPairX25519 -> NotificationsMode -> NtfToken
newNtfToken deviceToken ntfServer (ntfPubKey, ntfPrivKey) ntfDhKeys ntfMode =
  NtfToken
    { deviceToken,
      ntfServer,
      ntfTokenId = Nothing,
      ntfPubKey,
      ntfPrivKey,
      ntfDhKeys,
      ntfDhSecret = Nothing,
      ntfTknStatus = NTNew,
      ntfTknAction = Just NTARegister,
      ntfMode
    }

data NtfSubAction = NSANtf NtfSubNTFAction | NSASMP NtfSubSMPAction
  deriving (Show)

isDeleteNtfSubAction :: NtfSubAction -> Bool
isDeleteNtfSubAction = \case
  NSANtf a -> case a of
    NSACreate -> False
    NSACheck -> False
    NSADelete -> True
    NSARotate -> True
  NSASMP a -> case a of
    NSASmpKey -> False
    NSASmpDelete -> True

type NtfActionTs = UTCTime

data NtfSubNTFAction
  = NSACreate
  | NSACheck
  | NSADelete
  | NSARotate
  deriving (Show)

instance TextEncoding NtfSubNTFAction where
  textEncode = \case
    NSACreate -> "N"
    NSACheck -> "C"
    NSADelete -> "D"
    NSARotate -> "R"
  textDecode = \case
    "N" -> Just NSACreate
    "C" -> Just NSACheck
    "D" -> Just NSADelete
    "R" -> Just NSARotate
    _ -> Nothing

instance FromField NtfSubNTFAction where fromField = fromTextField_ textDecode

instance ToField NtfSubNTFAction where toField = toField . textEncode

data NtfSubSMPAction
  = NSASmpKey
  | NSASmpDelete
  deriving (Show)

instance TextEncoding NtfSubSMPAction where
  textEncode = \case
    NSASmpKey -> "K"
    NSASmpDelete -> "D"
  textDecode = \case
    "K" -> Just NSASmpKey
    "D" -> Just NSASmpDelete
    _ -> Nothing

instance FromField NtfSubSMPAction where fromField = fromTextField_ textDecode

instance ToField NtfSubSMPAction where toField = toField . textEncode

data NtfAgentSubStatus
  =
    NASNew
  |
    NASKey
  |
    NASCreated NtfSubStatus
  |
    NASOff
  |
    NASDeleted
  deriving (Eq, Show)

instance Encoding NtfAgentSubStatus where
  smpEncode = \case
    NASNew -> "NEW"
    NASKey -> "KEY"
    NASCreated status -> "CREATED " <> smpEncode status
    NASOff -> "OFF"
    NASDeleted -> "DELETED"
  smpP =
    A.takeTill (== ' ') >>= \case
      "NEW" -> pure NASNew
      "KEY" -> pure NASKey
      "CREATED" -> do
        _ <- A.space
        NASCreated <$> smpP
      "OFF" -> pure NASOff
      "DELETED" -> pure NASDeleted
      _ -> fail "bad NtfAgentSubStatus"

instance FromField NtfAgentSubStatus where fromField = fromTextField_ $ eitherToMaybe . smpDecode . encodeUtf8

instance ToField NtfAgentSubStatus where toField = toField . decodeLatin1 . smpEncode

data NtfSubscription = NtfSubscription
  { userId :: UserId,
    connId :: ConnId,
    smpServer :: SMPServer,
    ntfQueueId :: Maybe NotifierId,
    ntfServer :: NtfServer,
    ntfSubId :: Maybe NtfSubscriptionId,
    ntfSubStatus :: NtfAgentSubStatus
  }
  deriving (Show)

newNtfSubscription :: UserId -> ConnId -> SMPServer -> Maybe NotifierId -> NtfServer -> NtfAgentSubStatus -> NtfSubscription
newNtfSubscription userId connId smpServer ntfQueueId ntfServer ntfSubStatus =
  NtfSubscription
    { userId,
      connId,
      smpServer,
      ntfQueueId,
      ntfServer,
      ntfSubId = Nothing,
      ntfSubStatus
    }
