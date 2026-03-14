{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Zero.Chat.Names
  ( ZeroDomainClaim (..),
    ZeroDomainProof (..),
    mkDomainClaim,
    claimDomain,
  )
where

import qualified Data.Aeson.TH as JQ
import Zero.Chat.Badges (ProofPresHeader)
import Zero.Messaging.Agent.Protocol (OwnerId, ZeroDomain)
import Zero.Messaging.Agent.Store.DB (fromTextField_)
import qualified Zero.Messaging.Crypto as C
import Zero.Messaging.Encoding.String
import Zero.Messaging.Parsers (defaultJSON)
import Zero.Messaging.Util (decodeJSON, encodeJSON)
#if defined(dbPostgres)
import Database.PostgreSQL.Simple.FromField (FromField (..))
import Database.PostgreSQL.Simple.ToField (ToField (..))
#else
import Database.SQLite.Simple.FromField (FromField (..))
import Database.SQLite.Simple.ToField (ToField (..))
#endif

data ZeroDomainProof = ZeroDomainProof
  { linkOwnerId :: Maybe (StrJSON "OwnerId" OwnerId),
    presHeader :: ProofPresHeader,
    signature :: C.Signature 'C.Ed25519
  }
  deriving (Eq, Show)

$(JQ.deriveJSON defaultJSON ''ZeroDomainProof)

instance ToField ZeroDomainProof where toField = toField . encodeJSON

instance FromField ZeroDomainProof where fromField = fromTextField_ decodeJSON

data ZeroDomainClaim = ZeroDomainClaim
  { domain :: StrJSON "ZeroDomain" ZeroDomain,
    proof :: Maybe ZeroDomainProof
  }
  deriving (Eq, Show)

mkDomainClaim :: ZeroDomain -> ZeroDomainClaim
mkDomainClaim = (`ZeroDomainClaim` Nothing) . StrJSON

claimDomain :: ZeroDomainClaim -> ZeroDomain
claimDomain (ZeroDomainClaim n _) = unStrJSON n

$(JQ.deriveJSON defaultJSON ''ZeroDomainClaim)
