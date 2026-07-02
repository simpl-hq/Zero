{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}

-- chat badges and xftp file size quota helpers
module Zero.Chat.Badges
  ( BadgeType (..),
    BadgeStatus (..),
    BadgeInfo (..),
    BadgeCredential (..),
    BadgeProof (..),
    LocalBadge (..),
    JSONBadge (..),
    BBSPublicKeyStr (..),
    localBadgeInfo,
    localBadgeStatus,
    maxXFTPFileSize,
    maxFileSizeSupporter,
    maxFileSizeLegend,
    ProofPresHeaderTag (..),
    ProofPresHeader (..),
    BadgePurchase (..),
    BadgeMasterKey (..),
    BadgeRequest (..),
    VerifiedBadgeRequest (..),
    bbsBadgeHeader,
    generateMasterKey,
    verifyPayment,
    issueBadge,
    verifyCredential,
    generateBadgeProof,
    badgeProof,
    verifyBadge,
    verifyBadge_,
    mkBadgeStatus,
    BadgeRow,
    badgeToRow,
    localBadgeToRow,
    rowToBadge,
  ) where

import Control.Concurrent.STM
import Crypto.Random (ChaChaDRG)
import Data.Aeson (FromJSON (..), ToJSON (..))
import qualified Data.Aeson.TH as JQ
import qualified Data.Attoparsec.ByteString.Char8 as A
import Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as B
import Data.Either (fromRight)
import Data.Int (Int64)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.String
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)
import Data.Time.Clock (NominalDiffTime, UTCTime, addUTCTime, nominalDay)
import Zero.FileTransfer.Description (gb, maxFileSize)
import Zero.Messaging.Agent.Store.DB (Binary (..), BoolInt (..), fromTextField_)
import qualified Zero.Messaging.Crypto as C
import Zero.Messaging.Crypto.BBS
import Zero.Messaging.Encoding.String
import Zero.Messaging.Parsers (defaultJSON, dropPrefix, enumJSON)
#if defined(dbPostgres)
import Database.PostgreSQL.Simple.FromField (FromField (..))
import Database.PostgreSQL.Simple.ToField (ToField (..))
#else
import Database.SQLite.Simple.FromField (FromField (..))
import Database.SQLite.Simple.ToField (ToField (..))
#endif

data BadgeType
  = BTSupporter
  | BTLegend
  | BTInvestor
  | BTUnknown Text
  deriving (Eq, Show)

instance TextEncoding BadgeType where
  textEncode = \case
    BTSupporter -> "supporter"
    BTLegend -> "legend"
    BTInvestor -> "investor"
    BTUnknown tag -> tag
  textDecode s = Just $ case s of
    "supporter" -> BTSupporter
    "legend" -> BTLegend
    "investor" -> BTInvestor
    tag -> BTUnknown tag

instance ToJSON BadgeType where
  toJSON = textToJSON
  toEncoding = textToEncoding

instance FromJSON BadgeType where
  parseJSON = textParseJSON "BadgeType"

data BadgeStatus = BSActive | BSExpired | BSExpiredOld | BSFailed | BSUnknownKey
  deriving (Eq, Show)

data BadgeInfo = BadgeInfo
  { badgeType :: BadgeType,
    badgeExpiry :: Maybe UTCTime,
    badgeExtra :: Text
  }
  deriving (Eq, Show)

badgeOldInterval :: NominalDiffTime
badgeOldInterval = 31 * nominalDay

mkBadgeStatus :: UTCTime -> Maybe Bool -> BadgeInfo -> BadgeStatus
mkBadgeStatus now verified BadgeInfo {badgeExpiry} = case verified of
  Nothing -> BSUnknownKey
  Just False -> BSFailed
  Just True -> case badgeExpiry of
    Just e
      | addUTCTime badgeOldInterval e < now -> BSExpiredOld
      | e < now -> BSExpired
    _ -> BSActive

