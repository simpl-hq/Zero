{-# LANGUAGE OverloadedStrings #-}

module ViewTests where

import Data.Time
import Zero.Chat.View
import Test.Hspec

viewTests :: Spec
viewTests = do
  testRecent

testRecent :: Spec
testRecent = describe "recent" $ do
  let tz = hoursToTimeZone 1
      now1159 = UTCTime (fromGregorian 2023 6 7) (secondsToDiffTime $ 10 * 3600 + 59 * 60)
      now1200 = UTCTime (fromGregorian 2023 6 7) (secondsToDiffTime $ 11 * 3600)
      today0000 = UTCTime (fromGregorian 2023 6 6) (secondsToDiffTime $ 23 * 3600)
      today0600 = UTCTime (fromGregorian 2023 6 7) (secondsToDiffTime $ 5 * 3600)
      today1200 = UTCTime (fromGregorian 2023 6 7) (secondsToDiffTime $ 11 * 3600)
      today1800 = UTCTime (fromGregorian 2023 6 7) (secondsToDiffTime $ 17 * 3600)
      today2359 = UTCTime (fromGregorian 2023 6 7) (secondsToDiffTime $ 22 * 3600 + 59 * 60)
      yesterday0000 = UTCTime (fromGregorian 2023 6 5) (secondsToDiffTime $ 23 * 3600)
      yesterday1759 = UTCTime (fromGregorian 2023 6 6) (secondsToDiffTime $ 16 * 3600 + 59 * 60)
      yesterday1800 = UTCTime (fromGregorian 2023 6 6) (secondsToDiffTime $ 17 * 3600)
      yesterday2359 = UTCTime (fromGregorian 2023 6 6) (secondsToDiffTime $ 22 * 3600 + 59 * 60)
      sameDayLastMonth1900 = UTCTime (fromGregorian 2023 5 7) (secondsToDiffTime $ 18 * 3600)
      prevDayLastMonth1900 = UTCTime (fromGregorian 2023 5 6) (secondsToDiffTime $ 18 * 3600)
      sameDayLastYear1900 = UTCTime (fromGregorian 2022 6 7) (secondsToDiffTime $ 18 * 3600)
      prevDayLastYear1900 = UTCTime (fromGregorian 2022 6 6) (secondsToDiffTime $ 18 * 3600)
      tomorrow0000 = UTCTime (fromGregorian 2023 6 7) (secondsToDiffTime $ 23 * 3600)
      tomorrow1759 = UTCTime (fromGregorian 2023 6 8) (secondsToDiffTime $ 16 * 3600 + 59 * 60)
      tomorrow1800 = UTCTime (fromGregorian 2023 6 8) (secondsToDiffTime $ 17 * 3600)
      tomorrow2359 = UTCTime (fromGregorian 2023 6 8) (secondsToDiffTime $ 22 * 3600 + 59 * 60)
      sameDayNextMonth1900 = UTCTime (fromGregorian 2023 7 7) (secondsToDiffTime $ 18 * 3600)
      prevDayNextMonth1900 = UTCTime (fromGregorian 2023 7 6) (secondsToDiffTime $ 18 * 3600)
      sameDayNextYear1900 = UTCTime (fromGregorian 2024 6 7) (secondsToDiffTime $ 18 * 3600)
      prevDayNextYear1900 = UTCTime (fromGregorian 2024 6 6) (secondsToDiffTime $ 18 * 3600)
  test tz now1159 today0000 True
  test tz now1159 today0600 True
  test tz now1159 today1200 True
  test tz now1159 today1800 True
  test tz now1159 today2359 True
  test tz now1159 yesterday0000 False
  test tz now1159 yesterday1759 False
  test tz now1159 yesterday1800 True
  test tz now1159 yesterday2359 True
  test tz now1159 sameDayLastMonth1900 False
  test tz now1159 prevDayLastMonth1900 False
  test tz now1159 sameDayLastYear1900 False
  test tz now1159 prevDayLastYear1900 False
  test tz now1159 tomorrow0000 False
  test tz now1159 tomorrow1759 False
  test tz now1159 tomorrow1800 False
  test tz now1159 tomorrow2359 False
  test tz now1159 sameDayNextMonth1900 False
  test tz now1159 prevDayNextMonth1900 False
  test tz now1159 sameDayNextYear1900 False
  test tz now1159 prevDayNextYear1900 False

  test tz now1200 today0000 True
  test tz now1200 today0600 True
  test tz now1200 today1200 True
  test tz now1200 today1800 True
  test tz now1200 today2359 True
  test tz now1200 yesterday0000 False
  test tz now1200 yesterday1759 False
  test tz now1200 yesterday1800 False
  test tz now1200 yesterday2359 False
  test tz now1200 sameDayLastMonth1900 False
  test tz now1200 prevDayLastMonth1900 False
  test tz now1200 sameDayLastYear1900 False
  test tz now1200 prevDayLastYear1900 False
  test tz now1200 tomorrow0000 False
  test tz now1200 tomorrow1759 False
  test tz now1200 tomorrow1800 False
  test tz now1200 tomorrow2359 False
  test tz now1200 sameDayNextMonth1900 False
  test tz now1200 prevDayNextMonth1900 False
  test tz now1200 sameDayNextYear1900 False
  test tz now1200 prevDayNextYear1900 False
  where
    test tz now time expected =
      it ("returns " <> show expected <> " for time " <> show time <> " when time zone is " <> show tz <> " and current time is " <> show now) $
        recent now tz time `shouldBe` expected
