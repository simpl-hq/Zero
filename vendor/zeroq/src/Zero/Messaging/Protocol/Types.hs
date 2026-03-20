{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Zero.Messaging.Protocol.Types
  ( ClientNotice (..),
  ) where

import qualified Data.Aeson.TH as J
import Data.Int (Int64)
import Zero.Messaging.Parsers

data ClientNotice = ClientNotice
  { ttl :: Maybe Int64
  }
  deriving (Eq, Show)

$(J.deriveJSON defaultJSON ''ClientNotice)
