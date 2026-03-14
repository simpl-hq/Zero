{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Zero.Chat.Delivery where

import Data.ByteString.Char8 (ByteString)
import Data.Int (Int64)
import Data.Maybe (fromMaybe)
import Data.Time.Clock (UTCTime)
import Zero.Chat.Messages (GroupChatScopeInfo (..), MessageId, ShowGroupAsSender)
import Zero.Chat.Options.DB (FromField (..), ToField (..))
import Zero.Chat.Protocol
import Zero.Chat.Types
import Zero.Chat.Types.Shared
import Zero.Messaging.Agent.Store.DB (fromTextField_)
import Zero.Messaging.Encoding.String

type DeliveryWorkerKey = (GroupId, DeliveryWorkerScope)

data DeliveryWorkerScope
  = DWSGroup
  | DWSMemberSupport
  deriving (Eq, Ord, Show)

instance FromField DeliveryWorkerScope where fromField = fromTextField_ textDecode

instance ToField DeliveryWorkerScope where toField = toField . textEncode

instance TextEncoding DeliveryWorkerScope where
  textDecode = \case
    "group" -> Just DWSGroup
    "member_support" -> Just DWSMemberSupport
    _ -> Nothing
  textEncode = \case
    DWSGroup -> "group"
    DWSMemberSupport -> "member_support"

data DeliveryTaskContext = DeliveryTaskContext
  { jobScope :: DeliveryJobScope,
    sentAsGroup :: ShowGroupAsSender
  }
  deriving (Show)

data DeliveryJobScope
  = DJSGroup {jobSpec :: DeliveryJobSpec}
  | DJSMemberSupport {supportGMId :: GroupMemberId}
  deriving (Show)

data DeliveryJobSpec
  = DJDeliveryJob {includePending :: Bool}
  | DJRelayRemoved
  deriving (Show)

data DeliveryJobSpecTag
  = DJSTDeliveryJob
  | DJSTRelayRemoved
  deriving (Show)

instance FromField DeliveryJobSpecTag where fromField = fromTextField_ textDecode

instance ToField DeliveryJobSpecTag where toField = toField . textEncode

instance TextEncoding DeliveryJobSpecTag where
  textDecode = \case
    "delivery_job" -> Just DJSTDeliveryJob
    "relay_removed" -> Just DJSTRelayRemoved
    _ -> Nothing
  textEncode = \case
    DJSTDeliveryJob -> "delivery_job"
    DJSTRelayRemoved -> "relay_removed"

toWorkerScope :: DeliveryJobScope -> DeliveryWorkerScope
toWorkerScope = \case
  DJSGroup _ -> DWSGroup
  DJSMemberSupport _ -> DWSMemberSupport

isRelayRemoved :: DeliveryJobScope -> Bool
isRelayRemoved = \case
  DJSGroup {jobSpec} -> case jobSpec of
    DJRelayRemoved -> True
    _ -> False
  _ -> False

jobScopeImpliedSpec :: DeliveryJobScope -> DeliveryJobSpec
jobScopeImpliedSpec = \case
  DJSGroup {jobSpec} -> jobSpec
  DJSMemberSupport {} -> DJDeliveryJob {includePending = False}

jobSpecImpliedPending :: DeliveryJobSpec -> Bool
jobSpecImpliedPending = \case
  DJDeliveryJob {includePending} -> includePending
  DJRelayRemoved -> True

infoToDeliveryContext :: GroupInfo -> Maybe GroupChatScopeInfo -> ShowGroupAsSender -> DeliveryTaskContext
infoToDeliveryContext GroupInfo {membership} scopeInfo sentAsGroup = DeliveryTaskContext {jobScope, sentAsGroup}
  where
    jobScope = case scopeInfo of
      Nothing -> DJSGroup {jobSpec = DJDeliveryJob {includePending = False}}
      Just GCSIMemberSupport {groupMember_} ->
        let supportGMId = groupMemberId' $ fromMaybe membership groupMember_
         in DJSMemberSupport {supportGMId}

memberEventDeliveryScope :: GroupMember -> Maybe DeliveryJobScope
memberEventDeliveryScope m@GroupMember {memberRole, memberStatus}
  | memberStatus == GSMemPendingApproval = Nothing
  | memberStatus == GSMemPendingReview = Just $ DJSMemberSupport {supportGMId = groupMemberId' m}
  | memberRole >= GRModerator = Just DJSGroup {jobSpec = DJDeliveryJob {includePending = True}}
  | otherwise = Just DJSGroup {jobSpec = DJDeliveryJob {includePending = False}}

data NewMessageDeliveryTask = NewMessageDeliveryTask
  { messageId :: MessageId,
    taskContext :: DeliveryTaskContext
  }
  deriving (Show)

data MessageDeliveryTask = MessageDeliveryTask
  { taskId :: Int64,
    jobScope :: DeliveryJobScope,
    senderGMId :: GroupMemberId,
    fwdSender :: FwdSender,
    brokerTs :: UTCTime,
    verifiedMsg :: VerifiedMsg 'Json
  }

deliveryTaskId :: MessageDeliveryTask -> Int64
deliveryTaskId = taskId

data DeliveryTaskStatus
  = DTSNew
  | DTSProcessed
  | DTSError
  deriving (Show)

instance FromField DeliveryTaskStatus where fromField = fromTextField_ textDecode

instance ToField DeliveryTaskStatus where toField = toField . textEncode

instance TextEncoding DeliveryTaskStatus where
  textDecode = \case
    "new" -> Just DTSNew
    "processed" -> Just DTSProcessed
    "error" -> Just DTSError
    _ -> Nothing
  textEncode = \case
    DTSNew -> "new"
    DTSProcessed -> "processed"
    DTSError -> "error"

data MessageDeliveryJob = MessageDeliveryJob
  { jobId :: Int64,
    jobScope :: DeliveryJobScope,
    senderGMIds :: [GroupMemberId],
    body :: ByteString,
    cursorGMId_ :: Maybe GroupMemberId
  }
  deriving (Show)

deliveryJobId :: MessageDeliveryJob -> Int64
deliveryJobId = jobId

data DeliveryJobStatus
  = DJSPending
  | DJSComplete
  | DJSError
  deriving (Show)

instance FromField DeliveryJobStatus where fromField = fromTextField_ textDecode

instance ToField DeliveryJobStatus where toField = toField . textEncode

instance TextEncoding DeliveryJobStatus where
  textDecode = \case
    "pending" -> Just DJSPending
    "complete" -> Just DJSComplete
    "error" -> Just DJSError
    _ -> Nothing
  textEncode = \case
    DJSPending -> "pending"
    DJSComplete -> "complete"
    DJSError -> "error"