data BadgeCredential = BadgeCredential
  { badgeKeyIdx :: Int,
    masterKey :: BadgeMasterKey,
    signature :: BBSSignature,
    badgeInfo :: BadgeInfo
  }
  deriving (Eq, Show)

data BadgeProof = BadgeProof
  { badgeKeyIdx :: Int,
    presHeader :: BBSPresHeader,
    proof :: BBSProof,
    badgeInfo :: BadgeInfo
  }
  deriving (Eq, Show)

data LocalBadge
  = OwnBadge BadgeCredential BadgeStatus
  | PeerBadge BadgeProof BadgeStatus
  | ShownBadge BadgeInfo BadgeStatus
  deriving (Eq, Show)

localBadgeInfo :: LocalBadge -> BadgeInfo
localBadgeInfo = \case
  OwnBadge BadgeCredential {badgeInfo} _ -> badgeInfo
  PeerBadge BadgeProof {badgeInfo} _ -> badgeInfo
  ShownBadge i _ -> i

localBadgeStatus :: LocalBadge -> BadgeStatus
localBadgeStatus = \case
  OwnBadge _ st -> st
  PeerBadge _ st -> st
  ShownBadge _ st -> st

maxFileSizeSupporter :: Int64
maxFileSizeSupporter = gb 2

maxFileSizeLegend :: Int64
maxFileSizeLegend = gb 5

maxXFTPFileSize :: Maybe LocalBadge -> Int64
maxXFTPFileSize _ = maxFileSizeLegend

data ProofPresHeaderTag = PHTestTag | PHUnknownTag Char

instance StrEncoding ProofPresHeaderTag where
  strEncode = B.singleton . \case
    PHTestTag -> 'T'
    PHUnknownTag c -> c
  strP = tag <$> A.anyChar
    where
      tag = \case
        'T' -> PHTestTag
        c -> PHUnknownTag c

data ProofPresHeader
  = PHTest ByteString
  | PHUnknown Char ByteString
  deriving (Eq, Show)
  deriving (ToJSON, FromJSON) via (StrJSON "ProofPresHeader" ProofPresHeader)

instance StrEncoding ProofPresHeader where
  strEncode = \case
    PHTest nonce -> strEncode PHTestTag <> nonce
    PHUnknown c b -> strEncode (PHUnknownTag c) <> b
  strP =
    strP >>= \case
      PHTestTag -> PHTest <$> A.takeByteString
      PHUnknownTag c -> PHUnknown c <$> A.takeByteString

proofPresHeaderAccepted :: ProofPresHeader -> Bool
proofPresHeaderAccepted = \case
  PHTest _ -> True
  PHUnknown _ _ -> True

data BadgePurchase
  = BPAppleReceipt Text
  | BPGoogleReceipt Text
  | BPStripeSession
  | BPRedeemCode Text
  deriving (Eq, Show)

newtype BadgeMasterKey = BadgeMasterKey ByteString
  deriving newtype (Eq, Show, StrEncoding)

instance ToJSON BadgeMasterKey where
  toJSON = strToJSON
  toEncoding = strToJEncoding

instance FromJSON BadgeMasterKey where
  parseJSON = strParseJSON "BadgeMasterKey"

generateMasterKey :: TVar ChaChaDRG -> IO BadgeMasterKey
generateMasterKey drg = BadgeMasterKey <$> atomically (C.randomBytes 32 drg)

data BadgeRequest = BadgeRequest
  { masterKey :: BadgeMasterKey,
    badgeInfo :: BadgeInfo
  }
  deriving (Show)

newtype VerifiedBadgeRequest = VerifiedBadgeRequest BadgeRequest
  deriving (Show)

bbsBadgeHeader :: BBSHeader
bbsBadgeHeader = BBSHeader "Zero badges v1"

bbsBadgeMessageCount :: Int
bbsBadgeMessageCount = 4

