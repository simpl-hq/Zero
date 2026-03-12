-- This was written for one specific use case and then generalized

-- the specific use case was a JSON API with a consumer that would choke on the
-- "Set-Cookie" response header. The solution was to test for the API's
-- `pathInfo` in the Request and if it matched, filter the response headers

-- when using this, care should be taken not to strip out headers that are
-- needed for correct operation of the client (eg Content-Type).

module Network.Wai.Middleware.StripHeaders
    ( stripHeader
    , stripHeaders
    , stripHeaderIf
    , stripHeadersIf
    ) where

import Data.ByteString (ByteString)
import qualified Data.CaseInsensitive as CI
import Network.Wai (Middleware, Request, modifyResponse, mapResponseHeaders, ifRequest)
import Network.Wai.Internal (Response)


stripHeader :: ByteString -> (Response -> Response)
stripHeader h = mapResponseHeaders (filter (\ hdr -> fst hdr /= CI.mk h))

stripHeaders :: [ByteString] -> (Response -> Response)
stripHeaders hs =
  let hnames = map CI.mk hs
  in mapResponseHeaders (filter (\ hdr -> fst hdr `notElem` hnames))

-- | if the request satisifes the provided predicate, strip headers matching
-- the provided header name
--
-- since 3.0.8
stripHeaderIf :: ByteString -> (Request -> Bool) -> Middleware
stripHeaderIf h rpred =
  ifRequest rpred (modifyResponse $ stripHeader h)

-- | if the request satisifes the provided predicate, strip all headers whose
-- header name is in the list of provided header names
--
-- since 3.0.8
stripHeadersIf :: [ByteString] -> (Request -> Bool) -> Middleware
stripHeadersIf hs rpred
  = ifRequest rpred (modifyResponse $ stripHeaders hs)
