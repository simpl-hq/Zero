module ChatTests.DBUtils.SQLite where

import Database.SQLite.Simple (Query)
import Zero.Messaging.Agent.Store.SQLite.DB
import Zero.Messaging.TMap (TMap)

data TestParams = TestParams
  { tmpPath :: FilePath,
    printOutput :: Bool,
    chatQueryStats :: TMap Query SlowQueryStats,
    agentQueryStats :: TMap Query SlowQueryStats
  }
