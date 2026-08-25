module Main where

import Broadcast.Bot
import Broadcast.Options
import Zero.Chat.Core
import Zero.Chat.Terminal (terminalChatConfig)

main :: IO ()
main = do
  opts <- welcomeGetOpts
  zeroChatCore terminalChatConfig (mkChatOpts opts) $ broadcastBot opts
