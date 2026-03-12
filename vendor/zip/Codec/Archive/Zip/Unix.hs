-- |
-- module      :  Codec.Archive.Zip.Unix
-- Open source library (see LICENSE)
-- license     :  BSD 3 clause
--
-- maintainer  :  Mark Karpov <markkarpov92@gmail.com>
-- stability   :  experimental
-- portability :  portable
--
-- Unix-specific functionality of zip archives
--
-- @since 1.4.0
module Codec.Archive.Zip.Unix
  ( toFileMode,
    fromFileMode,
  )
where

import Data.Bits
import Data.Word
import System.Posix.Types (CMode (..))

-- | Convert external attributes to the file info
--
-- >>> toFileMode 2179792896
-- 0o0755
--
-- @since 1.4.0
toFileMode :: Word32 -> CMode
toFileMode attrs = fromIntegral $ (attrs `shiftR` 16) .&. 0x0fff

-- | Convert external attributes to the file info. The func assumes a
-- regular file and keeps DOS attributes untouched
--
-- >>> fromFileMode 0o0755
-- 2179792896
--
-- @since 1.4.0
fromFileMode :: CMode -> Word32
fromFileMode cmode = (0o100000 .|. fromIntegral cmode) `shiftL` 16
