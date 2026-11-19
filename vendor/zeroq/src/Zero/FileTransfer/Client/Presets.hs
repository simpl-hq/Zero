{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}

module Zero.FileTransfer.Client.Presets
  ( defaultXFTPServers,
  ) where

import Data.List.NonEmpty (NonEmpty)
import Zero.Messaging.Protocol (XFTPServerWithAuth)

defaultXFTPServers :: NonEmpty XFTPServerWithAuth
defaultXFTPServers =
  [ "xftp://RP75-w9zE9n-JoaGv2Fwik49YLCDcIJJFoFfh0-m6lU=@zerocdn.simpl.global:5223"
  ]
