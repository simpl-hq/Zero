{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Zero.RemoteControl.Types
  ( RCErrorType (..),
    RCPVersion,
    VersionRCP,
    VersionRangeRCP,
    RCHostHello (..),
    RCCtrlHello (..),
    RCHostPairing (..),
    KnownHostPairing (..),
    RCCtrlAddress (..),
    RCCtrlPairing (..),
    RCHostKeys (..),
    RCHostSession (..),
    HostSessKeys (..),
    RCCtrlSession (..),
    CtrlSessKeys (..),
    RCHostEncHello (..),
    RCCtrlEncHello (..),
    SessionCode,
    RCStepTMVar,
    currentRCPVersion,
    supportedRCPVRange,
  ) where

import qualified Data.Aeson as J
import qualified Data.Aeson.TH as JQ
import qualified Data.Attoparsec.ByteString.Char8 as A
import Data.ByteString (ByteString)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import Data.Word (Word16)
import qualified Data.X509 as X
import qualified Network.TLS as TLS
import qualified Zero.Messaging.Crypto as C
import Zero.Messaging.Crypto.SNTRUP761.Bindings
import Zero.Messaging.Encoding
import Zero.Messaging.Encoding.String
import Zero.Messaging.Parsers (defaultJSON, dropPrefix, sumTypeJSON)
import Zero.Messaging.Transport (TLS, TSbChainKeys, TransportPeer (..))
import Zero.Messaging.Transport.Client (TransportHost)
import Zero.Messaging.Util (AnyError (..), safeDecodeUtf8)
import Zero.Messaging.Version (VersionRange, VersionScope, mkVersionRange)
import Zero.Messaging.Version.Internal
import UnliftIO

data RCErrorType
  = RCEInternal {internalErr :: String}
  | RCEIdentity
  | RCENoLocalAddress
  | RCENewController
  | RCENotDiscovered
  | RCETLSStartFailed
  | RCEException {exception :: String}
  | RCECtrlAuth
  | RCECtrlNotFound
  | RCECtrlError {ctrlErr :: String}
  | RCEInvitation
  | RCEVersion
  | RCEEncrypt
  | RCEDecrypt
  | RCEBlockSize
  | RCESyntax {syntaxErr :: String}
  deriving (Eq, Show, Exception)

instance AnyError RCErrorType where
  fromSomeException e = case fromException e of
    Just (TLS.Terminated _ _ (TLS.Error_Protocol _ TLS.UnknownCa)) -> RCEIdentity
    _ -> RCEException $ show e
  {-# INLINE fromSomeException #-}

instance StrEncoding RCErrorType where
  strEncode = \case
    RCEInternal err -> "INTERNAL" <> text err
    RCEIdentity -> "IDENTITY"
    RCENoLocalAddress -> "NO_LOCAL_ADDR"
    RCENewController -> "NEW_CONTROLLER"
    RCENotDiscovered -> "NOT_DISCOVERED"
    RCETLSStartFailed -> "CTRL_TLS_START"
    RCEException err -> "EXCEPTION" <> text err
    RCECtrlAuth -> "CTRL_AUTH"
    RCECtrlNotFound -> "CTRL_NOT_FOUND"
    RCECtrlError err -> "CTRL_ERROR" <> text err
    RCEInvitation -> "INVITATION"
    RCEVersion -> "VERSION"
    RCEEncrypt -> "ENCRYPT"
    RCEDecrypt -> "DECRYPT"
    RCEBlockSize -> "BLOCK_SIZE"
    RCESyntax err -> "SYNTAX" <> text err
    where
      text = (" " <>) . encodeUtf8 . T.pack
  strP =
    A.takeTill (== ' ') >>= \case
      "INTERNAL" -> RCEInternal <$> textP
      "IDENTITY" -> pure RCEIdentity
      "NO_LOCAL_ADDR" -> pure RCENoLocalAddress
      "NEW_CONTROLLER" -> pure RCENewController
      "NOT_DISCOVERED" -> pure RCENotDiscovered
      "CTRL_TLS_START" -> pure RCETLSStartFailed
      "EXCEPTION" -> RCEException <$> textP
      "CTRL_AUTH" -> pure RCECtrlAuth
      "CTRL_NOT_FOUND" -> pure RCECtrlNotFound
      "CTRL_ERROR" -> RCECtrlError <$> textP
      "INVITATION" -> pure RCEInvitation
      "VERSION" -> pure RCEVersion
      "ENCRYPT" -> pure RCEEncrypt
      "DECRYPT" -> pure RCEDecrypt
      "BLOCK_SIZE" -> pure RCEBlockSize
      "SYNTAX" -> RCESyntax <$> textP
      _ -> fail "bad RCErrorType"
    where
      textP = T.unpack . safeDecodeUtf8 <$> (A.space *> A.takeByteString)

data RCPVersion

instance VersionScope RCPVersion

type VersionRCP = Version RCPVersion

type VersionRangeRCP = VersionRange RCPVersion

pattern VersionRCP :: Word16 -> VersionRCP
pattern VersionRCP v = Version v

currentRCPVersion :: VersionRCP
currentRCPVersion = VersionRCP 1

supportedRCPVRange :: VersionRangeRCP
supportedRCPVRange = mkVersionRange (VersionRCP 1) currentRCPVersion

data RCHostHello = RCHostHello
  { v :: VersionRCP,
    ca :: C.KeyHash,
    app :: J.Value,
    kem :: KEMPublicKey
  }
  deriving (Show)

$(JQ.deriveJSON defaultJSON ''RCHostHello)

data RCCtrlHello = RCCtrlHello {}
  deriving (Show)

$(JQ.deriveJSON defaultJSON {J.nullaryToObject = True} ''RCCtrlHello)

data RCHostPairing = RCHostPairing
  { caKey :: C.APrivateSignKey,
    caCert :: X.SignedCertificate,
    idPrivKey :: C.PrivateKeyEd25519,
    knownHost :: Maybe KnownHostPairing
  }

data KnownHostPairing = KnownHostPairing
  { hostFingerprint :: C.KeyHash,
    hostDhPubKey :: C.PublicKeyX25519
  }

data RCCtrlAddress = RCCtrlAddress
  { address :: TransportHost,
    interface :: Text
  }
  deriving (Show, Eq)

data RCCtrlPairing = RCCtrlPairing
  { caKey :: C.APrivateSignKey,
    caCert :: X.SignedCertificate,
    ctrlFingerprint :: C.KeyHash,
    idPubKey :: C.PublicKeyEd25519,
    dhPrivKey :: C.PrivateKeyX25519,
    prevDhPrivKey :: Maybe C.PrivateKeyX25519
  }

data RCHostKeys = RCHostKeys
  { sessKeys :: C.KeyPairEd25519,
    dhKeys :: C.KeyPairX25519
  }

data RCHostSession = RCHostSession
  { tls :: TLS 'TServer,
    sessionKeys :: HostSessKeys
  }

data HostSessKeys = HostSessKeys
  { chainKeys :: TSbChainKeys,
    idPrivKey :: C.PrivateKeyEd25519,
    sessPrivKey :: C.PrivateKeyEd25519
  }

data RCCtrlSession = RCCtrlSession
  { tls :: TLS 'TClient,
    sessionKeys :: CtrlSessKeys
  }

data CtrlSessKeys = CtrlSessKeys
  { chainKeys :: TSbChainKeys,
    idPubKey :: C.PublicKeyEd25519,
    sessPubKey :: C.PublicKeyEd25519
  }

data RCHostEncHello = RCHostEncHello
  { dhPubKey :: C.PublicKeyX25519,
    nonce :: C.CbNonce,
    encBody :: ByteString
  }
  deriving (Show)

instance Encoding RCHostEncHello where
  smpEncode RCHostEncHello {dhPubKey, nonce, encBody} =
    "HELLO " <> smpEncode (dhPubKey, nonce, Tail encBody)
  smpP = do
    (dhPubKey, nonce, Tail encBody) <- "HELLO " *> smpP
    pure RCHostEncHello {dhPubKey, nonce, encBody}

data RCCtrlEncHello
  = RCCtrlEncHello {kem :: KEMCiphertext, encBody :: ByteString}
  | RCCtrlEncError {nonce :: C.CbNonce, encMessage :: ByteString}
  deriving (Show)

instance Encoding RCCtrlEncHello where
  smpEncode = \case
    RCCtrlEncHello {kem, encBody} -> "HELLO " <> smpEncode (kem, Tail encBody)
    RCCtrlEncError {nonce, encMessage} -> "ERROR " <> smpEncode (nonce, Tail encMessage)
  smpP =
    A.takeTill (== ' ') >>= \case
      "HELLO" -> do
        (kem, Tail encBody) <- _smpP
        pure RCCtrlEncHello {kem, encBody}
      "ERROR" -> do
        (nonce, Tail encMessage) <- _smpP
        pure RCCtrlEncError {nonce, encMessage}
      _ -> fail "bad RCCtrlEncHello"

type SessionCode = ByteString

type RCStepTMVar a = TMVar (Either RCErrorType a)

$(JQ.deriveJSON (sumTypeJSON $ dropPrefix "RCE") ''RCErrorType)

$(JQ.deriveJSON defaultJSON ''RCCtrlAddress)
