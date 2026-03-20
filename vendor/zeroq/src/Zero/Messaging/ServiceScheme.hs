{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Zero.Messaging.ServiceScheme
  ( ServiceScheme (..),
    SrvLoc (..),
    zeroChat,
  ) where

import Control.Applicative ((<|>))
import qualified Data.Attoparsec.ByteString.Char8 as A
import qualified Data.ByteString.Char8 as B
import Data.Functor (($>))
import Network.Socket (ServiceName)
import Zero.Messaging.Encoding.String (StrEncoding (..))
import Zero.Messaging.Transport.Client (TransportHost (..))

data ServiceScheme = SSZero | SSAppServer SrvLoc
  deriving (Eq, Show)

instance StrEncoding ServiceScheme where
  strEncode = \case
    SSZero -> "zero:"
    SSAppServer srv -> "https://" <> strEncode srv
  strP =
    "zero:" $> SSZero
      <|> "https://" *> (SSAppServer <$> strP)

data SrvLoc = SrvLoc TransportHost ServiceName
  deriving (Eq, Ord, Show)

instance StrEncoding SrvLoc where
  strEncode (SrvLoc host port)
    | null port = strEncode host
    | otherwise = h <> B.pack (':' : port)
    where
      h = case host of
        THIPv6 _ -> ('[' `B.cons` strEncode host) `B.snoc` ']'
        _ -> strEncode host
  strP = SrvLoc <$> strP <*> (port <|> pure "")
    where
      port = show <$> (A.char ':' *> (A.decimal :: A.Parser Int))

zeroChat :: ServiceScheme
zeroChat = SSAppServer $ SrvLoc "zero.chat" ""
