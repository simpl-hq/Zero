module Zero.Messaging.Server.MsgStore.Journal.SharedLock
  ( withLockWaitShared,
    withLockMapWaitShared,
    withSharedWaitLock,
  )
where

import Control.Concurrent.STM
import qualified Control.Exception as E
import Control.Monad
import Data.Text (Text)
import Zero.Messaging.Agent.Lock
import Zero.Messaging.Agent.Client (getMapLock)
import Zero.Messaging.Protocol (RecipientId)
import Zero.Messaging.TMap (TMap)
import qualified Zero.Messaging.TMap as TM
import Zero.Messaging.Util (($>>), ($>>=))

withLockWaitShared :: RecipientId -> Lock -> TMVar RecipientId -> Text -> IO a -> IO a
withLockWaitShared rId lock shared name =
  E.bracket_
    (atomically $ waitShared rId shared >> putTMVar lock name)
    (void $ atomically $ takeTMVar lock)

withLockMapWaitShared :: RecipientId -> TMap RecipientId Lock -> TMVar RecipientId -> Text -> IO a -> IO a
withLockMapWaitShared rId locks shared name a =
  E.bracket
    (atomically $ waitShared rId shared >> getPutLock (getMapLock locks) rId name)
    (atomically . takeTMVar)
    (const a)

waitShared :: RecipientId -> TMVar RecipientId -> STM ()
waitShared rId shared = tryReadTMVar shared >>= mapM_ (\rId' -> when (rId == rId') retry)

withSharedWaitLock :: RecipientId -> TMap RecipientId Lock -> TMVar RecipientId -> IO a -> IO a
withSharedWaitLock rId locks shared =
  E.bracket_
    (atomically $ waitLock >> putTMVar shared rId)
    (atomically $ takeTMVar shared)
  where
    waitLock = TM.lookup rId locks $>>= tryReadTMVar $>> retry
