module Main where

import Server (zeroChatServer)
import Zero.Chat.Badges.CLI (runBadgeCommand)
import Zero.Chat.Terminal (terminalChatConfig)
import Zero.Chat.Terminal.Main (zeroChatCLI)
import System.Environment (getArgs)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ("badge" : _) -> runBadgeCommand args
    _ -> zeroChatCLI terminalChatConfig (Just zeroChatServer)
