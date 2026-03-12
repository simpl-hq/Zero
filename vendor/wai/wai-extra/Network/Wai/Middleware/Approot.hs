{-# LANGUAGE DeriveDataTypeable #-}
-- | Middleware for establishing the root of the app.
--
-- Many app need the ability to make URLs referring back to the
-- app itself. For example: generate RSS feeds or sitemaps, giving
-- users copy-paste links, or sending emails. In many cases, the approot can be
-- determined correctly from the request headers. Though, some things can
-- stop this, especially reverse proxies. This module provides multiple ways
-- of configuring approot discovery, and functions for applications to get that
-- approot
--
-- approots are structured such that they can be prepended to a string such as
-- @/foo/bar?baz=bin@. For example, if your app is hosted on
-- example.com using HTTPS, the approot would be @https://example.com@. Note
-- the lack of a trailing slash
module Network.Wai.Middleware.Approot
    ( -- * Middleware
      approotMiddleware
      -- * Common providers
    , envFallback
    , envFallbackNamed
    , hardcoded
    , fromRequest
      -- * Functions for applications
    , getApproot
    , getApprootMay
    ) where

import Control.Exception (Exception, throw)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as S8
import Data.Maybe (fromMaybe)
import Data.Typeable (Typeable)
import qualified Data.Vault.Lazy as V
import Network.Wai (Middleware, Request, vault)
import System.Environment (getEnvironment)
import System.IO.Unsafe (unsafePerformIO)

import Network.Wai.Request (guessApproot)

approotKey :: V.Key ByteString
approotKey = unsafePerformIO V.newKey
{-# NOINLINE approotKey #-}

-- | The most generic version of the middleware, allowing you to give a
-- func to get the approot for each request. For many use cases, one of the
-- helper functions provided by this module will give the needed
-- functionality more conveniently
--
-- since 3.0.7
approotMiddleware :: (Request -> IO ByteString) -- ^ get the approot
                  -> Middleware
approotMiddleware getRoot app req respond = do
    ar <- getRoot req
    let req' = req { vault = V.insert approotKey ar $ vault req }
    app req' respond

-- | Same as @'envFallbackNamed' "APPROOT"@
--
-- The env variable @APPROOT@ is used by Keter, School of Haskell, and yesod-devel.
--
-- since 3.0.7
envFallback :: IO Middleware
envFallback = envFallbackNamed "APPROOT"

-- | Produce a middleware that takes the approot from the given env
-- variable, falling back to the behavior of 'fromRequest' if the variable is
-- not set
--
-- since 3.0.7
envFallbackNamed :: String -> IO Middleware
envFallbackNamed name = do
    env <- getEnvironment
    pure $ case lookup name env of
        Just s -> hardcoded $ S8.pack s
        Nothing -> fromRequest

-- | Hard-code the given value as the approot
--
-- since 3.0.7
hardcoded :: ByteString -> Middleware
hardcoded ar = approotMiddleware (const $ return ar)

-- | Get the approot by analyzing the request. This isnt a full-proof
-- approach, but in many common cases will work. Situations that can break this
-- are:
--
-- * Requests which spoof headers and imply the conn is over HTTPS
--
-- * Reverse proxies that change ports in surprising ways
--
-- * Invalid Host headers
--
-- * Reverse proxies which modify the path info
--
-- Normally trusting headers in this way is insecure, though in the case of
-- approot, the worst that can happen is that the client will get an incorrect
-- URL. If you are relying on the approot for some security-sensitive purpose,
-- it is highly recommended to use @hardcoded@, which cant be spoofed.
--
-- since 3.0.7
fromRequest :: Middleware
fromRequest = approotMiddleware (return . guessApproot)

data ApprootMiddlewareNotSetup = ApprootMiddlewareNotSetup
    deriving (Show, Typeable)
instance Exception ApprootMiddlewareNotSetup

-- | Get the approot set by the middleware. If the middleware isnt in use,
-- then this func will return an exception. For a total version of the
-- func, see 'getApprootMay'.
--
-- since 3.0.7
getApproot :: Request -> ByteString
getApproot = fromMaybe (throw ApprootMiddlewareNotSetup) . getApprootMay

-- | A total version of 'getApproot', which returns 'Nothing' if the middleware
-- isnt in use.
--
-- since 3.0.7
getApprootMay :: Request -> Maybe ByteString
getApprootMay req = V.lookup approotKey $ vault req