bbsBadgeDisclosedIndexes :: [Int]
bbsBadgeDisclosedIndexes = [1, 2, 3]

encodeExpiry :: Maybe UTCTime -> ByteString
encodeExpiry = maybe "lifetime" strEncode

badgeMessages :: BadgeMasterKey -> BadgeInfo -> [ByteString]
badgeMessages (BadgeMasterKey ms) info = ms : badgeInfoMessages info

badgeInfoMessages :: BadgeInfo -> [ByteString]
badgeInfoMessages BadgeInfo {badgeType, badgeExpiry, badgeExtra} =
  [encodeExpiry badgeExpiry, encodeUtf8 (textEncode badgeType), encodeUtf8 badgeExtra]

verifyPayment :: BadgePurchase -> BadgeRequest -> IO (Maybe VerifiedBadgeRequest)
verifyPayment _payment req = pure $ Just (VerifiedBadgeRequest req)

issueBadge :: Int -> BBSSecretKey -> VerifiedBadgeRequest -> IO (Either String BadgeCredential)
issueBadge keyIdx sk (VerifiedBadgeRequest BadgeRequest {masterKey, badgeInfo})
  | badgeExtra badgeInfo /= "" = pure $ Left "badgeExtra must be empty (reserved)"
  | otherwise = fmap (\sig -> BadgeCredential keyIdx masterKey sig badgeInfo) <$> bbsSign sk bbsBadgeHeader (badgeMessages masterKey badgeInfo)

verifyCredential :: BBSPublicKey -> BadgeCredential -> IO Bool
verifyCredential pk (BadgeCredential _ masterKey signature badgeInfo) =
  bbsVerify pk signature bbsBadgeHeader (badgeMessages masterKey badgeInfo)

generateBadgeProof :: BBSPublicKey -> BadgeCredential -> BBSPresHeader -> IO (Either String BadgeProof)
generateBadgeProof pk (BadgeCredential keyIdx masterKey signature badgeInfo) ph =
  fmap (\p -> BadgeProof keyIdx ph p badgeInfo) <$> bbsProofGen pk signature bbsBadgeHeader ph bbsBadgeDisclosedIndexes (badgeMessages masterKey badgeInfo)

badgeProof :: BBSPublicKey -> BadgeCredential -> ProofPresHeader -> IO (Either String BadgeProof)
badgeProof pk cred ph = generateBadgeProof pk cred (BBSPresHeader $ strEncode ph)

verifyBadge :: Map Int BBSPublicKey -> BadgeProof -> IO (Maybe Bool)
verifyBadge keys b@(BadgeProof keyIdx _ _ _) = case M.lookup keyIdx keys of
  Nothing -> pure Nothing
  Just pk -> Just <$> verifyBadgeWith pk b

verifyBadgeWith :: BBSPublicKey -> BadgeProof -> IO Bool
verifyBadgeWith pk (BadgeProof _ ph@(BBSPresHeader phBytes) proof badgeInfo)
  | either (const False) proofPresHeaderAccepted (strDecode phBytes) =
      bbsProofVerify pk proof bbsBadgeHeader ph bbsBadgeDisclosedIndexes bbsBadgeMessageCount (badgeInfoMessages badgeInfo)
  | otherwise = pure False

verifyBadge_ :: Map Int BBSPublicKey -> Maybe BadgeProof -> IO (Maybe Bool)
verifyBadge_ keys = maybe (pure (Just False)) (verifyBadge keys)

instance FromField BadgeType where fromField = fromTextField_ textDecode

instance ToField BadgeType where toField = toField . textEncode

type BadgeRow = (Maybe (Binary ByteString), Maybe (Binary ByteString), Maybe UTCTime, Maybe Text, Maybe BoolInt, Maybe Text, Maybe (Binary ByteString), Maybe (Binary ByteString), Maybe Int)

