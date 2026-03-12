module Network.Wai.Middleware.MethodOverride
    ( methodOverride
    ) where

import Control.Monad (join)
import Network.Wai (Middleware, queryString, requestMethod)

-- | Overriding of HTTP request method via `_method` query string param.
--
-- This middleware only applies when the initial request method is POST
-- allows submitting of normal HTML forms, without worries of semantic
-- mismatches with the HTTP spec
methodOverride :: Middleware
methodOverride app req =
    app req'
  where
    req' =
        case (requestMethod req, join $ lookup "_method" $ queryString req) of
            ("POST", Just m) -> req { requestMethod = m }
            _ -> req
