module Main where

import Control.Logger.Simple
import Zero.Messaging.Server.CLI (getEnvPath)
import Zero.Messaging.Notifications.Server.Main

defaultCfgPath :: FilePath
defaultCfgPath = "/etc/opt/zero-notifications"

defaultLogPath :: FilePath
defaultLogPath = "/var/opt/zero-notifications"

logCfg :: LogConfig
logCfg = LogConfig {lc_file = Nothing, lc_stderr = True}

main :: IO ()
main = do
  cfgPath <- getEnvPath "NTF_SERVER_CFG_PATH" defaultCfgPath
  logPath <- getEnvPath "NTF_SERVER_LOG_PATH" defaultLogPath
  withGlobalLogging logCfg $ ntfServerCLI cfgPath logPath
