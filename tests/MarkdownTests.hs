{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}

module MarkdownTests where

import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import Zero.Chat.Markdown
import Zero.Messaging.Agent.Protocol (ZeroDomain (..), ZeroNameInfo (..), ZeroNameType (..), ZeroTLD (..))
import Zero.Messaging.Encoding.String
import Zero.Messaging.Util ((<$$>))
import System.Console.ANSI.Types
import Test.Hspec
import qualified URI.ByteString as U

markdownTests :: Spec
markdownTests = do
  textFormat
  secretText
  textSmall
  textColor
  textWithUri
  textWithHyperlink
  obfuscatedZeroLinks
  textWithEmail
  textWithPhone
  textWithMentions
  textWithCommands
  textWithZeroNames
  multilineMarkdownList
  testSanitizeUri

infixr 1 ==>, <==, <==>, ==>>, <<==, <<==>>

(==>) :: Text -> Markdown -> Expectation
s ==> m = parseMarkdown s `shouldBe` m

(<==) :: Text -> Markdown -> Expectation
s <== m = s <<== markdownToList m

(<==>) :: Text -> Markdown -> Expectation
s <==> m = (s ==> m) >> (s <== m)

(==>>) :: Text -> MarkdownList -> Expectation
s ==>> ft = parseMaybeMarkdownList s `shouldBe` Just ft

(<<==) :: Text -> MarkdownList -> Expectation
s <<== ft = T.concat (map markdownText ft) `shouldBe` s

(<<==>>) :: Text -> MarkdownList -> Expectation
s <<==>> ft = (s ==>> ft) >> (s <<== ft)

bold :: Text -> Markdown
bold = markdown Bold

textFormat :: Spec
textFormat = describe "text format (bold)" do
  it "correct markdown" do
    "this is *bold formatted* text"
      <==> "this is " <> bold "bold formatted" <> " text"
    "*bold formatted* text"
      <==> bold "bold formatted" <> " text"
    "this is *bold*"
      <==> "this is " <> bold "bold"
    " *bold* text"
      <==> " " <> bold "bold" <> " text"
    "   *bold* text"
      <==> "   " <> bold "bold" <> " text"
    "this is *bold* "
      <==> "this is " <> bold "bold" <> " "
    "this is *bold*   "
      <==> "this is " <> bold "bold" <> "   "
  it "ignored as markdown" do
    "this is * unformatted * text"
      <==> "this is * unformatted * text"
    "this is *unformatted * text"
      <==> "this is *unformatted * text"
    "this is * unformatted* text"
      <==> "this is * unformatted* text"
    "this is **unformatted** text"
      <==> "this is **unformatted** text"
    "this is*unformatted* text"
      <==> "this is*unformatted* text"
    "this is *unformatted text"
      <==> "this is *unformatted text"
    "*this* is *unformatted text"
      <==> bold "this" <> " is *unformatted text"
  it "ignored internal markdown" do
    "this is *long _bold_ (not italic)* text"
      <==> "this is " <> bold "long _bold_ (not italic)" <> " text"
    "snippet: `this is *bold text*`"
      <==> "snippet: " <> markdown Snippet "this is *bold text*"

