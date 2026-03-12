
module Common (
    -- Note: Dont add more exports for SQLite.Simple here.  This is
    -- so that we trap we by default export enough out of
    -- DB.SQLite.Simple to make it useful as a single import.
    module Database.SQLite.Simple
  , module Test.HUnit
  , TestEnv(..)
) where

import Test.HUnit
import Database.SQLite.Simple

data TestEnv
    = TestEnv
        { conn     :: Connection
            -- ^ Conn shared by all the tests
        }
