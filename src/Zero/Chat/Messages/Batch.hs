{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Zero.Chat.Messages.Batch
  ( MsgBatch (..),
    BatchMode (..),
    encodeBatchElement,
    encodeFwdElement,
    encodeBinaryBatch,
    batchMessages,
    batchDeliveryTasks1,
    batchElements,
    batchProfilesWithBody,
    batchProfiles,
    maxBatchElementSize,
  )
where

import Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as B
import Data.Char (ord)
import Data.Function (on)
import Data.List (foldl', sortBy)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as L
import Data.Ord (Down (..))
import Data.Word (Word8)
import Zero.Chat.Controller (ChatError (..), ChatErrorType (..))
import Zero.Chat.Delivery
import Zero.Chat.Messages
import Zero.Chat.Protocol
import Data.Maybe (isJust)
import Zero.Chat.Types (GroupMember (..), LocalProfile (..), VersionRangeChat)
import Zero.Messaging.Encoding (Large (..), smpEncode, smpEncodeList)

data BatchMode = BMJson | BMBinary
  deriving (Eq, Show)

encodeBatchElement :: Maybe SignedMsg -> ByteString -> ByteString
encodeBatchElement Nothing body = body
encodeBatchElement (Just SignedMsg {chatBinding, signatures}) body =
  "/" <> smpEncode (chatBinding, signatures) <> body

data MsgBatch = MsgBatch ByteString [SndMessage]

batchMessages :: BatchMode -> Int -> [Either ChatError SndMessage] -> [Either ChatError MsgBatch]
batchMessages mode maxLen = addBatch . foldr addToBatch ([], [], [], 0, 0)
  where
    addToBatch :: Either ChatError SndMessage -> ([Either ChatError MsgBatch], [ByteString], [SndMessage], Int, Int) -> ([Either ChatError MsgBatch], [ByteString], [SndMessage], Int, Int)
    addToBatch (Left err) acc = (Left err : addBatch acc, [], [], 0, 0)
    addToBatch (Right msg@SndMessage {msgBody, signedMsg_}) acc@(batches, bodies, msgs, len, n)
      | batchLen mode len' n' <= maxLen = (batches, body : bodies, msg : msgs, len', n')
      | msgLen <= maxLen = (addBatch acc, [body], [msg], msgLen, 1)
      | otherwise = (errLarge msg : addBatch acc, [], [], 0, 0)
      where
        body = encodeBatchElement signedMsg_ msgBody
        msgLen = B.length body
        len' = len + msgLen
        n' = n + 1
        errLarge SndMessage {msgId} = Left $ ChatError $ CEInternalError ("large message " <> show msgId)
    addBatch :: ([Either ChatError MsgBatch], [ByteString], [SndMessage], Int, Int) -> [Either ChatError MsgBatch]
    addBatch (batches, bodies, msgs, _, n)
      | n == 0 = batches
      | otherwise =
          let encoded = encodeBatch mode bodies
           in Right (MsgBatch encoded msgs) : batches

batchDeliveryTasks1 :: VersionRangeChat -> Int -> NonEmpty MessageDeliveryTask -> (Maybe ByteString, [MessageDeliveryTask], [MessageDeliveryTask])
batchDeliveryTasks1 _vr maxLen = toResult . foldl' addToBatch ([], [], [], 0, 0) . L.toList
  where
    addToBatch :: ([ByteString], [MessageDeliveryTask], [MessageDeliveryTask], Int, Int) -> MessageDeliveryTask -> ([ByteString], [MessageDeliveryTask], [MessageDeliveryTask], Int, Int)
    addToBatch (msgBodies, accepted, large, len, n) task
      | msgLen + 4 > maxLen = (msgBodies, accepted, task : large, len, n)
      | len' + (n + 1) * 2 + 2 <= maxLen = (msgBody : msgBodies, task : accepted, large, len', n + 1)
      | otherwise = (msgBodies, accepted, large, len, n)
      where
        MessageDeliveryTask {fwdSender, brokerTs = fwdBrokerTs, verifiedMsg} = task
        msgBody = encodeFwdElement GrpMsgForward {fwdSender, fwdBrokerTs} verifiedMsg
        msgLen = B.length msgBody
        len' = len + msgLen
    toResult :: ([ByteString], [MessageDeliveryTask], [MessageDeliveryTask], Int, Int) -> (Maybe ByteString, [MessageDeliveryTask], [MessageDeliveryTask])
    toResult (msgBodies, accepted, large, _, _) =
      let encoded = encodeBinaryBatch (reverse msgBodies)
          body = if null accepted then Nothing else Just encoded
       in (body, reverse accepted, reverse large)

batchElements :: Int -> [ByteString] -> ([ByteString], Int)
batchElements maxLen = finish . foldl' addToBatch ([], [], 0, 0, 0)
  where
    addToBatch (batches, elems, len, n, dropped) el
      | elLen + 4 > maxLen = (batches, elems, len, n, dropped + 1)
      | len + elLen + (n + 1) * 2 + 2 <= maxLen = (batches, el : elems, len + elLen, n + 1, dropped)
      | otherwise = (closeBatch elems : batches, [el], elLen, 1, dropped)
      where
        elLen = B.length el
    closeBatch elems = encodeBinaryBatch (reverse elems)
    finish (batches, elems, _, n, dropped)
      | n == 0 = (reverse batches, dropped)
      | otherwise = (reverse (closeBatch elems : batches), dropped)

encodeFwdElement :: GrpMsgForward -> VerifiedMsg 'Json -> ByteString
encodeFwdElement fwd verifiedMsg = ">" <> smpEncode fwd <> encodeBatchElement signedMsg_ msgBody
  where
    (_, signedMsg_, msgBody) = verifiedMsgParts verifiedMsg

encodeBatch :: BatchMode -> [ByteString] -> ByteString
encodeBatch _ [] = mempty
encodeBatch _ [msg] = msg
encodeBatch BMJson msgs = B.concat ["[", B.intercalate "," msgs, "]"]
encodeBatch BMBinary msgs = B.cons '=' $ smpEncodeList (map Large msgs)

encodeBinaryBatch :: [ByteString] -> ByteString
encodeBinaryBatch [] = mempty
encodeBinaryBatch msgs = B.cons '=' $ smpEncodeList (map Large msgs)

batchLen :: BatchMode -> Int -> Int -> Int
batchLen _ _ 0 = 0
batchLen _ len 1 = len
batchLen BMJson len n = len + n + 1
batchLen BMBinary len n = len + n * 2 + 2

maxBatchElementSize :: Int
maxBatchElementSize = maxEncodedMsgLength - 4

hasImage :: GroupMember -> Bool
hasImage GroupMember {memberProfile = LocalProfile {image}} = isJust image

batchProfilesWithBody :: Int -> ByteString -> [(GroupMember, ByteString)] -> (ByteString, [GroupMember], [(GroupMember, ByteString)], [GroupMember])
batchProfilesWithBody maxLen body labeled =
  let (_, _, acceptedPairs, overflow, large) =
        foldl' step initState (sortBy (compare `on` (hasImage . fst)) labeled)
   in (buildBody acceptedPairs, map fst acceptedPairs, overflow, large)
  where
    initEmpty = B.null body
    initLen = B.length body
    initCount = if initEmpty then 0 else ord (B.index body 1)
    initState = (initLen, initCount, [], [], [])
    step (totalLen, count, acceptedPairs, overflow, large) (s, e)
      | B.length e + 4 > maxLen = (totalLen, count, acceptedPairs, overflow, s : large)
      | count >= 255 = full
      | candidateLen <= maxLen = (candidateLen, count + 1, (s, e) : acceptedPairs, overflow, large)
      | otherwise = full
      where
        full = (totalLen, count, acceptedPairs, (s, e) : overflow, large)
        candidateLen
          | initEmpty && null acceptedPairs = 4 + B.length e
          | otherwise = totalLen + 2 + B.length e
    buildBody [] = body
    buildBody acceptedPairs =
      let prefixedNew = B.concat [smpEncode (Large e) | (_, e) <- acceptedPairs]
          newCount = initCount + length acceptedPairs
          tail_ = if initEmpty then B.empty else B.drop 2 body
       in B.concat [B.singleton '=', BS.singleton (fromIntegral newCount :: Word8), prefixedNew, tail_]

batchProfiles :: Int -> [(GroupMember, ByteString)] -> ([(ByteString, [GroupMember])], [GroupMember])
batchProfiles maxLen =
  finish . foldr addToBatch ([], [], [], 0, 0, []) . sortBy (compare `on` (Down . hasImage . fst))
  where
    addToBatch :: (GroupMember, ByteString) -> ([(ByteString, [GroupMember])], [ByteString], [GroupMember], Int, Int, [GroupMember]) -> ([(ByteString, [GroupMember])], [ByteString], [GroupMember], Int, Int, [GroupMember])
    addToBatch (s, e) acc@(batches, elems, members, len, n, large)
      | B.length e + 4 > maxLen = (batches, elems, members, len, n, s : large)
      | n + 1 <= 255 && len + B.length e + (n + 1) * 2 + 2 <= maxLen =
          (batches, e : elems, s : members, len + B.length e, n + 1, large)
      | otherwise =
          (flush acc, [e], [s], B.length e, 1, large)
    flush :: ([(ByteString, [GroupMember])], [ByteString], [GroupMember], Int, Int, [GroupMember]) -> [(ByteString, [GroupMember])]
    flush (batches, _, _, _, 0, _) = batches
    flush (batches, elems, members, _, _, _) =
      (encodeBinaryBatch elems, members) : batches
    finish acc@(_, _, _, _, _, large) = (flush acc, large)