secretText :: Spec
secretText = describe "secret text" do
  it "correct markdown" do
    "this is #black_secret# text"
      <==> "this is " <> markdown Secret "black_secret" <> " text"
    "##black_secret### text"
      <==> markdown Secret "#black_secret##" <> " text"
    "this is #black secret# text"
      <==> "this is " <> markdown Secret "black secret" <> " text"
    "##black secret### text"
      <==> markdown Secret "#black secret##" <> " text"
    "this is #secret#"
      <==> "this is " <> markdown Secret "secret"
    " #secret# text"
      <==> " " <> markdown Secret "secret" <> " text"
    "   #secret# text"
      <==> "   " <> markdown Secret "secret" <> " text"
    "this is #secret# "
      <==> "this is " <> markdown Secret "secret" <> " "
    "this is #secret#   "
      <==> "this is " <> markdown Secret "secret" <> "   "
  it "ignored as markdown" do
    "this is # unformatted # text"
      <==> "this is # unformatted # text"
    "this is #unformatted # text"
      <==> "this is " <> sname NTPublicGroup TLDZero "unformatted" [] "unformatted" <> " # text"
    "this is # unformatted# text"
      <==> "this is # unformatted# text"
    "this is ## unformatted ## text"
      <==> "this is ## unformatted ## text"
    "this is#unformatted# text"
      <==> "this is#unformatted# text"
    "this is #unformatted text"
      <==> "this is " <> sname NTPublicGroup TLDZero "unformatted" [] "unformatted" <> " text"
    "*this* is #unformatted text"
      <==> bold "this" <> " is " <> sname NTPublicGroup TLDZero "unformatted" [] "unformatted" <> " text"
  it "ignored internal markdown" do
    "snippet: `this is #secret_text#`"
      <==> "snippet: " <> markdown Snippet "this is #secret_text#"

small :: Text -> Markdown
small = markdown Small

textSmall :: Spec
textSmall = describe "text small" do
  it "correct markdown" do
    "this is !- small! text"
      <==> "this is " <> small "small" <> " text"
    "!- small! text"
      <==> small "small" <> " text"
    "this is !- small!"
      <==> "this is " <> small "small"
    " !- small! text"
      <==> " " <> small "small" <> " text"
    "this is !- small! "
      <==> "this is " <> small "small" <> " "
  it "ignored as markdown" do
    "this is !- unformatted ! text"
      <==> "this is !- unformatted ! text"
    "this is !-  unformatted! text"
      <==> "this is !-  unformatted! text"
    "this is!- unformatted! text"
      <==> "this is!- unformatted! text"
    "this is !- unformatted text"
      <==> "this is !- unformatted text"
  it "ignored internal markdown" do
    "this is !- long *small* (not bold)! text"
      <==> "this is " <> small "long *small* (not bold)" <> " text"

red :: Text -> Markdown
red = markdown (colored Red)

textColor :: Spec
textColor = describe "text color (red)" do
  it "correct markdown" do
    "this is !1 red color! text"
      <==> "this is " <> red "red color" <> " text"
    "!1 red! text"
      <==> red "red" <> " text"
    "this is !1 red!"
      <==> "this is " <> red "red"
    " !1 red! text"
      <==> " " <> red "red" <> " text"
    "   !1 red! text"
      <==> "   " <> red "red" <> " text"
    "this is !1 red! "
      <==> "this is " <> red "red" <> " "
    "this is !1 red!   "
      <==> "this is " <> red "red" <> "   "
  it "ignored as markdown" do
    "this is !1 unformatted ! text"
      <==> "this is !1 unformatted ! text"
    "this is !1 unformatted ! text"
      <==> "this is !1 unformatted ! text"
    "this is !1  unformatted! text"
      <==> "this is !1  unformatted! text"
    "this is!1 unformatted! text"
      <==> "this is!1 unformatted! text"
    "this is !1 unformatted text"
      <==> "this is !1 unformatted text"
    "*this* is !1 unformatted text"
      <==> bold "this" <> " is !1 unformatted text"
  it "ignored internal markdown" do
    "this is !1 long *red* (not bold)! text"
      <==> "this is " <> red "long *red* (not bold)" <> " text"
    "snippet: `this is !1 red text!`"
      <==> "snippet: " <> markdown Snippet "this is !1 red text!"

uri :: Text -> Markdown
uri = Markdown $ Just Uri

zeroLink :: ZeroLinkType -> Text -> NonEmpty Text -> Text -> Markdown
zeroLink linkType uriText smpHosts t = Markdown (zeroLinkFormat linkType uriText smpHosts Nothing) t

