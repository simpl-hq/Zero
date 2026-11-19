{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -fno-warn-ambiguous-fields #-}

module Zero.Chat.Library.Internal where

import qualified Codec.Compression.Zstd as Z1
import Control.Applicative ((<|>))
import Control.Concurrent.STM (retry)
import Control.Logger.Simple
import Control.Monad
import Control.Monad.Except
import Control.Monad.IO.Unlift
import Control.Monad.Reader
import Crypto.Random (ChaChaDRG)
import qualified Data.Aeson as J
import Data.Bifunctor (first)
import Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy.Char8 as LB
import Data.Char (isDigit)
import Data.Containers.ListUtils (nubOrd)
import Data.Either (partitionEithers, rights)
import Data.Fixed (div')
import Data.Foldable (foldr')
import Data.Functor (($>))
import Data.Functor.Identity
import Data.Int (Int64)
import Data.List (find, foldl', mapAccumL, partition)
import Data.List.NonEmpty (NonEmpty (..), (<|))
import qualified Data.List.NonEmpty as L
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing, mapMaybe)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import Data.Time (addUTCTime)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), diffUTCTime, getCurrentTime, nominalDiffTimeToSeconds, secondsToDiffTime)
import Zero.Chat.Badges (BadgeCredential (..), ProofPresHeader (..), BadgeProof (..), BadgeStatus (..), LocalBadge (..), badgeProof, mkBadgeStatus, verifyBadge)
import Zero.Chat.Names (ZeroDomainClaim (..), claimDomain)
import Zero.Chat.Call
import Zero.Chat.Controller
import Zero.Chat.Files
import Zero.Chat.Markdown
import Zero.Chat.Messages
import Zero.Chat.Messages.Batch (BatchMode (..), MsgBatch (..), batchElements, batchMessages, encodeBatchElement, encodeBinaryBatch, encodeFwdElement)
import Zero.Chat.Messages.CIContent
import Zero.Chat.Messages.CIContent.Events
import Zero.Chat.Operators
import Zero.Chat.ProfileGenerator (generateRandomProfile)
import Zero.Chat.Protocol
import Zero.Chat.Store
import Zero.Chat.Store.ContactRequest
import Zero.Chat.Store.Direct
import Zero.Chat.Store.Files
import Zero.Chat.Store.Groups
import Zero.Chat.Store.Messages
import Zero.Chat.Store.Profiles
import Zero.Chat.Store.Shared
import Zero.Chat.Types
import Zero.Chat.Types.MemberRelations
import Zero.Chat.Types.Preferences
import Zero.Chat.Types.Shared
import Zero.Chat.Util (encryptFile, shuffle)
import Zero.FileTransfer.Description (FileDescriptionURI (..), ValidFileDescription)
import qualified Zero.FileTransfer.Description as FD
import qualified Zero.Messaging.Crypto.Lazy as LC
import Zero.FileTransfer.Protocol (FileParty (..), FilePartyI)
import Zero.FileTransfer.Types (RcvFileId, SndFileId)
import Zero.Messaging.Agent
import Zero.Messaging.Agent.Client (getFastNetworkConfig, ipAddressProtected, withLockMap)
import Zero.Messaging.Agent.Env.SQLite (AgentConfig (..), ServerCfg (..))
import Zero.Messaging.Agent.Lock (withLock)
import Zero.Messaging.Agent.Protocol
import qualified Zero.Messaging.Agent.Protocol as AP (AgentErrorType (..))
import qualified Zero.Messaging.Agent.Store.DB as DB
import Zero.Messaging.Client (NetworkConfig (..), NetworkRequestMode (..))
import Zero.Messaging.Compression (compressionLevel, limitDecompress')
import qualified Zero.Messaging.Crypto as C
import Zero.Messaging.Crypto.File (CryptoFile (..), CryptoFileArgs (..))
import qualified Zero.Messaging.Crypto.File as CF
import Zero.Messaging.Crypto.Ratchet (PQEncryption (..), PQSupport (..), pattern IKPQOff, pattern PQEncOff, pattern PQEncOn, pattern PQSupportOff, pattern PQSupportOn)
import qualified Zero.Messaging.Crypto.Ratchet as CR
import Zero.Messaging.Encoding (smpEncode)
import Zero.Messaging.Encoding.String
import Zero.Messaging.Protocol (MsgBody, MsgFlags (..), ProtoServerWithAuth (..), ProtocolServer, ProtocolTypeI (..), SProtocolType (..), SubscriptionMode (..), UserProtocol, XFTPServer)
import qualified Zero.Messaging.Protocol as SMP
import qualified Zero.Messaging.TMap as TM
import Zero.Messaging.Util
import Zero.Messaging.Version
import System.FilePath (takeFileName, (</>))
import System.IO (Handle, IOMode (..), hFlush)
import UnliftIO.Concurrent (forkFinally, mkWeakThreadId)
import UnliftIO.Directory
import UnliftIO.IO (hClose, openFile)
import UnliftIO.STM

maxMsgReactions :: Int
maxMsgReactions = 3

maxRcvMentions :: Int
maxRcvMentions = 5

maxSndMentions :: Int
maxSndMentions = 3

withChatLock :: Text -> CM a -> CM a
withChatLock name action = asks chatLock >>= \l -> withLock l name action

withEntityLock :: Text -> ChatLockEntity -> CM a -> CM a
withEntityLock name entity action = do
  chatLock <- asks chatLock
  ls <- asks entityLocks
  atomically $ unlessM (isEmptyTMVar chatLock) retry
  withLockMap ls entity name action

withInvitationLock :: Text -> ByteString -> CM a -> CM a
withInvitationLock name = withEntityLock name . CLInvitation
{-# INLINE withInvitationLock #-}

withConnectionLock :: Text -> Int64 -> CM a -> CM a
withConnectionLock name = withEntityLock name . CLConnection
{-# INLINE withConnectionLock #-}

withContactLock :: Text -> ContactId -> CM a -> CM a
withContactLock name = withEntityLock name . CLContact
{-# INLINE withContactLock #-}

withGroupLock :: Text -> GroupId -> CM a -> CM a
withGroupLock name = withEntityLock name . CLGroup
{-# INLINE withGroupLock #-}

withUserContactLock :: Text -> Int64 -> CM a -> CM a
withUserContactLock name = withEntityLock name . CLUserContact
{-# INLINE withUserContactLock #-}

withContactRequestLock :: Text -> Int64 -> CM a -> CM a
withContactRequestLock name = withEntityLock name . CLContactRequest
{-# INLINE withContactRequestLock #-}

withFileLock :: Text -> Int64 -> CM a -> CM a
withFileLock name = withEntityLock name . CLFile
{-# INLINE withFileLock #-}

useServerCfgs :: forall p. UserProtocol p => SProtocolType p -> RandomAgentServers -> [(Text, ServerOperator)] -> [UserServer p] -> NonEmpty (ServerCfg p)
useServerCfgs p RandomAgentServers {smpServers, xftpServers} opDomains =
  fromMaybe (rndAgentServers p) . L.nonEmpty . agentServerCfgs p opDomains
  where
    rndAgentServers :: SProtocolType p -> NonEmpty (ServerCfg p)
    rndAgentServers = \case
      SPSMP -> smpServers
      SPXFTP -> xftpServers

contactCITimed :: Contact -> CM (Maybe CITimed)
contactCITimed ct = sndContactCITimed False ct Nothing

sndContactCITimed :: Bool -> Contact -> Maybe Int -> CM (Maybe CITimed)
sndContactCITimed live = sndCITimed_ live . contactTimedTTL

sndGroupCITimed :: Bool -> GroupInfo -> Maybe Int -> CM (Maybe CITimed)
sndGroupCITimed live = sndCITimed_ live . groupTimedTTL

sndCITimed_ :: Bool -> Maybe (Maybe Int) -> Maybe Int -> CM (Maybe CITimed)
sndCITimed_ live chatTTL itemTTL =
  forM (chatTTL >>= (itemTTL <|>)) $ \ttl ->
    CITimed ttl
      <$> if live
        then pure Nothing
        else Just . addUTCTime (realToFrac ttl) <$> liftIO getCurrentTime

callTimed :: Contact -> ACIContent -> CM (Maybe CITimed)
callTimed ct aciContent =
  case aciContentCallStatus aciContent of
    Just callStatus
      | callComplete callStatus -> do
          contactCITimed ct
    _ -> pure Nothing
  where
    aciContentCallStatus :: ACIContent -> Maybe CICallStatus
    aciContentCallStatus (ACIContent _ (CISndCall st _)) = Just st
    aciContentCallStatus (ACIContent _ (CIRcvCall st _)) = Just st
    aciContentCallStatus _ = Nothing

toggleNtf :: GroupMember -> Bool -> CM ()
toggleNtf m ntfOn =
  when (memberActive m) $
    forM_ (memberConnId m) $ \connId ->
      withAgent (\a -> toggleConnectionNtfs a connId ntfOn) `catchAllErrors` eToView

prepareGroupMsg :: DB.Connection -> User -> GroupInfo -> Maybe MsgScope -> ShowGroupAsSender -> MsgContent -> Map MemberName MsgMention -> Maybe ChatItemId -> Maybe CIForwardedFrom -> Maybe FileInvitation -> Maybe CITimed -> Bool -> ExceptT StoreError IO (ChatMsgEvent 'Json, Maybe (CIQuote 'CTGroup))
prepareGroupMsg db user g@GroupInfo {membership} msgScope showGroupAsSender mc mentions quotedItemId_ itemForwarded fInv_ timed_ live = do
  (mc', quotedItem_) <- case (quotedItemId_, itemForwarded) of
    (Nothing, Nothing) -> pure (mcSimple mc, Nothing)
    (Nothing, Just _) -> pure (mcForward mc, Nothing)
    (Just quotedItemId, Nothing) -> do
      CChatItem _ qci@ChatItem {meta = CIMeta {itemTs, itemSharedMsgId}, formattedText, mentions = quoteMentions, file} <-
        getGroupCIWithReactions db user g quotedItemId
      (origQmc, qd, sent, member_) <- quoteData qci membership
      let msgRef = MsgRef {msgId = itemSharedMsgId, sentAt = itemTs, sent, memberId = memberId' <$> member_}
          qmc = quoteContent mc origQmc file
          (qmc', ft', _) = updatedMentionNames qmc formattedText quoteMentions
          quotedItem = CIQuote {chatDir = qd, itemId = Just quotedItemId, sharedMsgId = itemSharedMsgId, sentAt = itemTs, content = qmc', formattedText = ft'}
      pure (mcQuote QuotedMsg {msgRef, content = qmc'} mc, Just quotedItem)
    (Just _, Just _) -> throwError SEInvalidQuote
  let mc'' = mc' {mentions = MsgMentions mentions, file = fInv_, ttl = ttl' <$> timed_, live = justTrue live, scope = msgScope, asGroup = justTrue showGroupAsSender}
  pure (XMsgNew mc'', quotedItem_)
  where
    quoteData :: ChatItem c d -> GroupMember -> ExceptT StoreError IO (MsgContent, CIQDirection 'CTGroup, Bool, Maybe GroupMember)
    quoteData ChatItem {meta = CIMeta {itemDeleted = Just _}} _ = throwError SEInvalidQuote
    quoteData ChatItem {chatDir = CIGroupSnd, content = CISndMsgContent qmc, meta = CIMeta {showGroupAsSender = sentAsGroup}} membership'
      | sentAsGroup = pure (qmc, CIQGroupSnd, True, Nothing)
      | otherwise = pure (qmc, CIQGroupSnd, True, Just membership')
    quoteData ChatItem {chatDir = CIGroupRcv m, content = CIRcvMsgContent qmc} _ = pure (qmc, CIQGroupRcv $ Just m, False, Just m)
    quoteData ChatItem {chatDir = CIChannelRcv, content = CIRcvMsgContent qmc} _ = pure (qmc, CIQGroupRcv Nothing, False, Nothing)
    quoteData _ _ = throwError SEInvalidQuote

updatedMentionNames :: MsgContent -> Maybe MarkdownList -> Map MemberName CIMention -> (MsgContent, Maybe MarkdownList, Map MemberName CIMention)
updatedMentionNames mc ft_ mentions = case ft_ of
  Just ft
    | not (null ft) && not (null mentions) && not (all sameName $ M.assocs mentions) ->
        let (mentions', ft') = mapAccumL update M.empty ft
            text = T.concat $ map markdownText ft'
         in (mc {text} :: MsgContent, Just ft', mentions')
  _ -> (mc, ft_, mentions)
  where
    sameName (name, CIMention {memberRef}) = case memberRef of
      Just CIMentionMember {displayName} -> case T.stripPrefix displayName name of
        Just rest
          | T.null rest -> True
          | otherwise -> case T.uncons rest of
              Just ('_', suffix) -> T.all isDigit suffix
              _ -> False
        Nothing -> False
      Nothing -> True
    update mentions' ft@(FormattedText f _) = case f of
      Just (Mention name) -> case M.lookup name mentions of
        Just mm@CIMention {memberRef} ->
          let name' = uniqueMentionName 0 $ case memberRef of
                Just CIMentionMember {displayName} -> displayName
                Nothing -> name
           in (M.insert name' mm mentions', FormattedText (Just $ Mention name') ('@' `T.cons` viewName name'))
        Nothing -> (mentions', ft)
      _ -> (mentions', ft)
      where
        uniqueMentionName :: Int -> Text -> Text
        uniqueMentionName pfx name =
          let prefixed = if pfx == 0 then name else (name `T.snoc` '_') <> tshow pfx
           in if prefixed `M.member` mentions' then uniqueMentionName (pfx + 1) name else prefixed

getCIMentions :: DB.Connection -> User -> GroupInfo -> Maybe MarkdownList -> Map MemberName GroupMemberId -> ExceptT StoreError IO (Map MemberName CIMention)
getCIMentions db user GroupInfo {groupId} ft_ mentions = case ft_ of
  Just ft | not (null ft) && not (null mentions) -> do
    let msgMentions = S.fromList $ mentionedNames ft
        n = M.size mentions
    unless (n <= maxSndMentions && all (`S.member` msgMentions) (M.keys mentions) && S.size (S.fromList $ M.elems mentions) == n) $
      throwError SEInvalidMention
    mapM (getMentionedGroupMember db user groupId) mentions
  _ -> pure M.empty

getRcvCIMentions :: DB.Connection -> User -> GroupInfo -> Maybe MarkdownList -> Map MemberName MsgMention -> IO (Map MemberName CIMention)
getRcvCIMentions db user GroupInfo {groupId} ft_ mentions = case ft_ of
  Just ft
    | not (null ft) && not (null mentions) ->
        let mentions' = uniqueMsgMentions maxRcvMentions mentions $ mentionedNames ft
         in mapM (getMentionedMemberByMemberId db user groupId) mentions'
  _ -> pure M.empty

uniqueMsgMentions :: Int -> Map MemberName MsgMention -> [ContactName] -> Map MemberName MsgMention
uniqueMsgMentions maxMentions mentions = go M.empty S.empty 0
  where
    go acc _ _ [] = acc
    go acc seen n (name : rest)
      | n >= maxMentions = acc
      | otherwise = case M.lookup name mentions of
          Just mm@MsgMention {memberId}
            | S.notMember memberId seen ->
                go (M.insert name mm acc) (S.insert memberId seen) (n + 1) rest
          _ -> go acc seen n rest

getMessageMentions :: DB.Connection -> User -> GroupId -> Text -> IO (Map MemberName GroupMemberId)
getMessageMentions db user gId msg = case parseMaybeMarkdownList msg of
  Just ft | not (null ft) -> M.fromList . catMaybes <$> mapM get (nubOrd $ mentionedNames ft)
  _ -> pure M.empty
  where
    get name =
      fmap (name,) . eitherToMaybe
        <$> runExceptT (getGroupMemberIdByName db user gId name)

msgContentTexts :: MsgContent -> (Text, Maybe MarkdownList)
msgContentTexts mc = let t = msgContentText mc in (t, parseMaybeMarkdownList t)

ciContentTexts :: CIContent d -> (Text, Maybe MarkdownList)
ciContentTexts content = let t = ciContentToText content in (t, parseMaybeMarkdownList t)

quoteContent :: forall d. MsgContent -> MsgContent -> Maybe (CIFile d) -> MsgContent
quoteContent mc qmc ciFile_
  | replaceContent = MCText qTextOrFile
  | otherwise = case qmc of
      MCImage _ image -> MCImage qTextOrFile image
      MCFile _ -> MCFile qTextOrFile
      _ -> qmc
  where
    replaceContent = case mc of
      MCText _ -> False
      MCFile _ -> False
      MCLink {} -> True
      MCImage {} -> True
      MCVideo {} -> True
      MCVoice {} -> False
      MCReport {} -> False
      MCChat {} -> True
      MCUnknown {} -> True
    qText = msgContentText qmc
    getFileName :: CIFile d -> String
    getFileName CIFile {fileName} = fileName
    qFileName = maybe qText (T.pack . getFileName) ciFile_
    qTextOrFile = if T.null qText then qFileName else qText

prohibitedGroupContent :: GroupInfo -> GroupMember -> Maybe GroupChatScopeInfo -> MsgContent -> Maybe MarkdownList -> Maybe f -> Bool -> Maybe GroupFeature
prohibitedGroupContent gInfo@GroupInfo {membership = mem@GroupMember {memberRole = userRole}} m scopeInfo mc ft file_ sent
  | not supportAllowed = Just GFSupport
  | isVoice mc && not (groupFeatureMemberAllowed SGFVoice m gInfo) && not hostApprovalVoice = Just GFVoice
  | isNothing scopeInfo && not (isVoice mc) && (isJust file_ || isMedia mc) && not (groupFeatureMemberAllowed SGFFiles m gInfo) = Just GFFiles
  | isNothing scopeInfo && isReport mc && (badReportUser || not (groupFeatureAllowed SGFReports gInfo)) = Just GFReports
  | isNothing scopeInfo && prohibitedZeroLinks gInfo m mc ft = Just GFZeroLinks
  | otherwise = Nothing
  where
    supportAllowed = case scopeInfo of
      Just (GCSIMemberSupport scopeMem_) ->
        groupFeatureAllowed SGFSupport gInfo || isJust (supportChat $ fromMaybe mem scopeMem_)
      Nothing -> True
    hostApprovalVoice
      | sent = userRole >= GRAdmin && sendApprovalPhase
      | otherwise = memberCategory m == GCHostMember && hostApprovalPhase
    hostApprovalPhase = case scopeInfo of
      Just (GCSIMemberSupport Nothing) -> memberStatus mem == GSMemPendingApproval
      _ -> False
    sendApprovalPhase = case scopeInfo of
      Just (GCSIMemberSupport (Just scopeMem)) -> memberStatus scopeMem == GSMemPendingApproval
      _ -> False
    badReportUser
      | sent = userRole >= GRModerator
      | otherwise = userRole < GRModerator

prohibitedZeroLinks :: GroupInfo -> GroupMember -> MsgContent -> Maybe MarkdownList -> Bool
prohibitedZeroLinks gInfo m mc ft =
  not (groupFeatureMemberAllowed SGFZeroLinks m gInfo)
    && (isChatLink mc || maybe False (any ftIsZeroLink) ft || hasObfuscatedZeroLink (msgContentText mc))
  where
    isChatLink = \case
      MCChat {} -> True
      _ -> False

ftIsZeroLink :: FormattedText -> Bool
ftIsZeroLink FormattedText {format} = maybe False isZeroLink format

roundedFDCount :: Int -> Int
roundedFDCount n
  | n <= 0 = 4
  | otherwise = max 4 $ fromIntegral $ (2 :: Integer) ^ (ceiling (logBase 2 (fromIntegral n) :: Double) :: Integer)

xftpSndFileTransfer_ :: User -> CryptoFile -> Integer -> Int -> Maybe ContactOrGroup -> CM (FileInvitation, CIFile 'MDSnd, FileTransferMeta)
xftpSndFileTransfer_ user file@(CryptoFile filePath cfArgs) fileSize n contactOrGroup_ = do
  let fileName = takeFileName filePath
      fInv = xftpFileInvitation fileName fileSize dummyFileDescr
  fsFilePath <- lift $ toFSFilePath filePath
  let srcFile = CryptoFile fsFilePath cfArgs
  aFileId <- withAgent $ \a -> xftpSendFile a (aUserId user) srcFile (roundedFDCount n)
  chSize <- asks $ fileChunkSize . config
  ft@FileTransferMeta {fileId} <- withStore' $ \db -> createSndFileTransferXFTP db user contactOrGroup_ file fInv (AgentSndFileId aFileId) Nothing chSize
  let fileSource = Just $ CryptoFile filePath cfArgs
      ciFile = CIFile {fileId, fileName, fileSize, fileSource, fileStatus = CIFSSndStored, fileProtocol = FPXFTP}
  pure (fInv, ciFile, ft)

cryptoFileDigest :: CryptoFile -> CM FD.FileDigest
cryptoFileDigest (CryptoFile filePath cfArgs) = do
  fsPath <- lift $ toFSFilePath filePath
  r <- liftIO $ runExceptT $ CF.readFile (CryptoFile fsPath cfArgs)
  either (throwChatError . CEInternalError . show) (pure . FD.FileDigest . LC.sha512Hash) r

xftpSndFileRedirect :: User -> FileTransferId -> ValidFileDescription 'FRecipient -> CM FileTransferMeta
xftpSndFileRedirect user ftId vfd = do
  let fileName = "redirect.yaml"
      file = CryptoFile fileName Nothing
      fInv = xftpFileInvitation fileName (fromIntegral $ B.length $ strEncode vfd) dummyFileDescr
  aFileId <- withAgent $ \a -> xftpSendDescription a (aUserId user) vfd (roundedFDCount 1)
  chSize <- asks $ fileChunkSize . config
  withStore' $ \db -> createSndFileTransferXFTP db user Nothing file fInv (AgentSndFileId aFileId) (Just ftId) chSize

dummyFileDescr :: FileDescr
dummyFileDescr = FileDescr {fileDescrText = "", fileDescrPartNo = 0, fileDescrComplete = False}

cancelFilesInProgress :: User -> [CIFileInfo] -> CM ()
cancelFilesInProgress user filesInfo = do
  let filesInfo' = filter (not . fileEnded) filesInfo
  (sfs, rfs) <- lift $ splitFTTypes <$> withStoreBatch (\db -> map (getFT db) filesInfo')
  forM_ rfs $ \RcvFileTransfer {fileId} -> lift (closeFileHandle fileId rcvFiles) `catchAllErrors` \_ -> pure ()
  lift . void . withStoreBatch' $ \db -> map (updateSndFileCancelled db) sfs
  lift . void . withStoreBatch' $ \db -> map (updateRcvFileCancelled db) rfs
  let xsfIds = mapMaybe (\(FileTransferMeta {fileId, xftpSndFile}, _) -> (,fileId) <$> xftpSndFile) sfs
      xrfIds = mapMaybe (\RcvFileTransfer {fileId, xftpRcvFile} -> (,fileId) <$> xftpRcvFile) rfs
  lift $ agentXFTPDeleteSndFilesRemote user xsfIds
  lift $ agentXFTPDeleteRcvFiles xrfIds
  where
    fileEnded CIFileInfo {fileStatus} = case fileStatus of
      Just (AFS _ status) -> ciFileEnded status
      Nothing -> True
    getFT :: DB.Connection -> CIFileInfo -> IO (Either ChatError FileTransfer)
    getFT db CIFileInfo {fileId} = runExceptT . withExceptT ChatErrorStore $ getFileTransfer db user fileId
    updateSndFileCancelled :: DB.Connection -> (FileTransferMeta, [SndFileTransfer]) -> IO ()
    updateSndFileCancelled db (FileTransferMeta {fileId}, sfts) = do
      updateFileCancelled db user fileId CIFSSndCancelled
      forM_ sfts $ \sft -> unless (sndFTEnded sft) $ updateSndFileStatus db sft FSCancelled
    updateRcvFileCancelled :: DB.Connection -> RcvFileTransfer -> IO ()
    updateRcvFileCancelled db ft@RcvFileTransfer {fileId} = do
      updateFileCancelled db user fileId CIFSRcvCancelled
      updateRcvFileStatus db fileId FSCancelled
      deleteRcvFileChunks db ft
    splitFTTypes :: [Either ChatError FileTransfer] -> ([(FileTransferMeta, [SndFileTransfer])], [RcvFileTransfer])
    splitFTTypes = foldr addFT ([], []) . rights
      where
        addFT f (sfs, rfs) = case f of
          FTSnd ft@FileTransferMeta {cancelled} sfts | not cancelled -> ((ft, sfts) : sfs, rfs)
          FTRcv ft@RcvFileTransfer {cancelled} | not cancelled -> (sfs, ft : rfs)
          _ -> (sfs, rfs)
    sndFTEnded SndFileTransfer {fileStatus} = fileStatus == FSCancelled || fileStatus == FSComplete

deleteFilesLocally :: [CIFileInfo] -> CM ()
deleteFilesLocally files =
  withFilesFolder $ \filesFolder ->
    liftIO . forM_ files $ \CIFileInfo {filePath} ->
      mapM_ (delete . (filesFolder </>)) filePath
  where
    delete :: FilePath -> IO ()
    delete fPath =
      removeFile fPath `catchAll` \_ ->
        removePathForcibly fPath `catchAll_` pure ()
    withFilesFolder :: (FilePath -> CM ()) -> CM ()
    withFilesFolder action = asks filesFolder >>= readTVarIO >>= mapM_ action

deleteDirectCIs :: User -> Contact -> [CChatItem 'CTDirect] -> CM [ChatItemDeletion]
deleteDirectCIs user ct items = do
  let ciFilesInfo = mapMaybe (\(CChatItem _ ChatItem {file}) -> mkCIFileInfo <$> file) items
  deleteCIFiles user ciFilesInfo
  (errs, deletions) <- lift $ partitionEithers <$> withStoreBatch' (\db -> map (deleteItem db) items)
  unless (null errs) $ toView $ CEvtChatErrors errs
  pure deletions
  where
    deleteItem db (CChatItem md ci) = do
      deleteDirectChatItem db user ct ci
      pure $ contactDeletion md ct ci Nothing

deleteGroupCIs :: User -> GroupInfo -> Maybe GroupChatScopeInfo -> [CChatItem 'CTGroup] -> Maybe GroupMember -> UTCTime -> CM [ChatItemDeletion]
deleteGroupCIs user gInfo chatScopeInfo items byGroupMember_ deletedTs = do
  let ciFilesInfo = mapMaybe (\(CChatItem _ ChatItem {file}) -> mkCIFileInfo <$> file) items
  deleteCIFiles user ciFilesInfo
  (errs, deletions) <- lift $ partitionEithers <$> withStoreBatch' (\db -> map (deleteItem db) items)
  unless (null errs) $ toView $ CEvtChatErrors errs
  cxt <- chatStoreCxt
  deletions' <- case chatScopeInfo of
    Nothing -> pure deletions
    Just scopeInfo@GCSIMemberSupport {groupMember_} -> do
      let decStats = countDeletedUnreadItems groupMember_ deletions
      gInfo' <- withFastStore' $ \db -> updateGroupScopeUnreadStats db cxt user gInfo scopeInfo decStats
      pure $ map (updateDeletionGroupInfo gInfo') deletions
  pure deletions'
  where
    deleteItem :: DB.Connection -> CChatItem 'CTGroup -> IO ChatItemDeletion
    deleteItem db (CChatItem md ci) = do
      ci' <- case byGroupMember_ of
        Just m -> Just <$> updateGroupChatItemModerated db user gInfo ci m deletedTs
        Nothing -> Nothing <$ deleteGroupChatItem db user gInfo ci
      pure $ groupDeletion md gInfo chatScopeInfo ci ci'
    countDeletedUnreadItems :: Maybe GroupMember -> [ChatItemDeletion] -> (Int, Int, Int)
    countDeletedUnreadItems scopeMember_ = foldl' countItem (0, 0, 0)
      where
        countItem :: (Int, Int, Int) -> ChatItemDeletion -> (Int, Int, Int)
        countItem (!unread, !unanswered, !mentions) ChatItemDeletion {deletedChatItem}
          | aChatItemIsRcvNew deletedChatItem =
              let unread' = unread + 1
                  unanswered' = case (scopeMember_, aChatItemRcvFromMember deletedChatItem) of
                    (Just scopeMember, Just rcvFromMember)
                      | groupMemberId' rcvFromMember == groupMemberId' scopeMember -> unanswered + 1
                    _ -> unanswered
                  mentions' = if isACIUserMention deletedChatItem then mentions + 1 else mentions
               in (unread', unanswered', mentions')
          | otherwise = (unread, unanswered, mentions)
    updateDeletionGroupInfo :: GroupInfo -> ChatItemDeletion -> ChatItemDeletion
    updateDeletionGroupInfo gInfo' ChatItemDeletion {deletedChatItem, toChatItem} =
      ChatItemDeletion
        { deletedChatItem = updateACIGroupInfo gInfo' deletedChatItem,
          toChatItem = updateACIGroupInfo gInfo' <$> toChatItem
        }

updateACIGroupInfo :: GroupInfo -> AChatItem -> AChatItem
updateACIGroupInfo gInfo' = \case
  AChatItem SCTGroup dir (GroupChat _gInfo chatScopeInfo) ci ->
    AChatItem SCTGroup dir (GroupChat gInfo' chatScopeInfo) ci
  aci -> aci

deleteGroupMemberCIs :: User -> GroupInfo -> GroupMember -> CM ()
deleteGroupMemberCIs user gInfo member = do
  filesInfo <- withStore' $ \db -> deleteGroupMemberCIs_ db user gInfo member
  deleteCIFiles user filesInfo

deleteGroupMembersCIs :: User -> GroupInfo -> [GroupMember] -> CM ()
deleteGroupMembersCIs user gInfo members = do
  filesInfo <- withStore' $ \db -> fmap concat $ forM members $ deleteGroupMemberCIs_ db user gInfo
  deleteCIFiles user filesInfo

deleteGroupMemberCIs_ :: DB.Connection -> User -> GroupInfo -> GroupMember -> IO [CIFileInfo]
deleteGroupMemberCIs_ db user gInfo member = do
  fs <- getGroupMemberFileInfo db user gInfo member
  deleteMemberCIs db user gInfo member
  pure fs

deleteLocalCIs :: User -> NoteFolder -> [CChatItem 'CTLocal] -> Bool -> Bool -> CM ChatResponse
deleteLocalCIs user nf items byUser timed = do
  let ciFilesInfo = mapMaybe (\(CChatItem _ ChatItem {file}) -> mkCIFileInfo <$> file) items
  deleteFilesLocally ciFilesInfo
  (errs, deletions) <- lift $ partitionEithers <$> withStoreBatch' (\db -> map (deleteItem db) items)
  unless (null errs) $ toView $ CEvtChatErrors errs
  pure $ CRChatItemsDeleted user deletions byUser timed
  where
    deleteItem db (CChatItem md ci) = do
      deleteLocalChatItem db user nf ci
      pure $ ChatItemDeletion (nfItem md ci) Nothing
    nfItem :: MsgDirectionI d => SMsgDirection d -> ChatItem 'CTLocal d -> AChatItem
    nfItem md = AChatItem SCTLocal md (LocalChat nf)

deleteCIFiles :: User -> [CIFileInfo] -> CM ()
deleteCIFiles user filesInfo = do
  cancelFilesInProgress user filesInfo
  deleteFilesLocally filesInfo

markDirectCIsDeleted :: User -> Contact -> [CChatItem 'CTDirect] -> UTCTime -> CM [ChatItemDeletion]
markDirectCIsDeleted user ct items deletedTs = do
  let ciFilesInfo = mapMaybe (\(CChatItem _ ChatItem {file}) -> mkCIFileInfo <$> file) items
  cancelFilesInProgress user ciFilesInfo
  (errs, deletions) <- lift $ partitionEithers <$> withStoreBatch' (\db -> map (markDeleted db) items)
  unless (null errs) $ toView $ CEvtChatErrors errs
  pure deletions
  where
    markDeleted db (CChatItem md ci) = do
      ci' <- markDirectChatItemDeleted db user ct ci deletedTs
      pure $ contactDeletion md ct ci (Just ci')

markGroupCIsDeleted :: User -> GroupInfo -> Maybe GroupChatScopeInfo -> [CChatItem 'CTGroup] -> Maybe GroupMember -> UTCTime -> CM [ChatItemDeletion]
markGroupCIsDeleted user gInfo chatScopeInfo items byGroupMember_ deletedTs = do
  let ciFilesInfo = mapMaybe (\(CChatItem _ ChatItem {file}) -> mkCIFileInfo <$> file) items
  cancelFilesInProgress user ciFilesInfo
  (errs, deletions) <- lift $ partitionEithers <$> withStoreBatch' (\db -> map (markDeleted db) items)
  unless (null errs) $ toView $ CEvtChatErrors errs
  pure deletions
  where
    markDeleted db (CChatItem md ci) = do
      ci' <- markGroupChatItemDeleted db user gInfo ci byGroupMember_ deletedTs
      pure $ groupDeletion md gInfo chatScopeInfo ci (Just ci')

markGroupMemberCIsDeleted :: User -> GroupInfo -> GroupMember -> GroupMember -> CM ()
markGroupMemberCIsDeleted user gInfo member byGroupMember = do
  deletedTs <- liftIO getCurrentTime
  filesInfo <- withStore' $ \db -> markGroupMemberCIsDeleted_ db user gInfo member byGroupMember deletedTs
  cancelFilesInProgress user filesInfo

markGroupMembersCIsDeleted :: User -> GroupInfo -> [GroupMember] -> GroupMember -> CM ()
markGroupMembersCIsDeleted user gInfo members byGroupMember = do
  deletedTs <- liftIO getCurrentTime
  filesInfo <- withStore' $ \db -> fmap concat $ forM members $ \m -> markGroupMemberCIsDeleted_ db user gInfo m byGroupMember deletedTs
  cancelFilesInProgress user filesInfo

markGroupMemberCIsDeleted_ :: DB.Connection -> User -> GroupInfo -> GroupMember -> GroupMember -> UTCTime -> IO [CIFileInfo]
markGroupMemberCIsDeleted_ db user gInfo member byGroupMember deletedTs = do
  fs <- getGroupMemberFileInfo db user gInfo member
  markMemberCIsDeleted db user gInfo member byGroupMember deletedTs
  pure fs

groupDeletion :: MsgDirectionI d => SMsgDirection d -> GroupInfo -> Maybe GroupChatScopeInfo -> ChatItem 'CTGroup d -> Maybe (ChatItem 'CTGroup d) -> ChatItemDeletion
groupDeletion md g chatScopeInfo ci ci' = ChatItemDeletion (gItem ci) (gItem <$> ci')
  where
    gItem = AChatItem SCTGroup md (GroupChat g chatScopeInfo)

contactDeletion :: MsgDirectionI d => SMsgDirection d -> Contact -> ChatItem 'CTDirect d -> Maybe (ChatItem 'CTDirect d) -> ChatItemDeletion
contactDeletion md ct ci ci' = ChatItemDeletion (ctItem ci) (ctItem <$> ci')
  where
    ctItem = AChatItem SCTDirect md (DirectChat ct)

updateCallItemStatus :: User -> Contact -> Call -> WebRTCCallStatus -> Maybe MessageId -> CM ()
updateCallItemStatus user ct@Contact {contactId} Call {chatItemId} receivedStatus msgId_ = do
  aciContent_ <- callStatusItemContent user ct chatItemId receivedStatus
  forM_ aciContent_ $ \aciContent -> do
    timed_ <- callTimed ct aciContent
    updateDirectChatItemView user ct chatItemId aciContent False False timed_ msgId_
    forM_ (timed_ >>= timedDeleteAt') $
      startProximateTimedItemThread user (ChatRef CTDirect contactId Nothing, chatItemId)

updateDirectChatItemView :: User -> Contact -> ChatItemId -> ACIContent -> Bool -> Bool -> Maybe CITimed -> Maybe MessageId -> CM ()
updateDirectChatItemView user ct chatItemId (ACIContent msgDir ciContent) edited live timed_ msgId_ = do
  ci' <- withStore $ \db -> updateDirectChatItem db user ct chatItemId ciContent edited live timed_ msgId_
  toView $ CEvtChatItemUpdated user (AChatItem SCTDirect msgDir (DirectChat ct) ci')

callStatusItemContent :: User -> Contact -> ChatItemId -> WebRTCCallStatus -> CM (Maybe ACIContent)
callStatusItemContent user Contact {contactId} chatItemId receivedStatus = do
  CChatItem msgDir ChatItem {meta = CIMeta {updatedAt}, content} <-
    withStore $ \db -> getDirectChatItem db user contactId chatItemId
  ts <- liftIO getCurrentTime
  let callDuration :: Int = nominalDiffTimeToSeconds (ts `diffUTCTime` updatedAt) `div'` 1
      callStatus = case content of
        CISndCall st _ -> Just st
        CIRcvCall st _ -> Just st
        _ -> Nothing
      newState_ = case (callStatus, receivedStatus) of
        (Just CISCallProgress, WCSConnected) -> Nothing
        (Just CISCallProgress, WCSDisconnected) -> Just (CISCallEnded, callDuration)
        (Just CISCallProgress, WCSFailed) -> Just (CISCallEnded, callDuration)
        (Just CISCallPending, WCSDisconnected) -> Just (CISCallMissed, 0)
        (Just CISCallEnded, _) -> Nothing
        (Just CISCallError, _) -> Nothing
        (Just _, WCSConnecting) -> Just (CISCallNegotiated, 0)
        (Just _, WCSConnected) -> Just (CISCallProgress, 0)
        (Just _, WCSDisconnected) -> Just (CISCallEnded, 0)
        (Just _, WCSFailed) -> Just (CISCallError, 0)
        (Nothing, _) -> Nothing
  pure $ aciContent msgDir <$> newState_
  where
    aciContent :: forall d. SMsgDirection d -> (CICallStatus, Int) -> ACIContent
    aciContent msgDir (callStatus', duration) = case msgDir of
      SMDSnd -> ACIContent SMDSnd $ CISndCall callStatus' duration
      SMDRcv -> ACIContent SMDRcv $ CIRcvCall callStatus' duration

toFSFilePath :: FilePath -> CM' FilePath
toFSFilePath f =
  maybe f (</> f) <$> (chatReadVar' filesFolder)

setFileToEncrypt :: RcvFileTransfer -> CM RcvFileTransfer
setFileToEncrypt ft@RcvFileTransfer {fileId} = do
  cfArgs <- atomically . CF.randomArgs =<< asks random
  withStore' $ \db -> setFileCryptoArgs db fileId cfArgs
  pure (ft :: RcvFileTransfer) {cryptoArgs = Just cfArgs}

receiveFile' :: User -> RcvFileTransfer -> Bool -> Maybe Bool -> Maybe FilePath -> CM ChatResponse
receiveFile' user ft userApprovedRelays rcvInline_ filePath_ = do
  (CRRcvFileAccepted user <$> acceptFileReceive user ft userApprovedRelays rcvInline_ filePath_) `catchAllErrors` processError
  where
    processError e
      | rctFileCancelled e = pure $ CRRcvFileAcceptedSndCancelled user ft
      | otherwise = throwError e

receiveFileEvt' :: User -> RcvFileTransfer -> Bool -> Maybe Bool -> Maybe FilePath -> CM ChatEvent
receiveFileEvt' user ft userApprovedRelays rcvInline_ filePath_ = do
  (CEvtRcvFileAccepted user <$> acceptFileReceive user ft userApprovedRelays rcvInline_ filePath_) `catchAllErrors` processError
  where
    processError e
      | rctFileCancelled e = pure $ CEvtRcvFileAcceptedSndCancelled user ft
      | otherwise = throwError e

rctFileCancelled :: ChatError -> Bool
rctFileCancelled = \case
  ChatErrorAgent (SMP _ SMP.AUTH) _ _ -> True
  ChatErrorAgent (CONN DUPLICATE _) _ _ -> True
  _ -> False

acceptFileReceive :: User -> RcvFileTransfer -> Bool -> Maybe Bool -> Maybe FilePath -> CM AChatItem
acceptFileReceive user@User {userId} RcvFileTransfer {fileId, xftpRcvFile, fileInvitation = FileInvitation {fileName = fName, fileConnReq, fileInline, fileSize}, fileStatus, grpMemberId, cryptoArgs} userApprovedRelays rcvInline_ filePath_ = do
  unless (fileStatus == RFSNew) $ case fileStatus of
    RFSCancelled _ -> throwChatError $ CEFileCancelled fName
    _ -> throwChatError $ CEFileAlreadyReceiving fName
  cxt <- chatStoreCxt
  case (xftpRcvFile, fileConnReq) of
    (Just XFTPRcvFile {userApprovedRelays = approvedBeforeReady}, _) -> do
      let userApproved = approvedBeforeReady || userApprovedRelays
      filePath <- getRcvFilePath fileId filePath_ fName False
      (ci, rfd) <- withStore $ \db -> do
        ci <- xftpAcceptRcvFT db cxt user fileId filePath userApproved
        rfd <- getRcvFileDescrByRcvFileId db fileId
        pure (ci, rfd)
      receiveViaCompleteFD user fileId rfd fileSize userApproved cryptoArgs
      pure ci
    (Nothing, Just _fileConnReq) -> throwChatError $ CEException "accepting file via a separate connection is deprecated"
    _ -> do
      chatRef <- withStore $ \db -> getChatRefByFileId db user fileId
      case (chatRef, grpMemberId) of
        (ChatRef CTDirect contactId _, Nothing) -> do
          ct <- withStore $ \db -> getContact db cxt user contactId
          acceptFile $ \msg -> void $ sendDirectContactMessage user ct msg
        (ChatRef CTGroup groupId _, Just memId) -> do
          GroupMember {activeConn} <- withStore $ \db -> getGroupMember db cxt user groupId memId
          case activeConn of
            Just conn -> do
              acceptFile $ \msg -> void $ sendDirectMemberMessage conn msg groupId
            _ -> throwChatError $ CEFileInternal "member connection not active"
        _ -> throwChatError $ CEFileInternal "invalid chat ref for file transfer"
  where
    acceptFile :: (ChatMsgEvent 'Json -> CM ()) -> CM AChatItem
    acceptFile send = do
      filePath <- getRcvFilePath fileId filePath_ fName True
      inline <- receiveInline
      cxt <- chatStoreCxt
      if
        | inline -> do
            (ci, sharedMsgId) <- withStore $ \db ->
              liftM2 (,) (acceptRcvInlineFT db cxt user fileId filePath) (getSharedMsgIdByFileId db userId fileId)
            send $ XFileAcptInv sharedMsgId Nothing fName
            pure ci
        | fileInline == Just IFMSent -> throwChatError $ CEFileAlreadyReceiving fName
        | otherwise -> throwChatError $ CEException "accepting file via a separate connection is deprecated"
    receiveInline :: CM Bool
    receiveInline = do
      ChatConfig {fileChunkSize, inlineFiles = InlineFilesConfig {receiveChunks, offerChunks}} <- asks config
      pure $
        rcvInline_ /= Just False
          && fileInline == Just IFMOffer
          && ( fileSize <= fileChunkSize * receiveChunks
                || (rcvInline_ == Just True && fileSize <= fileChunkSize * offerChunks)
             )

receiveViaCompleteFD :: User -> FileTransferId -> RcvFileDescr -> Integer -> Bool -> Maybe CryptoFileArgs -> CM ()
receiveViaCompleteFD user fileId RcvFileDescr {fileDescrText, fileDescrComplete} expectedFileSize userApprovedRelays cfArgs =
  when fileDescrComplete $ do
    rd <- parseFileDescription fileDescrText
    let FD.ValidFileDescription FD.FileDescription {size = FD.FileSize encSize, redirect} = rd
        redirectSize = maybe 0 (\FD.RedirectFileInfo {size = FD.FileSize s} -> toInteger s) redirect
        rcvSize = max (toInteger encSize) redirectSize
        maxRcvSize = min expectedFileSize (toInteger FD.maxFileSizeHard) + toInteger (FD.mb 10 :: Int64)
    when (rcvSize > maxRcvSize) $ throwChatError $ CEFileRcvChunk "declared file size exceeds the file invitation size"
    if userApprovedRelays
      then receive' rd True
      else do
        let srvs = fileDescrServers rd
        unknownSrvs <- getUnknownSrvs srvs
        let approved = null unknownSrvs
        ifM
          ((approved ||) <$> ipProtectedForSrvs srvs)
          (receive' rd approved)
          (relaysNotApproved unknownSrvs)
  where
    receive' :: ValidFileDescription 'FRecipient -> Bool -> CM ()
    receive' rd approved = do
      aFileId <- withAgent $ \a -> xftpReceiveFile a (aUserId user) rd cfArgs approved
      startReceivingFile user fileId
      withStore' $ \db -> updateRcvFileAgentId db fileId (Just $ AgentRcvFileId aFileId)
    getUnknownSrvs :: [XFTPServer] -> CM [XFTPServer]
    getUnknownSrvs srvs = do
      knownSrvs <- L.map protoServer' <$> getKnownAgentServers SPXFTP user
      pure $ filter (`notElem` knownSrvs) srvs
    ipProtectedForSrvs :: [XFTPServer] -> CM Bool
    ipProtectedForSrvs srvs = do
      netCfg <- lift getNetworkConfig
      pure $ all (ipAddressProtected netCfg) srvs
    relaysNotApproved :: [XFTPServer] -> CM ()
    relaysNotApproved unknownSrvs = do
      aci_ <- resetRcvCIFileStatus user fileId CIFSRcvInvitation
      forM_ aci_ $ \aci -> do
        cleanupACIFile aci
        toView $ CEvtChatItemUpdated user aci
      throwChatError $ CEFileNotApproved fileId unknownSrvs

cleanupACIFile :: AChatItem -> CM ()
cleanupACIFile (AChatItem _ _ _ ChatItem {file = Just CIFile {fileSource = Just CryptoFile {filePath}}}) = do
  fsFilePath <- lift $ toFSFilePath filePath
  removeFile fsFilePath `catchAllErrors` \_ -> pure ()
cleanupACIFile _ = pure ()

getKnownAgentServers :: (ProtocolTypeI p, UserProtocol p) => SProtocolType p -> User -> CM (NonEmpty (ServerCfg p))
getKnownAgentServers p user = do
  as <- asks randomAgentServers
  withStore $ \db -> do
    opDomains <- operatorDomains . serverOperators <$> getServerOperators db
    srvs <- liftIO $ getProtocolServers db p user
    pure $ useServerCfgs p as opDomains srvs

protoServer' :: ServerCfg p -> ProtocolServer p
protoServer' ServerCfg {server} = protoServer server

getNetworkConfig :: CM' NetworkConfig
getNetworkConfig = withAgent' $ liftIO . getFastNetworkConfig

resetRcvCIFileStatus :: User -> FileTransferId -> CIFileStatus 'MDRcv -> CM (Maybe AChatItem)
resetRcvCIFileStatus user fileId ciFileStatus = do
  cxt <- chatStoreCxt
  withStore $ \db -> do
    liftIO $ do
      updateCIFileStatus db user fileId ciFileStatus
      updateRcvFileStatus db fileId FSNew
      updateRcvFileAgentId db fileId Nothing
    lookupChatItemByFileId db cxt user fileId

receiveViaURI :: User -> FileDescriptionURI -> CryptoFile -> CM RcvFileTransfer
receiveViaURI user@User {userId} FileDescriptionURI {description} cf@CryptoFile {cryptoArgs} = do
  fileId <- withStore $ \db -> createRcvStandaloneFileTransfer db userId cf fileSize chunkSize
  aFileId <- withAgent $ \a -> xftpReceiveFile a (aUserId user) description cryptoArgs True
  withStore $ \db -> do
    liftIO $ do
      updateRcvFileStatus db fileId FSConnected
      updateCIFileStatus db user fileId $ CIFSRcvTransfer 0 1
      updateRcvFileAgentId db fileId (Just $ AgentRcvFileId aFileId)
    getRcvFileTransfer db user fileId
  where
    FD.ValidFileDescription FD.FileDescription {size = FD.FileSize fileSize, chunkSize = FD.FileSize chunkSize} = description

startReceivingFile :: User -> FileTransferId -> CM ()
startReceivingFile user fileId = do
  cxt <- chatStoreCxt
  ci <- withStore $ \db -> do
    liftIO $ updateRcvFileStatus db fileId FSConnected
    liftIO $ updateCIFileStatus db user fileId $ CIFSRcvTransfer 0 1
    getChatItemByFileId db cxt user fileId
  toView $ CEvtRcvFileStart user ci

getRcvFilePath :: FileTransferId -> Maybe FilePath -> String -> Bool -> CM FilePath
getRcvFilePath fileId fPath_ fn keepHandle = case fPath_ of
  Nothing ->
    chatReadVar filesFolder >>= \case
      Nothing -> do
        defaultFolder <- lift getDefaultFilesFolder
        fPath <- liftIO $ defaultFolder `uniqueCombine` fn
        createEmptyFile fPath $> fPath
      Just filesFolder -> do
        fPath <- liftIO $ filesFolder `uniqueCombine` fn
        createEmptyFile fPath
        pure $ takeFileName fPath
  Just fPath ->
    ifM
      (doesDirectoryExist fPath)
      (createInPassedDirectory fPath)
      $ ifM
        (doesFileExist fPath)
        (throwChatError $ CEFileAlreadyExists fPath)
        (createEmptyFile fPath $> fPath)
  where
    createInPassedDirectory :: FilePath -> CM FilePath
    createInPassedDirectory fPathDir = do
      fPath <- liftIO $ fPathDir `uniqueCombine` fn
      createEmptyFile fPath $> fPath
    createEmptyFile :: FilePath -> CM ()
    createEmptyFile fPath = emptyFile `catchThrow` (ChatError . CEFileWrite fPath . show)
      where
        emptyFile :: CM ()
        emptyFile
          | keepHandle = do
              h <- getFileHandle fileId fPath rcvFiles AppendMode
              liftIO $ B.hPut h "" >> hFlush h
          | otherwise = liftIO $ B.writeFile fPath ""

acceptContactRequest :: NetworkRequestMode -> User -> UserContactRequest -> IncognitoEnabled -> CM (Contact, Connection, SndQueueSecured)
acceptContactRequest nm user@User {userId} UserContactRequest {agentInvitationId = AgentInvId invId, contactId_, cReqChatVRange, localDisplayName = cName, profileId, profile = cp, userContactLinkId_, xContactId, pqSupport} incognito = do
  subMode <- chatReadVar subscriptionMode
  let pqSup = PQSupportOn
      pqSup' = pqSup `CR.pqSupportAnd` pqSupport
  cxt <- chatStoreCxt
  let chatV = vr cxt `peerConnChatVersion` cReqChatVRange
  (ct, conn, incognitoProfile) <- case contactId_ of
    Nothing -> do
      incognitoProfile <- if incognito then Just . NewIncognito <$> liftIO generateRandomProfile else pure Nothing
      connId <- withAgent $ \a -> prepareConnectionToAccept a (aUserId user) True invId pqSup'
      (ct, conn) <- withStore' $ \db ->
        createContactFromRequest db user userContactLinkId_ connId chatV cReqChatVRange cName profileId cp xContactId incognitoProfile subMode pqSup' False
      pure (ct, conn, incognitoProfile)
    Just contactId -> do
      ct <- withFastStore $ \db -> getContact db cxt user contactId
      case contactConn ct of
        Nothing -> do
          incognitoProfile <- if incognito then Just . NewIncognito <$> liftIO generateRandomProfile else pure Nothing
          connId <- withAgent $ \a -> prepareConnectionToAccept a (aUserId user) True invId pqSup'
          currentTs <- liftIO getCurrentTime
          conn <- withStore' $ \db -> do
            forM_ xContactId $ \xcId -> setContactAcceptedXContactId db ct xcId
            createAcceptedContactConn db user userContactLinkId_ contactId connId chatV cReqChatVRange pqSup' incognitoProfile subMode currentTs
          pure (ct {activeConn = Just conn} :: Contact, conn, incognitoProfile)
        Just conn@Connection {customUserProfileId} -> do
          incognitoProfile <- forM customUserProfileId $ \pId -> withFastStore $ \db -> getProfileById db userId pId
          pure (ct, conn, ExistingIncognito <$> incognitoProfile)
  profileToSend <- presentUserBadge user incognitoProfile $ userProfileDirect user (fromIncognitoProfile <$> incognitoProfile) (Just ct) True
  dm <- encodeConnInfoPQ pqSup' chatV $ XInfo profileToSend
  (ct,conn,) <$> withAgent (\a -> acceptContact a nm (aUserId user) (aConnId conn) True invId dm pqSup' subMode)

acceptContactRequestAsync :: User -> Int64 -> Contact -> UserContactRequest -> Maybe IncognitoProfile -> CM Contact
acceptContactRequestAsync
  user
  uclId
  ct@Contact {contactId}
  UserContactRequest {agentInvitationId = AgentInvId cReqInvId, cReqChatVRange, xContactId, pqSupport = cReqPQSup}
  incognitoProfile = do
    subMode <- chatReadVar subscriptionMode
    profileToSend <- presentUserBadge user incognitoProfile $ userProfileDirect user (fromIncognitoProfile <$> incognitoProfile) (Just ct) True
    cxt <- chatStoreCxt
    let chatV = vr cxt `peerConnChatVersion` cReqChatVRange
    (cmdId, acId) <- prepareAgentAccept user True cReqInvId cReqPQSup
    currentTs <- liftIO getCurrentTime
    ct' <- withStore $ \db -> do
      forM_ xContactId $ \xcId -> liftIO $ setContactAcceptedXContactId db ct xcId
      Connection {connId} <- liftIO $ createAcceptedContactConn db user (Just uclId) contactId acId chatV cReqChatVRange cReqPQSup incognitoProfile subMode currentTs
      liftIO $ setCommandConnId db user cmdId connId
      getContact db cxt user contactId
    agentAcceptContactAsync cmdId acId True cReqInvId (XInfo profileToSend) cReqPQSup chatV subMode
    pure ct'

acceptGroupJoinRequestAsync :: User -> Int64 -> GroupInfo -> InvitationId -> VersionRangeChat -> Profile -> Maybe XContactId -> Maybe MemberId -> Maybe SharedMsgId -> GroupAcceptance -> GroupMemberRole -> Maybe IncognitoProfile -> Maybe MemberKey -> Maybe GroupMember -> CM GroupMember
acceptGroupJoinRequestAsync
  user@User {userId}
  uclId
  gInfo@GroupInfo {groupProfile, membership, businessChat}
  cReqInvId
  cReqChatVRange
  cReqProfile
  cReqXContactId_
  cReqMemberId_
  welcomeMsgId_
  gAccepted
  gLinkMemRole
  incognitoProfile
  memberKey_
  existingMem_ = do
    gVar <- asks random
    let initialStatus = acceptanceToStatus (memberAdmission groupProfile) gAccepted
    cxt <- chatStoreCxt
    (groupMemberId, memberId) <- case existingMem_ of
      Just m -> do
        withStore $ \db -> do
          liftIO $ updateGroupMemberStatus db userId m initialStatus
          void $ updateMemberProfile db cxt user m cReqProfile
        pure (groupMemberId' m, memberId' m)
      Nothing -> withStore $ \db ->
        createJoiningMember db cxt gVar user gInfo cReqChatVRange cReqProfile cReqXContactId_ cReqMemberId_ welcomeMsgId_ gLinkMemRole initialStatus memberKey_
    let currentMemCount = fromIntegral $ currentMembers $ groupSummary gInfo
    let Profile {displayName} = userProfileInGroup user gInfo (fromIncognitoProfile <$> incognitoProfile)
        GroupMember {memberRole = userRole, memberId = userMemberId} = membership
        msg =
          XGrpLinkInv $
            GroupLinkInvitation
              { fromMember = MemberIdRole userMemberId userRole,
                fromMemberName = displayName,
                invitedMember = MemberIdRole memberId gLinkMemRole,
                groupProfile,
                accepted = Just gAccepted,
                business = businessChat,
                groupSize = Just currentMemCount
              }
    subMode <- chatReadVar subscriptionMode
    let chatV = vr cxt `peerConnChatVersion` cReqChatVRange
    (cmdId, acId) <- prepareAgentAccept user True cReqInvId PQSupportOff
    m <- withStore $ \db -> do
      liftIO $ createJoiningMemberConnection db user uclId (cmdId, acId) chatV cReqChatVRange groupMemberId subMode
      getGroupMemberById db cxt user groupMemberId
    agentAcceptContactAsync cmdId acId True cReqInvId msg PQSupportOff chatV subMode
    pure m

acceptGroupJoinSendRejectAsync :: User -> Int64 -> GroupInfo -> InvitationId -> VersionRangeChat -> Profile -> Maybe XContactId -> GroupRejectionReason -> CM GroupMember
acceptGroupJoinSendRejectAsync
  user
  uclId
  gInfo@GroupInfo {groupProfile, membership}
  cReqInvId
  cReqChatVRange
  cReqProfile
  cReqXContactId_
  rejectionReason = do
    gVar <- asks random
    cxt <- chatStoreCxt
    (groupMemberId, memberId) <- withStore $ \db ->
      createJoiningMember db cxt gVar user gInfo cReqChatVRange cReqProfile cReqXContactId_ Nothing Nothing GRObserver GSMemRejected Nothing
    let GroupMember {memberRole = userRole, memberId = userMemberId} = membership
        msg =
          XGrpLinkReject $
            GroupLinkRejection
              { fromMember = MemberIdRole userMemberId userRole,
                invitedMember = MemberIdRole memberId GRObserver,
                groupProfile,
                rejectionReason
              }
    subMode <- chatReadVar subscriptionMode
    let chatV = vr cxt `peerConnChatVersion` cReqChatVRange
    (cmdId, acId) <- prepareAgentAccept user False cReqInvId PQSupportOff
    m <- withStore $ \db -> do
      liftIO $ createJoiningMemberConnection db user uclId (cmdId, acId) chatV cReqChatVRange groupMemberId subMode
      getGroupMemberById db cxt user groupMemberId
    agentAcceptContactAsync cmdId acId False cReqInvId msg PQSupportOff chatV subMode
    pure m

acceptBusinessJoinRequestAsync :: User -> Int64 -> GroupInfo -> GroupMember -> UserContactRequest -> CM (GroupInfo, GroupMember)
acceptBusinessJoinRequestAsync
  user
  uclId
  gInfo@GroupInfo {membership = GroupMember {memberRole = userRole, memberId = userMemberId}}
  clientMember@GroupMember {groupMemberId, memberId}
  UserContactRequest {agentInvitationId = AgentInvId cReqInvId, cReqChatVRange, xContactId} = do
    cxt <- chatStoreCxt
    let userProfile@Profile {displayName, preferences} = fromLocalProfile $ profile' user
        groupPreferences = maybe defaultBusinessGroupPrefs businessGroupPrefs preferences
        msg =
          XGrpLinkInv $
            GroupLinkInvitation
              { fromMember = MemberIdRole userMemberId userRole,
                fromMemberName = displayName,
                invitedMember = MemberIdRole memberId GRMember,
                groupProfile = businessGroupProfile userProfile groupPreferences,
                accepted = Just GAAccepted,
                business = Just $ BusinessChatInfo {chatType = BCBusiness, businessId = userMemberId, customerId = memberId, businessDomain = Nothing},
                groupSize = Just 1
              }
    subMode <- chatReadVar subscriptionMode
    let chatV = vr cxt `peerConnChatVersion` cReqChatVRange
    (cmdId, acId) <- prepareAgentAccept user True cReqInvId PQSupportOff
    withStore' $ \db -> do
      forM_ xContactId $ \xcId -> setBusinessChatAcceptedXContactId db gInfo xcId
      createJoiningMemberConnection db user uclId (cmdId, acId) chatV cReqChatVRange groupMemberId subMode
    agentAcceptContactAsync cmdId acId True cReqInvId msg PQSupportOff chatV subMode
    let cd = CDGroupSnd gInfo Nothing
    createInternalChatItem user cd (CISndGroupE2EEInfo $ e2eInfoGroup gInfo) Nothing
    createGroupFeatureItems user cd CISndGroupFeature gInfo
    pure (gInfo, clientMember)

acceptRelayJoinRequestAsync :: User -> Int64 -> GroupInfo -> GroupMember -> InvitationId -> VersionRangeChat -> ShortLinkContact -> CM (GroupInfo, GroupMember)
acceptRelayJoinRequestAsync
  user
  uclId
  gInfo
  _ownerMember@GroupMember {groupMemberId}
  cReqInvId
  cReqChatVRange
  relayLink = do
    ChatConfig {webPreviewConfig} <- asks config
    let webDomain_ = (\WebPreviewConfig {webDomain} -> webDomain) <$> webPreviewConfig
        msg = XGrpRelayAcpt relayLink RelayCapabilities {webDomain = webDomain_}
    subMode <- chatReadVar subscriptionMode
    cxt <- chatStoreCxt
    let chatV = vr cxt `peerConnChatVersion` cReqChatVRange
    (cmdId, acId) <- prepareAgentAccept user True cReqInvId PQSupportOff
    r <- withStore $ \db -> do
      liftIO $ createJoiningMemberConnection db user uclId (cmdId, acId) chatV cReqChatVRange groupMemberId subMode
      gInfo' <- liftIO $ updateRelayOwnStatusFromTo db gInfo RSInvited RSAccepted
      ownerMember' <- getGroupMemberById db cxt user groupMemberId
      pure (gInfo', ownerMember')
    agentAcceptContactAsync cmdId acId True cReqInvId msg PQSupportOff chatV subMode
    pure r

rejectRelayInvitationAsync
  :: User
  -> Int64
  -> StoreCxt
  -> GroupRelayInvitation
  -> InvitationId
  -> VersionRangeChat
  -> Int64
  -> RelayRejectionReason
  -> CM ()
rejectRelayInvitationAsync user uclId cxt groupRelayInv invId reqChatVRange initialDelay reason = do
  (_gInfo, ownerMember) <- withStore $ \db ->
    createRelayRequestGroup db cxt user groupRelayInv invId reqChatVRange initialDelay GSMemInvited RSRejected
  let GroupMember {groupMemberId} = ownerMember
      msg = XGrpRelayReject reason
  subMode <- chatReadVar subscriptionMode
  chatVR <- chatVersionRange
  let chatV = chatVR `peerConnChatVersion` reqChatVRange
  (cmdId, acId) <- prepareAgentAccept user False invId PQSupportOff
  withStore' $ \db ->
    createJoiningMemberConnection db user uclId (cmdId, acId) chatV reqChatVRange groupMemberId subMode
  agentAcceptContactAsync cmdId acId False invId msg PQSupportOff chatV subMode

businessGroupProfile :: Profile -> GroupPreferences -> GroupProfile
businessGroupProfile Profile {displayName, fullName, shortDescr, description, image} groupPreferences =
  GroupProfile {displayName, fullName, description, shortDescr, image, publicGroup = Nothing, groupPreferences = Just groupPreferences, memberAdmission = Nothing}

introduceToModerators :: StoreCxt -> User -> GroupInfo -> GroupMember -> CM ()
introduceToModerators cxt user gInfo@GroupInfo {groupId} m@GroupMember {memberRole, memberId} = do
  forM_ (memberConn m) $ \mConn -> do
    let msg =
          if maxVersion (memberChatVRange m) >= groupKnockingVersion
            then XGrpLinkAcpt GAPendingReview memberRole memberId
            else XMsgNew $ mcSimple (MCText pendingReviewMessage)
    void $ sendDirectMemberMessage mConn msg groupId
  modMs <- withStore' $ \db -> getGroupModerators db cxt user gInfo
  let rcpModMs = filter shouldIntroduceToMod modMs
  introduceMember user gInfo m rcpModMs (Just $ MSMember $ memberId' m)
  where
    shouldIntroduceToMod :: GroupMember -> Bool
    shouldIntroduceToMod mem =
      memberCurrent mem
        && groupMemberId' mem /= groupMemberId' m
        && maxVersion (memberChatVRange mem) >= groupKnockingVersion

introduceToAll :: StoreCxt -> User -> GroupInfo -> GroupMember -> CM ()
introduceToAll cxt user gInfo m = do
  (members, vector) <- withStore $ \db -> liftM2 (,) (liftIO $ getGroupMembers db cxt user gInfo) (getMemberRelationsVector db m)
  let recipients = filter (shouldIntroduce m vector) members
  introduceMember user gInfo m recipients Nothing

introduceToRemaining :: StoreCxt -> User -> GroupInfo -> GroupMember -> CM ()
introduceToRemaining cxt user gInfo m = do
  (members, vector) <- withStore $ \db -> liftM2 (,) (liftIO $ getGroupMembers db cxt user gInfo) (getMemberRelationsVector db m)
  let recipients = filter (shouldIntroduce m vector) members
  introduceMember user gInfo m recipients Nothing

shouldIntroduce :: GroupMember -> ByteString -> GroupMember -> Bool
shouldIntroduce m vec mem =
  memberCurrent mem
    && groupMemberId' mem /= groupMemberId' m
    && getRelation (indexInGroup mem) vec == MRNew

introduceMember :: User -> GroupInfo -> GroupMember -> [GroupMember] -> Maybe MsgScope -> CM ()
introduceMember _ _ GroupMember {activeConn = Nothing} _ _ = throwChatError $ CEInternalError "member connection not active"
introduceMember user gInfo@GroupInfo {groupId} toMember@GroupMember {activeConn = Just conn} introduceToMembers msgScope = do
  void . sendGroupMessage' user gInfo introduceToMembers $ XGrpMemNew (memberInfo gInfo toMember) msgScope
  sendIntroductions introduceToMembers
  where
    sendIntroductions reMembers = do
      updateToMemberVector reMembers
      updateReMembersVectors reMembers
      shuffledReMembers <- liftIO $ shuffleMembers reMembers
      if toMember `supportsVersion` batchSendVersion
        then do
          let events = map (memberIntroEvt gInfo) shuffledReMembers
          forM_ (L.nonEmpty events) $ \events' ->
            sendGroupMemberMessages user gInfo conn events'
        else forM_ shuffledReMembers $ \reMember ->
          void $ sendDirectMemberMessage conn (memberIntroEvt gInfo reMember) groupId
    updateToMemberVector :: [GroupMember] -> CM ()
    updateToMemberVector reMembers = do
      let relations = map (\GroupMember {indexInGroup} -> (indexInGroup, (IDReferencedIntroduced, MRIntroduced))) reMembers
      withStore' $ \db -> setMemberVectorNewRelations db toMember relations
    updateReMembersVectors :: [GroupMember] -> CM ()
    updateReMembersVectors reMembers = do
      let GroupMember {indexInGroup} = toMember
      withStore' $ \db -> setMembersVectorsNewRelation db reMembers indexInGroup IDSubjectIntroduced MRIntroduced
    shuffleMembers :: [GroupMember] -> IO [GroupMember]
    shuffleMembers reMembers = do
      let (admins, others) = partition isAdmin reMembers
          (admPics, admNoPics) = partition hasPicture admins
          (othPics, othNoPics) = partition hasPicture others
      mconcat <$> mapM shuffle [admPics, admNoPics, othPics, othNoPics]
      where
        isAdmin GroupMember {memberRole} = memberRole >= GRAdmin
        hasPicture GroupMember {memberProfile = LocalProfile {image}} = isJust image

memberIntroEvt :: GroupInfo -> GroupMember -> ChatMsgEvent 'Json
memberIntroEvt gInfo reMember =
  let mInfo = memberInfo gInfo reMember
      mRestrictions = memberRestrictions reMember
   in XGrpMemIntro mInfo mRestrictions

serveRoster :: User -> GroupInfo -> GroupMember -> CM ()
serveRoster user gInfo member =
  when (member `supportsVersion` groupRosterVersion) $ do
    cxt <- chatStoreCxt
    withStore' (\db -> getStoredGroupRoster db gInfo) >>= \case
      Just (ownerGMId, brokerTs, sm@SignedMsg {signedBody}, blob_, storedVer_) ->
        case J.eitherDecodeStrict' signedBody :: Either String (ChatMessage 'Json) of
          Left e -> logError $ "serveRoster: cannot decode saved roster message: " <> tshow e
          Right chatMsg@ChatMessage {msgId} ->
            withStore' (\db -> runExceptT $ getGroupMemberById db cxt user ownerGMId) >>= \case
              Right owner -> do
                let fwd = GrpMsgForward {fwdSender = FwdMember (memberId' owner) (memberShortenedName owner), fwdBrokerTs = brokerTs}
                sendFwdMemberMessage member fwd (VMSigned MSSVerified sm chatMsg)
                forM_ ((,) <$> msgId <*> blob_) $ \(sid, blob) ->
                  sendInlineBlobChunks user gInfo [member] sid blob
                forM_ storedVer_ $ \v -> withStore' $ \db -> setMemberRosterServedVersion db member v
              Left e -> logError $ "serveRoster: roster owner not found: " <> tshow e
      Nothing -> pure ()

introduceInChannel :: StoreCxt -> User -> GroupInfo -> GroupMember -> CM ()
introduceInChannel _ _ _ GroupMember {activeConn = Nothing} = throwChatError $ CEInternalError "member connection not active"
introduceInChannel cxt user gInfo subscriber@GroupMember {activeConn = Just conn, indexInGroup = subscriberIdx} = do
  (owners, adminsMods) <- withStore' $ \db ->
    (,) <$> getGroupOwners db cxt user gInfo <*> getGroupAdminsMods db cxt user gInfo
  let modMs = owners <> adminsMods
  void $ sendGroupMessage' user gInfo modMs $ XGrpMemNew (memberInfo gInfo subscriber) Nothing
  withStore' $ \db ->
    setMemberVectorNewRelations db subscriber [(indexInGroup m, (IDSubjectIntroduced, MRIntroduced)) | m <- modMs]
  sendIntros owners
  serveRoster user gInfo subscriber
  sendIntros adminsMods
  withStore' $ \db ->
    setMembersVectorsNewRelation db modMs subscriberIdx IDSubjectIntroduced MRIntroduced
  where
    sendIntros ms = forM_ (L.nonEmpty $ map (memberIntroEvt gInfo) ms) $ \evts ->
      sendGroupMemberMessages user gInfo conn evts

userProfileInGroup :: User -> GroupInfo -> Maybe Profile -> Profile
userProfileInGroup user g = userProfileInGroup' user (Just g)
{-# INLINE userProfileInGroup #-}

userProfileInGroup' :: User -> Maybe GroupInfo -> Maybe Profile -> Profile
userProfileInGroup' User {profile = p} mg incognitoProfile =
  let p' = fromMaybe (fromLocalProfile p) incognitoProfile
   in maybe p' (\g -> redactedMemberProfile g (membership g) p') mg

memberInfo :: GroupInfo -> GroupMember -> MemberInfo
memberInfo g m@GroupMember {memberId, memberRole, memberProfile, memberPubKey, activeConn} =
  MemberInfo
    { memberId,
      memberRole,
      v = ChatVersionRange . peerChatVRange <$> activeConn,
      profile = redactedMemberProfile g m $ fromLocalProfile memberProfile,
      memberKey = MemberKey <$> memberPubKey
    }

redactedMemberProfile :: GroupInfo -> GroupMember -> Profile -> Profile
redactedMemberProfile g m Profile {displayName, fullName, shortDescr, description, image, contactLink = lnk, peerType, badge, contactDomain} =
  Profile {displayName, fullName, shortDescr = removeZeroLink True =<< shortDescr, description = removeZeroLink False =<< description, image, contactLink, preferences = Nothing, peerType, badge, contactDomain = redactedDomain}
  where
    contactLink = if allowZeroLinks then lnk else Nothing
    redactedDomain = if allowDirect then (\d -> d {proof = Nothing} :: ZeroDomainClaim) <$> contactDomain else Nothing
    allowDirect = groupFeatureMemberAllowed SGFDirectMessages m g
    allowZeroLinks = groupFeatureMemberAllowed SGFZeroLinks m g && allowDirect
    removeZeroLink dropOnLink s
      | allowZeroLinks = Just s
      | otherwise = case parseMaybeMarkdownList s of
          Nothing -> dropObfuscated
          Just fts
            | not (any ftIsZeroLink fts) -> dropObfuscated
            | dropOnLink || T.null (T.strip kept) || hasObfuscatedZeroLink kept -> Nothing
            | otherwise -> Just kept
            where
              kept = T.concat $ map (\(FormattedText _ t) -> t) $ filter (not . ftIsZeroLink) fts
      where
        dropObfuscated = if hasObfuscatedZeroLink s then Nothing else Just s

isRosterRole :: GroupMemberRole -> Bool
isRosterRole r = r == GRMember || r == GRModerator || r == GRAdmin

isPrivilegedRole :: GroupMemberRole -> Bool
isPrivilegedRole r = r >= GRMember

roleRequiredToChange :: GroupMemberRole -> GroupMemberRole -> GroupMemberRole
roleRequiredToChange from to
  | from <= GRMember && to <= GRMember = GRModerator
  | otherwise = maximum ([GRAdmin, from, to] :: [GroupMemberRole])

validateGroupRoster :: [RosterMember] -> [RosterMember]
validateGroupRoster entries =
  dedup S.empty $ filter (\RosterMember {role} -> isRosterRole role) entries
  where
    dedup _ [] = []
    dedup seen (rm@RosterMember {memberId} : rms)
      | memberId `S.member` seen = dedup seen rms
      | otherwise = rm : dedup (S.insert memberId seen) rms

buildGroupRoster :: [GroupMember] -> [RosterMember]
buildGroupRoster mods = take maxGroupRosterSize $ mapMaybe rosterMember mods
  where
    rosterMember GroupMember {memberId, memberPubKey, memberRole}
      | isRosterRole memberRole = (\k -> RosterMember {memberId, key = MemberKey k, role = memberRole, privileges = 0}) <$> memberPubKey
      | otherwise = Nothing

sendHistory :: User -> GroupInfo -> GroupMember -> CM ()
sendHistory _ _ GroupMember {activeConn = Nothing} = throwChatError $ CEInternalError "member connection not active"
sendHistory user gInfo@GroupInfo {membership} m@GroupMember {activeConn = Just conn} =
  when (m `supportsVersion` batchSendVersion) $ do
    (errs, items) <- partitionEithers <$> withStore' (\db -> getGroupHistoryItems db user gInfo m 100)
    (errs', fwdMsgsByItem) <- partitionEithers <$> mapM (tryAllErrors . itemForwardMsgs) items
    let errors = map ChatErrorStore errs <> errs'
    unless (null errors) $ toView $ CEvtChatErrors errors
    let fwdEls = map (uncurry encodeFwdElement) (concat fwdMsgsByItem)
    welcomeEl <- welcomeElement
    let (batches, dropped) = batchElements maxEncodedMsgLength (fwdEls <> maybe [] (: []) welcomeEl)
    when (dropped > 0) $ toView $ CEvtChatErrors [ChatError $ CEInternalError ("sendHistory: dropped " <> show dropped <> " oversized history messages")]
    forM_ batches $ \body ->
      void $ withAgent $ \a -> sendMessages a [(aConnId conn, PQEncOff, MsgFlags False, VRValue Nothing body)]
  where
    welcomeElement :: CM (Maybe ByteString)
    welcomeElement = case descrEvent_ of
      Just descr ->
        withStore' (\db -> getMemberJoinRequest db user gInfo m) >>= \case
          Just (_, Just _welcomeMsgId) -> pure Nothing
          _ -> do
            vr <- chatVersionRange
            sharedMsgId <- SharedMsgId <$> drgRandomBytes 24
            case encodeChatMessage maxEncodedMsgLength ChatMessage {chatVRange = vr, msgId = Just sharedMsgId, chatMsgEvent = descr} of
              ECMEncoded body -> pure $ Just (encodeBatchElement Nothing body)
              ECMLarge -> Nothing <$ toView (CEvtChatErrors [ChatError $ CEInternalError "sendHistory: welcome message too large"])
      Nothing -> pure Nothing
    descrEvent_ :: Maybe (ChatMsgEvent 'Json)
    descrEvent_
      | useRelays' gInfo = Nothing
      | m `supportsVersion` groupHistoryIncludeWelcomeVersion = do
          let GroupInfo {groupProfile = GroupProfile {description}} = gInfo
          fmap (\descr -> XMsgNew $ mcSimple (MCText descr)) description
      | otherwise = Nothing
    itemForwardMsgs :: (CChatItem 'CTGroup, (Maybe SignedMsg, Maybe GroupMemberId)) -> CM [(GrpMsgForward, VerifiedMsg 'Json)]
    itemForwardMsgs (cci, (signedMsg_, signedByGMId_)) = case cci of
      (CChatItem SMDRcv ci@ChatItem {content = CIRcvMsgContent mc, file})
        | not (maybe False blockedByAdmin (chatItemRcvFromMember ci)) -> do
            fInvDescr_ <- join <$> forM file getRcvFileInvDescr
            member_ <- maybe (resolveAuthor signedByGMId_) (pure . Just) (chatItemRcvFromMember ci)
            processContentItem member_ ci mc fInvDescr_
        | otherwise -> pure []
      (CChatItem SMDSnd ci@ChatItem {content = CISndMsgContent mc, file, meta = CIMeta {showGroupAsSender}}) -> do
        fInvDescr_ <- join <$> forM file getSndFileInvDescr
        let member_ = if showGroupAsSender && isNothing signedMsg_ then Nothing else Just membership
        processContentItem member_ ci mc fInvDescr_
      _ -> pure []
      where
        resolveAuthor :: Maybe GroupMemberId -> CM (Maybe GroupMember)
        resolveAuthor Nothing = pure Nothing
        resolveAuthor (Just gmId) = do
          cxt <- chatStoreCxt
          eitherToMaybe <$> withStore' (\db -> runExceptT $ getGroupMemberById db cxt user gmId)
        getRcvFileInvDescr :: CIFile 'MDRcv -> CM (Maybe (FileInvitation, RcvFileDescrText))
        getRcvFileInvDescr ciFile@CIFile {fileId, fileProtocol, fileStatus} = do
          expired <- fileExpired
          if fileProtocol /= FPXFTP || fileStatus == CIFSRcvCancelled || expired
            then pure Nothing
            else do
              rfd <- withStore $ \db -> getRcvFileDescrByRcvFileId db fileId
              pure $ invCompleteDescr ciFile rfd
        getSndFileInvDescr :: CIFile 'MDSnd -> CM (Maybe (FileInvitation, RcvFileDescrText))
        getSndFileInvDescr ciFile@CIFile {fileId, fileProtocol, fileStatus} = do
          expired <- fileExpired
          if fileProtocol /= FPXFTP || fileStatus == CIFSSndCancelled || expired
            then pure Nothing
            else do
              rfd <- withStore $ \db -> getRcvFileDescrBySndFileId db fileId
              pure $ invCompleteDescr ciFile rfd
        fileExpired :: CM Bool
        fileExpired = do
          ttl <- asks $ rcvFilesTTL . agentConfig . config
          cutoffTs <- addUTCTime (-ttl) <$> liftIO getCurrentTime
          pure $ chatItemTs cci < cutoffTs
        invCompleteDescr :: CIFile d -> RcvFileDescr -> Maybe (FileInvitation, RcvFileDescrText)
        invCompleteDescr CIFile {fileName, fileSize} RcvFileDescr {fileDescrText, fileDescrComplete}
          | fileDescrComplete =
              let fInvDescr = FileDescr {fileDescrText = "", fileDescrPartNo = 0, fileDescrComplete = False}
                  fInv = xftpFileInvitation fileName fileSize fInvDescr
               in Just (fInv, fileDescrText)
          | otherwise = Nothing
        processContentItem :: Maybe GroupMember -> ChatItem 'CTGroup d -> MsgContent -> Maybe (FileInvitation, RcvFileDescrText) -> CM [(GrpMsgForward, VerifiedMsg 'Json)]
        processContentItem member_ ChatItem {formattedText, meta, quotedItem, mentions} mc fInvDescr_ =
          if isNothing fInvDescr_ && not (msgContentHasText mc)
            then pure []
            else do
              let CIMeta {itemTs, itemSharedMsgId, itemTimed, showGroupAsSender} = meta
                  quotedItemId_ = quoteItemId =<< quotedItem
                  fInv_ = fst <$> fInvDescr_
                  (mc', _, mentions') = updatedMentionNames mc formattedText mentions
                  mentions'' = M.map (\CIMention {memberId} -> MsgMention {memberId}) mentions'
                  senderVRange = maybe (memberChatVRange' membership) memberChatVRange' member_
                  fwdSender = maybe FwdChannel (\am -> FwdMember (memberId' am) (memberShortenedName am)) member_
                  fwd = GrpMsgForward {fwdSender, fwdBrokerTs = itemTs}
              contentVM <- case signedMsg_ of
                Just sm@SignedMsg {signedBody}
                  | Right chatMsg <- (J.eitherDecodeStrict' signedBody :: Either String (ChatMessage 'Json)) ->
                      pure $ VMSigned MSSVerified sm chatMsg
                _ -> do
                  (chatMsgEvent, _) <- withStore $ \db -> prepareGroupMsg db user gInfo Nothing showGroupAsSender mc' mentions'' quotedItemId_ Nothing fInv_ itemTimed False
                  pure $ VMUnsigned ChatMessage {chatVRange = senderVRange, msgId = itemSharedMsgId, chatMsgEvent}
              fileDescrEvents <- case (snd <$> fInvDescr_, itemSharedMsgId) of
                (Just fileDescrText, Just msgId) -> do
                  partSize <- asks $ xftpDescrPartSize . config
                  let parts = splitFileDescr partSize fileDescrText
                  pure . L.toList $ L.map (XMsgFileDescr msgId) parts
                _ -> pure []
              let fileDescrVMs = map (VMUnsigned . ChatMessage senderVRange Nothing) fileDescrEvents
              pure $ map ((,) fwd) (contentVM : fileDescrVMs)

memberShortenedName :: GroupMember -> ContactName
memberShortenedName GroupMember {memberProfile = LocalProfile {displayName}}
  | T.length displayName <= 16 = displayName
  | otherwise = T.take 16 displayName `T.snoc` '…'

splitFileDescr :: Int -> RcvFileDescrText -> NonEmpty FileDescr
splitFileDescr partSize rfdText = splitParts 1 rfdText
  where
    splitParts partNo remText =
      let (part, rest) = T.splitAt partSize remText
          complete = T.null rest
          fileDescr = FileDescr {fileDescrText = part, fileDescrPartNo = partNo, fileDescrComplete = complete}
       in if complete
            then fileDescr :| []
            else fileDescr <| splitParts (partNo + 1) rest

setGroupLinkData' :: NetworkRequestMode -> User -> GroupInfo -> CM (Maybe GroupLink)
setGroupLinkData' nm user gInfo =
  withFastStore' (\db -> runExceptT $ getGroupLink db user gInfo) >>= \case
    Right gLink@GroupLink {shortLinkDataSet}
      | shortLinkDataSet -> Just <$> setGroupLinkData nm user gInfo gLink
    _ -> pure Nothing

setGroupLinkData :: NetworkRequestMode -> User -> GroupInfo -> GroupLink -> CM GroupLink
setGroupLinkData nm user gInfo gLink = do
  cxt <- chatStoreCxt
  (conn, groupRelays) <- withFastStore $ \db ->
    (,) <$> getGroupLinkConnection db cxt user gInfo <*> liftIO (getPublishableGroupRelays db cxt user gInfo)
  let (userLinkData, crClientData) = groupLinkData gInfo gLink groupRelays
      linkType = if useRelays' gInfo then CCTChannel else CCTGroup
  sLnk <- shortenShortLink' . setShortLinkType_ linkType =<< withAgent (\a -> setConnShortLink a nm (aConnId conn) SCMContact userLinkData (Just crClientData))
  withFastStore' $ \db -> setGroupLinkShortLink db gLink sLnk

setGroupLinkDataAsync :: User -> GroupInfo -> GroupLink -> CM ()
setGroupLinkDataAsync user gInfo gLink = do
  cxt <- chatStoreCxt
  (conn, groupRelays) <- withStore $ \db ->
    (,) <$> getGroupLinkConnection db cxt user gInfo <*> liftIO (getPublishableGroupRelays db cxt user gInfo)
  let (userLinkData, crClientData) = groupLinkData gInfo gLink groupRelays
  setAgentConnShortLinkAsync user conn userLinkData (Just crClientData)

connectToRelayAsync :: User -> GroupInfo -> ShortLinkContact -> CM ()
connectToRelayAsync user gInfo relayLink = do
  cxt <- chatStoreCxt
  gVar <- asks random
  relayMember@GroupMember {activeConn} <- withFastStore $ \db -> getCreateRelayForMember db cxt gVar user gInfo relayLink
  case activeConn of
    Just _ -> pure ()
    Nothing -> do
      subMode <- chatReadVar subscriptionMode
      newConnIds <- getAgentConnShortLinkAsync user CFGetRelayDataJoin Nothing relayLink
      withFastStore' $ \db -> createRelayMemberConnectionAsync db user gInfo relayMember relayLink newConnIds subMode

updatePublicGroupData :: User -> GroupInfo -> CM GroupInfo
updatePublicGroupData user gInfo
  | useRelays' gInfo && memberRole' (membership gInfo) == GROwner = do
      cxt <- chatStoreCxt
      (gInfo', gLink) <- withStore $ \db -> do
        gInfo' <- updatePublicMemberCount db cxt user gInfo
        gLink <- getGroupLink db user gInfo'
        pure (gInfo', gLink)
      setGroupLinkDataAsync user gInfo' gLink
      pure gInfo'
  | useRelays' gInfo && isRelay (membership gInfo) = do
      cxt <- chatStoreCxt
      withStore $ \db -> updatePublicMemberCount db cxt user gInfo
  | otherwise = pure gInfo

updateGroupFromLinkData :: User -> GroupInfo -> GroupShortLinkData -> Maybe ZeroDomain -> CM (GroupInfo, Bool)
updateGroupFromLinkData user gInfo@GroupInfo {groupProfile = p, groupSummary = GroupSummary {publicMemberCount = localCount}} GroupShortLinkData {groupProfile, publicGroupData} resolvedDomain_
  | profileChanged || countChanged || verifyResolved = do
      cxt <- chatStoreCxt
      withStore $ \db -> do
        g <- if profileChanged then updateGroupProfile db user gInfo groupProfile else pure gInfo
        g' <- case publicGroupData of
          Just PublicGroupData {publicMemberCount} | countChanged ->
            setPublicMemberCount db cxt user g publicMemberCount
          _ -> pure g
        g'' <- if verifyResolved then liftIO $ setGroupDomainVerified db user g' True else pure g'
        pure (g'', profileChanged)
  | otherwise = pure (gInfo, False)
  where
    profileChanged = p /= groupProfile
    countChanged = case publicGroupData of
      Just PublicGroupData {publicMemberCount} -> Just publicMemberCount /= localCount
      _ -> False
    groupClaim GroupProfile {publicGroup} = claimDomain <$> (publicGroup >>= publicGroupAccess >>= groupDomainClaim)
    newClaim = groupClaim groupProfile
    verifyResolved = isJust resolvedDomain_ && resolvedDomain_ == newClaim

updateContactFromLinkData :: User -> Contact -> Profile -> CM Contact
updateContactFromLinkData user ct@Contact {profile = profile@LocalProfile {contactDomain = prevClaim, contactDomainVerified}} linkProfile@Profile {contactDomain = newClaim}
  | profileChanged || verifyChanged = do
      cxt <- chatStoreCxt
      withFastStore $ \db -> do
        ct' <- updateContactProfile db cxt user ct linkProfile
        if verifyChanged then liftIO $ setContactDomainVerified db user ct' True else pure ct'
  | otherwise = pure ct
  where
    profileChanged = fromLocalProfile profile /= linkProfile
    claimChanged = (claimDomain <$> prevClaim) /= (claimDomain <$> newClaim)
    verifyChanged = contactDomainVerified /= Just True || claimChanged

groupLinkData :: GroupInfo -> GroupLink -> [GroupRelay] -> (UserConnLinkData 'CMContact, CRClientData)
groupLinkData gInfo@GroupInfo {groupProfile, groupSummary = GroupSummary {publicMemberCount}, membership = GroupMember {memberId}, groupKeys} GroupLink {groupLinkId} groupRelays =
  let direct = not $ useRelays' gInfo
      relays = mapMaybe (\GroupRelay {relayLink} -> relayLink) groupRelays
      publicGroupData_ = PublicGroupData <$> publicMemberCount
      userData = encodeShortLinkData $ GroupShortLinkData {groupProfile, publicGroupData = publicGroupData_}
      owners = case groupKeys of
        Just GroupKeys {groupRootKey = GRKPrivate rootPrivKey, memberPrivKey} ->
          let ownerId = unMemberId memberId
              ownerKey = C.publicKey memberPrivKey
              authOwnerSig = C.sign' rootPrivKey (ownerId <> C.encodePubKey ownerKey)
           in [OwnerAuth {ownerId, ownerKey, authOwnerSig}]
        _ -> []
      userLinkData = UserContactLinkData UserContactData {direct, owners, relays, userData}
      crClientData = encodeJSON $ CRDataGroup groupLinkId
   in (userLinkData, crClientData)

restoreShortLink' :: ConnShortLink m -> CM (ConnShortLink m)
restoreShortLink' l = (`restoreShortLink` l) <$> asks (shortLinkPresetServers . config)

getShortLinkConnReq' :: NetworkRequestMode -> User -> ConnShortLink m -> CM (FixedLinkData m, ConnLinkData m)
getShortLinkConnReq' nm user l = do
  l' <- restoreShortLink' l
  withAgent $ \a -> getConnShortLink a nm (aUserId user) l'

getShortLinkConnReq :: NetworkRequestMode -> User -> ConnShortLink m -> CM (FixedLinkData m, ConnLinkData m)
getShortLinkConnReq nm user l = do
  (fd, cData) <- getShortLinkConnReq' nm user l
  case cData of
    ContactLinkData _ UserContactData {direct, relays}
      | not supported -> throwChatError CEUnsupportedConnReq
      where
        supported = direct || not (null relays)
    _ -> pure ()
  pure (fd, cData)

encodeShortLinkData :: J.ToJSON a => a -> UserLinkData
encodeShortLinkData d =
  let s = LB.toStrict $ J.encode d
      s'
        | B.length s > 10240 = B.cons 'X' $ Z1.compress compressionLevel s
        | otherwise = s
   in UserLinkData s'

decodeLinkUserData :: J.FromJSON a => ConnLinkData c -> IO (Maybe a)
decodeLinkUserData cData
  | B.null s = pure Nothing
  | B.head s == 'X' = case limitDecompress' maxDecompressedMsgLength $ B.drop 1 s of
      Left e -> Nothing <$ logError ("Error decompressing link data: " <> tshow e)
      Right s' -> decode s'
  | otherwise = decode s
  where
    decode s' = case J.eitherDecodeStrict s' of
      Right d -> pure $ Just d
      Left e -> Nothing <$ logError ("Error decoding link data: " <> tshow e)
    s = linkUserData' cData

shortenShortLink' :: ConnShortLink m -> CM (ConnShortLink m)
shortenShortLink' l = (`shortenShortLink` l) <$> asks (shortLinkPresetServers . config)

shortenCreatedLink :: CreatedConnLink m -> CM (CreatedConnLink m)
shortenCreatedLink (CCLink cReq sLnk) = CCLink cReq <$> mapM shortenShortLink' sLnk

deleteGroupLink' :: User -> GroupInfo -> CM ()
deleteGroupLink' user gInfo = do
  cxt <- chatStoreCxt
  conn <- withStore $ \db -> getGroupLinkConnection db cxt user gInfo
  deleteGroupLink_ user gInfo conn

deleteGroupLinkIfExists :: User -> GroupInfo -> CM ()
deleteGroupLinkIfExists user gInfo = do
  cxt <- chatStoreCxt
  conn_ <- eitherToMaybe <$> withStore' (\db -> runExceptT $ getGroupLinkConnection db cxt user gInfo)
  mapM_ (deleteGroupLink_ user gInfo) conn_

deleteGroupLink_ :: User -> GroupInfo -> Connection -> CM ()
deleteGroupLink_ user gInfo conn = do
  deleteAgentConnectionAsync $ aConnId conn
  withStore' $ \db -> deleteGroupLink db user gInfo

startProximateTimedItemThread :: User -> (ChatRef, ChatItemId) -> UTCTime -> CM ()
startProximateTimedItemThread user itemRef deleteAt = do
  interval <- asks (cleanupManagerInterval . config)
  ts <- liftIO getCurrentTime
  when (diffUTCTime deleteAt ts <= interval) $
    startTimedItemThread user itemRef deleteAt

startTimedItemThread :: User -> (ChatRef, ChatItemId) -> UTCTime -> CM ()
startTimedItemThread user itemRef deleteAt = do
  itemThreads <- asks timedItemThreads
  threadTVar_ <- atomically $ do
    exists <- TM.member itemRef itemThreads
    if not exists
      then do
        threadTVar <- newTVar Nothing
        TM.insert itemRef threadTVar itemThreads
        pure $ Just threadTVar
      else pure Nothing
  forM_ threadTVar_ $ \threadTVar -> do
    tId <- mkWeakThreadId =<< deleteTimedItem user itemRef deleteAt `forkFinally` const (atomically $ TM.delete itemRef itemThreads)
    atomically $ writeTVar threadTVar (Just tId)

deleteTimedItem :: User -> (ChatRef, ChatItemId) -> UTCTime -> CM ()
deleteTimedItem user (ChatRef cType chatId scope, itemId) deleteAt = do
  ts <- liftIO getCurrentTime
  liftIO $ threadDelay' $ diffToMicroseconds $ diffUTCTime deleteAt ts
  lift waitChatStartedAndActivated
  cxt <- chatStoreCxt
  case cType of
    CTDirect -> do
      (ct, ci) <- withStore $ \db -> (,) <$> getContact db cxt user chatId <*> getDirectChatItem db user chatId itemId
      deletions <- deleteDirectCIs user ct [ci]
      toView $ CEvtChatItemsDeleted user deletions True True
    CTGroup -> do
      (gInfo, ci) <- withStore $ \db -> (,) <$> getGroupInfo db cxt user chatId <*> getGroupChatItem db user chatId itemId
      deletedTs <- liftIO getCurrentTime
      chatScopeInfo <- mapM (getChatScopeInfo cxt user) scope
      deletions <- deleteGroupCIs user gInfo chatScopeInfo [ci] Nothing deletedTs
      toView $ CEvtChatItemsDeleted user deletions True True
    _ -> eToView $ ChatError $ CEInternalError "bad deleteTimedItem cType"

startUpdatedTimedItemThread :: User -> ChatRef -> ChatItem c d -> ChatItem c d -> CM ()
startUpdatedTimedItemThread user chatRef ci ci' =
  case (chatItemTimed ci >>= timedDeleteAt', chatItemTimed ci' >>= timedDeleteAt') of
    (Nothing, Just deleteAt') ->
      startProximateTimedItemThread user (chatRef, chatItemId' ci') deleteAt'
    _ -> pure ()

metaBrokerTs :: MsgMeta -> UTCTime
metaBrokerTs MsgMeta {broker = (_, brokerTs)} = brokerTs

createContactPQSndItem :: User -> Contact -> Connection -> PQEncryption -> CM (Contact, Connection)
createContactPQSndItem user ct conn@Connection {pqSndEnabled} pqSndEnabled' =
  flip catchAllErrors (const $ pure (ct, conn)) $ case (pqSndEnabled, pqSndEnabled') of
    (Just b, b') | b' /= b -> createPQItem $ CISndConnEvent (SCEPqEnabled pqSndEnabled')
    (Nothing, PQEncOn) -> createPQItem $ CISndDirectE2EEInfo (e2eInfoEncrypted $ Just pqSndEnabled')
    _ -> pure (ct, conn)
  where
    createPQItem ciContent = do
      let conn' = conn {pqSndEnabled = Just pqSndEnabled'} :: Connection
          ct' = ct {activeConn = Just conn'} :: Contact
      when (contactPQEnabled ct /= contactPQEnabled ct') $ do
        createInternalChatItem user (CDDirectSnd ct') ciContent Nothing
        toView $ CEvtContactPQEnabled user ct' pqSndEnabled'
      pure (ct', conn')

updateContactPQRcv :: User -> Contact -> Connection -> PQEncryption -> CM (Contact, Connection)
updateContactPQRcv user ct conn@Connection {connId, pqRcvEnabled} pqRcvEnabled' =
  flip catchAllErrors (const $ pure (ct, conn)) $ case (pqRcvEnabled, pqRcvEnabled') of
    (Just b, b') | b' /= b -> updatePQ $ CIRcvConnEvent (RCEPqEnabled pqRcvEnabled')
    (Nothing, PQEncOn) -> updatePQ $ CIRcvDirectE2EEInfo (e2eInfoEncrypted $ Just pqRcvEnabled')
    _ -> pure (ct, conn)
  where
    updatePQ ciContent = do
      withStore' $ \db -> updateConnPQRcvEnabled db connId pqRcvEnabled'
      let conn' = conn {pqRcvEnabled = Just pqRcvEnabled'} :: Connection
          ct' = ct {activeConn = Just conn'} :: Contact
      when (contactPQEnabled ct /= contactPQEnabled ct') $ do
        createInternalChatItem user (CDDirectRcv ct') ciContent Nothing
        toView $ CEvtContactPQEnabled user ct' pqRcvEnabled'
      pure (ct', conn')

updatePeerChatVRange :: Connection -> VersionRangeChat -> CM Connection
updatePeerChatVRange conn@Connection {connId, connChatVersion = v, peerChatVRange, connType, pqSupport, pqEncryption} msgVRange = do
  v' <- lift $ upgradedConnVersion v msgVRange
  conn' <-
    if msgVRange /= peerChatVRange || v' /= v
      then do
        withStore' $ \db -> setPeerChatVRange db connId v' msgVRange
        pure conn {connChatVersion = v', peerChatVRange = msgVRange}
      else pure conn
  if connType == ConnContact && v' >= pqEncryptionCompressionVersion && (pqSupport /= PQSupportOn || pqEncryption /= PQEncOn)
    then do
      withStore' $ \db -> updateConnSupportPQ db connId PQSupportOn PQEncOn
      pure conn' {pqSupport = PQSupportOn, pqEncryption = PQEncOn}
    else pure conn'

updateMemberChatVRange :: GroupMember -> Connection -> VersionRangeChat -> CM (GroupMember, Connection)
updateMemberChatVRange mem@GroupMember {groupMemberId, memberChatVRange} conn@Connection {connId, connChatVersion = v, peerChatVRange} msgVRange = do
  v' <- lift $ upgradedConnVersion v msgVRange
  if msgVRange /= peerChatVRange || v' /= v || msgVRange /= memberChatVRange
    then do
      withStore' $ \db -> do
        setPeerChatVRange db connId v' msgVRange
        setMemberChatVRange db groupMemberId msgVRange
      let conn' = conn {connChatVersion = v', peerChatVRange = msgVRange}
      pure (mem {memberChatVRange = msgVRange, activeConn = Just conn'}, conn')
    else pure (mem, conn)

upgradedConnVersion :: VersionChat -> VersionRangeChat -> CM' VersionChat
upgradedConnVersion v peerVR = do
  vr <- chatVersionRange'
  pure $ maybe v (\(Compatible v') -> max v v') $ vr `compatibleVersion` peerVR

parseFileDescription :: FilePartyI p => Text -> CM (ValidFileDescription p)
parseFileDescription =
  liftEither . first (ChatError . CEInvalidFileDescription) . (strDecode . encodeUtf8)

fileDescrServers :: ValidFileDescription p -> [XFTPServer]
fileDescrServers (FD.ValidFileDescription FD.FileDescription {chunks}) =
  S.toList $ S.fromList $ concatMap (\FD.FileChunk {replicas} -> map (\FD.FileChunkReplica {server} -> server) replicas) chunks

getChatItemFileServers :: User -> SMsgDirection d -> ChatItem c d -> CM [XFTPServer]
getChatItemFileServers user dir ci = case ci of
  ChatItem {file = Just CIFile {fileId, fileProtocol = FPXFTP}} ->
    itemFileServers fileId `catchAllErrors` \_ -> pure []
  _ -> pure []
  where
    itemFileServers fileId = case dir of
      SMDSnd -> do
        sfd_ <- withStore' $ \db -> getSndFTPrivateSndDescr db user fileId
        case sfd_ of
          Just sfdText -> fileDescrServers <$> (parseFileDescription sfdText :: CM (ValidFileDescription 'FSender))
          Nothing -> pure []
      SMDRcv -> do
        RcvFileDescr {fileDescrText} <- withStore $ \db -> getRcvFileDescrByRcvFileId db fileId
        fileDescrServers <$> (parseFileDescription fileDescrText :: CM (ValidFileDescription 'FRecipient))

sendDirectFileInline :: User -> Contact -> FileTransferMeta -> SharedMsgId -> CM ()
sendDirectFileInline user ct ft sharedMsgId = do
  msgDeliveryId <- sendFileInline_ ft sharedMsgId $ sendDirectContactMessage user ct
  withStore $ \db -> updateSndDirectFTDelivery db ct ft msgDeliveryId

sendMemberFileInline :: GroupMember -> Connection -> FileTransferMeta -> SharedMsgId -> CM ()
sendMemberFileInline m@GroupMember {groupId} conn ft sharedMsgId = do
  msgDeliveryId <- sendFileInline_ ft sharedMsgId $ \msg -> do
    (sndMsg, msgDeliveryId, _) <- sendDirectMemberMessage conn msg groupId
    pure (sndMsg, msgDeliveryId)
  withStore' $ \db -> updateSndGroupFTDelivery db m conn ft msgDeliveryId

sendFileInline_ :: FileTransferMeta -> SharedMsgId -> (ChatMsgEvent 'Binary -> CM (SndMessage, Int64)) -> CM Int64
sendFileInline_ FileTransferMeta {filePath, chunkSize} sharedMsgId sendMsg =
  sendChunks 1 =<< liftIO . B.readFile =<< lift (toFSFilePath filePath)
  where
    sendChunks chunkNo bytes = do
      let (chunk, rest) = B.splitAt chSize bytes
      (_, msgDeliveryId) <- sendMsg $ BFileChunk sharedMsgId $ FileChunk chunkNo chunk
      if B.null rest
        then pure msgDeliveryId
        else sendChunks (chunkNo + 1) rest
    chSize = fromIntegral chunkSize

parseChatMessage :: Connection -> ByteString -> CM (ChatMessage 'Json)
parseChatMessage conn s = snd <$> parseChatMessage' conn s
{-# INLINE parseChatMessage #-}

parseChatMessage' :: Connection -> ByteString -> CM (Maybe SignedMsg, ChatMessage 'Json)
parseChatMessage' conn s =
  case parseChatMessages s of
    [msg] -> liftEither . first (ChatError . errType) $ (\(APMsg _ (ParsedMsg _ sm m)) -> (sm,) <$> checkEncoding m) =<< msg
    _ -> throwChatError $ CEException "parseChatMessage: single message is expected"
  where
    errType = CEInvalidChatMessage conn Nothing (safeDecodeUtf8 s)

getChatScopeInfo :: StoreCxt -> User -> GroupChatScope -> CM GroupChatScopeInfo
getChatScopeInfo cxt user = \case
  GCSMemberSupport Nothing -> pure $ GCSIMemberSupport Nothing
  GCSMemberSupport (Just gmId) -> do
    supportMem <- withFastStore $ \db -> getGroupMemberById db cxt user gmId
    pure $ GCSIMemberSupport (Just supportMem)

getGroupRecipients :: StoreCxt -> User -> GroupInfo -> Maybe GroupChatScopeInfo -> VersionChat -> CM [GroupMember]
getGroupRecipients cxt user gInfo@GroupInfo {membership} scopeInfo modsCompatVersion
  | useRelays' gInfo && not (isRelay membership) = do
      unless (memberCurrent membership && memberActive membership) $ throwChatError $ CECommandError "not current member"
      withFastStore' $ \db -> getGroupRelayMembers db cxt user gInfo
  | otherwise = case scopeInfo of
      Nothing -> do
        unless (memberCurrent membership && memberActive membership) $ throwChatError $ CECommandError "not current member"
        ms <- withFastStore' $ \db -> getGroupMembers db cxt user gInfo
        pure $ filter memberCurrent ms
      Just (GCSIMemberSupport Nothing) -> do
        modMs <- withFastStore' $ \db -> getGroupModerators db cxt user gInfo
        let rcpModMs' = filter (\m -> compatible m && memberCurrent m) modMs
        when (null rcpModMs') $ throwChatError $ CECommandError "no admins support this message"
        pure rcpModMs'
      Just (GCSIMemberSupport (Just supportMem)) -> do
        unless (memberCurrent membership && memberActive membership) $ throwChatError $ CECommandError "not current member"
        unless (memberCurrentOrPending supportMem) $ throwChatError $ CECommandError "support member not current or pending"
        if memberStatus supportMem == GSMemPendingApproval
          then pure [supportMem]
          else do
            modMs <- withFastStore' $ \db -> getGroupModerators db cxt user gInfo
            let rcpModMs' = filter (\m -> compatible m && memberCurrent m) modMs
            pure $ [supportMem] <> rcpModMs'
  where
    compatible GroupMember {activeConn, memberChatVRange} =
      maxVersion (maybe memberChatVRange peerChatVRange activeConn) >= modsCompatVersion

mkLocalGroupChatScope :: GroupInfo -> CM (GroupInfo, Maybe GroupChatScopeInfo)
mkLocalGroupChatScope gInfo@GroupInfo {membership}
  | memberPending membership = do
      (gInfo', scopeInfo) <- mkGroupSupportChatInfo gInfo
      pure (gInfo', Just scopeInfo)
  | otherwise =
      pure (gInfo, Nothing)

mkGroupChatScope :: GroupInfo -> GroupMember -> CM (GroupInfo, GroupMember, Maybe GroupChatScopeInfo)
mkGroupChatScope gInfo@GroupInfo {membership} m
  | memberPending membership = do
      (gInfo', scopeInfo) <- mkGroupSupportChatInfo gInfo
      pure (gInfo', m, Just scopeInfo)
  | memberPending m = do
      (m', scopeInfo) <- mkMemberSupportChatInfo m
      pure (gInfo, m', Just scopeInfo)
  | otherwise =
      pure (gInfo, m, Nothing)

mkGetMessageChatScope :: StoreCxt -> User -> GroupInfo -> GroupMember -> MsgContent -> Maybe MsgScope -> CM (GroupInfo, GroupMember, Maybe GroupChatScopeInfo)
mkGetMessageChatScope cxt user gInfo@GroupInfo {membership} m mc msgScope_ =
  mkGroupChatScope gInfo m >>= \case
    groupScope@(_gInfo', _m', Just _scopeInfo) -> pure groupScope
    (_, _, Nothing)
      | isReport mc -> do
          (_m', scopeInfo) <- mkMemberSupportChatInfo m
          pure (gInfo, m, Just scopeInfo)
      | otherwise -> case msgScope_ of
          Nothing -> pure (gInfo, m, Nothing)
          Just (MSMember mId)
            | sameMemberId mId membership -> do
                (gInfo', scopeInfo) <- mkGroupSupportChatInfo gInfo
                pure (gInfo', m, Just scopeInfo)
            | otherwise -> do
                referredMember <- withStore $ \db -> getGroupMemberByMemberId db cxt user gInfo mId
                (_referredMember', scopeInfo) <- mkMemberSupportChatInfo referredMember
                pure (gInfo, m, Just scopeInfo)

mkGroupSupportChatInfo :: GroupInfo -> CM (GroupInfo, GroupChatScopeInfo)
mkGroupSupportChatInfo gInfo@GroupInfo {membership} =
  case supportChat membership of
    Nothing -> do
      chatTs <- liftIO getCurrentTime
      withStore' $ \db -> setSupportChatTs db (groupMemberId' membership) chatTs
      let gInfo' = gInfo {membership = membership {supportChat = Just $ GroupSupportChat chatTs 0 0 0 Nothing}}
          scopeInfo = GCSIMemberSupport {groupMember_ = Nothing}
      pure (gInfo', scopeInfo)
    Just _supportChat ->
      let scopeInfo = GCSIMemberSupport {groupMember_ = Nothing}
       in pure (gInfo, scopeInfo)

mkMemberSupportChatInfo :: GroupMember -> CM (GroupMember, GroupChatScopeInfo)
mkMemberSupportChatInfo m@GroupMember {groupMemberId, supportChat} =
  case supportChat of
    Nothing -> do
      chatTs <- liftIO getCurrentTime
      withStore' $ \db -> setSupportChatTs db groupMemberId chatTs
      let m' = m {supportChat = Just $ GroupSupportChat chatTs 0 0 0 Nothing}
          scopeInfo = GCSIMemberSupport {groupMember_ = Just m'}
      pure (m', scopeInfo)
    Just _supportChat ->
      let scopeInfo = GCSIMemberSupport {groupMember_ = Just m}
       in pure (m, scopeInfo)

appendFileChunk :: RcvFileTransfer -> Integer -> ByteString -> Bool -> CM ()
appendFileChunk ft@RcvFileTransfer {fileId, fileStatus, cryptoArgs, fileInvitation = FileInvitation {fileName}} chunkNo chunk final =
  case fileStatus of
    RFSConnected filePath -> append_ filePath
    RFSAccepted filePath -> append_ filePath
    RFSCancelled _ -> pure ()
    _ -> throwChatError $ CEFileInternal "receiving file transfer not in progress"
  where
    append_ :: FilePath -> CM ()
    append_ filePath = do
      fsFilePath <- lift $ toFSFilePath filePath
      h <- getFileHandle fileId fsFilePath rcvFiles AppendMode
      liftIO (B.hPut h chunk >> hFlush h) `catchThrow` (fileErr . show)
      withStore' $ \db -> updatedRcvFileChunkStored db ft chunkNo
      when final $ do
        lift $ closeFileHandle fileId rcvFiles
        forM_ cryptoArgs $ \cfArgs -> do
          tmpFile <- lift getChatTempDirectory >>= liftIO . (`uniqueCombine` fileName)
          tryAllErrors (liftError encryptErr $ encryptFile fsFilePath tmpFile cfArgs) >>= \case
            Right () -> do
              removeFile fsFilePath `catchAllErrors` \_ -> pure ()
              renameFile tmpFile fsFilePath
            Left e -> do
              eToView e
              removeFile tmpFile `catchAllErrors` \_ -> pure ()
              withStore' (`removeFileCryptoArgs` fileId)
      where
        encryptErr e = fileErr $ e <> ", received file not encrypted"
        fileErr = ChatError . CEFileWrite filePath

getFileHandle :: Int64 -> FilePath -> (ChatController -> TVar (Map Int64 Handle)) -> IOMode -> CM Handle
getFileHandle fileId filePath files ioMode = do
  fs <- asks files
  h_ <- M.lookup fileId <$> readTVarIO fs
  maybe (newHandle fs) pure h_
  where
    newHandle fs = do
      h <- openFile filePath ioMode `catchThrow` (ChatError . CEFileInternal . show)
      atomically . modifyTVar fs $ M.insert fileId h
      pure h

isFileActive :: Int64 -> (ChatController -> TVar (Map Int64 Handle)) -> CM Bool
isFileActive fileId files = do
  fs <- asks files
  isJust . M.lookup fileId <$> readTVarIO fs

cancelRcvFileTransfer :: User -> RcvFileTransfer -> CM ()
cancelRcvFileTransfer user ft@RcvFileTransfer {fileId, xftpRcvFile} =
  cancel' `catchAllErrors` \e -> eToView e
  where
    cancel' = do
      lift $ closeFileHandle fileId rcvFiles
      withStore' $ \db -> do
        updateFileCancelled db user fileId CIFSRcvCancelled
        updateRcvFileStatus db fileId FSCancelled
        deleteRcvFileChunks db ft
      case xftpRcvFile of
        Just XFTPRcvFile {agentRcvFileId = Just (AgentRcvFileId aFileId), agentRcvFileDeleted} ->
          unless agentRcvFileDeleted $ agentXFTPDeleteRcvFile aFileId fileId
        _ -> pure ()

cancelSndFile :: User -> FileTransferMeta -> [SndFileTransfer] -> Bool -> CM ()
cancelSndFile user FileTransferMeta {fileId, xftpSndFile} fts sendCancel = do
  withStore' (\db -> updateFileCancelled db user fileId CIFSSndCancelled)
    `catchAllErrors` eToView
  case xftpSndFile of
    Nothing ->
      forM_ fts (\ft -> cancelSndFileTransfer user ft sendCancel)
    Just xsf -> do
      forM_ fts (\ft -> cancelSndFileTransfer user ft False)
      lift (agentXFTPDeleteSndFileRemote user xsf fileId) `catchAllErrors` eToView

cancelSndFileTransfer :: User -> SndFileTransfer -> Bool -> CM ()
cancelSndFileTransfer user@User {userId} ft@SndFileTransfer {fileId, connId, fileStatus, fileInline} sendCancel =
  unless (fileStatus == FSCancelled || fileStatus == FSComplete) $
    cancel' `catchAllErrors` \e -> eToView e
  where
    cancel' = do
      withStore' $ \db -> updateSndFileStatus db ft FSCancelled
      when sendCancel $ case fileInline of
        Just _ -> do
          cxt <- chatStoreCxt
          (sharedMsgId, conn) <- withStore $ \db -> (,) <$> getSharedMsgIdByFileId db userId fileId <*> getConnectionById db cxt user connId
          void $ sendDirectMessage_ conn (BFileChunk sharedMsgId FileChunkCancel) (ConnectionId connId)
        _ -> throwChatError $ CEException "cancelSndFileTransfer: cancelling file via a separate connection is deprecated"

closeFileHandle :: Int64 -> (ChatController -> TVar (Map Int64 Handle)) -> CM' ()
closeFileHandle fileId files = do
  fs <- asks files
  h_ <- atomically . stateTVar fs $ \m -> (M.lookup fileId m, M.delete fileId m)
  liftIO $ mapM_ hClose h_ `catchAll_` pure ()

cleanupGroupRosterFile :: User -> GroupInfo -> CM ()
cleanupGroupRosterFile User {userId} GroupInfo {groupId} = do
  infos <- withStore' $ \db -> getGroupRosterFileInfo db userId groupId
  forM_ infos $ \(fileId, filePath_) -> do
    lift $ closeFileHandle fileId rcvFiles
    forM_ filePath_ removeFsFile
  withStore' $ \db -> do
    deleteGroupRosterFile db userId groupId
    deleteGroupRosterTransfers db groupId

cleanupRosterTransfer :: GroupInfo -> GroupMemberId -> CM ()
cleanupRosterTransfer gInfo fromMemberId =
  withStore' (\db -> getRosterTransferId db gInfo fromMemberId) >>= mapM_ cleanupRosterTransferById

cleanupRosterTransferById :: Int64 -> CM ()
cleanupRosterTransferById transferId = do
  file_ <- withStore' $ \db -> getRosterTransferFile db transferId
  forM_ file_ $ \(fileId, filePath_) -> do
    lift $ closeFileHandle fileId rcvFiles
    forM_ filePath_ removeFsFile
  withStore' $ \db -> do
    deleteRosterTransferFile db transferId
    deleteRosterTransfer db transferId

resetRosterPartialChunks :: RcvFileTransfer -> CM ()
resetRosterPartialChunks ft@RcvFileTransfer {fileId, fileStatus} = do
  lift $ closeFileHandle fileId rcvFiles
  forM_ (rcvFilePath fileStatus) removeFsFile
  withStore' $ \db -> deleteRcvFileChunks db ft
  where
    rcvFilePath = \case
      RFSAccepted p -> Just p
      RFSConnected p -> Just p
      _ -> Nothing

removeFsFile :: FilePath -> CM ()
removeFsFile fp = do
  p <- lift $ toFSFilePath fp
  removeFile p `catchAllErrors` \_ -> pure ()

deleteMembersConnections :: User -> [GroupMember] -> CM ()
deleteMembersConnections user members = deleteMembersConnections' user members False

deleteMembersConnections' :: User -> [GroupMember] -> Bool -> CM ()
deleteMembersConnections' user members waitDelivery = do
  let memberConns = mapMaybe (\GroupMember {activeConn} -> activeConn) members
  deleteAgentConnectionsAsync' (map aConnId memberConns) waitDelivery
  lift . void . withStoreBatch' $ \db -> map (\Connection {connId} -> deleteConnectionRecord db user connId) memberConns

deleteMemberConnection :: GroupMember -> CM ()
deleteMemberConnection mem = deleteMemberConnection' mem False

deleteMemberConnection' :: GroupMember -> Bool -> CM ()
deleteMemberConnection' GroupMember {activeConn} waitDelivery = do
  forM_ activeConn $ \conn -> do
    deleteAgentConnectionAsync' (aConnId conn) waitDelivery
    withStore' $ \db -> updateConnectionStatus db conn ConnDeleted

deleteOrUpdateMemberRecord :: User -> GroupInfo -> GroupMember -> CM GroupInfo
deleteOrUpdateMemberRecord user gInfo m =
  withStore' $ \db -> deleteOrUpdateMemberRecordIO db user gInfo m

deleteOrUpdateMemberRecordIO :: DB.Connection -> User -> GroupInfo -> GroupMember -> IO GroupInfo
deleteOrUpdateMemberRecordIO db user@User {userId} gInfo m = do
  (gInfo', m') <- deleteSupportChatIfExists db user gInfo m
  if isRelay m'
    then deleteGroupMember db user m'
    else
      checkGroupMemberHasItems db user m' >>= \case
        Just _ -> updateGroupMemberStatus db userId m' GSMemRemoved
        Nothing
          | useRelays' gInfo -> updateGroupMemberRemovedAt db user m'
          | otherwise -> deleteGroupMember db user m'
  pure gInfo'

fullyDeleteMemberRecord :: User -> GroupInfo -> GroupMember -> CM GroupInfo
fullyDeleteMemberRecord user gInfo m =
  withStore' $ \db -> fullyDeleteMemberRecordIO db user gInfo m

fullyDeleteMemberRecordIO :: DB.Connection -> User -> GroupInfo -> GroupMember -> IO GroupInfo
fullyDeleteMemberRecordIO db user gInfo m = do
  (gInfo', m') <- deleteSupportChatIfExists db user gInfo m
  if useRelays' gInfo && not (isRelay m')
    then updateGroupMemberRemovedAt db user m'
    else deleteGroupMember db user m'
  pure gInfo'

updateMemberRecordDeleted :: User -> GroupInfo -> GroupMember -> GroupMemberStatus -> CM GroupInfo
updateMemberRecordDeleted user@User {userId} gInfo m newStatus =
  withStore' $ \db -> do
    (gInfo', m') <- deleteSupportChatIfExists db user gInfo m
    updateGroupMemberStatus db userId m' newStatus
    deactivateRelay_ db m
    pure gInfo'

deactivateRelay_ :: DB.Connection -> GroupMember -> IO ()
deactivateRelay_ db m =
  when (isRelay m) $ do
    relay_ <- runExceptT $ getGroupRelayByGMId db (groupMemberId' m)
    forM_ relay_ $ \relay -> void $ updateRelayStatus db relay RSInactive

deleteSupportChatIfExists :: DB.Connection -> User -> GroupInfo -> GroupMember -> IO (GroupInfo, GroupMember)
deleteSupportChatIfExists db user gInfo m = do
  gInfo' <-
    if gmRequiresAttention m
      then decreaseGroupMembersRequireAttention db user gInfo
      else pure gInfo
  m' <-
    if isJust (supportChat m)
      then deleteGroupMemberSupportChat db m
      else pure m
  pure (gInfo', m')

sendDirectContactMessages :: MsgEncodingI e => User -> Contact -> NonEmpty (ChatMsgEvent e) -> CM [Either ChatError SndMessage]
sendDirectContactMessages user ct events = do
  Connection {connChatVersion = v} <- liftEither $ contactSendConn_ ct
  if v >= batchSend2Version
    then sendDirectContactMessages' user ct events
    else forM (L.toList events) $ \evt ->
      (Right . fst <$> sendDirectContactMessage user ct evt) `catchAllErrors` \e -> pure (Left e)

sendDirectContactMessages' :: MsgEncodingI e => User -> Contact -> NonEmpty (ChatMsgEvent e) -> CM [Either ChatError SndMessage]
sendDirectContactMessages' user ct events = do
  conn@Connection {connId} <- liftEither $ contactSendConn_ ct
  let idsEvts = L.map (ConnectionId connId,Nothing,) events
      msgFlags = MsgFlags {notification = any (hasNotification . toCMEventTag) events}
  sndMsgs_ <- lift $ createSndMessages idsEvts
  (sndMsgs', pqEnc_) <- batchSendConnMessagesB BMJson user conn msgFlags sndMsgs_
  forM_ pqEnc_ $ \pqEnc' -> void $ createContactPQSndItem user ct conn pqEnc'
  pure sndMsgs'

presentUserBadge :: User -> Maybe i -> Profile -> CM Profile
presentUserBadge User {profile = LocalProfile {localBadge}} incognitoProfile p = case (incognitoProfile, localBadge) of
  (Nothing, Just (OwnBadge cred@(BadgeCredential keyIdx _ _ _) st)) | st == BSActive || st == BSExpired -> do
    keys <- asks $ badgePublicKeys . config
    case M.lookup keyIdx keys of
      Nothing -> p <$ logError "presentUserBadge: badge key index not in config"
      Just key -> do
        nonce <- drgRandomBytes 16
        liftIO (badgeProof key cred (PHTest nonce)) >>= \case
          Right proof -> pure p {badge = Just proof}
          Left e -> p <$ logError ("presentUserBadge: proof generation failed: " <> T.pack e)
  _ -> pure p

linkDataBadge :: ContactShortLinkData -> CM ContactShortLinkData
linkDataBadge cld@ContactShortLinkData {profile = Profile {badge}} = case badge of
  Nothing -> pure cld
  Just b@(BadgeProof _ _ _ info) -> do
    keys <- asks $ badgePublicKeys . config
    verified <- liftIO $ verifyBadge keys b
    now <- liftIO getCurrentTime
    pure (cld :: ContactShortLinkData) {localBadge = Just $ ShownBadge info (mkBadgeStatus now verified info)}

sendDirectContactMessage :: MsgEncodingI e => User -> Contact -> ChatMsgEvent e -> CM (SndMessage, Int64)
sendDirectContactMessage user ct chatMsgEvent = do
  conn@Connection {connId} <- liftEither $ contactSendConn_ ct
  r <- sendDirectMessage_ conn chatMsgEvent (ConnectionId connId)
  let (sndMessage, msgDeliveryId, pqEnc') = r
  void $ createContactPQSndItem user ct conn pqEnc'
  pure (sndMessage, msgDeliveryId)

contactSendConn_ :: Contact -> Either ChatError Connection
contactSendConn_ ct@Contact {activeConn} = case activeConn of
  Nothing -> err $ CEContactNotReady ct
  Just conn
    | not (connReady conn) -> err $ CEContactNotReady ct
    | not (contactActive ct) -> err $ CEContactNotActive ct
    | connDisabled conn -> err $ CEContactDisabled ct
    | otherwise -> Right conn
  where
    err = Left . ChatError

sendDirectMemberMessage :: MsgEncodingI e => Connection -> ChatMsgEvent e -> GroupId -> CM (SndMessage, Int64, PQEncryption)
sendDirectMemberMessage conn chatMsgEvent groupId = sendDirectMessage_ conn chatMsgEvent (GroupId groupId)

sendDirectMessage_ :: MsgEncodingI e => Connection -> ChatMsgEvent e -> ConnOrGroupId -> CM (SndMessage, Int64, PQEncryption)
sendDirectMessage_ conn chatMsgEvent connOrGroupId = do
  when (connDisabled conn) $ throwChatError (CEConnectionDisabled conn)
  msg@SndMessage {msgId, msgBody} <- createSndMessage chatMsgEvent connOrGroupId
  (msgDeliveryId, pqEnc') <- deliverMessage conn (toCMEventTag chatMsgEvent) msgBody msgId
  pure (msg, msgDeliveryId, pqEnc')

createSndMessage :: MsgEncodingI e => ChatMsgEvent e -> ConnOrGroupId -> CM SndMessage
createSndMessage chatMsgEvent connOrGroupId =
  liftEither . runIdentity =<< lift (createSndMessages $ Identity (connOrGroupId, Nothing, chatMsgEvent))

createSndMessages :: forall e t. (MsgEncodingI e, Traversable t) => t (ConnOrGroupId, Maybe MsgSigning, ChatMsgEvent e) -> CM' (t (Either ChatError SndMessage))
createSndMessages idsEvents = do
  g <- asks random
  vr <- chatVersionRange'
  withStoreBatch $ \db -> fmap (createMsg db g vr) idsEvents
  where
    createMsg :: DB.Connection -> TVar ChaChaDRG -> VersionRangeChat -> (ConnOrGroupId, Maybe MsgSigning, ChatMsgEvent e) -> IO (Either ChatError SndMessage)
    createMsg db g vr (connOrGroupId, msgSigning_, evnt) = runExceptT $ do
      withExceptT ChatErrorStore $ createNewSndMessage db g connOrGroupId evnt msgSigning_ encodeMessage
      where
        encodeMessage sharedMsgId =
          encodeChatMessage maxEncodedMsgLength ChatMessage {chatVRange = vr, msgId = Just sharedMsgId, chatMsgEvent = evnt}

groupMsgSigning :: Bool -> GroupInfo -> ChatMsgEvent e -> Maybe MsgSigning
groupMsgSigning sign gInfo@GroupInfo {membership = GroupMember {memberId}, groupKeys = Just GroupKeys {publicGroupId, memberPrivKey}} evt
  | useRelays' gInfo && shouldSign =
      Just $ MsgSigning CBGroup (smpEncode (publicGroupId, memberId)) KRMember memberPrivKey
  where
    tag = toCMEventTag evt
    shouldSign = requiresSignature tag || (sign && signableContent tag)
groupMsgSigning _ _ _ = Nothing

sendGroupMemberMessages :: forall e. MsgEncodingI e => User -> GroupInfo -> Connection -> NonEmpty (ChatMsgEvent e) -> CM ()
sendGroupMemberMessages user gInfo@GroupInfo {groupId} conn events = do
  when (connDisabled conn) $ throwChatError (CEConnectionDisabled conn)
  let idsEvts = L.map (\evt -> (GroupId groupId, groupMsgSigning False gInfo evt, evt)) events
      mode = if useRelays' gInfo then BMBinary else BMJson
  (errs, msgs) <- lift $ partitionEithers . L.toList <$> createSndMessages idsEvts
  unless (null errs) $ toView $ CEvtChatErrors errs
  forM_ (L.nonEmpty msgs) $ \msgs' ->
    batchSendConnMessages mode user conn MsgFlags {notification = True} msgs'

batchSendConnMessages :: BatchMode -> User -> Connection -> MsgFlags -> NonEmpty SndMessage -> CM ([Either ChatError SndMessage], Maybe PQEncryption)
batchSendConnMessages mode user conn msgFlags msgs =
  batchSendConnMessagesB mode user conn msgFlags $ L.map Right msgs

batchSendConnMessagesB :: BatchMode -> User -> Connection -> MsgFlags -> NonEmpty (Either ChatError SndMessage) -> CM ([Either ChatError SndMessage], Maybe PQEncryption)
batchSendConnMessagesB mode _user conn msgFlags msgs_ = do
  let batched_ = batchSndMessagesJSON mode msgs_
  case L.nonEmpty batched_ of
    Just batched' -> do
      let msgReqs = L.map (fmap msgBatchReq_) batched'
      delivered <- deliverMessagesB msgReqs
      let msgs' = concat $ L.zipWith flattenMsgs batched' delivered
          pqEnc = findLastPQEnc delivered
      when (length msgs' /= length msgs_) $ logError "batchSendConnMessagesB: msgs_ and msgs' length mismatch"
      pure (msgs', pqEnc)
    Nothing -> pure ([], Nothing)
  where
    msgBatchReq_ :: MsgBatch -> ChatMsgReq
    msgBatchReq_ (MsgBatch batchBody sndMsgs) =
      (conn, msgFlags, (vrValue batchBody, map (\SndMessage {msgId} -> msgId) sndMsgs))
    flattenMsgs :: Either ChatError MsgBatch -> Either ChatError ([Int64], PQEncryption) -> [Either ChatError SndMessage]
    flattenMsgs (Right (MsgBatch _ sndMsgs)) (Right _) = map Right sndMsgs
    flattenMsgs (Right (MsgBatch _ sndMsgs)) (Left ce) = replicate (length sndMsgs) (Left ce)
    flattenMsgs (Left ce) _ = [Left ce]
    findLastPQEnc :: NonEmpty (Either ChatError ([Int64], PQEncryption)) -> Maybe PQEncryption
    findLastPQEnc = foldr' (\x acc -> case x of Right (_, pqEnc) -> Just pqEnc; Left _ -> acc) Nothing

batchSndMessagesJSON :: BatchMode -> NonEmpty (Either ChatError SndMessage) -> [Either ChatError MsgBatch]
batchSndMessagesJSON mode = batchMessages mode maxEncodedMsgLength . L.toList

encodeConnInfo :: MsgEncodingI e => ChatMsgEvent e -> CM ByteString
encodeConnInfo chatMsgEvent = do
  cxt <- chatStoreCxt
  encodeConnInfoPQ PQSupportOff (maxVersion (vr cxt)) chatMsgEvent

encodeConnInfoPQ :: MsgEncodingI e => PQSupport -> VersionChat -> ChatMsgEvent e -> CM ByteString
encodeConnInfoPQ pqSup v chatMsgEvent = do
  cxt <- chatStoreCxt
  let info = ChatMessage {chatVRange = vr cxt, msgId = Nothing, chatMsgEvent}
  case encodeChatMessage maxEncodedInfoLength info of
    ECMEncoded connInfo -> case pqSup of
      PQSupportOn | v >= pqEncryptionCompressionVersion && B.length connInfo > maxCompressedInfoLength -> do
        let connInfo' = compressedBatchMsgBody_ connInfo
        when (B.length connInfo' > maxCompressedInfoLength) $ throwChatError $ CEException "large compressed info"
        pure connInfo'
      _ -> pure connInfo
    ECMLarge -> throwChatError $ CEException "large info"

encodeSignedConnInfo :: MsgEncodingI e => MsgSigning -> ChatMsgEvent e -> CM ByteString
encodeSignedConnInfo signing chatMsgEvent = do
  vr <- chatVersionRange
  let info = ChatMessage {chatVRange = vr, msgId = Nothing, chatMsgEvent}
  case encodeChatMessage maxEncodedInfoLength info of
    ECMEncoded body -> pure $ encodeBatchElement (Just $ signChatMsgBody signing body) body
    ECMLarge -> throwChatError $ CEException "large signed info"

encodeXMemberConnInfo :: GroupInfo -> MemberId -> Profile -> CM ByteString
encodeXMemberConnInfo GroupInfo {membership = GroupMember {memberId}, groupKeys} relayMemberId profileToSend =
  case groupKeys of
    Just GroupKeys {publicGroupId, memberPrivKey} ->
      let xMemberEvt = XMember profileToSend memberId (MemberKey $ C.publicKey memberPrivKey) (Just relayMemberId)
          signing = MsgSigning CBGroup (smpEncode (publicGroupId, memberId)) KRMember memberPrivKey
       in encodeSignedConnInfo signing xMemberEvt
    Nothing -> throwChatError $ CEInternalError "no group keys for channel membership"

deliverMessage :: Connection -> CMEventTag e -> MsgBody -> MessageId -> CM (Int64, PQEncryption)
deliverMessage conn cmEventTag msgBody msgId = do
  let msgFlags = MsgFlags {notification = hasNotification cmEventTag}
  deliverMessage' conn msgFlags msgBody msgId

deliverMessage' :: Connection -> MsgFlags -> MsgBody -> MessageId -> CM (Int64, PQEncryption)
deliverMessage' conn msgFlags msgBody msgId =
  deliverMessages ((conn, msgFlags, (vrValue msgBody, [msgId])) :| []) >>= \case
    r :| [] -> case r of
      Right ([deliveryId], pqEnc) -> pure (deliveryId, pqEnc)
      Right (deliveryIds, _) -> throwChatError $ CEInternalError $ "deliverMessage: expected 1 delivery id, got " <> show (length deliveryIds)
      Left e -> throwError e
    rs -> throwChatError $ CEInternalError $ "deliverMessage: expected 1 result, got " <> show (length rs)

type ChatMsgReq = (Connection, MsgFlags, (ValueOrRef MsgBody, [MessageId]))

deliverMessages :: NonEmpty ChatMsgReq -> CM (NonEmpty (Either ChatError ([Int64], PQEncryption)))
deliverMessages msgs = deliverMessagesB $ L.map Right msgs

deliverMessagesB :: NonEmpty (Either ChatError ChatMsgReq) -> CM (NonEmpty (Either ChatError ([Int64], PQEncryption)))
deliverMessagesB msgReqs = do
  msgReqs' <- if any connSupportsPQ msgReqs then liftIO compressBodies else pure msgReqs
  sent <- L.zipWith prepareBatch msgReqs' <$> withAgent (`sendMessagesB` snd (mapAccumL toAgent Nothing msgReqs'))
  lift . void $ withStoreBatch' $ \db -> map (updatePQSndEnabled db) (rights . L.toList $ sent)
  lift . withStoreBatch $ \db -> L.map (bindRight $ createDelivery db) sent
  where
    connSupportsPQ = \case
      Right (Connection {pqSupport = PQSupportOn, connChatVersion = v}, _, _) -> v >= pqEncryptionCompressionVersion
      _ -> False
    compressBodies =
      forME msgReqs $ \(conn, msgFlags, (mbr, msgIds)) -> runExceptT $ do
        mbr' <- case mbr of
          VRValue i msgBody | B.length msgBody > maxCompressedMsgLength -> do
            let msgBody' = compressedBatchMsgBody_ msgBody
            when (B.length msgBody' > maxCompressedMsgLength) $ throwError $ ChatError $ CEException "large compressed message"
            pure $ VRValue i msgBody'
          v -> pure v
        pure (conn, msgFlags, (mbr', msgIds))
    toAgent prev = \case
      Right (conn@Connection {connId, pqEncryption}, msgFlags, (mbr, _msgIds)) ->
        let cId = case prev of
              Just prevId | prevId == connId -> ""
              _ -> aConnId conn
         in (Just connId, Right (cId, pqEncryption, msgFlags, mbr))
      Left _ce -> (prev, Left (AP.INTERNAL "ChatError, skip"))
    prepareBatch (Right req) (Right ar) = Right (req, ar)
    prepareBatch (Left ce) _ = Left ce
    prepareBatch _ (Left ae) = Left $ chatErrorAgent ae
    createDelivery :: DB.Connection -> (ChatMsgReq, (AgentMsgId, PQEncryption)) -> IO (Either ChatError ([Int64], PQEncryption))
    createDelivery db ((Connection {connId}, _, (_, msgIds)), (agentMsgId, pqEnc')) = do
      Right . (,pqEnc') <$> mapM (createSndMsgDelivery db (SndMsgDelivery {connId, agentMsgId})) msgIds
    updatePQSndEnabled :: DB.Connection -> (ChatMsgReq, (AgentMsgId, PQEncryption)) -> IO ()
    updatePQSndEnabled db ((Connection {connId, pqSndEnabled}, _, _), (_, pqSndEnabled')) =
      case (pqSndEnabled, pqSndEnabled') of
        (Just b, b') | b' /= b -> updatePQ
        (Nothing, PQEncOn) -> updatePQ
        _ -> pure ()
      where
        updatePQ = updateConnPQSndEnabled db connId pqSndEnabled'

sendGroupMessage :: MsgEncodingI e => User -> GroupInfo -> Maybe GroupChatScope -> [GroupMember] -> Bool -> ChatMsgEvent e -> CM SndMessage
sendGroupMessage user gInfo gcScope members sign chatMsgEvent = do
  sendGroupMessages user gInfo gcScope False members sign (chatMsgEvent :| []) >>= \case
    ((Right msg) :| [], _) -> pure msg
    _ -> throwChatError $ CEInternalError "sendGroupMessage: expected 1 message"

sendGroupMessage' :: MsgEncodingI e => User -> GroupInfo -> [GroupMember] -> ChatMsgEvent e -> CM SndMessage
sendGroupMessage' user gInfo members chatMsgEvent =
  sendGroupMessages_ user gInfo members False (chatMsgEvent :| []) >>= \case
    ((Right msg) :| [], _) -> pure msg
    _ -> throwChatError $ CEInternalError "sendGroupMessage': expected 1 message"

data RosterDelta
  = RDRoleChanged GroupMemberRole [GroupMember]
  | RDRemoved [GroupMember]

applyRosterDelta :: RosterDelta -> [GroupMember] -> [GroupMember]
applyRosterDelta delta current = case delta of
  RDRoleChanged role changed -> map (\m -> (m :: GroupMember) {memberRole = role}) changed <> without changed
  RDRemoved removed -> without removed
  where
    without ms = let ids = S.fromList (map groupMemberId' ms) in filter ((`S.notMember` ids) . groupMemberId') current

broadcastRoster :: User -> GroupInfo -> RosterDelta -> CM VersionRoster
broadcastRoster user gInfo delta = do
  let rosterVer = maybe (VersionRoster 0) (\(VersionRoster n) -> VersionRoster (n + 1)) (rosterVersion gInfo)
  withStore' $ \db -> setGroupRosterVersion db gInfo rosterVer
  sendRosterBlob rosterVer `catchAllErrors` eToView
  pure rosterVer
  where
    sendRosterBlob rosterVer = do
      cxt <- chatStoreCxt
      (relays, rosterMems) <- withStore' $ \db ->
        (,) <$> getGroupRelayMembers db cxt user gInfo <*> getGroupRosterMembers db cxt user gInfo
      forM_ (L.nonEmpty relays) $ \relays' ->
        sendRoster user gInfo (L.toList relays') rosterVer (buildGroupRoster $ applyRosterDelta delta rosterMems)

sendGroupRosterToRelay :: User -> GroupInfo -> GroupMember -> CM ()
sendGroupRosterToRelay user gInfo relayMember =
  forM_ (rosterVersion gInfo) $ \rosterVer -> do
    cxt <- chatStoreCxt
    rosterMems <- withStore' $ \db -> getGroupRosterMembers db cxt user gInfo
    sendRoster user gInfo [relayMember] rosterVer (buildGroupRoster rosterMems)

sendRoster :: User -> GroupInfo -> [GroupMember] -> VersionRoster -> [RosterMember] -> CM ()
sendRoster user gInfo members rosterVer roster = do
  let blob = encodeRosterBlob roster
      fileInv = InlineFileInvitation {fileSize = fromIntegral (B.length blob), fileDigest = FD.FileDigest $ LC.sha512Hash $ LB.fromStrict blob}
  SndMessage {sharedMsgId} <- sendGroupMessage' user gInfo members (XGrpRoster GroupRoster {version = rosterVer, fileInv})
  sendInlineBlobChunks user gInfo members sharedMsgId blob

sendInlineBlobChunks :: User -> GroupInfo -> [GroupMember] -> SharedMsgId -> ByteString -> CM ()
sendInlineBlobChunks user gInfo members sharedMsgId blob = do
  chSize <- fromIntegral <$> asks (fileChunkSize . config)
  go chSize 1 blob
  where
    go chSize chunkNo bytes = do
      let (chunk, rest) = B.splitAt chSize bytes
      void $ sendGroupMessage' user gInfo members (BFileChunk sharedMsgId (FileChunk chunkNo chunk))
      unless (B.null rest) $ go chSize (chunkNo + 1) rest

sendRelayCapIfNeeded :: User -> GroupInfo -> CM ()
sendRelayCapIfNeeded user gInfo = do
  ChatConfig {webPreviewConfig} <- asks config
  let currentWebDomain = (\WebPreviewConfig {webDomain} -> webDomain) <$> webPreviewConfig
  sentWebDomain <- withStore' (`getRelaySentWebDomain` gInfo)
  when (currentWebDomain /= sentWebDomain) $ do
    cxt <- chatStoreCxt
    owners <- withStore' $ \db -> getGroupOwners db cxt user gInfo
    let capableOwners = filter (\m -> memberCurrent m && m `supportsVersion` relayWebCapVersion) owners
    unless (null capableOwners) $ do
      void $ sendGroupMessage' user gInfo capableOwners (XGrpRelayCap RelayCapabilities {webDomain = currentWebDomain})
      withStore' $ \db -> updateRelaySentWebDomain db gInfo currentWebDomain

sendGroupMessages :: MsgEncodingI e => User -> GroupInfo -> Maybe GroupChatScope -> ShowGroupAsSender -> [GroupMember] -> Bool -> NonEmpty (ChatMsgEvent e) -> CM (NonEmpty (Either ChatError SndMessage), GroupSndResult)
sendGroupMessages user gInfo scope asGroup members sign events = do
  sendGroupProfileUpdate user gInfo scope asGroup members
  sendGroupMessages_ user gInfo members sign events

sendGroupSignedMessages :: MsgEncodingI e => User -> GroupInfo -> Maybe GroupChatScope -> ShowGroupAsSender -> [GroupMember] -> NonEmpty (Maybe MsgSigning, ChatMsgEvent e) -> CM (NonEmpty (Either ChatError SndMessage), GroupSndResult)
sendGroupSignedMessages user gInfo scope asGroup members signedEvents = do
  sendGroupProfileUpdate user gInfo scope asGroup members
  sendGroupSignedMessages_ gInfo members signedEvents

sendGroupProfileUpdate :: User -> GroupInfo -> Maybe GroupChatScope -> ShowGroupAsSender -> [GroupMember] -> CM ()
sendGroupProfileUpdate user gInfo scope asGroup members =
  when shouldSendProfileUpdate $
    sendProfileUpdate `catchAllErrors` eToView
  where
    User {profile = p, userMemberProfileUpdatedAt} = user
    GroupInfo {userMemberProfileSentAt} = gInfo
    shouldSendProfileUpdate
      | asGroup = False
      | isJust scope = False
      | incognitoMembership gInfo = False
      | otherwise =
          case (userMemberProfileSentAt, userMemberProfileUpdatedAt) of
            (Just lastSentTs, Just lastUpdateTs) -> lastSentTs < lastUpdateTs
            (Nothing, Just _) -> True
            _ -> False
    sendProfileUpdate = do
      let members' = filter (`supportsVersion` memberProfileUpdateVersion) members
      profileUpdate <- presentUserBadge user Nothing $ redactedMemberProfile gInfo (membership gInfo) $ fromLocalProfile p
      void $ sendGroupMessage' user gInfo members' $ XInfo profileUpdate
      currentTs <- liftIO getCurrentTime
      withStore' $ \db -> updateUserMemberProfileSentAt db user gInfo currentTs

data GroupSndResult = GroupSndResult
  { sentTo :: [(GroupMemberId, Either ChatError [MessageId], Either ChatError ([Int64], PQEncryption))],
    pending :: [(GroupMemberId, Either ChatError MessageId, Either ChatError ())],
    forwarded :: [GroupMember]
  }

sendGroupMessages_ :: MsgEncodingI e => User -> GroupInfo -> [GroupMember] -> Bool -> NonEmpty (ChatMsgEvent e) -> CM (NonEmpty (Either ChatError SndMessage), GroupSndResult)
sendGroupMessages_ _user gInfo recipientMembers sign events =
  sendGroupSignedMessages_ gInfo recipientMembers $ L.map (\evt -> (groupMsgSigning sign gInfo evt, evt)) events

sendGroupSignedMessages_ :: MsgEncodingI e => GroupInfo -> [GroupMember] -> NonEmpty (Maybe MsgSigning, ChatMsgEvent e) -> CM (NonEmpty (Either ChatError SndMessage), GroupSndResult)
sendGroupSignedMessages_ gInfo@GroupInfo {groupId} recipientMembers signedEvents = do
  sndMsgs_ <- lift $ createSndMessages idsEvts
  recipientMembers' <- liftIO $ shuffleMembers recipientMembers
  let msgFlags = MsgFlags {notification = any (hasNotification . toCMEventTag) events}
      (toSendSeparate, toSendBatched, toPending, forwarded, _, dups) =
        foldr' (addMember recipientMembers') ([], [], [], [], S.empty, 0 :: Int) recipientMembers'
  when (dups /= 0) $ logError $ "sendGroupMessages_: " <> tshow dups <> " duplicate members"
  let (sendToMemIds, msgReqs) = prepareMsgReqs msgFlags sndMsgs_ toSendSeparate toSendBatched
  delivered <- maybe (pure []) (fmap L.toList . deliverMessagesB) $ L.nonEmpty msgReqs
  when (length delivered /= length sendToMemIds) $ logError "sendGroupMessages_: sendToMemIds and delivered length mismatch"
  let (pendingMemIds, pendingReqs) = preparePending sndMsgs_ toPending
  stored <- lift $ withStoreBatch (\db -> map (bindRight $ createPendingMsg db) pendingReqs)
  when (length stored /= length pendingMemIds) $ logError "sendGroupMessages_: pendingMemIds and stored length mismatch"
  let sentTo = zipWith3 (\mId mReq r -> (mId, fmap (\(_, _, (_, msgIds)) -> msgIds) mReq, r)) sendToMemIds msgReqs delivered
      pending = zipWith3 (\mId pReq r -> (mId, fmap snd pReq, r)) pendingMemIds pendingReqs stored
  pure (sndMsgs_, GroupSndResult {sentTo, pending, forwarded})
  where
    events = L.map snd signedEvents
    idsEvts = L.map (\(signing, evt) -> (GroupId groupId, signing, evt)) signedEvents
    shuffleMembers :: [GroupMember] -> IO [GroupMember]
    shuffleMembers ms = do
      let (adminMs, otherMs) = partition isAdmin ms
      liftM2 (<>) (shuffle adminMs) (shuffle otherMs)
      where
        isAdmin GroupMember {memberRole} = memberRole >= GRAdmin
    addMember members m acc@(toSendSeparate, toSendBatched, pending, forwarded, !mIds, !dups) =
      case memberSendAction gInfo events members m of
        Just a
          | mId `S.member` mIds -> (toSendSeparate, toSendBatched, pending, forwarded, mIds, dups + 1)
          | otherwise -> case a of
              MSASend conn -> ((m, conn) : toSendSeparate, toSendBatched, pending, forwarded, mIds', dups)
              MSASendBatched conn -> (toSendSeparate, (m, conn) : toSendBatched, pending, forwarded, mIds', dups)
              MSAPending -> (toSendSeparate, toSendBatched, m : pending, forwarded, mIds', dups)
              MSAForwarded -> (toSendSeparate, toSendBatched, pending, m : forwarded, mIds', dups)
        Nothing -> acc
      where
        mId = groupMemberId' m
        mIds' = S.insert mId mIds
    prepareMsgReqs :: MsgFlags -> NonEmpty (Either ChatError SndMessage) -> [(GroupMember, Connection)] -> [(GroupMember, Connection)] -> ([GroupMemberId], [Either ChatError ChatMsgReq])
    prepareMsgReqs msgFlags msgs toSendSeparate toSendBatched = do
      let mode = if useRelays' gInfo then BMBinary else BMJson
          batched_ = batchSndMessagesJSON mode msgs
      case L.nonEmpty batched_ of
        Just batched' -> do
          let lenMsgs = length msgs
              (memsSep, mreqsSep) = foldMembers lenMsgs sndMessageMBR msgs toSendSeparate
              (memsBtch, mreqsBtch) = foldMembers (length batched' + lenMsgs) msgBatchMBR batched' toSendBatched
          (memsSep <> memsBtch, mreqsSep <> mreqsBtch)
        Nothing -> ([], [])
      where
        foldMembers :: forall a. Int -> (Maybe Int -> Int -> a -> (ValueOrRef MsgBody, [MessageId])) -> NonEmpty (Either ChatError a) -> [(GroupMember, Connection)] -> ([GroupMemberId], [Either ChatError ChatMsgReq])
        foldMembers lastRef mkMb mbs mems = snd $ foldr' foldMsgBodies (lastMemIdx_, ([], [])) mems
          where
            lastMemIdx_ = let len = length mems in if len > 1 then Just len else Nothing
            foldMsgBodies :: (GroupMember, Connection) -> (Maybe Int, ([GroupMemberId], [Either ChatError ChatMsgReq])) -> (Maybe Int, ([GroupMemberId], [Either ChatError ChatMsgReq]))
            foldMsgBodies (GroupMember {groupMemberId}, conn) (memIdx_, memIdsReqs) =
              (subtract 1 <$> memIdx_,) $ snd $ foldr' addBody (lastRef, memIdsReqs) mbs
              where
                addBody :: Either ChatError a -> (Int, ([GroupMemberId], [Either ChatError ChatMsgReq])) -> (Int, ([GroupMemberId], [Either ChatError ChatMsgReq]))
                addBody mb (i, (memIds, reqs)) =
                  let req = (conn,msgFlags,) . mkMb memIdx_ i <$> mb
                   in (i - 1, (groupMemberId : memIds, req : reqs))
        sndMessageMBR :: Maybe Int -> Int -> SndMessage -> (ValueOrRef MsgBody, [MessageId])
        sndMessageMBR memIdx_ i SndMessage {msgId, msgBody} = (vrValue_ memIdx_ i msgBody, [msgId])
        msgBatchMBR :: Maybe Int -> Int -> MsgBatch -> (ValueOrRef MsgBody, [MessageId])
        msgBatchMBR memIdx_ i (MsgBatch batchBody sndMsgs) = (vrValue_ memIdx_ i batchBody, map (\SndMessage {msgId} -> msgId) sndMsgs)
        vrValue_ memIdx_ i v = case memIdx_ of
          Nothing -> VRValue Nothing v
          Just 1 -> VRValue (Just i) v
          Just _ -> VRRef i
    preparePending :: NonEmpty (Either ChatError SndMessage) -> [GroupMember] -> ([GroupMemberId], [Either ChatError (GroupMemberId, MessageId)])
    preparePending msgs_ =
      foldr' foldMsgs ([], [])
      where
        foldMsgs :: GroupMember -> ([GroupMemberId], [Either ChatError (GroupMemberId, MessageId)]) -> ([GroupMemberId], [Either ChatError (GroupMemberId, MessageId)])
        foldMsgs GroupMember {groupMemberId} memIdsReqs =
          foldr' (\msg_ (memIds, reqs) -> (groupMemberId : memIds, fmap pendingReq msg_ : reqs)) memIdsReqs msgs_
          where
            pendingReq :: SndMessage -> (GroupMemberId, MessageId)
            pendingReq SndMessage {msgId} = (groupMemberId, msgId)
    createPendingMsg :: DB.Connection -> (GroupMemberId, MessageId) -> IO (Either ChatError ())
    createPendingMsg db (groupMemberId, msgId) =
      createPendingGroupMessage db groupMemberId msgId $> Right ()

data MemberSendAction = MSASend Connection | MSASendBatched Connection | MSAPending | MSAForwarded

memberSendAction :: GroupInfo -> NonEmpty (ChatMsgEvent e) -> [GroupMember] -> GroupMember -> Maybe MemberSendAction
memberSendAction gInfo@GroupInfo {membership} events members m@GroupMember {memberRole, memberStatus}
  | useRelays' gInfo =
      if
        | isRelay membership && not (isRelay m) -> MSASendBatched . snd <$> readyMemberConn m
        | not (isRelay membership) && isRelay m -> MSASendBatched . snd <$> readyMemberConn m
        | otherwise -> Nothing
  | otherwise = case memberConn m of
      Nothing -> pendingOrForwarded
      Just conn@Connection {connStatus}
        | connDisabled conn || connStatus == ConnDeleted || isConnFailed connStatus || memberStatus == GSMemRejected -> Nothing
        | connInactive conn -> Just MSAPending
        | connStatus == ConnSndReady || connStatus == ConnReady -> sendBatchedOrSeparate conn
        | otherwise -> pendingOrForwarded
  where
    sendBatchedOrSeparate conn
      | memberRole >= GRAdmin && not (m `supportsVersion` batchSend2Version) = Just (MSASend conn)
      | otherwise = Just (MSASendBatched conn)
    pendingOrForwarded = case memberCategory m of
      GCUserMember -> Nothing
      GCInviteeMember -> Just MSAPending
      GCHostMember -> Just MSAPending
      GCPreMember -> forwardSupportedOrPending (invitedByGroupMemberId membership)
      GCPostMember -> forwardSupportedOrPending (invitedByGroupMemberId m)
      where
        forwardSupportedOrPending invitingMemberId_
          | membersSupport && all isForwardedGroupMsg events = Just MSAForwarded
          | any isXGrpMsgForward events = Nothing
          | otherwise = Just MSAPending
          where
            membersSupport =
              m `supportsVersion` groupForwardVersion && invitingMemberSupportsForward
            invitingMemberSupportsForward = case invitingMemberId_ of
              Just invMemberId ->
                case find (\m' -> groupMemberId' m' == invMemberId) members of
                  Just invitingMember -> invitingMember `supportsVersion` groupForwardVersion
                  Nothing -> False
              Nothing -> False
            isXGrpMsgForward event = case event of
              XGrpMsgForward {} -> True
              _ -> False

readyMemberConn :: GroupMember -> Maybe (GroupMemberId, Connection)
readyMemberConn GroupMember {groupMemberId, activeConn = Just conn@Connection {connStatus}, memberStatus}
  | (connStatus == ConnReady || connStatus == ConnSndReady)
      && not (connDisabled conn)
      && not (connInactive conn)
      && memberStatus /= GSMemRejected =
      Just (groupMemberId, conn)
  | otherwise = Nothing
readyMemberConn GroupMember {activeConn = Nothing} = Nothing

sendGroupMemberMessage :: MsgEncodingI e => GroupInfo -> GroupMember -> ChatMsgEvent e -> CM ()
sendGroupMemberMessage gInfo@GroupInfo {groupId} m@GroupMember {groupMemberId} chatMsgEvent = do
  msg <- createSndMessage chatMsgEvent (GroupId groupId)
  messageMember msg `catchAllErrors` eToView
  where
    messageMember :: SndMessage -> CM ()
    messageMember SndMessage {msgId, msgBody} = forM_ (memberSendAction gInfo (chatMsgEvent :| []) [m] m) $ \case
      MSASend conn -> void $ deliverMessage conn (toCMEventTag chatMsgEvent) msgBody msgId
      MSASendBatched conn -> void $ deliverMessage conn (toCMEventTag chatMsgEvent) msgBody msgId
      MSAPending -> withStore' $ \db -> createPendingGroupMessage db groupMemberId msgId
      MSAForwarded -> pure ()

sendFwdMemberMessage :: GroupMember -> GrpMsgForward -> VerifiedMsg 'Json -> CM ()
sendFwdMemberMessage member fwd verifiedMsg =
  forM_ (readyMemberConn member) $ \(_, conn) -> do
    let body = encodeBinaryBatch [encodeFwdElement fwd verifiedMsg]
    void $ withAgent $ \a -> sendMessages a [(aConnId conn, PQEncOff, MsgFlags False, VRValue Nothing body)]

sendPendingGroupMessages :: User -> GroupInfo -> GroupMember -> Connection -> CM ()
sendPendingGroupMessages user gInfo GroupMember {groupMemberId} conn = do
  let mode = if useRelays' gInfo then BMBinary else BMJson
  msgs <- withStore' $ \db -> getPendingGroupMessages db groupMemberId
  forM_ (L.nonEmpty msgs) $ \msgs' -> do
    void $ batchSendConnMessages mode user conn MsgFlags {notification = True} msgs'
    lift . void . withStoreBatch' $ \db -> L.map (\SndMessage {msgId} -> deletePendingGroupMessage db groupMemberId msgId) msgs'

saveDirectRcvMSG :: forall e. MsgEncodingI e => Connection -> MsgMeta -> ChatMessage e -> CM (Connection, RcvMessage)
saveDirectRcvMSG conn@Connection {connId} agentMsgMeta chatMsg@ChatMessage {chatVRange, msgId = sharedMsgId_, chatMsgEvent} = do
  conn' <- updatePeerChatVRange conn chatVRange
  let agentMsgId = fst $ recipient agentMsgMeta
      brokerTs = metaBrokerTs agentMsgMeta
      newMsg = NewRcvMessage {chatMsgEvent, verifiedMsg = VMUnsigned chatMsg, brokerTs}
      rcvMsgDelivery = RcvMsgDelivery {connId, agentMsgId, agentMsgMeta}
  msg <- withStore $ \db -> createNewMessageAndRcvMsgDelivery db (ConnectionId connId) newMsg sharedMsgId_ rcvMsgDelivery Nothing
  pure (conn', msg)

saveGroupRcvMsg :: forall e. MsgEncodingI e => User -> GroupId -> GroupMember -> Connection -> MsgMeta -> VerifiedMsg e -> CM (GroupMember, Connection, RcvMessage)
saveGroupRcvMsg user groupId authorMember conn@Connection {connId} agentMsgMeta verifiedMsg = do
  let ChatMessage {chatVRange, msgId = sharedMsgId_, chatMsgEvent} = verifiedChatMsg verifiedMsg
  (am'@GroupMember {memberId = amMemId, groupMemberId = amGroupMemId}, conn') <- case encoding @e of
    SBinary -> pure (authorMember, conn)
    SJson -> updateMemberChatVRange authorMember conn chatVRange
  let agentMsgId = fst $ recipient agentMsgMeta
      brokerTs = metaBrokerTs agentMsgMeta
      newMsg = NewRcvMessage {chatMsgEvent, verifiedMsg, brokerTs}
      rcvMsgDelivery = RcvMsgDelivery {connId, agentMsgId, agentMsgMeta}
  msg <-
    withStore (\db -> createNewMessageAndRcvMsgDelivery db (GroupId groupId) newMsg sharedMsgId_ rcvMsgDelivery $ Just amGroupMemId)
      `catchAllErrors` \e -> case e of
        ChatErrorStore (SEDuplicateGroupMessage _ _ _ (Just forwardedByGroupMemberId)) -> do
          cxt <- chatStoreCxt
          fm <- withStore $ \db -> getGroupMember db cxt user groupId forwardedByGroupMemberId
          forM_ (memberConn fm) $ \fmConn ->
            void $ sendDirectMemberMessage fmConn (XGrpMemCon amMemId) groupId
          throwError e
        _ -> throwError e
  pure (am', conn', msg)

saveGroupFwdRcvMsg :: MsgEncodingI e => User -> GroupInfo -> GroupMember -> Maybe GroupMember -> VerifiedMsg e -> UTCTime -> CM (Maybe RcvMessage)
saveGroupFwdRcvMsg user gInfo@GroupInfo {groupId} forwardingMember refAuthorMember_ verifiedMsg brokerTs = do
  let ChatMessage {msgId = sharedMsgId_, chatMsgEvent} = verifiedChatMsg verifiedMsg
      newMsg = NewRcvMessage {chatMsgEvent, verifiedMsg, brokerTs}
      fwdMemberId = Just $ groupMemberId' forwardingMember
      refAuthorId = groupMemberId' <$> refAuthorMember_
  withStore' (\db -> runExceptT $ createNewRcvMessage db (GroupId groupId) newMsg sharedMsgId_ refAuthorId fwdMemberId) >>= \case
    Right msg -> pure $ Just msg
    Left e@SEDuplicateGroupMessage {authorGroupMemberId, forwardedByGroupMemberId}
      | useRelays' gInfo -> pure Nothing
      | otherwise -> case (authorGroupMemberId, forwardedByGroupMemberId) of
          (Just authorGMId, Nothing) -> do
            cxt <- chatStoreCxt
            am@GroupMember {memberId = amMemberId} <- withStore $ \db -> getGroupMember db cxt user groupId authorGMId
            if maybe False (\ref -> sameMemberId (memberId' ref) am) refAuthorMember_
              then forM_ (memberConn forwardingMember) $ \fmConn ->
                void $ sendDirectMemberMessage fmConn (XGrpMemCon amMemberId) groupId
              else toView $ CEvtMessageError user "error" "saveGroupFwdRcvMsg: referenced author member id doesn't match message member id"
            throwError $ ChatErrorStore e
          _ -> throwError $ ChatErrorStore e
    Left e -> throwError $ ChatErrorStore e

saveSndChatItem :: ChatTypeI c => User -> ChatDirection c 'MDSnd -> SndMessage -> CIContent 'MDSnd -> CM (ChatItem c 'MDSnd)
saveSndChatItem user cd msg content = saveSndChatItem' user cd msg content Nothing Nothing Nothing Nothing False

saveSndChatItem' :: ChatTypeI c => User -> ChatDirection c 'MDSnd -> SndMessage -> CIContent 'MDSnd -> Maybe (CIFile 'MDSnd) -> Maybe (CIQuote c) -> Maybe CIForwardedFrom -> Maybe CITimed -> Bool -> CM (ChatItem c 'MDSnd)
saveSndChatItem' user cd msg content ciFile quotedItem itemForwarded itemTimed live = do
  let itemTexts = ciContentTexts content
  saveSndChatItems user cd False [Right NewSndChatItemData {msg, content, itemTexts, itemMentions = M.empty, ciFile, quotedItem, itemForwarded}] itemTimed live >>= \case
    [Right ci] -> pure ci
    _ -> throwChatError $ CEInternalError "saveSndChatItem': expected 1 item"

data NewSndChatItemData c = NewSndChatItemData
  { msg :: SndMessage,
    content :: CIContent 'MDSnd,
    itemTexts :: (Text, Maybe MarkdownList),
    itemMentions :: Map MemberName CIMention,
    ciFile :: Maybe (CIFile 'MDSnd),
    quotedItem :: Maybe (CIQuote c),
    itemForwarded :: Maybe CIForwardedFrom
  }

saveSndChatItems ::
  forall c.
  ChatTypeI c =>
  User ->
  ChatDirection c 'MDSnd ->
  ShowGroupAsSender ->
  [Either ChatError (NewSndChatItemData c)] ->
  Maybe CITimed ->
  Bool ->
  CM [Either ChatError (ChatItem c 'MDSnd)]
saveSndChatItems user cd showGroupAsSender itemsData itemTimed live = do
  createdAt <- liftIO getCurrentTime
  cxt <- chatStoreCxt
  when (contactChatDeleted cd || any (\NewSndChatItemData {content} -> ciRequiresAttention content) (rights itemsData)) $
    void (withStore' $ \db -> updateChatTsStats db cxt user cd createdAt Nothing)
  lift $ withStoreBatch (\db -> map (bindRight $ createItem db createdAt) itemsData)
  where
    createItem :: DB.Connection -> UTCTime -> NewSndChatItemData c -> IO (Either ChatError (ChatItem c 'MDSnd))
    createItem db createdAt NewSndChatItemData {msg = msg@SndMessage {sharedMsgId, signedMsg_}, content, itemTexts, itemMentions, ciFile, quotedItem, itemForwarded} = do
      let hasLink_ = ciContentHasLink content (snd itemTexts)
      ciId <- createNewSndChatItem db user cd showGroupAsSender msg content quotedItem itemForwarded itemTimed live hasLink_ createdAt
      forM_ ciFile $ \CIFile {fileId} -> updateFileTransferChatItemId db fileId ciId createdAt
      let ci = mkChatItem_ cd showGroupAsSender ciId content itemTexts ciFile quotedItem (Just sharedMsgId) itemForwarded itemTimed live False hasLink_ createdAt Nothing (toMsgVerified (signMessagesRequired cd) (MSSVerified <$ signedMsg_)) createdAt
      Right <$> case cd of
        CDGroupSnd g _scope | not (null itemMentions) -> createGroupCIMentions db g ci itemMentions
        _ -> pure ci

saveRcvChatItemNoParse :: (ChatTypeI c, ChatTypeQuotable c) => User -> ChatDirection c 'MDRcv -> RcvMessage -> UTCTime -> CIContent 'MDRcv -> CM (ChatItem c 'MDRcv, ChatInfo c)
saveRcvChatItemNoParse user cd msg brokerTs = saveRcvChatItem user cd msg brokerTs . ciContentNoParse

saveRcvChatItem :: (ChatTypeI c, ChatTypeQuotable c) => User -> ChatDirection c 'MDRcv -> RcvMessage -> UTCTime -> (CIContent 'MDRcv, (Text, Maybe MarkdownList)) -> CM (ChatItem c 'MDRcv, ChatInfo c)
saveRcvChatItem user cd msg@RcvMessage {sharedMsgId_} brokerTs content =
  saveRcvChatItem' user cd msg sharedMsgId_ brokerTs content Nothing Nothing False M.empty

ciContentNoParse :: CIContent 'MDRcv -> (CIContent 'MDRcv, (Text, Maybe MarkdownList))
ciContentNoParse content = (content, (ciContentToText content, Nothing))

saveRcvChatItem' :: (ChatTypeI c, ChatTypeQuotable c) => User -> ChatDirection c 'MDRcv -> RcvMessage -> Maybe SharedMsgId -> UTCTime -> (CIContent 'MDRcv, (Text, Maybe MarkdownList)) -> Maybe (CIFile 'MDRcv) -> Maybe CITimed -> Bool -> Map MemberName MsgMention -> CM (ChatItem c 'MDRcv, ChatInfo c)
saveRcvChatItem' user cd msg@RcvMessage {chatMsgEvent, msgSigned, forwardedByMember} sharedMsgId_ brokerTs (content, (t, ft_)) ciFile itemTimed live mentions = do
  createdAt <- liftIO getCurrentTime
  cxt <- chatStoreCxt
  withStore' $ \db -> do
    (mentions' :: Map MemberName CIMention, userMention) <- case toChatInfo cd of
      GroupChat g@GroupInfo {membership} _ -> groupMentions db g membership
      _ -> pure (M.empty, False)
    cInfo' <-
      if (ciRequiresAttention content || contactChatDeleted cd)
        then updateChatTsStats db cxt user cd createdAt (memberChatStats userMention)
        else pure $ toChatInfo cd
    let showAsGroup = case cd of CDChannelRcv {} -> True; _ -> False
        hasLink_ = ciContentHasLink content ft_
    (ciId, quotedItem, itemForwarded) <- createNewRcvChatItem db user cd msg sharedMsgId_ content itemTimed live userMention hasLink_ brokerTs createdAt
    forM_ ciFile $ \CIFile {fileId} -> updateFileTransferChatItemId db fileId ciId createdAt
    let ci = mkChatItem_ cd showAsGroup ciId content (t, ft_) ciFile quotedItem sharedMsgId_ itemForwarded itemTimed live userMention hasLink_ brokerTs forwardedByMember (toMsgVerified (signMessagesRequired cd) msgSigned) createdAt
    ci' <- case toChatInfo cd of
      GroupChat g _ | not (null mentions') -> createGroupCIMentions db g ci mentions'
      _ -> pure ci
    pure (ci', cInfo')
  where
    groupMentions db g membership = do
      mentions' <- getRcvCIMentions db user g ft_ mentions
      let senderBlocked = case cd of
            CDGroupRcv _g _scope m -> memberBlocked m
            _ -> False
          userReply = not senderBlocked && case cmToQuotedMsg chatMsgEvent of
            Just QuotedMsg {msgRef = MsgRef {memberId = Just mId}} -> sameMemberId mId membership
            _ -> False
          userMention' = userReply || any (\CIMention {memberId} -> sameMemberId memberId membership) mentions'
       in pure (mentions', userMention')
    memberChatStats :: Bool -> Maybe (Int, MemberAttention, Int)
    memberChatStats userMention = case cd of
      CDGroupRcv _g (Just scope) m ->
        let unread = fromEnum $ ciCreateStatus content == CISRcvNew
         in Just (unread, memberAttentionChange unread (Just brokerTs) (Just m) scope, fromEnum userMention)
      CDChannelRcv _g (Just scope) ->
        let unread = fromEnum $ ciCreateStatus content == CISRcvNew
         in Just (unread, memberAttentionChange unread (Just brokerTs) Nothing scope, fromEnum userMention)
      _ -> Nothing

mkChatItem :: (ChatTypeI c, MsgDirectionI d) => ChatDirection c d -> ShowGroupAsSender -> ChatItemId -> CIContent d -> Maybe (CIFile d) -> Maybe (CIQuote c) -> Maybe SharedMsgId -> Maybe CIForwardedFrom -> Maybe CITimed -> Bool -> Bool -> ChatItemTs -> Maybe GroupMemberId -> Maybe MsgVerified -> UTCTime -> ChatItem c d
mkChatItem cd showGroupAsSender ciId content file quotedItem sharedMsgId itemForwarded itemTimed live userMention itemTs forwardedByMember msgVerified currentTs =
  let ts@(_, ft_) = ciContentTexts content
      hasLink_ = ciContentHasLink content ft_
   in mkChatItem_ cd showGroupAsSender ciId content ts file quotedItem sharedMsgId itemForwarded itemTimed live userMention hasLink_ itemTs forwardedByMember msgVerified currentTs

mkChatItem_ :: (ChatTypeI c, MsgDirectionI d) => ChatDirection c d -> ShowGroupAsSender -> ChatItemId -> CIContent d -> (Text, Maybe MarkdownList) -> Maybe (CIFile d) -> Maybe (CIQuote c) -> Maybe SharedMsgId -> Maybe CIForwardedFrom -> Maybe CITimed -> Bool -> Bool -> Bool -> ChatItemTs -> Maybe GroupMemberId -> Maybe MsgVerified -> UTCTime -> ChatItem c d
mkChatItem_ cd showGroupAsSender ciId content (itemText, formattedText) file quotedItem sharedMsgId itemForwarded itemTimed live userMention hasLink_ itemTs forwardedByMember msgVerified currentTs =
  let itemStatus = ciCreateStatus content
      meta = mkCIMeta ciId content itemText itemStatus Nothing sharedMsgId itemForwarded Nothing False itemTimed (justTrue live) userMention hasLink_ currentTs itemTs forwardedByMember showGroupAsSender msgVerified currentTs currentTs
   in ChatItem {chatDir = toCIDirection cd, meta, content, mentions = M.empty, formattedText, quotedItem, reactions = [], file}

ciContentHasLink :: CIContent d -> Maybe MarkdownList -> Bool
ciContentHasLink content ft_ = case ciMsgContent content of
  Just mc -> msgContentHasLink mc ft_
  Nothing -> False

msgContentHasLink :: MsgContent -> Maybe MarkdownList -> Bool
msgContentHasLink mc ft_ = case msgContentTag mc of
  MCLink_ -> True
  _ -> maybe False hasLinks ft_

prepareAgentCreation :: ConnectionModeI c => User -> CommandFunction -> Bool -> SConnectionMode c -> CM (CommandId, ConnId)
prepareAgentCreation user cmdFunction enableNtfs cMode = do
  cmdId <- withStore' $ \db -> createCommand db user Nothing cmdFunction
  connId <- withAgent $ \a -> prepareConnectionToCreate a (aUserId user) enableNtfs cMode PQSupportOff
  pure (cmdId, connId)

prepareAgentJoin :: User -> Maybe Connection -> Bool -> ConnectionRequestUri c -> CM (CommandId, ConnId)
prepareAgentJoin user conn_ enableNtfs cReqUri = do
  cmdId <- withStore' $ \db -> createCommand db user (dbConnId <$> conn_) CFJoinConn
  connId <- case conn_ of
    Just conn -> pure $ aConnId conn
    Nothing -> withAgent $ \a -> prepareConnectionToJoin a (aUserId user) enableNtfs cReqUri PQSupportOff
  pure (cmdId, connId)

joinAgentConnectionAsync :: ConnectionModeI c => CommandId -> Bool -> ConnId -> Bool -> ConnectionRequestUri c -> ConnInfo -> SubscriptionMode -> CM ()
joinAgentConnectionAsync cmdId updateConn connId enableNtfs cReqUri cInfo subMode =
  withAgent $ \a -> joinConnectionAsync a (aCorrId cmdId) updateConn connId enableNtfs cReqUri cInfo PQSupportOff subMode

allowAgentConnectionAsync :: MsgEncodingI e => User -> Connection -> ConfirmationId -> ChatMsgEvent e -> CM ()
allowAgentConnectionAsync user conn@Connection {connId, pqSupport, connChatVersion} confId msg = do
  cmdId <- withStore' $ \db -> createCommand db user (Just connId) CFAllowConn
  dm <- encodeConnInfoPQ pqSupport connChatVersion msg
  withAgent $ \a -> allowConnectionAsync a (aCorrId cmdId) (aConnId conn) confId dm
  withStore' $ \db -> updateConnectionStatus db conn ConnAccepted

prepareAgentAccept :: User -> Bool -> InvitationId -> PQSupport -> CM (CommandId, ConnId)
prepareAgentAccept user enableNtfs invId pqSup = do
  cmdId <- withStore' $ \db -> createCommand db user Nothing CFAcceptContact
  connId <- withAgent $ \a -> prepareConnectionToAccept a (aUserId user) enableNtfs invId pqSup
  pure (cmdId, connId)

agentAcceptContactAsync :: MsgEncodingI e => CommandId -> ConnId -> Bool -> InvitationId -> ChatMsgEvent e -> PQSupport -> VersionChat -> SubscriptionMode -> CM ()
agentAcceptContactAsync cmdId connId enableNtfs invId msg pqSup chatV subMode = do
  dm <- encodeConnInfoPQ pqSup chatV msg
  withAgent $ \a -> acceptContactAsync a (aCorrId cmdId) connId enableNtfs invId dm pqSup subMode

deleteAgentConnectionAsync :: ConnId -> CM ()
deleteAgentConnectionAsync acId = deleteAgentConnectionAsync' acId False
{-# INLINE deleteAgentConnectionAsync #-}

deleteAgentConnectionAsync' :: ConnId -> Bool -> CM ()
deleteAgentConnectionAsync' acId waitDelivery = do
  withAgent (\a -> deleteConnectionAsync a waitDelivery acId) `catchAllErrors` eToView

deleteAgentConnectionsAsync :: [ConnId] -> CM ()
deleteAgentConnectionsAsync acIds = deleteAgentConnectionsAsync' acIds False
{-# INLINE deleteAgentConnectionsAsync #-}

deleteAgentConnectionsAsync' :: [ConnId] -> Bool -> CM ()
deleteAgentConnectionsAsync' [] _ = pure ()
deleteAgentConnectionsAsync' acIds waitDelivery = do
  withAgent (\a -> deleteConnectionsAsync a waitDelivery acIds) `catchAllErrors` eToView

setAgentConnShortLinkAsync :: User -> Connection -> UserConnLinkData 'CMContact -> Maybe CRClientData -> CM ()
setAgentConnShortLinkAsync user conn@Connection {connId} userLinkData crClientData_ = do
  cmdId <- withStore' $ \db -> createCommand db user (Just connId) CFSetShortLink
  withAgent $ \a -> setConnShortLinkAsync a (aCorrId cmdId) (aConnId conn) userLinkData crClientData_

getAgentConnShortLinkAsync :: User -> CommandFunction -> Maybe Connection -> ShortLinkContact -> CM (CommandId, ConnId)
getAgentConnShortLinkAsync user cmdFunc conn_ shortLink = do
  shortLink' <- restoreShortLink' shortLink
  cmdId <- withStore' $ \db -> createCommand db user (dbConnId <$> conn_) cmdFunc
  connId <- withAgent $ \a -> getConnShortLinkAsync a (aUserId user) (aCorrId cmdId) (aConnId <$> conn_) shortLink'
  pure (cmdId, connId)

agentXFTPDeleteRcvFile :: RcvFileId -> FileTransferId -> CM ()
agentXFTPDeleteRcvFile aFileId fileId = do
  lift $ withAgent' (`xftpDeleteRcvFile` aFileId)
  withStore' $ \db -> setRcvFTAgentDeleted db fileId

agentXFTPDeleteRcvFiles :: [(XFTPRcvFile, FileTransferId)] -> CM' ()
agentXFTPDeleteRcvFiles rcvFiles = do
  let rcvFiles' = filter (not . agentRcvFileDeleted . fst) rcvFiles
      rfIds = mapMaybe fileIds rcvFiles'
  withAgent' $ \a -> xftpDeleteRcvFiles a (map fst rfIds)
  void . withStoreBatch' $ \db -> map (setRcvFTAgentDeleted db . snd) rfIds
  where
    fileIds :: (XFTPRcvFile, FileTransferId) -> Maybe (RcvFileId, FileTransferId)
    fileIds (XFTPRcvFile {agentRcvFileId = Just (AgentRcvFileId aFileId)}, fileId) = Just (aFileId, fileId)
    fileIds _ = Nothing

agentXFTPDeleteSndFileRemote :: User -> XFTPSndFile -> FileTransferId -> CM' ()
agentXFTPDeleteSndFileRemote user xsf fileId =
  agentXFTPDeleteSndFilesRemote user [(xsf, fileId)]

agentXFTPDeleteSndFilesRemote :: User -> [(XFTPSndFile, FileTransferId)] -> CM' ()
agentXFTPDeleteSndFilesRemote user sndFiles = do
  (_errs, redirects) <- partitionEithers <$> withStoreBatch' (\db -> map (lookupFileTransferRedirectMeta db user . snd) sndFiles)
  let redirects' = mapMaybe mapRedirectMeta $ concat redirects
      sndFilesAll = redirects' <> sndFiles
      sndFilesAll' = filter (not . agentSndFileDeleted . fst) sndFilesAll
  (sfsNoDescr, sfsWithDescr) <- partitionSndDescr sndFilesAll' [] []
  withAgent' $ \a -> xftpDeleteSndFilesInternal a sfsNoDescr
  withAgent' $ \a -> xftpDeleteSndFilesRemote a (aUserId user) sfsWithDescr
  void . withStoreBatch' $ \db -> map (setSndFTAgentDeleted db user . snd) sndFilesAll'
  where
    mapRedirectMeta :: FileTransferMeta -> Maybe (XFTPSndFile, FileTransferId)
    mapRedirectMeta FileTransferMeta {fileId = fileId, xftpSndFile = Just sndFileRedirect} = Just (sndFileRedirect, fileId)
    mapRedirectMeta _ = Nothing
    partitionSndDescr ::
      [(XFTPSndFile, FileTransferId)] ->
      [SndFileId] ->
      [(SndFileId, ValidFileDescription 'FSender)] ->
      CM' ([SndFileId], [(SndFileId, ValidFileDescription 'FSender)])
    partitionSndDescr [] filesWithoutDescr filesWithDescr = pure (filesWithoutDescr, filesWithDescr)
    partitionSndDescr ((XFTPSndFile {agentSndFileId = AgentSndFileId aFileId, privateSndFileDescr}, _) : xsfs) filesWithoutDescr filesWithDescr =
      case privateSndFileDescr of
        Nothing -> partitionSndDescr xsfs (aFileId : filesWithoutDescr) filesWithDescr
        Just sfdText ->
          tryAllErrors' (parseFileDescription sfdText) >>= \case
            Left _ -> partitionSndDescr xsfs (aFileId : filesWithoutDescr) filesWithDescr
            Right sfd -> partitionSndDescr xsfs filesWithoutDescr ((aFileId, sfd) : filesWithDescr)

connRequestPQEncryption :: ConnectionRequestUri c -> Maybe PQEncryption
connRequestPQEncryption = \case
  CRContactUri _ -> Nothing
  CRInvitationUri _ (CR.E2ERatchetParamsUri vr' _ _ pq) ->
    Just $ PQEncryption $ maxVersion vr' >= CR.pqRatchetE2EEncryptVersion && isJust pq

createRcvFeatureItems :: User -> Contact -> Contact -> CM' ()
createRcvFeatureItems user ct ct' =
  createFeatureItems user ct ct' CDDirectRcv CIRcvChatFeature CIRcvChatPreference contactPreference

createSndFeatureItems :: User -> Contact -> Contact -> CM' ()
createSndFeatureItems user ct ct' =
  createFeatureItems user ct ct' CDDirectSnd CISndChatFeature CISndChatPreference getPref
  where
    getPref ContactUserPreference {userPreference} = case userPreference of
      CUPContact {preference} -> preference
      CUPUser {preference} -> preference

createContactChangedFeatureItems :: User -> Contact -> Contact -> CM' ()
createContactChangedFeatureItems user ct ct' =
  createFeatureItems user ct ct' CDDirectRcv CIRcvChatFeature CIRcvChatPreference getPref
  where
    getPref ContactUserPreference {userPreference} = case userPreference of
      CUPContact {preference} -> preference
      CUPUser {preference} -> preference

type FeatureContent a d = ChatFeature -> a -> Maybe Int -> CIContent d

createFeatureEnabledItems :: User -> Contact -> CM ()
createFeatureEnabledItems user ct = createFeatureEnabledItems_ user ct >>= toView . CEvtNewChatItems user

createFeatureEnabledItems_ :: User -> Contact -> CM [AChatItem]
createFeatureEnabledItems_ user ct@Contact {mergedPreferences} =
  forM allChatFeatures $ \(ACF f) -> do
    let state = featureState $ getContactUserPreference f mergedPreferences
    createChatItem user (CDDirectRcv ct) False (uncurry (CIRcvChatFeature $ chatFeature f) state) Nothing Nothing Nothing

createFeatureItems ::
  MsgDirectionI d =>
  User ->
  Contact ->
  Contact ->
  (Contact -> ChatDirection 'CTDirect d) ->
  FeatureContent PrefEnabled d ->
  FeatureContent FeatureAllowed d ->
  (forall f. ContactUserPreference (FeaturePreference f) -> FeaturePreference f) ->
  CM' ()
createFeatureItems user ct ct' = createContactsFeatureItems user [(ct, ct')]

createContactsFeatureItems ::
  forall d.
  MsgDirectionI d =>
  User ->
  [(Contact, Contact)] ->
  (Contact -> ChatDirection 'CTDirect d) ->
  FeatureContent PrefEnabled d ->
  FeatureContent FeatureAllowed d ->
  (forall f. ContactUserPreference (FeaturePreference f) -> FeaturePreference f) ->
  CM' ()
createContactsFeatureItems user cts chatDir ciFeature ciOffer getPref = do
  let dirsCIContents = map contactChangedFeatures cts
  (errs, acis) <- partitionEithers <$> createChatItems user Nothing dirsCIContents
  unless (null errs) $ toView' $ CEvtChatErrors errs
  toView' $ CEvtNewChatItems user acis
  where
    contactChangedFeatures :: (Contact, Contact) -> (ChatDirection 'CTDirect d, ShowGroupAsSender, [(CIContent d, Maybe SharedMsgId, Maybe MsgSigStatus)])
    contactChangedFeatures (Contact {mergedPreferences = cups}, ct'@Contact {mergedPreferences = cups'}) = do
      let contents = mapMaybe (\(ACF f) -> featureCIContent_ f) allChatFeatures
      (chatDir ct', False, contents)
      where
        featureCIContent_ :: forall f. FeatureI f => SChatFeature f -> Maybe (CIContent d, Maybe SharedMsgId, Maybe MsgSigStatus)
        featureCIContent_ f
          | state /= state' = Just (fContent ciFeature state', Nothing, Nothing)
          | prefState /= prefState' = Just (fContent ciOffer prefState', Nothing, Nothing)
          | otherwise = Nothing
          where
            fContent :: FeatureContent a d -> (a, Maybe Int) -> CIContent d
            fContent ci (s, param) = ci f' s param
            f' = chatFeature f
            state = featureState cup
            state' = featureState cup'
            prefState = preferenceState $ getPref cup
            prefState' = preferenceState $ getPref cup'
            cup = getContactUserPreference f cups
            cup' = getContactUserPreference f cups'

groupFeatures :: GroupInfo -> [AGroupFeature]
groupFeatures g = if useRelays' g then channelGroupFeatures else regularGroupFeatures

createGroupFeatureChangedItems :: MsgDirectionI d => User -> ChatDirection 'CTGroup d -> (GroupFeature -> GroupPreference -> Maybe Int -> Maybe GroupMemberRole -> CIContent d) -> GroupInfo -> GroupInfo -> CM ()
createGroupFeatureChangedItems user cd ciContent GroupInfo {fullGroupPreferences = gps} g'@GroupInfo {fullGroupPreferences = gps'} =
  forM_ (groupFeatures g') $ \(AGF f) -> do
    let state = groupFeatureState $ getGroupPreference f gps
        pref' = getGroupPreference f gps'
        state'@(_, param', role') = groupFeatureState pref'
    when (state /= state') $
      createInternalChatItem user cd (ciContent (toGroupFeature f) (toGroupPreference pref') param' role') Nothing

sameGroupProfileInfo :: GroupProfile -> GroupProfile -> Bool
sameGroupProfileInfo p p' = p {groupPreferences = Nothing} == p' {groupPreferences = Nothing}

createGroupFeatureItems :: MsgDirectionI d => User -> ChatDirection 'CTGroup d -> (GroupFeature -> GroupPreference -> Maybe Int -> Maybe GroupMemberRole -> CIContent d) -> GroupInfo -> CM ()
createGroupFeatureItems user cd ciContent g = createGroupFeatureItems_ user cd False ciContent g >>= toView . CEvtNewChatItems user

createGroupFeatureItems_ :: MsgDirectionI d => User -> ChatDirection 'CTGroup d -> ShowGroupAsSender -> (GroupFeature -> GroupPreference -> Maybe Int -> Maybe GroupMemberRole -> CIContent d) -> GroupInfo -> CM [AChatItem]
createGroupFeatureItems_ user cd showGroupAsSender ciContent g@GroupInfo {fullGroupPreferences} =
  forM (groupFeatures g) $ \(AGF f) -> do
    let p = getGroupPreference f fullGroupPreferences
        (_, param, role) = groupFeatureState p
    createChatItem user cd showGroupAsSender (ciContent (toGroupFeature f) (toGroupPreference p) param role) Nothing Nothing Nothing

createInternalChatItem :: (ChatTypeI c, MsgDirectionI d) => User -> ChatDirection c d -> CIContent d -> Maybe UTCTime -> CM ()
createInternalChatItem user cd content itemTs_ = do
  ci <- createChatItem user cd False content Nothing Nothing itemTs_
  toView $ CEvtNewChatItems user [ci]

createChatItem :: (ChatTypeI c, MsgDirectionI d) => User -> ChatDirection c d -> ShowGroupAsSender -> CIContent d -> Maybe SharedMsgId -> Maybe MsgSigStatus -> Maybe UTCTime -> CM AChatItem
createChatItem user cd showGroupAsSender content sharedMsgId msgSigned itemTs_ =
  lift (createChatItems user itemTs_ [(cd, showGroupAsSender, [(content, sharedMsgId, msgSigned)])]) >>= \case
    [Right ci] -> pure ci
    [Left e] -> throwError e
    rs -> throwChatError $ CEInternalError $ "createInternalChatItem: expected 1 result, got " <> show (length rs)

createChatItems ::
  forall c d.
  (ChatTypeI c, MsgDirectionI d) =>
  User ->
  Maybe UTCTime ->
  [(ChatDirection c d, ShowGroupAsSender, [(CIContent d, Maybe SharedMsgId, Maybe MsgSigStatus)])] ->
  CM' [Either ChatError AChatItem]
createChatItems user itemTs_ dirsCIContents = do
  createdAt <- liftIO getCurrentTime
  let itemTs = fromMaybe createdAt itemTs_
  cxt <- chatStoreCxt'
  void . withStoreBatch' $ \db -> map (updateChat db cxt createdAt) dirsCIContents
  withStoreBatch' $ \db -> concatMap (createACIs db itemTs createdAt) dirsCIContents
  where
    updateChat :: DB.Connection -> StoreCxt -> UTCTime -> (ChatDirection c d, ShowGroupAsSender, [(CIContent d, Maybe SharedMsgId, Maybe MsgSigStatus)]) -> IO ()
    updateChat db cxt createdAt (cd, _, contents)
      | any (\(content, _, _) -> ciRequiresAttention content) contents || contactChatDeleted cd = void $ updateChatTsStats db cxt user cd createdAt memberChatStats
      | otherwise = pure ()
      where
        memberChatStats :: Maybe (Int, MemberAttention, Int)
        memberChatStats = case cd of
          CDGroupRcv _g (Just scope) m -> do
            let unread = length $ filter (\(content, _, _) -> ciRequiresAttention content) contents
             in Just (unread, memberAttentionChange unread itemTs_ (Just m) scope, 0)
          _ -> Nothing
    createACIs :: DB.Connection -> UTCTime -> UTCTime -> (ChatDirection c d, ShowGroupAsSender, [(CIContent d, Maybe SharedMsgId, Maybe MsgSigStatus)]) -> [IO AChatItem]
    createACIs db itemTs createdAt (cd, showGroupAsSender, contents) = map createACI contents
      where
        createACI (content, sharedMsgId, msgSigned) = do
          let hasLink_ = ciContentHasLink content Nothing
              msgVerified = toMsgVerified False msgSigned
          ciId <- createNewChatItemNoMsg db user cd showGroupAsSender content sharedMsgId hasLink_ msgVerified itemTs createdAt
          let ci = mkChatItem cd showGroupAsSender ciId content Nothing Nothing Nothing Nothing Nothing False False itemTs Nothing msgVerified createdAt
          pure $ AChatItem (chatTypeI @c) (msgDirection @d) (toChatInfo cd) ci

memberAttentionChange :: Int -> (Maybe UTCTime) -> Maybe GroupMember -> GroupChatScopeInfo -> MemberAttention
memberAttentionChange unread brokerTs_ rcvMem_ = \case
  GCSIMemberSupport (Just suppMem)
    | maybe False ((groupMemberId' suppMem ==) . groupMemberId') rcvMem_ -> MAInc unread brokerTs_
    | msgIsNewerThanLastUnanswered -> MAReset
    | otherwise -> MAInc 0 Nothing
    where
      msgIsNewerThanLastUnanswered = case (supportChat suppMem >>= lastMsgFromMemberTs, brokerTs_) of
        (Just lastMsgTs, Just brokerTs) -> lastMsgTs < brokerTs
        _ -> False
  GCSIMemberSupport Nothing -> MAInc 0 Nothing

createLocalChatItems ::
  User ->
  ChatDirection 'CTLocal 'MDSnd ->
  NonEmpty (CIContent 'MDSnd, Maybe (CIFile 'MDSnd), Maybe CIForwardedFrom, (Text, Maybe MarkdownList)) ->
  UTCTime ->
  CM [ChatItem 'CTLocal 'MDSnd]
createLocalChatItems user cd itemsData createdAt = do
  cxt <- chatStoreCxt
  void $ withStore' $ \db -> updateChatTsStats db cxt user cd createdAt Nothing
  (errs, items) <- lift $ partitionEithers <$> withStoreBatch' (\db -> map (createItem db) $ L.toList itemsData)
  unless (null errs) $ toView $ CEvtChatErrors errs
  pure items
  where
    createItem :: DB.Connection -> (CIContent 'MDSnd, Maybe (CIFile 'MDSnd), Maybe CIForwardedFrom, (Text, Maybe MarkdownList)) -> IO (ChatItem 'CTLocal 'MDSnd)
    createItem db (content, ciFile, itemForwarded, ts@(_, ft_)) = do
      let hasLink_ = ciContentHasLink content ft_
      ciId <- createNewChatItem_ db user cd False Nothing Nothing content (Nothing, Nothing, Nothing, Nothing, Nothing) itemForwarded Nothing False False hasLink_ createdAt Nothing Nothing Nothing Nothing createdAt
      forM_ ciFile $ \CIFile {fileId} -> updateFileTransferChatItemId db fileId ciId createdAt
      pure $ mkChatItem_ cd False ciId content ts ciFile Nothing Nothing itemForwarded Nothing False False hasLink_ createdAt Nothing Nothing createdAt

withUser' :: (User -> CM ChatResponse) -> CM ChatResponse
withUser' action =
  asks currentUser
    >>= readTVarIO
    >>= maybe (throwChatError CENoActiveUser) action

withUser :: (User -> CM ChatResponse) -> CM ChatResponse
withUser action = withUser' $ \user ->
  ifM (lift chatStarted) (action user) (throwChatError CEChatNotStarted)

withUser_ :: CM ChatResponse -> CM ChatResponse
withUser_ = withUser . const

withUserId' :: UserId -> (User -> CM ChatResponse) -> CM ChatResponse
withUserId' userId action = withUser' $ \user -> do
  checkSameUser userId user
  action user

withUserId :: UserId -> (User -> CM ChatResponse) -> CM ChatResponse
withUserId userId action = withUser $ \user -> do
  checkSameUser userId user
  action user

checkSameUser :: UserId -> User -> CM ()
checkSameUser userId User {userId = activeUserId} = when (userId /= activeUserId) $ throwChatError (CEDifferentActiveUser userId activeUserId)

chatStarted :: CM' Bool
chatStarted = fmap isJust . readTVarIO =<< asks agentAsync

waitChatStartedAndActivated :: CM' ()
waitChatStartedAndActivated = do
  agentStarted <- asks agentAsync
  chatActivated <- asks chatActivated
  atomically $ do
    started <- readTVar agentStarted
    activated <- readTVar chatActivated
    unless (isJust started && activated) retry

chatStoreCxt :: CM StoreCxt
chatStoreCxt = lift chatStoreCxt'
{-# INLINE chatStoreCxt #-}

chatStoreCxt' :: CM' StoreCxt
chatStoreCxt' = mkStoreCxt <$> asks config
{-# INLINE chatStoreCxt' #-}

chatVersionRange :: CM VersionRangeChat
chatVersionRange = lift chatVersionRange'
{-# INLINE chatVersionRange #-}

chatVersionRange' :: CM' VersionRangeChat
chatVersionRange' = do
  ChatConfig {chatVRange} <- asks config
  pure chatVRange
{-# INLINE chatVersionRange' #-}

adminContactReq :: ConnReqContact
adminContactReq =
  either error id $ strDecode "zero:/contact#/?v=1&smp=smp%3A%2F%2FPQUV2eL0t7OStZOoAsPEV2QYWt4-xilbakvGUGOItUo%3D%40zerorelay.simpl.global%2FK1rslx-m5bpXVIdMZg9NLUZ_8JBm8xTt%23MCowBQYDK2VuAyEALDeVe-sG8mRY22LsXlPgiwTNs9dbiLrNuA7f3ZMAJ2w%3D"

contactCReqHash :: ConnReqContact -> ConnReqUriHash
contactCReqHash = ConnReqUriHash . C.sha256Hash . strEncode

zeroChatImage :: ImageData
zeroChatImage = ImageData "data:image/jpg;base64,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8k0wCiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKluv4PxqKpbr+D8aAK9FFFABRRRQAUUUUAFFFFAFi1/j/AAqKpbX+P8KioAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAr0H4J/8lV0v/cn/APRT159XoPwT/wCSq6X/ALk//op6APq+iiikAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAcL8ZP+SUa59If/AEdHXyTX1t8ZP+SUa59If/R0dfJNMAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACpbr+D8aiqW6/g/GgCvRRRQAUUUUAFFFFABRRRQBYtf4/wAKiqW1/j/CoqACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAK2/CXiW48I+JLbWraCKeWAOBHKTtO5Svb61iUUAey/8NFa5/0BNO/76f8Axo/4aK1z/oCad/30/wDjXjVFAHsv/DRWuf8AQE07/vp/8aP+Gitc/wCgJp3/AH0/+NeNUUAey/8ADRWuf9ATTv8Avp/8aP8AhorXP+gJp3/fT/4141RQB7L/AMNFa5/0BNO/76f/ABo/4aK1z/oCad/30/8AjXjVFAHsv/DRWuf9ATTv++n/AMaP+Gitc/6Amnf99P8A4141Xpfwk+HDeL9V/tLUYiNFtHG8Hj7Q452D29fy78AHu/w98Q6/4p0P+19Z0+2sYZiDaxx7tzr/AHzk8A9vXr0xXXUiIsaKiKFRRhVUYAHoKWkAUUUUAFFFeVfGH4kjwxp7aJpU3/E4uk+d1PNtGe/sx7enX0yAcj8bfiOl+8vhPSZFa3jcfbpl5DupyIx7AgEn1GOxz4lQSSSSck0UwCiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKluv4PxqKpbr+D8aAK9FFFABRRRQAUUUUAFFFFAFi1/j/Coqltf4/wAKioAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKK0NE0W+8Q6xbaVp0JlurhtqjsPUk9gByTQBseA/BV7448Qx2FvujtY8PdXGOIk/+KPQD+gNfXek6VZaHpVtpunwLDa26BI0Hp6n1J6k9yayvBXg+x8FeHotMswHkPz3E5GGmk7n6dgOwroqQBRRRQAUUVleJPENh4W0K41bUpNkEI4UfekbsqjuT/nigDE+Inju18DaA1wdsuoz5S0tyfvN/eP+yO/4DvXyRqF/dapqE9/ezvPdTuZJJHPLE1peLPFN/wCMPEE+rag3zP8ALFED8sSDoo+n6nJrEpgFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFS3X8H41FUt1/B+NAFeiiigAooooAKKKKACiiigCxa/x/hUVS2v8AH+FRUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAPiiknmSGFGklkYKiKMlieAAO5r6q+FXw6j8F6P9qvUVtau1Bnbr5K9RGD/ADPc/QVynwU+Gv2OKLxXrMH+kSLmwgcf6tT/AMtCPU9vQc9xj26kAUUUUAFFFFAEV1dQWVpNdXUqQwQoXkkc4CqBkk18m/E34gT+ONd/cl49JtSVtYTxu9ZGHqf0HHrnp/jN8Sv7bu38N6PPnTYH/wBJmQ8XEgP3R6qp/M/QV4/TAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACpbr+D8aiqW6/g/GgCvRRRQAUUUUAFFFFABRRRQBYtf4/wqKpbX+P8KioAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAr1X4PfDY+J9QXXNVh/wCJPav8kbDi5kHb3Ud/Xp645r4d+BLrxz4gW2G+LT4MPd3AH3V/uj/aPb8T2r630+wtdL0+CwsoFgtYEEccaDhQKALIAAwBgCiiikAUUUUAFeOfGf4lf2NayeGdHnxqE6YupkPMEZH3R6Mw/IfUY6n4nfEGDwPoe2Bkk1e6UraxHnZ6yMPQfqePXHydc3M95dS3NzK8s8rl5JHOSzE5JJoAiooopgFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABUt1/B+NRVLdfwfjQBXooooAKKKKACiiigAooooAsWv8AH+FRVLa/x/hUVABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAVq+HPD1/4o1y30nTY988zcsfuxr3Zj2ArPtrae9uorW2ieWeZwkcaDJZicAAV9Y/DH4fQeB9DzOEk1e6UNdSjnb6RqfQfqefTABveEvC1h4P8PwaTYL8qfNLKRhpZD1Y/wCeBgVuUUUgCiiigArC8XeKrDwd4fn1W/bIX5YogcNNIeij/HsMmtTUdQtNJ064v76dYLW3QvJI3RQP89K+RviH46u/HPiBrp90VhBlLS3J+4v94/7R6n8B2oAxfEXiC/8AFGuXOralLvuJm6D7qL2VR2ArLoopgFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAVLdfwfjUVS3X8H40AV6KKKACiiigAooooAKKKKALFr/H+FRVLa/x/hUVABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRXsHwZ+Gv9t3aeJNYgzptu/8Ao0Lji4kB+8fVVP5n6GgDrvgx8Nf7GtY/EusQY1GdM2sLjmCMj7x9GYfkPqcexUUUgCiiigApCQoJJAA5JNLXh3xr+JX2dJfCejT/AL5xtv50P3Qf+WQPqf4vbjucAHJ/F/4knxTqJ0bSpj/Y1q/zOp4uZB/F/ujt69fTHllFFMAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAqW6/g/Goqluv4PxoAr0UUUAFFFFABRRRQAUUUUAWLX+P8KiqW1/j/AAqKgAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiitvwp4Xv8Axfr8Gk6enzud0kpHyxIOrt7D9Tgd6AN34Z/D+fxxroEoePSbUhrqYcZ9I1P94/oOfTP1la2sFjaQ2trEkNvCgSONBgKoGABWf4b8O2HhXQrfSdNj2wQjlj96Rj1Zj3J/+t0Fa1IAooooAKKK5rxx4ysfBPh6TUbrEk7ZS2t84Msnp9B1J7D3xQBz3xX+IyeDdI+w2EitrV2h8odfIToZCP5D1+lfK8kjzSvLK7PI5LMzHJYnqSauazrF9r+r3OqajMZrq4fc7Hp7ADsAOAPQVRpgFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABUt1/B+NRVLdfwfjQBXooooAKKKKACiiigAooooAsWv8f4VFUtr/H+FRUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQBYsLG61O/gsbKF57mdxHHGg5ZjX1v8ADrwHa+BtAWD5JdRuAHu5wPvN2Uf7I7evJ71wX7P3hiw/sm68SyJ5l+Z2toiw4iUKpJHud2M+gx3OfbqQBRRRQAUUUUAUdZ1ix0DSLnVNRmENrbpudj19gB3JPAHqa+QvHHjK+8beIZNRusxwLlLa3zkRR9h9T1J7n2xXpXxXTxv4z1f7FYeHtTXRbRz5Q8ojz36GQj+Q9PrXnP8Awrbxp/0LWo/9+jTA5aiup/4Vt40/6FrUf+/Ro/4Vt40/6FrUf+/RoA5aiup/4Vt40/6FrUf+/Ro/4Vt40/6FrUf+/RoA5aiup/4Vt40/6FrUf+/Ro/4Vt40/6FrUf+/RoA5aiup/4Vt40/6FrUf+/Ro/4Vt40/6FrUf+/RoA5aiup/4Vt40/6FrUf+/Ro/4Vt40/6FrUf+/RoA5aiup/4Vt40/6FrUf+/RrA1LTb3SL+Wx1G2ktrqLG+KQYZcgEZH0IP40AVaKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAqW6/g/Goqluv4PxoAr0UUUAFFFFABRRRQAUUUUAWLX+P8KiqW1/j/AAqKgAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKAPpz9n/8A5J3N/wBhCX/0BK9Uryv9n/8A5J3N/wBhCX/0BK9UpAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAV8l/Gf/AJKzrf8A2w/9ER19aV8l/Gf/AJKzrf8A2w/9ER0AcHRRRTAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACpbr+D8aiqW6/g/GgCvRRRQAUUUUAFFFFABRRRQBYtf4/wAKiqW1/j/CoqACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA+nP2f/APknc3/YQl/9ASvVK8E+D/xD8LeFvBkun6zqn2W6a8eUJ9nlf5SqgHKqR2Nd/wD8Ln8Af9B//wAk5/8A4ikB3lFcH/wufwB/0H//ACTn/wDiKP8Ahc/gD/oP/wDknP8A/EUAd5RXB/8AC5/AH/Qf/wDJOf8A+Io/4XP4A/6D/wD5Jz//ABFAHeUVwf8AwufwB/0H/wDyTn/+Io/4XP4A/wCg/wD+Sc//AMRQB3lFcH/wufwB/wBB/wD8k5//AIij/hc/gD/oP/8AknP/APEUAd5RXB/8Ln8Af9B//wAk5/8A4ij/AIXP4A/6D/8A5Jz/APxFAHeUVwf/AAufwB/0H/8AyTn/APiKP+Fz+AP+g/8A+Sc//wARQB3lFcH/AMLn8Af9B/8A8k5//iKP+Fz+AP8AoP8A/knP/wDEUAd5RXB/8Ln8Af8AQf8A/JOf/wCIo/4XP4A/6D//AJJz/wDxFAHeV8l/Gf8A5Kzrf/bD/wBER17x/wALn8Af9B//AMk5/wD4ivnj4m61p/iH4h6pqml3H2iyn8ry5djJu2xIp4YAjkEdKAOSooopgFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABUt1/B+NRVLdfwfjQBXooooAKKKKACiiigAooooAsWv8f4VFUtr/H+FRUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAVLdfwfjUVS3X8H40AV6KKKACiiigAooooAKKKKALFr/H+FRVLa/x/hUVABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFS3X8H41FUt1/B+NAFeiiigAooooAKKKKACiiigCxa/x/hUVS2v8AH+FRUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAVLdfwfjUVS3X8H40AV6KKKACiiigAooooAKKKKALFr/AB/hUVS2v8f4VFQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABUt1/B+NRVLdfwfjQBXooooAKKKKACiiigAooooAsWv8f4VFUtr/H+FRUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAVLdfwfjUVS3X8H40AV6KKKACiiigAooooAKKKKALFr1aoj1p1ucSY9RRIMSMPegBtFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQADrUt11WmRjMij3ouDmTHoKAIqKKKACiiigAooooAKKKKAFVtrA+lWJxnDDoarVZhIkjMZ6igCGilIIJB6ikoAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKUAkgDqaAJYBjLHoKrs25ifWrExEcYjHU1WoAKKKKACiiigAooooAKKKKAClVijBh2pKKALTqJUDr1qCiOQxtkdO4qdlWUbkPNAEFFKQQcEYNJQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFKAScAZNACVOiiJC7daFVYhuc81BJIZGyenYUANZi7Fj3pKKKACiiigAooooAKKKKACiiigAooooAKVWKHKnFJRQBZEySDEgwfWgwZ5Vsiq1KrMvQkUASGNx1U03B9KcLhx1waf9qP8Ad/WgCKipftX+x+tH2r/Y/WgCKipftX+x+tH2r/Y/WgCKipftX+x+tH2r/Y/WgCKipftX+x+tH2r/AGP1oAioqX7V/sfrR9q/2P1oAioqX7V/sfrR9q/2P1oAioqX7V/sfrR9q/2P1oAioqX7V/sfrR9q/wBj9aAIqKl+1f7H60fav9j9aAIqKl+1f7H60fav9j9aAIqKl+1f7H60fav9j9aAIqKl+1f7H60fav8AY/WgCKipftX+x+tH2r/Y/WgCKipftX+x+tH2r/Y/WgCKipftX+x+tH2r/Y/WgCKipftX+x+tH2r/AGP1oAioqX7V/sfrR9q/2P1oAioqX7V/sfrR9q/2P1oAioqX7V/sfrR9q/2P1oAioqX7V/sfrR9q/wBj9aAIsH0pwjc9FNP+1H+7+tMNw56YFAEggxyzYFBmSMYjGT61XZmbqSaSgBWYucsc0lFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQB//9k="

zeroTeamContactProfile :: Profile
zeroTeamContactProfile =
  Profile
    { displayName = "Ask Zero",
      fullName = "",
      shortDescr = Just "Send questions about Zero and your suggestions",
      description = Nothing,
      image = Just zeroChatImage,
      contactLink = Just $ CLFull adminContactReq,
      peerType = Nothing,
      preferences = Nothing,
      badge = Nothing,
      contactDomain = Nothing
    }

timeItToView :: String -> CM' a -> CM' a
timeItToView s action = do
  t1 <- liftIO getCurrentTime
  a <- action
  t2 <- liftIO getCurrentTime
  let diff = diffToMilliseconds $ diffUTCTime t2 t1
  toView' $ CEvtTimedAction s diff
  pure a

epochStart :: UTCTime
epochStart = UTCTime (fromGregorian 1970 1 1) (secondsToDiffTime 0)

drgRandomBytes :: Int -> CM ByteString
drgRandomBytes n = asks random >>= atomically . C.randomBytes n