badgeToRow :: Maybe BadgeProof -> Maybe Bool -> BadgeRow
badgeToRow badge verified = localBadgeToRow $ (`PeerBadge` st) <$> badge
  where
    st = case verified of
      Just True -> BSActive
      Just False -> BSFailed
      Nothing -> BSUnknownKey

localBadgeToRow :: Maybe LocalBadge -> BadgeRow
localBadgeToRow (Just lb) = case lb of
  OwnBadge (BadgeCredential idx (BadgeMasterKey mk) (BBSSignature sg) BadgeInfo {badgeType, badgeExpiry, badgeExtra}) st ->
    (Nothing, Nothing, badgeExpiry, Just (textEncode badgeType), verifiedField st, Just badgeExtra, Just (Binary mk), Just (Binary sg), Just idx)
  PeerBadge (BadgeProof idx (BBSPresHeader ph) (BBSProof p) BadgeInfo {badgeType, badgeExpiry, badgeExtra}) st ->
    (Just (Binary p), Just (Binary ph), badgeExpiry, Just (textEncode badgeType), verifiedField st, Just badgeExtra, Nothing, Nothing, Just idx)
  ShownBadge BadgeInfo {badgeType, badgeExpiry, badgeExtra} st ->
    (Nothing, Nothing, badgeExpiry, Just (textEncode badgeType), verifiedField st, Just badgeExtra, Nothing, Nothing, Nothing)
  where
    verifiedField st = case st of
      BSFailed -> Just (BI False)
      BSUnknownKey -> Nothing
      _ -> Just (BI True)
localBadgeToRow Nothing = (Nothing, Nothing, Nothing, Nothing, Just (BI False), Nothing, Nothing, Nothing, Nothing)

rowToBadge :: UTCTime -> BadgeRow -> Maybe LocalBadge
rowToBadge now (p_, ph_, badgeExpiry, type_, verified_, extra_, mk_, sg_, idx_) = do
  btText <- type_
  bt <- textDecode btText
  let info = BadgeInfo {badgeType = bt, badgeExpiry, badgeExtra = maybe "" id extra_}
      st = mkBadgeStatus now (unBI <$> verified_) info
  case (mk_, sg_, p_, ph_, idx_) of
    (Just (Binary mk), Just (Binary sg), _, _, Just idx) -> Just $ OwnBadge (BadgeCredential idx (BadgeMasterKey mk) (BBSSignature sg) info) st
    (_, _, Just (Binary p), Just (Binary ph), Just idx) -> Just $ PeerBadge (BadgeProof idx (BBSPresHeader ph) (BBSProof p) info) st
    _ -> Just $ ShownBadge info st

$(JQ.deriveJSON (enumJSON $ dropPrefix "BS") ''BadgeStatus)

$(JQ.deriveJSON defaultJSON ''BadgeInfo)

$(JQ.deriveJSON defaultJSON ''BadgeRequest)

$(JQ.deriveJSON defaultJSON ''BadgeCredential)

$(JQ.deriveJSON defaultJSON ''BadgeProof)

data JSONBadge = JSONBadge {badge :: BadgeInfo, status :: BadgeStatus}

$(JQ.deriveJSON defaultJSON ''JSONBadge)

instance ToJSON LocalBadge where
  toJSON lb = toJSON $ JSONBadge (localBadgeInfo lb) (localBadgeStatus lb)
  toEncoding lb = toEncoding $ JSONBadge (localBadgeInfo lb) (localBadgeStatus lb)

instance FromJSON LocalBadge where
  parseJSON v = do
    JSONBadge info st <- parseJSON v
    pure $ ShownBadge info st

newtype BBSPublicKeyStr = BBSPublicKeyStr {toBBSPublicKey :: BBSPublicKey}

instance IsString BBSPublicKeyStr where
  fromString = BBSPublicKeyStr . fromRight (error "bad base64 in BBSPublicKey") . strDecode . B.pack
