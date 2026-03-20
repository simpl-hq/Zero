{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Zero.Messaging.Server.MsgStore
  ( MsgLogRecord (..),
  ) where

import Zero.Messaging.Encoding.String
import Zero.Messaging.Protocol (Message (..), RecipientId)

data MsgLogRecord = MLRv3 RecipientId Message

instance StrEncoding MsgLogRecord where
  strEncode (MLRv3 rId msg) = strEncode (Str "v3", rId, msg)
  strP = "v3 " *> (MLRv3 <$> strP_ <*> strP)
