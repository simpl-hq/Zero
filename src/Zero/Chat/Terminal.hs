{-# LANGUAGE CPP #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}

module Zero.Chat.Terminal where

import Control.Monad
import qualified Data.List.NonEmpty as L
import Zero.Chat (defaultChatConfig)
import Zero.Chat.Controller
import Zero.Chat.Core
import Zero.Chat.Help (chatWelcome)
import Zero.Chat.Library.Commands (_defaultNtfServers)
import Zero.Chat.Operators
import Zero.Chat.Operators.Presets (operatorZero, zeroChatRelays)
import Zero.Chat.Options
import Zero.Chat.Terminal.Input
import Zero.Chat.Terminal.Output
import Zero.FileTransfer.Client.Presets (defaultXFTPServers)
import Zero.Messaging.Client (NetworkConfig (..), SMPProxyFallback (..), SMPProxyMode (..), defaultNetworkConfig)
import Zero.Messaging.Util (raceAny_)
#if !defined(dbPostgres)
import Control.Exception (handle, throwIO)
import qualified Data.ByteArray as BA
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import Database.SQLite.Simple (SQLError (..))
import qualified Database.SQLite.Simple as DB
import Zero.Chat.Options.DB
import System.IO (hFlush, hSetEcho, stdin, stdout)
#endif

terminalChatConfig :: ChatConfig
terminalChatConfig =
  defaultChatConfig
    { presetServers =
        PresetServers
          { operators =
              [ PresetOperator
                  { operator = Just operatorZero,
                    smp =
                      map
                        (presetServer True)
                        [ "smp://pJ5gVPxIPmCXflOJ7W7avwpDka1mEHcNaHEqcAwBx0c=@zerorelay.simpl.global:5223",
                          "smp://TctoW4I8Pkb7i547zF_zX4OEj0EG1GEFYfh1QAPD3Ok=@zeroeu.simpl.global:5223"
                        ],
                    useSMP = 2,
                    xftp = map (presetServer True) $ L.toList defaultXFTPServers,
                    useXFTP = 1,
                    chatRelays = zeroChatRelays,
                    useChatRelays = 2
                  }
              ],
            ntf = _defaultNtfServers,
            netCfg =
              defaultNetworkConfig
                { smpProxyMode = SPMUnknown,
                  smpProxyFallback = SPFAllowProtected
                }
          },
      deviceNameForRemote = "Zero CLI"
    }

zeroChatTerminal :: WithTerminal t => ChatConfig -> ChatOpts -> t -> IO ()
zeroChatTerminal cfg options t = run options
  where
#if defined(dbPostgres)
    run opts =
      zeroChatCore cfg opts $ \u cc -> do
        ct <- newChatTerminal t opts
        when (firstTime cc) . printToTerminal ct $ chatWelcome u
        runChatTerminal ct cc opts
#else
    run opts@ChatOpts {coreOptions = coreOptions@CoreChatOpts {dbOptions}} =
      handle checkDBKeyError . zeroChatCore cfg opts $ \u cc -> do
        ct <- newChatTerminal t opts
        when (firstTime cc) . printToTerminal ct $ chatWelcome u
        runChatTerminal ct cc opts
      where
        checkDBKeyError :: SQLError -> IO ()
        checkDBKeyError e = case sqlError e of
          DB.ErrorNotADatabase -> do
            putStrLn $ "Database file is invalid or " <> if BA.null (dbKey dbOptions) then "encrypted." else "you passed an incorrect encryption key."
            run =<< getKeyOpts
          _ -> throwIO e
        getKeyOpts :: IO ChatOpts
        getKeyOpts = do
          putStr "Enter database encryption key (Ctrl-C to exit):"
          hFlush stdout
          hSetEcho stdin False
          key <- getLine
          hSetEcho stdin True
          putStrLn ""
          pure opts {coreOptions = coreOptions {dbOptions = dbOptions {dbKey = BA.convert $ encodeUtf8 $ T.pack key}}}
#endif

runChatTerminal :: ChatTerminal -> ChatController -> ChatOpts -> IO ()
runChatTerminal ct cc opts = raceAny_ [runTerminalInput ct cc, runTerminalOutput ct cc opts, runInputLoop ct cc]
