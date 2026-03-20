{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE TemplateHaskell #-}

module Zero.Messaging.ZeroName
  ( ZeroNameInfo (..),
    ZeroDomain (..),
    ZeroTLD (..),
    ZeroNameType (..),
    fullDomainName,
    shortNameInfoStr,
  )
where

import Control.Applicative (optional, (<|>))
import qualified Data.Aeson.TH as J
import qualified Data.Attoparsec.ByteString.Char8 as A
import qualified Data.Attoparsec.Text as AT
import Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as B
import Data.Char (isDigit)
import Data.Functor (($>))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (decodeLatin1, encodeUtf8)
import Zero.Messaging.Agent.Store.DB (FromField (..), ToField (..), fromTextField_)
import Zero.Messaging.Encoding (Encoding (..))
import Zero.Messaging.Encoding.String
import Zero.Messaging.Parsers (defaultJSON, dropPrefix, enumJSON)
import Zero.Messaging.Util (eitherToMaybe, safeDecodeUtf8, (<$?>))

data ZeroNameInfo = ZeroNameInfo
  { nameType :: ZeroNameType,
    nameDomain :: ZeroDomain
  }
  deriving (Eq, Show)

data ZeroDomain = ZeroDomain
  { nameTLD :: ZeroTLD,
    domain :: Text,
    subDomain :: [Text]
  }
  deriving (Eq, Show)

data ZeroTLD = TLDZero | TLDTesting | TLDWeb
  deriving (Eq, Show)

data ZeroNameType = NTPublicGroup | NTContact
  deriving (Eq, Show)

instance StrEncoding ZeroNameType where
  strEncode = \case
    NTPublicGroup -> "#"
    NTContact -> "@"
  strP = A.char '#' $> NTPublicGroup <|> A.char '@' $> NTContact

nameLabelP :: AT.Parser Text
nameLabelP = do
  label <- T.intercalate "-" <$> AT.takeWhile1 (\c -> isNameLetter c || isDigit c) `AT.sepBy1` AT.char '-'
  if T.length label > 63 then fail "name label exceeds 63 bytes" else pure label
  where
    isNameLetter c = c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'

boundedNonSpace :: A.Parser ByteString
boundedNonSpace = do
  bs <- A.scan (0 :: Int) $ \i c ->
    if i <= 253 && not (A.isSpace c) then Just (i + 1) else Nothing
  if B.null bs
    then fail "expected non-empty name token"
    else if B.length bs > 253 then fail "name exceeds 253 bytes" else pure bs

instance StrEncoding ZeroNameInfo where
  strEncode ZeroNameInfo {nameType, nameDomain} =
    strEncode nameType <> strEncode nameDomain
  strP = optional "zero:/name" *> ((strP >>= infoP) <|> infoP NTPublicGroup)
    where
      infoP NTPublicGroup = ZeroNameInfo NTPublicGroup <$> (strP <|> bareName)
      infoP NTContact = ZeroNameInfo NTContact <$> strP
      bareName = parseBare . safeDecodeUtf8 <$?> boundedNonSpace
      parseBare s = (\name -> ZeroDomain TLDZero (T.toLower name) []) <$> AT.parseOnly (nameLabelP <* AT.endOfInput) s

instance StrEncoding ZeroDomain where
  strEncode = encodeUtf8 . fullDomainName
  strP = parseDomain . safeDecodeUtf8 <$?> boundedNonSpace
    where
      parseDomain s = AT.parseOnly (nameLabelP `AT.sepBy1` AT.char '.' <* AT.endOfInput) s >>= mkDomain
      mkDomain labels = case reverse lowered of
        [] -> Left "empty name"
        [_] -> Left "domain requires TLD"
        "zero" : name : sub -> Right (ZeroDomain TLDZero name sub)
        "testing" : name : sub -> Right (ZeroDomain TLDTesting name sub)
        _ -> Right (ZeroDomain TLDWeb (T.intercalate "." lowered) [])
        where
          lowered = map T.toLower labels

instance Encoding ZeroDomain where
  smpEncode = strEncode
  smpP = strP

fullDomainName :: ZeroDomain -> Text
fullDomainName ZeroDomain {nameTLD, domain, subDomain} = T.intercalate "." (reverse subDomain ++ [domain] ++ tld')
  where
    tld' = case nameTLD of
      TLDZero -> ["zero"]
      TLDTesting -> ["testing"]
      TLDWeb -> []

shortNameInfoStr :: ZeroNameInfo -> Text
shortNameInfoStr = \case
  ZeroNameInfo {nameType = NTPublicGroup, nameDomain = ZeroDomain {nameTLD = TLDZero, domain, subDomain = []}} -> "#" <> domain
  info -> pfx <> fullDomainName (nameDomain info)
    where
      pfx = case nameType info of
        NTPublicGroup -> "#"
        NTContact -> "@"

instance ToField ZeroDomain where toField = toField . decodeLatin1 . strEncode

instance FromField ZeroDomain where fromField = fromTextField_ (eitherToMaybe . strDecode . encodeUtf8)

$(J.deriveJSON (enumJSON $ dropPrefix "TLD") ''ZeroTLD)

$(J.deriveJSON (enumJSON $ dropPrefix "NT") ''ZeroNameType)

$(J.deriveJSON defaultJSON ''ZeroDomain)

$(J.deriveJSON defaultJSON ''ZeroNameInfo)
