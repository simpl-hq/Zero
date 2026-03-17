{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PostfixOperators #-}

module ChatTests.Names where

import ChatClient
import ChatTests.DBUtils
import ChatTests.Groups (memberJoinChannel, prepareChannel1Relay)
import ChatTests.Utils
import Control.Concurrent.Async (concurrently_)
import qualified Data.Text as T
import NameResolver
import Zero.Messaging.ZeroName (ZeroDomain (..), ZeroNameInfo (..), ZeroNameType (..), ZeroTLD (..))
import Test.Hspec hiding (it)

chatNamesTests :: SpecWith TestParams
chatNamesTests = do
  it "connect by resolved name" testConnectByName
  it "connect by name not claimed in link profile is rejected" testConnectByNameNotClaimed
  it "connect by name to a known contact not claimed in profile is rejected" testConnectByNameKnownContactNotClaimed
  it "connect by unregistered name fails to resolve" testConnectByNameNotFound
  it "set name not resolving to own address is rejected" testSetNameNotOwnAddress
  it "channel name is not verified just by joining via link" testChannelDomainLinkJoinUnverified
  it "verify channel name, fail on re-point, retain status on refresh" testChannelDomainVerify
  it "connect by channel name" testConnectByChannelName
  it "connect by name resolving to channel (primary) and direct contact" testConnectByNameChannelAndContact
  it "connect by name resolving to direct contact (primary) and channel" testConnectByNameContactAndChannel
  it "connect by name resolving to business (primary) and channel" testConnectByNameBusinessAndChannel

testConnectByName :: HasCallStack => TestParams -> IO ()
testConnectByName ps = withSmpServerAndNames $ \reg ->
  testChat2 aliceProfile bobProfile (test reg) ps
  where
    aliceName = ZeroNameInfo NTContact (ZeroDomain TLDZero "alice" [])
    test reg alice bob = do
      mapM_ enableNamesRole [alice, bob]
      alice ##> "/ad"
      (shortLink, _) <- getContactLinks alice True
      registerName reg aliceName (contactNameRecord "alice" (T.pack shortLink))
      alice ##> "/_set domain 1 alice.zero"
      alice <## "new contact address set"
      bob ##> "/c @alice.zero"
      bob <## "alice: connection started"
      alice <## "bob (Bob) wants to connect to you!"
      alice <## "to accept: /ac bob"
      alice <## "to reject: /rc bob (the sender will NOT be notified)"
      alice ##> "/ac bob"
      alice <## "bob (Bob): accepting contact request, you can send messages to contact"
      concurrently_
        (bob <## "alice (Alice): contact is connected")
        (alice <## "bob (Bob): contact is connected")
      alice <##> bob
      bob ##> "/i alice"
      bob <## "contact ID: 2"
      bob <## "receiving messages via: localhost"
      bob <## "sending messages via: localhost"
      _ <- getTermLine bob
      bob <## "Zero name: @alice.zero (verified)"
      bob <## "you've shared main profile with this contact"
      bob <## "connection not verified, use /code command to see security code"
      bob <## "quantum resistant end-to-end encryption"
      _ <- getTermLine bob
      pure ()

testConnectByNameNotClaimed :: HasCallStack => TestParams -> IO ()
testConnectByNameNotClaimed ps = withSmpServerAndNames $ \reg ->
  testChat2 aliceProfile bobProfile (test reg) ps
  where
    aliceName = ZeroNameInfo NTContact (ZeroDomain TLDZero "alice" [])
    test reg alice bob = do
      mapM_ enableNamesRole [alice, bob]
      alice ##> "/ad"
      (shortLink, _) <- getContactLinks alice True
      registerName reg aliceName (contactNameRecord "alice" (T.pack shortLink))
      bob ##> "/c @alice.zero"
      bob <## "Zero name alice.zero is not included in the connection link's profile"

testConnectByNameKnownContactNotClaimed :: HasCallStack => TestParams -> IO ()
testConnectByNameKnownContactNotClaimed ps = withSmpServerAndNames $ \reg ->
  testChat2 aliceProfile bobProfile (test reg) ps
  where
    aliceName = ZeroNameInfo NTContact (ZeroDomain TLDZero "alice" [])
    test reg alice bob = do
      mapM_ enableNamesRole [alice, bob]
      alice ##> "/ad"
      (shortLink, _) <- getContactLinks alice True
      bob ##> ("/c " <> shortLink)
      bob <## "connection request sent!"
      alice <## "bob (Bob) wants to connect to you!"
      alice <## "to accept: /ac bob"
      alice <## "to reject: /rc bob (the sender will NOT be notified)"
      alice ##> "/ac bob"
      alice <## "bob (Bob): accepting contact request, you can send messages to contact"
      concurrently_
        (bob <## "alice (Alice): contact is connected")
        (alice <## "bob (Bob): contact is connected")
      registerName reg aliceName (contactNameRecord "alice" (T.pack shortLink))
      bob ##> "/c @alice.zero"
      bob <## "Zero name alice.zero is not included in the connection link's profile"

testConnectByNameNotFound :: HasCallStack => TestParams -> IO ()
testConnectByNameNotFound ps = withSmpServerAndNames $ \_reg ->
  testChat2 aliceProfile bobProfile test ps
  where
    test _alice bob = do
      enableNamesRole bob
      bob ##> "/c @nobody.zero"
      bob .<## "smpErr = NAME {nameErr = NOT_FOUND}}"

testSetNameNotOwnAddress :: HasCallStack => TestParams -> IO ()
testSetNameNotOwnAddress ps = withSmpServerAndNames $ \reg ->
  testChat2 aliceProfile bobProfile (test reg) ps
  where
    aliceName = ZeroNameInfo NTContact (ZeroDomain TLDZero "alice" [])
    test reg alice bob = do
      mapM_ enableNamesRole [alice, bob]
      bob ##> "/ad"
      (bobShortLink, _) <- getContactLinks bob True
      registerName reg aliceName (contactNameRecord "alice" (T.pack bobShortLink))
      alice ##> "/ad"
      _ <- getContactLinks alice True
      alice ##> "/_set domain 1 alice.zero"
      alice <## "Zero name alice.zero has no valid connection link"

testChannelDomainLinkJoinUnverified :: HasCallStack => TestParams -> IO ()
testChannelDomainLinkJoinUnverified ps = withSmpServerAndNames $ \reg ->
  withNewTestChat ps "alice" aliceProfile $ \alice ->
    withNewTestChatOpts ps relayTestOpts "cath" cathProfile $ \cath ->
      withNewTestChat ps "bob" bobProfile $ \bob -> do
        mapM_ enableNamesRole [alice, cath, bob]
        (shortLink, fullLink) <- prepareChannel1Relay "team" alice cath
        registerName reg teamName (channelNameRecord "team" (T.pack shortLink))
        alice ##> "/public group access #team domain=team.zero"
        alice <## "updated public group access: domain=team.zero"
        cath <## "alice updated group #team: (signed)"
        cath <## "updated public group access: domain=team.zero"
        memberJoinChannel "team" [cath] [alice] shortLink fullLink bob
        bob ##> ("/_connect plan 1 " <> shortLink <> " resolve=allGroups")
        bob <## "group link: known group #team"
        bob <## "use #team <message> to send messages"
  where
    teamName = ZeroNameInfo NTPublicGroup (ZeroDomain TLDZero "team" [])

testChannelDomainVerify :: HasCallStack => TestParams -> IO ()
testChannelDomainVerify ps = withSmpServerAndNames $ \reg ->
  withNewTestChat ps "alice" aliceProfile $ \alice ->
    withNewTestChatOpts ps relayTestOpts "cath" cathProfile $ \cath ->
      withNewTestChat ps "bob" bobProfile $ \bob -> do
        mapM_ enableNamesRole [alice, cath, bob]
        (shortLink, fullLink) <- prepareChannel1Relay "team" alice cath
        registerName reg teamName (channelNameRecord "team" (T.pack shortLink))
        alice ##> "/public group access #team domain=team.zero"
        alice <## "updated public group access: domain=team.zero"
        cath <## "alice updated group #team: (signed)"
        cath <## "updated public group access: domain=team.zero"
        alice ##> "/_verify domain #1"
        alice <## "Zero name #team verified"
        memberJoinChannel "team" [cath] [alice] shortLink fullLink bob
        bob ##> "/_verify domain #1"
        bob <## "Zero name #team verified"
        registerName reg teamName (channelNameRecord "team" "https://zero.chat/other")
        bob ##> "/_verify domain #1"
        bob <## "Zero name #team not verified: the name does not resolve to the link in the group profile"
        bob ##> ("/_connect plan 1 " <> shortLink <> " resolve=allGroups")
        bob <## "group link: known group #team"
        bob <## "Zero name: #team (verification failed)"
        bob <## "use #team <message> to send messages"
  where
    teamName = ZeroNameInfo NTPublicGroup (ZeroDomain TLDZero "team" [])

testConnectByChannelName :: HasCallStack => TestParams -> IO ()
testConnectByChannelName ps = withSmpServerAndNames $ \reg ->
  withNewTestChat ps "alice" aliceProfile $ \alice ->
    withNewTestChatOpts ps relayTestOpts "cath" cathProfile $ \cath ->
      withNewTestChat ps "bob" bobProfile $ \bob -> do
        mapM_ enableNamesRole [alice, cath, bob]
        (shortLink, _) <- prepareChannel1Relay "team" alice cath
        registerName reg teamName (channelNameRecord "team" (T.pack shortLink))
        alice ##> "/public group access #team domain=team.zero"
        alice <## "updated public group access: domain=team.zero"
        cath <## "alice updated group #team: (signed)"
        cath <## "updated public group access: domain=team.zero"
        bob ##> "/c #team.zero"
        bob <## "#team: connection started"
        concurrentlyN_
          [ bob
              <### [ "#team: joining the group (connecting to relay cath)...",
                     "#team: you joined the group (connected to relay cath)"
                   ]
          , do
              cath <## "bob (Bob): accepting request to join group #team..."
              cath <## "#team: bob joined the group"
          , alice <### [EndsWith "introduced bob (Bob) in the channel"]
          ]
        bob ##> ("/_connect plan 1 " <> shortLink)
        bob <## "group link: known group #team"
        bob <## "Zero name: #team (verified)"
        bob <## "use #team <message> to send messages"
  where
    teamName = ZeroNameInfo NTPublicGroup (ZeroDomain TLDZero "team" [])

testConnectByNameChannelAndContact :: HasCallStack => TestParams -> IO ()
testConnectByNameChannelAndContact ps = withSmpServerAndNames $ \reg ->
  withNewTestChat ps "alice" aliceProfile $ \alice ->
    withNewTestChatOpts ps relayTestOpts "cath" cathProfile $ \cath ->
      withNewTestChat ps "bob" bobProfile $ \bob -> do
        mapM_ enableNamesRole [alice, cath, bob]
        (channelLink, _) <- prepareChannel1Relay "team" alice cath
        alice ##> "/ad"
        (contactLink, _) <- getContactLinks alice True
        registerName reg teamName (contactAndChannelNameRecord "team" (T.pack contactLink) (T.pack channelLink))
        alice ##> "/public group access #team domain=team.zero"
        alice <## "updated public group access: domain=team.zero"
        cath <## "alice updated group #team: (signed)"
        cath <## "updated public group access: domain=team.zero"
        bob ##> "/c #team.zero"
        bob <## "#team: connection started"
        concurrentlyN_
          [ bob
              <### [ "#team: joining the group (connecting to relay cath)...",
                     "#team: you joined the group (connected to relay cath)"
                   ]
          , do
              cath <## "bob (Bob): accepting request to join group #team..."
              cath <## "#team: bob joined the group"
          , alice <### [EndsWith "introduced bob (Bob) in the channel"]
          ]
        bob ##> "/_connect plan 1 team.zero"
        bob <## "group link: known group #team"
        bob <## "Zero name: #team (verified)"
        bob <## "use #team <message> to send messages"
        bob <## "You can also connect to @team.zero in direct chat"
  where
    teamName = ZeroNameInfo NTPublicGroup (ZeroDomain TLDZero "team" [])

testConnectByNameContactAndChannel :: HasCallStack => TestParams -> IO ()
testConnectByNameContactAndChannel ps = withSmpServerAndNames $ \reg ->
  withNewTestChat ps "alice" aliceProfile $ \alice ->
    withNewTestChatOpts ps relayTestOpts "cath" cathProfile $ \cath ->
      withNewTestChat ps "bob" bobProfile $ \bob -> do
        mapM_ enableNamesRole [alice, cath, bob]
        (channelLink, _) <- prepareChannel1Relay "acme" alice cath
        alice ##> "/ad"
        (contactLink, _) <- getContactLinks alice True
        registerName reg acmeName (contactAndChannelNameRecord "acme" (T.pack contactLink) (T.pack channelLink))
        alice ##> "/_set domain 1 acme.zero"
        alice <## "new contact address set"
        bob ##> "/_connect plan 1 acme.zero"
        bob <## "contact address: ok to connect"
        _ <- getTermLine bob
        bob <## "You can also join channel #acme"
  where
    acmeName = ZeroNameInfo NTContact (ZeroDomain TLDZero "acme" [])

testConnectByNameBusinessAndChannel :: HasCallStack => TestParams -> IO ()
testConnectByNameBusinessAndChannel ps = withSmpServerAndNames $ \reg ->
  withNewTestChat ps "alice" aliceProfile $ \alice ->
    withNewTestChatOpts ps relayTestOpts "cath" cathProfile $ \cath ->
      withNewTestChat ps "bob" bobProfile $ \bob -> do
        mapM_ enableNamesRole [alice, cath, bob]
        (channelLink, _) <- prepareChannel1Relay "biz" alice cath
        alice ##> "/ad"
        (contactLink, fullLink) <- getContactLinks alice True
        registerName reg bizName (contactAndChannelNameRecord "biz" (T.pack contactLink) (T.pack channelLink))
        alice ##> "/auto_accept on business"
        alice <## "auto_accept on, business"
        alice ##> "/_set domain 1 biz.zero"
        alice <## "new contact address set"
        bob ##> "/_connect plan 1 biz.zero"
        bob <## "business address: ok to connect"
        contactSLinkData <- getTermLine bob
        bob <## "You can also join channel #biz"
        bob ##> ("/_prepare contact 1 " <> fullLink <> " " <> contactLink <> " domain=biz.zero " <> contactSLinkData)
        bob <## "#alice: group is prepared"
        alice ##> "/p alice Alice Biz"
        alice <## "user bio changed to Alice Biz (your 0 contacts are notified)"
        bob ##> "/_connect plan 1 @biz.zero resolve=never"
        bob <## "business address: known prepared business #alice"
        bob ##> "/_connect group #1"
        bob <## "#alice: connection started"
        alice <## "#bob (Bob): accepting business address request..."
        bob <## "#alice: joining the group..."
        alice <## "#bob: bob_1 joined the group"
        bob <## "#alice: you joined the group"
        bob ##> "/_connect plan 1 @biz.zero resolve=never"
        bob <## "business address: known business #alice"
        bob <## "use #alice <message> to send messages"
        bob ##> "/i #alice"
        bob <## "group ID: 1"
        bob <## "current members: 2"
        bob <## "Zero name: @biz.zero (verified)"
  where
    bizName = ZeroNameInfo NTContact (ZeroDomain TLDZero "biz" [])
