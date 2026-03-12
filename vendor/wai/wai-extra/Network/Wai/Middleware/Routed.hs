-- |
--
-- since 3.0.9
module Network.Wai.Middleware.Routed
    ( routedMiddleware
    , hostedMiddleware
    ) where

import Data.ByteString (ByteString)
import Data.Text (Text)
import Network.Wai

-- | apply a middleware based on a test of pathInfo
--
-- example:
--
-- > let corsify = routedMiddleWare ("static" `elem`) addCorsHeaders
--
-- since 3.0.9
routedMiddleware :: ([Text] -> Bool) -- ^ Only use middleware if this pathInfo test returns True
                 -> Middleware -- ^ middleware to apply the path prefix guard to
                 -> Middleware -- ^ modified middleware
routedMiddleware pathCheck middle app req
  | pathCheck (pathInfo req) = middle app req
  | otherwise                = app req

-- | only apply the middleware to certain hosts
--
-- since 3.0.9
hostedMiddleware :: ByteString -- ^ Domain the middleware applies to
                 -> Middleware -- ^ middleware to apply the path prefix guard to
                 -> Middleware -- ^ modified middleware
hostedMiddleware domain middle app req
  | hasDomain domain req = middle app req
  | otherwise            = app req

hasDomain :: ByteString -> Request -> Bool
hasDomain domain req = maybe False (== domain) mHost
  where mHost = requestHeaderHost req
