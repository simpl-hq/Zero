module Main where

import Control.Logger.Simple
import Zero.Messaging.Server.CLI (getEnvPath)
import Zero.Messaging.Server.Main (smpServerCLI_)
import Zero.Messaging.Server.Web (serveStaticFiles, attachStaticFiles)
import SMPWeb (smpGenerateSite)

defaultCfgPath :: FilePath
defaultCfgPath = "/etc/opt/zero"

defaultLogPath :: FilePath
defaultLogPath = "/var/opt/zero"

logCfg :: LogConfig
logCfg = LogConfig {lc_file = Nothing, lc_stderr = True}

main :: IO ()
main = do
  cfgPath <- getEnvPath "SMP_SERVER_CFG_PATH" defaultCfgPath
  logPath <- getEnvPath "SMP_SERVER_LOG_PATH" defaultLogPath
  withGlobalLogging logCfg $ smpServerCLI_ smpGenerateSite serveStaticFiles attachStaticFiles cfgPath logPath
