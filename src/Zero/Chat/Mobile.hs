{-# LANGUAGE CPP #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -fobject-code #-}

module Zero.Chat.Mobile where

import Control.Concurrent.STM
import Control.Exception (SomeException, catch)
import Control.Monad.Except
import Control.Monad.Reader
import Data.Aeson (ToJSON (..))
import qualified Data.Aeson as J
import qualified Data.Aeson.TH as JQ
import Data.Bifunctor (first)
import qualified Data.ByteString.Base64.URL as U
import Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy.Char8 as LB
import Data.Functor (($>))
import Data.List (find)
import qualified Data.List.NonEmpty as L
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Word (Word8)
import Foreign.C.String
import Foreign.C.Types (CInt (..))
import Foreign.Ptr
import Foreign.StablePtr
import Foreign.Storable (poke)
import GHC.IO.Encoding (setFileSystemEncoding, setForeignEncoding, setLocaleEncoding)
import Zero.Chat
import Zero.Chat.Controller
import Zero.Chat.Library.Commands
import Zero.Chat.Markdown (ParsedMarkdown (..), parseMaybeMarkdownList, parseUri, sanitizeUri)
import Zero.Chat.Mobile.Badges
import Zero.Chat.Mobile.File
import Zero.Chat.Mobile.Shared
import Zero.Chat.Mobile.WebRTC
import Zero.Chat.Options
import Zero.Chat.Options.DB
import Zero.Chat.Remote.Types
import Zero.Chat.Store
import Zero.Chat.Store.Profiles
import Zero.Chat.Types
import Zero.Messaging.Agent.Client (agentClientStore)
import Zero.Messaging.Agent.Env.SQLite (createAgentStore)
import Zero.Messaging.Agent.Protocol (AgentErrorType)
import Zero.Messaging.Agent.Store.Interface (closeDBStore, reopenDBStore)
import Zero.Messaging.Agent.Store.Shared (MigrationConfig (..), MigrationConfirmation (..), MigrationError)
import qualified Zero.Messaging.Crypto as C
import Zero.Messaging.Encoding.String
import Zero.Messaging.Parsers (defaultJSON, dropPrefix, sumTypeJSON)
import Zero.Messaging.Protocol (AProtoServerWithAuth (..), AProtocolType (..), BasicAuth (..), ProtoServerWithAuth (..), ProtocolServer (..))
import Zero.Messaging.Util (catchAll, liftEitherWith, safeDecodeUtf8)
import System.IO (utf8)
import System.Timeout (timeout)
import qualified URI.ByteString as U
#if !defined(dbPostgres)
import Data.ByteArray (ScrubbedBytes)
import Database.SQLite.Simple (SQLError (..))
import qualified Database.SQLite.Simple as DB
import qualified Zero.Messaging.Agent.Store.DB as DB
#endif

data DBMigrationResult
  = DBMOk
  | DBMInvalidConfirmation
  | DBMErrorNotADatabase {dbFile :: String}
  | DBMErrorMigration {dbFile :: String, migrationError :: MigrationError}
  | DBMErrorSQL {dbFile :: String, migrationSQLError :: String}
  | DBMAgentError {agentError :: AgentErrorType}
  deriving (Show)

$(JQ.deriveToJSON (sumTypeJSON $ dropPrefix "DBM") ''DBMigrationResult)

data APIResult r
  = APIResult  {remoteHostId :: Maybe RemoteHostId, result :: r}
  | APIError {remoteHostId :: Maybe RemoteHostId, error :: ChatError}

eitherToResult :: Maybe RemoteHostId -> Either ChatError r -> APIResult r
eitherToResult rhId = either (APIError rhId) (APIResult rhId)
{-# INLINE eitherToResult #-}

data ParsedUri = ParsedUri
  { uriInfo :: Maybe UriInfo,
    parseError :: Text
  }

data UriInfo = UriInfo
  { scheme :: Text,
    sanitized :: Maybe Text
  }

$(JQ.deriveJSON defaultJSON ''UriInfo)

$(JQ.deriveJSON defaultJSON ''ParsedUri)

$(pure [])

instance ToJSON r => ToJSON (APIResult r) where
  toEncoding = $(JQ.mkToEncoding (defaultJSON {J.sumEncoding = J.UntaggedValue}) ''APIResult)
  toJSON = $(JQ.mkToJSON (defaultJSON {J.sumEncoding = J.UntaggedValue}) ''APIResult)

foreign export ccall zero_core_runtime_init :: CString -> IO ()

foreign export ccall zero_core_runtime_migrate_init :: CString -> CString -> CString -> Ptr (StablePtr ChatController) -> IO CJSONString

foreign export ccall zero_core_runtime_migrate_init_key :: CString -> CString -> CInt -> CString -> CInt -> Ptr (StablePtr ChatController) -> IO CJSONString

foreign export ccall zero_core_runtime_close_store :: StablePtr ChatController -> IO CString

foreign export ccall zero_core_runtime_reopen_store :: StablePtr ChatController -> IO CString

foreign export ccall zero_core_runtime_send_cmd :: StablePtr ChatController -> CString -> IO CJSONString

foreign export ccall zero_core_runtime_send_cmd_retry :: StablePtr ChatController -> CString -> CInt -> IO CJSONString

foreign export ccall zero_core_runtime_send_remote_cmd :: StablePtr ChatController -> CInt -> CString -> IO CJSONString

foreign export ccall zero_core_runtime_send_remote_cmd_retry :: StablePtr ChatController -> CInt -> CString -> CInt -> IO CJSONString

foreign export ccall zero_core_runtime_recv_msg :: StablePtr ChatController -> IO CJSONString

foreign export ccall zero_core_runtime_recv_msg_wait :: StablePtr ChatController -> CInt -> IO CJSONString

foreign export ccall zero_core_runtime_parse_markdown :: CString -> IO CJSONString

foreign export ccall zero_core_runtime_parse_server :: CString -> IO CJSONString

foreign export ccall zero_core_runtime_parse_uri :: CString -> CInt -> IO CJSONString

foreign export ccall zero_core_runtime_password_hash :: CString -> CString -> IO CString

foreign export ccall zero_core_runtime_valid_name :: CString -> IO CString

foreign export ccall zero_core_runtime_json_length :: CString -> IO CInt

foreign export ccall zero_core_runtime_badge_keygen :: IO CJSONString

foreign export ccall zero_core_runtime_badge_issue :: CString -> IO CJSONString

foreign export ccall zero_core_runtime_encrypt_media :: StablePtr ChatController -> CString -> Ptr Word8 -> CInt -> IO CString

foreign export ccall zero_core_runtime_decrypt_media :: CString -> Ptr Word8 -> CInt -> IO CString

foreign export ccall zero_core_runtime_write_file :: StablePtr ChatController -> CString -> Ptr Word8 -> CInt -> IO CJSONString

foreign export ccall zero_core_runtime_read_file :: CString -> CString -> CString -> IO (Ptr Word8)

foreign export ccall zero_core_runtime_encrypt_file :: StablePtr ChatController -> CString -> CString -> IO CJSONString

foreign export ccall zero_core_runtime_decrypt_file :: CString -> CString -> CString -> CString -> IO CString

zero_core_runtime_init :: CString -> IO ()
zero_core_runtime_init _ = do
  setLocaleEncoding utf8
  setFileSystemEncoding utf8
  setForeignEncoding utf8

zero_core_runtime_migrate_init :: CString -> CString -> CString -> Ptr (StablePtr ChatController) -> IO CJSONString
zero_core_runtime_migrate_init fp key conf = zero_core_runtime_migrate_init_key fp key 0 conf 0

zero_core_runtime_migrate_init_key :: CString -> CString -> CInt -> CString -> CInt -> Ptr (StablePtr ChatController) -> IO CJSONString
zero_core_runtime_migrate_init_key fp key keepKey conf background ctrl = do
  setLocaleEncoding utf8
  setFileSystemEncoding utf8
  setForeignEncoding utf8

  chatDbOpts <- mobileDbOpts fp key
  confirm <- peekCAString conf
  r <-
    chatMigrateInitKey chatDbOpts (keepKey /= 0) confirm (background /= 0) >>= \case
      Right cc -> (newStablePtr cc >>= poke ctrl) $> DBMOk
      Left e -> pure e
  newCStringFromLazyBS $ J.encode r

zero_core_runtime_close_store :: StablePtr ChatController -> IO CString
zero_core_runtime_close_store cPtr = deRefStablePtr cPtr >>= chatCloseStore >>= newCAString

zero_core_runtime_reopen_store :: StablePtr ChatController -> IO CString
zero_core_runtime_reopen_store cPtr = do
  c <- deRefStablePtr cPtr
  newCAString =<< chatReopenStore c

zero_core_runtime_send_cmd :: StablePtr ChatController -> CString -> IO CJSONString
zero_core_runtime_send_cmd cPtr cCmd = zero_core_runtime_send_cmd_retry cPtr cCmd 0

zero_core_runtime_send_cmd_retry :: StablePtr ChatController -> CString -> CInt -> IO CJSONString
zero_core_runtime_send_cmd_retry cPtr cCmd cRetryNum = do
  c <- deRefStablePtr cPtr
  cmd <- B.packCString cCmd
  newCStringFromLazyBS =<< chatSendRemoteCmdRetry c Nothing cmd (fromIntegral cRetryNum)
{-# INLINE zero_core_runtime_send_cmd_retry #-}

zero_core_runtime_send_remote_cmd :: StablePtr ChatController -> CInt -> CString -> IO CJSONString
zero_core_runtime_send_remote_cmd cPtr cRhId cCmd = zero_core_runtime_send_remote_cmd_retry cPtr cRhId cCmd 0

zero_core_runtime_send_remote_cmd_retry :: StablePtr ChatController -> CInt -> CString -> CInt -> IO CJSONString
zero_core_runtime_send_remote_cmd_retry cPtr cRemoteHostId cCmd cRetryNum = do
  c <- deRefStablePtr cPtr
  cmd <- B.packCString cCmd
  let rhId = Just $ fromIntegral cRemoteHostId
  newCStringFromLazyBS =<< chatSendRemoteCmdRetry c rhId cmd (fromIntegral cRetryNum)
{-# INLINE zero_core_runtime_send_remote_cmd_retry #-}

zero_core_runtime_recv_msg :: StablePtr ChatController -> IO CJSONString
zero_core_runtime_recv_msg cc = deRefStablePtr cc >>= chatRecvMsg >>= newCStringFromLazyBS

zero_core_runtime_recv_msg_wait :: StablePtr ChatController -> CInt -> IO CJSONString
zero_core_runtime_recv_msg_wait cc t = deRefStablePtr cc >>= (`chatRecvMsgWait` fromIntegral t) >>= newCStringFromLazyBS

zero_core_runtime_parse_markdown :: CString -> IO CJSONString
zero_core_runtime_parse_markdown s = newCStringFromLazyBS . chatParseMarkdown =<< B.packCString s

zero_core_runtime_parse_server :: CString -> IO CJSONString
zero_core_runtime_parse_server s = newCStringFromLazyBS . chatParseServer =<< B.packCString s

zero_core_runtime_parse_uri :: CString -> CInt -> IO CJSONString
zero_core_runtime_parse_uri s safe = newCStringFromLazyBS . chatParseUri (safe /= 0) =<< B.packCString s

zero_core_runtime_password_hash :: CString -> CString -> IO CString
zero_core_runtime_password_hash cPwd cSalt = do
  pwd <- B.packCString cPwd
  salt <- B.packCString cSalt
  newCStringFromBS $ chatPasswordHash pwd salt

zero_core_runtime_valid_name :: CString -> IO CString
zero_core_runtime_valid_name cName = newCString . mkValidName =<< peekCString cName

zero_core_runtime_json_length :: CString -> IO CInt
zero_core_runtime_json_length s = fromIntegral . subtract 2 . LB.length . J.encode . safeDecodeUtf8 <$> B.packCString s

mobileChatOpts :: ChatDbOpts -> ChatOpts
mobileChatOpts dbOptions =
  ChatOpts
    { coreOptions =
        CoreChatOpts
          { dbOptions,
            smpServers = [],
            xftpServers = [],
            simpleNetCfg = defaultSimpleNetCfg,
            logLevel = CLLImportant,
            logConnections = False,
            logServerHosts = True,
            logAgent = Nothing,
            logFile = Nothing,
            tbqSize = 4096,
            deviceName = Nothing,
            chatRelay = False,
            webPreviewConfig = Nothing,
            chatRelayServer = Nothing,
            headless = False,
            highlyAvailable = False,
            yesToUpMigrations = False,
            migrationBackupPath = Just "",
            maintenance = True
          },
      chatCmd = "",
      chatCmdDelay = 3,
      chatCmdLog = CCLNone,
      chatServerPort = Nothing,
      optFilesFolder = Nothing,
      optTempDirectory = Nothing,
      showReactions = False,
      allowInstantFiles = True,
      autoAcceptFileSize = 0,
      muteNotifications = True,
      markRead = False,
      createBot = Nothing,
      userDisplayName = Nothing,
      userImageFile = Nothing
    }

defaultMobileConfig :: ChatConfig
defaultMobileConfig =
  defaultChatConfig
    { confirmMigrations = MCYesUp,
      logLevel = CLLError,
      deviceNameForRemote = "Mobile"
    }

getActiveUser_ :: DBStore -> IO (Maybe User)
getActiveUser_ st = find activeUser <$> withTransaction st getUsers

#if !defined(dbPostgres)
chatMigrateInit :: String -> ScrubbedBytes -> String -> IO (Either DBMigrationResult ChatController)
chatMigrateInit dbFilePrefix dbKey confirm = do
  let chatDBOpts = ChatDbOpts {dbFilePrefix, dbKey, trackQueries = DB.TQSlow 5000, vacuumOnMigration = True}
  chatMigrateInitKey chatDBOpts False confirm False
#endif

chatMigrateInitKey :: ChatDbOpts -> Bool -> String -> Bool -> IO (Either DBMigrationResult ChatController)
chatMigrateInitKey chatDbOpts keepKey confirm backgroundMode = runExceptT $ do
  confirmMigrations <- liftEitherWith (const DBMInvalidConfirmation) $ strDecode $ B.pack confirm
  let migrationConfig = MigrationConfig confirmMigrations (Just "")
  chatStore <- migrate createChatStore (toDBOpts chatDbOpts chatSuffix keepKey chatDBFunctions) migrationConfig
  agentStore <- migrate createAgentStore (toDBOpts chatDbOpts agentSuffix keepKey []) migrationConfig
  ExceptT $ initialize chatStore ChatDatabase {chatStore, agentStore}
  where
    opts = mobileChatOpts $ removeDbKey chatDbOpts
    initialize st db = do
      user_ <- liftIO $ getActiveUser_ st
      first DBMAgentError <$> newChatController db user_ defaultMobileConfig opts backgroundMode
    migrate createStore dbOpts confirmMigrations =
      ExceptT $
        (first (DBMErrorMigration errDbStr) <$> createStore dbOpts confirmMigrations)
#if !defined(dbPostgres)
          `catch` (pure . checkDBError)
#endif
          `catchAll` (pure . dbError)
      where
        errDbStr = errorDbStr dbOpts
#if !defined(dbPostgres)
        checkDBError e = case sqlError e of
          DB.ErrorNotADatabase -> Left $ DBMErrorNotADatabase errDbStr
          _ -> dbError e
#endif
        dbError :: Show e => e -> Either DBMigrationResult DBStore
        dbError e = Left . DBMErrorSQL errDbStr $ show e

chatCloseStore :: ChatController -> IO String
chatCloseStore ChatController {chatStore, smpAgent} = handleErr $ do
  closeDBStore chatStore
  closeDBStore $ agentClientStore smpAgent

chatReopenStore :: ChatController -> IO String
chatReopenStore ChatController {chatStore, smpAgent} = handleErr $ do
  reopenDBStore chatStore
  reopenDBStore (agentClientStore smpAgent)

handleErr :: IO () -> IO String
handleErr a = (a $> "") `catch` (pure . show @SomeException)

chatSendCmd :: ChatController -> B.ByteString -> IO JSONByteString
chatSendCmd cc cmd = chatSendRemoteCmdRetry cc Nothing cmd 0
{-# INLINE chatSendCmd #-}

chatSendRemoteCmdRetry :: ChatController -> Maybe RemoteHostId -> B.ByteString -> Int -> IO JSONByteString
chatSendRemoteCmdRetry cc rh s retryNum = J.encode . eitherToResult rh <$> runReaderT (execChatCommand rh s retryNum) cc

chatRecvMsg :: ChatController -> IO JSONByteString
chatRecvMsg ChatController {outputQ} = J.encode . uncurry eitherToResult <$> readChatResponse
  where
    readChatResponse =
      atomically (readTBQueue outputQ) >>= \case
        (_, Right CEvtTerminalEvent {}) -> readChatResponse
        out -> pure out

chatRecvMsgWait :: ChatController -> Int -> IO JSONByteString
chatRecvMsgWait cc time = fromMaybe "" <$> timeout time (chatRecvMsg cc)

chatParseMarkdown :: ByteString -> JSONByteString
chatParseMarkdown = J.encode . ParsedMarkdown . parseMaybeMarkdownList . safeDecodeUtf8
{-# INLINE chatParseMarkdown #-}

chatParseServer :: ByteString -> JSONByteString
chatParseServer = J.encode . toServerAddress . strDecode
  where
    toServerAddress :: Either String AProtoServerWithAuth -> ParsedServerAddress
    toServerAddress = \case
      Right (AProtoServerWithAuth protocol (ProtoServerWithAuth ProtocolServer {host, port, keyHash = C.KeyHash kh} auth)) ->
        let basicAuth = maybe "" (\(BasicAuth a) -> enc a) auth
         in ParsedServerAddress (Just ServerAddress {serverProtocol = AProtocolType protocol, hostnames = L.map enc host, port, keyHash = enc kh, basicAuth}) ""
      Left e -> ParsedServerAddress Nothing e
    enc :: StrEncoding a => a -> String
    enc = B.unpack . strEncode

chatParseUri :: Bool -> ByteString -> JSONByteString
chatParseUri safe s = J.encode $ case parseUri s of
  Left e -> ParsedUri Nothing e
  Right uri@U.URI {uriScheme = U.Scheme sch} ->
    let sanitized = safeDecodeUtf8 . U.serializeURIRef' <$> sanitizeUri safe uri
        uriInfo = UriInfo {scheme = safeDecodeUtf8 sch, sanitized}
     in ParsedUri (Just uriInfo) ""

chatPasswordHash :: ByteString -> ByteString -> ByteString
chatPasswordHash pwd salt = either (const "") passwordHash salt'
  where
    salt' = U.decode salt
    passwordHash = U.encode . C.sha512Hash . (pwd <>)
