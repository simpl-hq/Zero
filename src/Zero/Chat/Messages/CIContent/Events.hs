{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE TemplateHaskell #-}

module Zero.Chat.Messages.CIContent.Events where

import Data.Aeson (FromJSON (..), ToJSON (..))
import qualified Data.Aeson.TH as J
import Zero.Chat.Types
import Zero.Chat.Types.Shared
import Zero.Messaging.Agent.Protocol (RatchetSyncState (..), SwitchPhase (..))
import Zero.Messaging.Parsers (dropPrefix, singleFieldJSON, sumTypeJSON)
import Zero.Messaging.Crypto.Ratchet (PQEncryption)

data RcvGroupEvent
  = RGEMemberAdded {groupMemberId :: GroupMemberId, profile :: Profile}
  | RGEMemberConnected
  | RGEMemberAccepted {groupMemberId :: GroupMemberId, profile :: Profile}
  | RGEUserAccepted
  | RGEMemberLeft
  | RGEMemberRole {groupMemberId :: GroupMemberId, profile :: Profile, role :: GroupMemberRole}
  | RGEMemberBlocked {groupMemberId :: GroupMemberId, profile :: Profile, blocked :: Bool}
  | RGEUserRole {role :: GroupMemberRole}
  | RGEMemberDeleted {groupMemberId :: GroupMemberId, profile :: Profile}
  | RGEUserDeleted
  | RGEGroupDeleted
  | RGEGroupUpdated {groupProfile :: GroupProfile}
  | RGEInvitedViaGroupLink
  | RGEMemberCreatedContact
  | RGEMemberProfileUpdated {fromProfile :: Profile, toProfile :: Profile}
  | RGENewMemberPendingReview
  | RGEMsgBadSignature
  deriving (Show)

data SndGroupEvent
  = SGEMemberRole {groupMemberId :: GroupMemberId, profile :: Profile, role :: GroupMemberRole}
  | SGEMemberBlocked {groupMemberId :: GroupMemberId, profile :: Profile, blocked :: Bool}
  | SGEUserRole {role :: GroupMemberRole}
  | SGEMemberDeleted {groupMemberId :: GroupMemberId, profile :: Profile}
  | SGEUserLeft
  | SGEGroupUpdated {groupProfile :: GroupProfile}
  | SGEMemberAccepted {groupMemberId :: GroupMemberId, profile :: Profile}
  | SGEUserPendingReview
  deriving (Show)

data RcvConnEvent
  = RCESwitchQueue {phase :: SwitchPhase}
  | RCERatchetSync {syncStatus :: RatchetSyncState}
  | RCEVerificationCodeReset
  | RCEPqEnabled {enabled :: PQEncryption}
  deriving (Show)

data SndConnEvent
  = SCESwitchQueue {phase :: SwitchPhase, member :: Maybe GroupMemberRef}
  | SCERatchetSync {syncStatus :: RatchetSyncState, member :: Maybe GroupMemberRef}
  | SCEPqEnabled {enabled :: PQEncryption}
  deriving (Show)

data RcvDirectEvent
  = RDEContactDeleted
  | RDEProfileUpdated {fromProfile :: Profile, toProfile :: Profile}
  | RDEGroupInvLinkReceived {groupProfile :: GroupProfile}
  deriving (Show)

$(J.deriveJSON (sumTypeJSON $ dropPrefix "RGE") ''RcvGroupEvent)

newtype DBRcvGroupEvent = RGE RcvGroupEvent

instance FromJSON DBRcvGroupEvent where
  parseJSON v = RGE <$> $(J.mkParseJSON (singleFieldJSON $ dropPrefix "RGE") ''RcvGroupEvent) v

instance ToJSON DBRcvGroupEvent where
  toJSON (RGE v) = $(J.mkToJSON (singleFieldJSON $ dropPrefix "RGE") ''RcvGroupEvent) v
  toEncoding (RGE v) = $(J.mkToEncoding (singleFieldJSON $ dropPrefix "RGE") ''RcvGroupEvent) v

$(J.deriveJSON (sumTypeJSON $ dropPrefix "SGE") ''SndGroupEvent)

newtype DBSndGroupEvent = SGE SndGroupEvent

instance FromJSON DBSndGroupEvent where
  parseJSON v = SGE <$> $(J.mkParseJSON (singleFieldJSON $ dropPrefix "SGE") ''SndGroupEvent) v

instance ToJSON DBSndGroupEvent where
  toJSON (SGE v) = $(J.mkToJSON (singleFieldJSON $ dropPrefix "SGE") ''SndGroupEvent) v
  toEncoding (SGE v) = $(J.mkToEncoding (singleFieldJSON $ dropPrefix "SGE") ''SndGroupEvent) v

$(J.deriveJSON (sumTypeJSON $ dropPrefix "RCE") ''RcvConnEvent)

newtype DBRcvConnEvent = RCE RcvConnEvent

instance FromJSON DBRcvConnEvent where
  parseJSON v = RCE <$> $(J.mkParseJSON (singleFieldJSON $ dropPrefix "RCE") ''RcvConnEvent) v

instance ToJSON DBRcvConnEvent where
  toJSON (RCE v) = $(J.mkToJSON (singleFieldJSON $ dropPrefix "RCE") ''RcvConnEvent) v
  toEncoding (RCE v) = $(J.mkToEncoding (singleFieldJSON $ dropPrefix "RCE") ''RcvConnEvent) v

$(J.deriveJSON (sumTypeJSON $ dropPrefix "SCE") ''SndConnEvent)

newtype DBSndConnEvent = SCE SndConnEvent

instance FromJSON DBSndConnEvent where
  parseJSON v = SCE <$> $(J.mkParseJSON (singleFieldJSON $ dropPrefix "SCE") ''SndConnEvent) v

instance ToJSON DBSndConnEvent where
  toJSON (SCE v) = $(J.mkToJSON (singleFieldJSON $ dropPrefix "SCE") ''SndConnEvent) v
  toEncoding (SCE v) = $(J.mkToEncoding (singleFieldJSON $ dropPrefix "SCE") ''SndConnEvent) v

$(J.deriveJSON (sumTypeJSON $ dropPrefix "RDE") ''RcvDirectEvent)

newtype DBRcvDirectEvent = RDE RcvDirectEvent

instance FromJSON DBRcvDirectEvent where
  parseJSON v = RDE <$> $(J.mkParseJSON (singleFieldJSON $ dropPrefix "RDE") ''RcvDirectEvent) v

instance ToJSON DBRcvDirectEvent where
  toJSON (RDE v) = $(J.mkToJSON (singleFieldJSON $ dropPrefix "RDE") ''RcvDirectEvent) v
  toEncoding (RDE v) = $(J.mkToEncoding (singleFieldJSON $ dropPrefix "RDE") ''RcvDirectEvent) v