zeroLinkFormat :: ZeroLinkType -> Text -> NonEmpty Text -> Maybe Text -> Maybe Format
zeroLinkFormat linkType uriText smpHosts showText = case strDecode $ encodeUtf8 uriText of
  Right zeroUri -> Just ZeroLink {linkType, zeroUri, smpHosts, showText}
  Left e -> error e

textWithUri :: Spec
textWithUri = describe "text with Uri" do
  it "correct markdown" do
    "https://zero.chat" <==> uri "https://zero.chat"
    "https://zero.chat." <==> uri "https://zero.chat" <> "."
    "https://zero.chat, hello" <==> uri "https://zero.chat" <> ", hello"
    "http://zero.chat" <==> uri "http://zero.chat"
    "this is https://zero.chat" <==> "this is " <> uri "https://zero.chat"
    "https://zero.chat site" <==> uri "https://zero.chat" <> " site"
    "Zero on GitHub: https://github.com/simpl-hq/zero/" <==> "Zero on GitHub: " <> uri "https://github.com/simpl-hq/zero/"
    "Zero on GitHub: https://github.com/simpl-hq/zero." <==> "Zero on GitHub: " <> uri "https://github.com/simpl-hq/zero" <> "."
    "https://github.com/simpl-hq/zero/ - Zero on GitHub" <==> uri "https://github.com/simpl-hq/zero/" <> " - Zero on GitHub"
    "https://en.m.wikipedia.org/wiki/Servo_(software)" <==> uri "https://en.m.wikipedia.org/wiki/Servo_(software)"
    "https://zero.chat/page_name_" <==> uri "https://zero.chat/page_name_"
    "https://zero.chat/page_name_, hello" <==> uri "https://zero.chat/page_name_" <> ", hello"
    "https://zero.chat/page!" <==> uri "https://zero.chat/page!"
    "https://zero.chat/page!, hello" <==> uri "https://zero.chat/page!" <> ", hello"
    "example.com" <==> uri "example.com"
    "example.com." <==> uri "example.com" <> "."
    "example.com..." <==> uri "example.com" <> "..."
    "www.example.com" <==> uri "www.example.com"
    "example.academy" <==> uri "example.academy"
    "this is example.com" <==> "this is " <> uri "example.com"
    "x.com" <==> uri "x.com"
  it "ignored as markdown" do
    "_https://zero.chat" <==> "_https://zero.chat"
    "this is _https://zero.chat" <==> "this is _https://zero.chat"
    "this is https://" <==> "this is https://"
    "example.c" <==> "example.c"
    "www.www.example.com" <==> "www.www.example.com"
    "www.example1.com" <==> "www.example1.com"
    "www." <==> "www."
    ".com" <==> ".com"
    "example.academytoolong" <==> "example.academytoolong"
    "zero:/example" <==> "zero:/example"
  it "Zero links" do
    let inv = "/invitation#/?v=1&smp=smp%3A%2F%2F1234-w%3D%3D%40smp.zero.im%3A5223%2F3456-w%3D%3D%23%2F%3Fv%3D1-2%26dh%3DMCowBQYDK2VuAyEAjiswwI3O_NlS8Fk3HJUW870EY2bAwmttMBsvRB9eV3o%253D&e2e=v%3D2%26x3dh%3DMEIwBQYDK2VvAzkAmKuSYeQ_m0SixPDS8Wq8VBaTS1cW-Lp0n0h4Diu-kUpR-qXx4SDJ32YGEFoGFGSbGPry5Ychr6U%3D%2CMEIwBQYDK2VvAzkAmKuSYeQ_m0SixPDS8Wq8VBaTS1cW-Lp0n0h4Diu-kUpR-qXx4SDJ32YGEFoGFGSbGPry5Ychr6U%3D"
    ("https://zero.chat" <> inv) <==> zeroLink XLInvitation ("zero:" <> inv) ["smp.zero.im"] ("https://zero.chat" <> inv)
    ("zero:" <> inv) <==> zeroLink XLInvitation ("zero:" <> inv) ["smp.zero.im"] ("zero:" <> inv)
    ("https://example.com" <> inv) <==> zeroLink XLInvitation ("zero:" <> inv) ["smp.zero.im"] ("https://example.com" <> inv)
    let ct = "/contact#/?v=2&smp=smp%3A%2F%2F1234-w%3D%3D%40smp.zero.im%3A5223%2F3456-w%3D%3D%23%2F%3Fv%3D1-2%26dh%3DMCowBQYDK2VuAyEAjiswwI3O_NlS8Fk3HJUW870EY2bAwmttMBsvRB9eV3o%253D"
    ("https://zero.chat" <> ct) <==> zeroLink XLContact ("zero:" <> ct) ["smp.zero.im"] ("https://zero.chat" <> ct)
    ("zero:" <> ct) <==> zeroLink XLContact ("zero:" <> ct) ["smp.zero.im"] ("zero:" <> ct)
    let gr = "/contact#/?v=2&smp=smp%3A%2F%2Fu2dS9sG8nMNURyZwqASV4yROM28Er0luVTx5X1CsMrU%3D%40smp4.zero.im%2FWHV0YU1sYlU7NqiEHkHDB6gxO1ofTync%23%2F%3Fv%3D1-2%26dh%3DMCowBQYDK2VuAyEAWbebOqVYuBXaiqHcXYjEHCpYi6VzDlu6CVaijDTmsQU%253D%26srv%3Do5vmywmrnaxalvz6wi3zicyftgio6psuvyniis6gco6bp6ekl4cqj4id.onion&data=%7B%22type%22%3A%22group%22%2C%22groupLinkId%22%3A%22mL-7Divb94GGmGmRBef5Dg%3D%3D%22%7D"
    ("https://zero.chat" <> gr) <==> zeroLink XLGroup ("zero:" <> gr) ["smp4.zero.im", "o5vmywmrnaxalvz6wi3zicyftgio6psuvyniis6gco6bp6ekl4cqj4id.onion"] ("https://zero.chat" <> gr)
    ("zero:" <> gr) <==> zeroLink XLGroup ("zero:" <> gr) ["smp4.zero.im", "o5vmywmrnaxalvz6wi3zicyftgio6psuvyniis6gco6bp6ekl4cqj4id.onion"] ("zero:" <> gr)

