{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}

-- chat badges and xftp file size quota helpers
module Zero.Chat.Mobile.Badges
  ( zero_core_runtime_badge_keygen,
    zero_core_runtime_badge_issue,
    BadgeResult (..),
    BadgeIssueReq (..),
    IssuerKeyPair (..),
  )
where

import Data.Aeson (FromJSON (..), ToJSON (..))
import qualified Data.Aeson as J
import qualified Data.Aeson.TH as JQ
import qualified Data.ByteString as B
import Data.Text (Text)
import qualified Data.Text as T
import Foreign.C (CString)
import Zero.Chat.Badges
import Zero.Chat.Mobile.Shared (CJSONString, newCStringFromLazyBS)
import Zero.Messaging.Crypto.BBS (BBSPublicKey, BBSSecretKey, bbsKeyGen)
import Zero.Messaging.Parsers (defaultJSON)

data IssuerKeyPair = IssuerKeyPair
  { publicKey :: BBSPublicKey,
    secretKey :: BBSSecretKey
  }

data BadgeIssueReq = BadgeIssueReq
  { badgeKeyIdx :: Int,
    secretKey :: BBSSecretKey,
    request :: BadgeRequest
  }

data BadgeResult r
  = BadgeResult {result :: r}
  | BadgeError {error :: Text}

$(JQ.deriveJSON defaultJSON ''IssuerKeyPair)

$(JQ.deriveJSON defaultJSON ''BadgeIssueReq)

$(pure [])

instance ToJSON r => ToJSON (BadgeResult r) where
  toEncoding = $(JQ.mkToEncoding (defaultJSON {J.sumEncoding = J.UntaggedValue}) ''BadgeResult)
  toJSON = $(JQ.mkToJSON (defaultJSON {J.sumEncoding = J.UntaggedValue}) ''BadgeResult)

instance FromJSON r => FromJSON (BadgeResult r) where
  parseJSON = $(JQ.mkParseJSON (defaultJSON {J.sumEncoding = J.UntaggedValue}) ''BadgeResult)

zero_core_runtime_badge_keygen :: IO CJSONString
zero_core_runtime_badge_keygen =
  bbsKeyGen >>= \case
    Right (pk, sk) -> encodeResult $ BadgeResult (IssuerKeyPair pk sk)
    Left e -> encodeResult @IssuerKeyPair $ BadgeError (T.pack e)

zero_core_runtime_badge_issue :: CString -> IO CJSONString
zero_core_runtime_badge_issue cReq = do
  bs <- B.packCString cReq
  encodeResult @BadgeCredential =<< case J.eitherDecodeStrict' bs of
    Left e -> pure $ BadgeError (T.pack e)
    Right BadgeIssueReq {badgeKeyIdx, secretKey, request} ->
      either (BadgeError . T.pack) BadgeResult <$> issueBadge badgeKeyIdx secretKey (VerifiedBadgeRequest request)

encodeResult :: ToJSON r => BadgeResult r -> IO CJSONString
encodeResult = newCStringFromLazyBS . J.encode
