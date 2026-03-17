{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module NameResolver
  ( NameRegistry,
    withNameResolver,
    registerName,
    contactNameRecord,
    channelNameRecord,
    contactAndChannelNameRecord,
    resolverNamesConfig,
  )
where

import Control.Concurrent.STM
import qualified Data.Aeson as J
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import Network.HTTP.Types (hContentType, notFound404, ok200)
import Network.Wai (Application, pathInfo, responseLBS)
import qualified Network.Wai.Handler.Warp as Warp
import Zero.Messaging.Names.Record (NameRecord (..))
import Zero.Messaging.Server.Names (NamesConfig (..))
import Zero.Messaging.ZeroName (ZeroNameInfo (..), fullDomainName)

type NameRegistry = TVar (Map Text NameRecord)

withNameResolver :: (Int -> TVar (Map Text NameRecord) -> IO a) -> IO a
withNameResolver action = do
  reg <- newTVarIO M.empty
  Warp.withApplication (pure (app reg)) $ \port -> action port reg
  where
    app :: TVar (Map Text NameRecord) -> Application
    app reg req send = do
      (st, body) <- case pathInfo req of
        ["health"] -> pure (ok200, "{}")
        ["resolve", d] -> maybe (notFound404, "{}") (\r -> (ok200, J.encode r)) . M.lookup d <$> readTVarIO reg
        _ -> pure (notFound404, "{}")
      send $ responseLBS st [(hContentType, "application/json")] body

registerName :: TVar (Map Text NameRecord) -> ZeroNameInfo -> NameRecord -> IO ()
registerName reg ZeroNameInfo {nameDomain} r =
  atomically $ modifyTVar' reg $ M.insert (fullDomainName nameDomain) r

contactNameRecord :: Text -> Text -> NameRecord
contactNameRecord name link = (emptyRecord name) {nrZeroContact = [link]}

channelNameRecord :: Text -> Text -> NameRecord
channelNameRecord name link = (emptyRecord name) {nrZeroChannel = [link]}

contactAndChannelNameRecord :: Text -> Text -> Text -> NameRecord
contactAndChannelNameRecord name contactLink channelLink =
  (emptyRecord name) {nrZeroContact = [contactLink], nrZeroChannel = [channelLink]}

emptyRecord :: Text -> NameRecord
emptyRecord name =
  NameRecord
    { nrName = name,
      nrNickname = "",
      nrWebsite = "",
      nrLocation = "",
      nrZeroContact = [],
      nrZeroChannel = [],
      nrEth = Nothing,
      nrBtc = Nothing,
      nrXmr = Nothing,
      nrDot = Nothing,
      nrOwner = "",
      nrResolver = ""
    }

resolverNamesConfig :: Int -> NamesConfig
resolverNamesConfig port =
  NamesConfig
    { resolverEndpoint = "http://127.0.0.1:" <> show port,
      resolverAuth = Nothing,
      resolverTimeoutMs = 1000,
      resolverMaxResponseBytes = 65536
    }
