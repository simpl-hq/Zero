{-# LANGUAGE DeriveDataTypeable, GeneralizedNewtypeDeriving #-}
------------------------------------------------------------------------------
-- |
-- Module:      DB.SQLite.Simple.Internal
-- copyright:   (c) 2011-2012 Leon P Smith
-- (c) 2012-2013 Janne Hellsten
-- license:     BSD3
-- maintainer:  Janne Hellsten <jjhellst@gmail.com>
-- portability: portable
--
-- Internal bits.  This interface is less stable and can change at any time
-- in particular this means that while the rest of the sqlite-simple
-- package endeavors to follow the package versioning policy,  this module
-- doesnt.  Also, at the moment there are things in here that aren't
-- particularly internal and are exported elsewhere;  these will eventually
-- disappear from this module
--
------------------------------------------------------------------------------

module Database.SQLite.Simple.Internal where

import           Control.Exception (Exception)
import           Control.Monad
import           Control.Applicative
import           Data.ByteString (ByteString)
import           Data.ByteString.Char8()
import           Data.IORef
import           Data.Typeable (Typeable)
import           Data.Word
import           Control.Monad.Trans.State.Strict
import           Control.Monad.Trans.Reader

import           Database.SQLite.Simple.Ok
import qualified Database.SQLite3 as Base

-- | Conn to an open db.
--
-- you can use 'connectionHandle' to gain access to the underlying
-- <http://hackage.haskell.org/package/direct-sqlite> conn.
-- this may be useful if you need to access some direct-sqlite
-- functionality that's not exposed in the sqlite-simple API.  This
-- should be a safe thing to do although mixing both APIs is
-- discouraged
data Connection = Connection
  { connectionHandle :: {-# UNPACK #-} !Base.Database
  , connectionTempNameCounter :: {-# UNPACK #-} !(IORef Word64)
  }

data ColumnOutOfBounds = ColumnOutOfBounds { errorColumnIndex :: !Int }
                      deriving (Eq, Show, Typeable)

instance Exception ColumnOutOfBounds

-- | A Field represents metadata about a particular field
data Field = Field {
     result   :: Base.SQLData
   , column   :: {-# UNPACK #-} !Int
   }

-- named type for holding RowParser read-only state.  Just for making
-- it easier to make sense out of types in FromRow
newtype RowParseRO = RowParseRO { nColumns :: Int }

newtype RowParser a = RP { unRP :: ReaderT RowParseRO (StateT (Int, [Base.SQLData]) Ok) a }
   deriving ( Functor, Applicative, Alternative, Monad, MonadPlus )

gettypename :: Base.SQLData -> ByteString
gettypename (Base.SQLInteger _) = "INTEGER"
gettypename (Base.SQLFloat _) = "FLOAT"
gettypename (Base.SQLText _) = "TEXT"
gettypename (Base.SQLBlob _) = "BLOB"
gettypename Base.SQLNull = "NULL"

