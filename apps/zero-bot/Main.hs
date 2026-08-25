{-# LANGUAGE NamedFieldPuns #-}

module Main where

import Zero.Chat.Bot
import Zero.Chat.Controller (versionNumber)
import Zero.Chat.Core
import Zero.Chat.Options
import Zero.Chat.Terminal (terminalChatConfig)
import System.Directory (getAppUserDataDirectory)
import Text.Read

main :: IO ()
main = do
  opts <- welcomeGetOpts
  zeroChatCore terminalChatConfig opts $
    chatBotRepl welcomeMessage $ \_contact msg ->
      pure $ case readMaybe msg :: Maybe Integer of
        Just n -> msg <> " * " <> msg <> " = " <> show (n * n)
        _ -> "\"" <> msg <> "\" is not a number"

welcomeMessage :: String
welcomeMessage = "Hello! I am a simple squaring bot.\nIf you send me a number, I will calculate its square"

welcomeGetOpts :: IO ChatOpts
welcomeGetOpts = do
  appDir <- getAppUserDataDirectory "zero"
  opts@ChatOpts {coreOptions} <- getChatOpts appDir "zero_bot"
  putStrLn $ "Zero Bot v" ++ versionNumber
  printDbOpts coreOptions
  pure opts
