{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE TemplateHaskell #-}

module Zero.Messaging.Names.Record
  ( NameRecord (..),
  )
where

import qualified Data.Aeson as J
import qualified Data.Aeson.TH as JQ
import Data.Text (Text)
import Zero.Messaging.Parsers (defaultJSON, dropPrefix)

data NameRecord = NameRecord
  { nrName :: Text,
    nrNickname :: Text,
    nrWebsite :: Text,
    nrLocation :: Text,
    nrZeroContact :: [Text],
    nrZeroChannel :: [Text],
    nrEth :: Maybe Text,
    nrBtc :: Maybe Text,
    nrXmr :: Maybe Text,
    nrDot :: Maybe Text,
    nrOwner :: Text,
    nrResolver :: Text
  }
  deriving (Eq, Show)

$( JQ.deriveJSON
    defaultJSON {J.omitNothingFields = False, J.fieldLabelModifier = dropPrefix "nr"}
    ''NameRecord
 )