web :: Text -> Text -> Text -> Markdown
web t u = Markdown $ Just HyperLink {showText = Just t, linkUri = u}

textWithHyperlink :: Spec
textWithHyperlink = describe "text with HyperLink without link text" do
  let addr = "https://smp6.zero.im/a#lrdvu2d8A1GumSmoKb2krQmtKhWXq-tyGpHuM7aMwsw"
      addr' = "zero:/a#lrdvu2d8A1GumSmoKb2krQmtKhWXq-tyGpHuM7aMwsw?h=smp6.zero.im"
  it "correct markdown" do
    "[click here](https://example.com)" <==> web "click here" "https://example.com" "[click here](https://example.com)"
    "For details [click here](https://example.com)" <==> "For details " <> web "click here" "https://example.com" "[click here](https://example.com)"
    "[example.com](https://example.com)" <==> web "example.com" "https://example.com" "[example.com](https://example.com)"
    "[example.com/page](https://example.com/page)" <==> web "example.com/page" "https://example.com/page" "[example.com/page](https://example.com/page)"
    ("[Connect to me](" <> addr <> ")") <==> Markdown (zeroLinkFormat XLContact addr' ["smp6.zero.im"] (Just "Connect to me")) ("[Connect to me](" <> addr <> ")")
  it "potentially spoofed link" do
    "[https://example.com](https://another.com)" <==> "[https://example.com](https://another.com)"
    "[example.com/page](https://another.com/page)" <==> "[example.com/page](https://another.com/page)"
    ("[Connect.to.me](" <> addr <> ")") <==> Markdown Nothing ("[Connect.to.me](" <> addr <> ")")
  it "ignored as markdown" do
    "[click here](example.com)" <==> "[click here](example.com)"
    "[click here](https://example.com )" <==> "[click here](https://example.com )"

obfuscatedZeroLinks :: Spec
obfuscatedZeroLinks = describe "Zero links obfuscated with whitespace" do
  let addr = "https://smp6.zero.im/a#lrdvu2d8A1GumSmoKb2krQmtKhWXq-tyGpHuM7aMwsw"
      inv = "/invitation#/?v=1&smp=smp%3A%2F%2F1234-w%3D%3D%40smp.zero.im%3A5223%2F3456-w%3D%3D%23%2F%3Fv%3D1-2%26dh%3DMCowBQYDK2VuAyEAjiswwI3O_NlS8Fk3HJUW870EY2bAwmttMBsvRB9eV3o%253D&e2e=v%3D2%26x3dh%3DMEIwBQYDK2VvAzkAmKuSYeQ_m0SixPDS8Wq8VBaTS1cW-Lp0n0h4Diu-kUpR-qXx4SDJ32YGEFoGFGSbGPry5Ychr6U%3D%2CMEIwBQYDK2VvAzkAmKuSYeQ_m0SixPDS8Wq8VBaTS1cW-Lp0n0h4Diu-kUpR-qXx4SDJ32YGEFoGFGSbGPry5Ychr6U%3D"
  let spaced s = T.replace "://" ":// " s
  it "detects links split with spaces or newlines" do
    hasObfuscatedZeroLink addr `shouldBe` True
    hasObfuscatedZeroLink (spaced addr) `shouldBe` True
    hasObfuscatedZeroLink (T.intercalate "\n" $ T.chunksOf 8 addr) `shouldBe` True
    hasObfuscatedZeroLink ("connect with me: " <> spaced addr) `shouldBe` True
    hasObfuscatedZeroLink (T.intercalate " " $ T.chunksOf 8 $ "https://zero.chat" <> inv) `shouldBe` True
  it "detects a split link followed by other text" do
    hasObfuscatedZeroLink (spaced addr <> "\nplease connect") `shouldBe` True
  it "ignores text without a Zero link" do
    hasObfuscatedZeroLink "" `shouldBe` False
    hasObfuscatedZeroLink "hello there, this is a normal message" `shouldBe` False
    hasObfuscatedZeroLink "see https://example.com/page?ref=123 for details" `shouldBe` False

email :: Text -> Markdown
email = Markdown $ Just Email

textWithEmail :: Spec
textWithEmail = describe "text with Email" do
  it "correct markdown" do
    "support@simpl.global" <==> email "support@simpl.global"
    "test support@simpl.global" <==> "test " <> email "support@simpl.global"
    "test chat+123@zero.chat" <==> "test " <> email "chat+123@zero.chat"
    "test chat.chat+123@zero.chat" <==> "test " <> email "chat.chat+123@zero.chat"
    "support@simpl.global test" <==> email "support@simpl.global" <> " test"
    "test1 support@simpl.global test2" <==> "test1 " <> email "support@simpl.global" <> " test2"
    "test support@simpl.global." <==> "test " <> email "support@simpl.global" <> "."
    "test support@simpl.global..." <==> "test " <> email "support@simpl.global" <> "..."
  it "ignored as email markdown" do
    "chat @zero.chat" <==> "chat " <> sname NTContact TLDWeb "zero.chat" [] "zero.chat"
    "this is chat @zero.chat" <==> "this is chat " <> sname NTContact TLDWeb "zero.chat" [] "zero.chat"
    "this is chat@ zero.chat" <==> "this is chat@ " <> uri "zero.chat"
    "this is chat @ zero.chat" <==> "this is chat @ " <> uri "zero.chat"
    "*this* is chat @ zero.chat" <==> bold "this" <> " is chat @ " <> uri "zero.chat"

phone :: Text -> Markdown
phone = Markdown $ Just Phone

textWithPhone :: Spec
textWithPhone = describe "text with Phone" do
  it "correct markdown" do
    "07777777777" <==> phone "07777777777"
    "test 07777777777" <==> "test " <> phone "07777777777"
    "07777777777 test" <==> phone "07777777777" <> " test"
    "test1 07777777777 test2" <==> "test1 " <> phone "07777777777" <> " test2"
    "test 07777 777 777 test" <==> "test " <> phone "07777 777 777" <> " test"
    "test +447777777777 test" <==> "test " <> phone "+447777777777" <> " test"
    "test +44 (0) 7777 777 777 test" <==> "test " <> phone "+44 (0) 7777 777 777" <> " test"
    "test +44-7777-777-777 test" <==> "test " <> phone "+44-7777-777-777" <> " test"
    "test +44 (0) 7777.777.777 https://zero.chat test"
      <==> "test " <> phone "+44 (0) 7777.777.777" <> " " <> uri "https://zero.chat" <> " test"
  it "ignored as markdown (too short)" $
    "test 077777 test" <==> "test 077777 test"
  it "ignored as markdown (double spaces)" $ do
    "test 07777  777  777 test" <==> "test 07777  777  777 test"
    "*test* 07777  777  777 test" <==> bold "test" <> " 07777  777  777 test"

mention :: Text -> Text -> Markdown
mention = Markdown . Just . Mention

textWithMentions :: Spec
textWithMentions = describe "text with mentions" do
  it "correct markdown" do
    "@alice" <==> mention "alice" "@alice"
    "hello @alice" <==> "hello " <> mention "alice" "@alice"
    "hello @alice !" <==> "hello " <> mention "alice" "@alice" <> " !"
    "hello @alice!" <==> "hello " <> mention "alice" "@alice" <> "!"
    "hello @alice..." <==> "hello " <> mention "alice" "@alice" <> "..."
    "hello @alice@example.com" <==> "hello " <> mention "alice@example.com" "@alice@example.com"
    "hello @'alice @ example.com'" <==> "hello " <> mention "alice @ example.com" "@'alice @ example.com'"
    "@'alice jones'" <==> mention "alice jones" "@'alice jones'"
    "hello @'alice jones'!" <==> "hello " <> mention "alice jones" "@'alice jones'" <> "!"
    "hello @'a.j.'!" <==> "hello " <> mention "a.j." "@'a.j.'" <> "!"
  it "ignored as markdown" $ do
    "hello @'alice jones!" <==> "hello @'alice jones!"
    "hello @bob @'alice jones!" <==> "hello " <> mention "bob" "@bob" <> " @'alice jones!"
    "hello @ alice!" <==> "hello @ alice!"
    "hello @bob @ alice!" <==> "hello " <> mention "bob" "@bob" <> " @ alice!"
    "hello @bob @" <==> "hello " <> mention "bob" "@bob" <> " @"

command :: Text -> Text -> Markdown
command = Markdown . Just . Command

textWithCommands :: Spec
textWithCommands = describe "text with commands" do
  it "correct markdown" do
    "/start" <==> command "start" "/start"
    "send /help" <==> "send " <> command "help" "/help"
    "send /help !" <==> "send " <> command "help" "/help" <> " !"
    "send /help!" <==> "send " <> command "help" "/help" <> "!"
    "send /help..." <==> "send " <> command "help" "/help" <> "..."
    "send /'filter 1'" <==> "send " <> command "filter 1" "/'filter 1'"
    "/'filter 1'" <==> command "filter 1" "/'filter 1'"
    "/filter 1" <==> command "filter" "/filter" <> " 1"
    "send /'filter 1'." <==> "send " <> command "filter 1" "/'filter 1'" <> "."
    "send /'filter 1.'!" <==> "send " <> command "filter 1." "/'filter 1.'" <> "!"
  it "ignored as markdown" $ do
    "send /'filter 1" <==> "send /'filter 1"
    "send /help /'filter 1" <==> "send " <> command "help" "/help" <> " /'filter 1"
    "send / help!" <==> "send / help!"
    "send /help / filter" <==> "send " <> command "help" "/help" <> " / filter"
    "send /help /" <==> "send " <> command "help" "/help" <> " /"
    "send /he?lp" <==> "send /he?lp"

uri' :: Text -> FormattedText
uri' = FormattedText $ Just Uri

command' :: Text -> Text -> FormattedText
command' = FormattedText . Just . Command

sname :: ZeroNameType -> ZeroTLD -> Text -> [Text] -> Text -> Markdown
sname nt ns dom sub txt = markdown (ZeroName $ ZeroNameInfo nt (ZeroDomain ns dom sub)) (pfx <> txt)
  where
    pfx = case nt of NTPublicGroup -> "#"; NTContact -> "@"

textWithZeroNames :: Spec
textWithZeroNames = describe "text with Zero names" do
  it "channel names - zero namespace" do
    "#privacy" <==> sname NTPublicGroup TLDZero "privacy" [] "privacy"
    "#privacy.zero" <==> sname NTPublicGroup TLDZero "privacy" [] "privacy.zero"
    "#my-channel.zero" <==> sname NTPublicGroup TLDZero "my-channel" [] "my-channel.zero"
    "hello #privacy!" <==> "hello " <> sname NTPublicGroup TLDZero "privacy" [] "privacy" <> "!"
    "see #privacy.zero now" <==> "see " <> sname NTPublicGroup TLDZero "privacy" [] "privacy.zero" <> " now"
    "#123" <==> sname NTPublicGroup TLDZero "123" [] "123"
  it "channel names - subdomains" do
    "#support.acme.zero" <==> sname NTPublicGroup TLDZero "acme" ["support"] "support.acme.zero"
    "#a.b.acme.zero" <==> sname NTPublicGroup TLDZero "acme" ["b", "a"] "a.b.acme.zero"
  it "channel names - testing namespace" do
    "#test.testing" <==> sname NTPublicGroup TLDTesting "test" [] "test.testing"
    "#sub.test.testing" <==> sname NTPublicGroup TLDTesting "test" ["sub"] "sub.test.testing"
  it "channel names - web domains" do
    "#example.com" <==> sname NTPublicGroup TLDWeb "example.com" [] "example.com"
    "#news.bbc.co.uk" <==> sname NTPublicGroup TLDWeb "news.bbc.co.uk" [] "news.bbc.co.uk"
    "#123.com" <==> sname NTPublicGroup TLDWeb "123.com" [] "123.com"
  it "contact names" do
    "@privacy.zero" <==> sname NTContact TLDZero "privacy" [] "privacy.zero"
    "@my-name.zero" <==> sname NTContact TLDZero "my-name" [] "my-name.zero"
    "@alice.example.com" <==> sname NTContact TLDWeb "alice.example.com" [] "alice.example.com"
  it "not parsed as names" do
    "#secret#" <==> markdown Secret "secret"
    "##double secret##" <==> markdown Secret "#double secret#"
    "#" <==> "#"

multilineMarkdownList :: Spec
multilineMarkdownList = describe "multiline markdown" do
  it "correct markdown" do
    "http://zero.chat\nhttp://app.zero.chat" <<==>> [uri' "http://zero.chat", "\n", uri' "http://app.zero.chat"]
  it "combines the same formats" do
    "http://zero.chat\ntext 1\ntext 2\nhttp://app.zero.chat" <<==>> [uri' "http://zero.chat", "\ntext 1\ntext 2\n", uri' "http://app.zero.chat"]
  it "no markdown" do
    parseMaybeMarkdownList "not a\nmarkdown" `shouldBe` Nothing
  let inv = "/invitation#/?v=1&smp=smp%3A%2F%2F1234-w%3D%3D%40smp.zero.im%3A5223%2F3456-w%3D%3D%23%2F%3Fv%3D1-2%26dh%3DMCowBQYDK2VuAyEAjiswwI3O_NlS8Fk3HJUW870EY2bAwmttMBsvRB9eV3o%253D&e2e=v%3D2%26x3dh%3DMEIwBQYDK2VvAzkAmKuSYeQ_m0SixPDS8Wq8VBaTS1cW-Lp0n0h4Diu-kUpR-qXx4SDJ32YGEFoGFGSbGPry5Ychr6U%3D%2CMEIwBQYDK2VvAzkAmKuSYeQ_m0SixPDS8Wq8VBaTS1cW-Lp0n0h4Diu-kUpR-qXx4SDJ32YGEFoGFGSbGPry5Ychr6U%3D"
  it "multiline with zero link" do
    ("https://zero.chat" <> inv <> "\ntext")
      <<==>>
        [ FormattedText (zeroLinkFormat XLInvitation ("zero:" <> inv) ["smp.zero.im"] Nothing) ("https://zero.chat" <> inv),
          "\ntext"
        ]
  it "command markdown" do
    "/link 1" <<==>> [command' "link 1" "/link 1"]
    " /link 1" <<==>> [command' "link 1" " /link 1"]

testSanitizeUri :: Spec
testSanitizeUri = describe "sanitizeUri" $ do
  it "should allow the first parameter and whitelisted parameters on pages without IDs" $ do
    "https://example.com/page?ref=123" `sanitized` Just "https://example.com/page"
    "https://example.com/page?name" `sanitized` Nothing
    "https://example.com/page?name=abc" `sanitized` Nothing
    "https://example.com/page?name=abc&ref=123" `sanitized` Just "https://example.com/page?name=abc"
    "https://example.com/page?search=query" `sanitized` Nothing
    "https://example.com/page?q=query" `sanitized` Nothing
    "https://example.com/page?ref=123&q=query" `sanitized` Just "https://example.com/page?q=query"
    "https://youtube.com/watch?v=abc&t=123" `sanitized` Nothing
    "https://www.youtube.com/watch?v=abc" `sanitized` Nothing
    "https://www.youtube.com/watch?v=abc&t=123" `sanitized` Nothing
    "https://www.youtube.com/watch?ref=456&v=abc&t=123" `sanitized` Just "https://www.youtube.com/watch?v=abc&t=123"
  it "should only allow whitelisted parameters if path contains IDs" $ do
    "https://youtu.be/a123?si=456" `sanitized` Just "https://youtu.be/a123"
    "https://youtu.be/a123?t=456" `sanitized` Nothing
    "https://youtu.be/a123?si=456&t=789" `sanitized` Just "https://youtu.be/a123?t=789"
  it "should allow some parameters in safe mode, but sanitize in unsafe" $ do
    "https://example.com/page/a123?source=abc" `eagerSanitized` Just "https://example.com/page/a123"
    "https://example.com/page/a123?source=abc" `safeSanitized` Nothing
    "https://example.com/page/a123?name=abc" `eagerSanitized` Just "https://example.com/page/a123"
    "https://example.com/page/a123?name=abc" `safeSanitized` Nothing
  it "should keep whitelisted parameters in safe mode even if they match a blacklist prefix" $ do
    "https://example.com/playlist?list=abc" `sanitized` Nothing
    "https://example.com/playlist?list=abc&si=def" `sanitized` Just "https://example.com/playlist?list=abc"
    "https://github.com/owner/repo?ref=main" `sanitized` Nothing
  where
    s `eagerSanitized` res = sanitized_ False s res
    s `safeSanitized` res = sanitized_ True s res
    s `sanitized` res = do
      s `eagerSanitized` res
      s `safeSanitized` res
    sanitized_ safe s res = (U.serializeURIRef' <$$> (sanitizeUri safe <$> parseUri s)) `shouldBe` Right res
