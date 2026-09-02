module Directory.Search where

import Data.Text (Text)
import Data.Time.Clock (UTCTime)
import Zero.Chat.Types

data SearchRequest = SearchRequest
  { searchType :: SearchType,
    searchTime :: UTCTime,
    lastGroup :: GroupId
  }

data SearchType = STAll | STRecent | STSearch Text
