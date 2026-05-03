{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}

module Zero.Messaging.Crypto.SNTRUP761
  ( KEMHybridSecret (..),
    kcbDecrypt,
    kcbEncrypt,
    kemHybridSecret,
  ) where

import Crypto.Hash (Digest, SHA3_256, hash)
import Data.ByteArray (ScrubbedBytes)
import qualified Data.ByteArray as BA
import Data.ByteString (ByteString)
import Zero.Messaging.Crypto
import qualified Zero.Messaging.Crypto as C
import Zero.Messaging.Crypto.SNTRUP761.Bindings

newtype KEMHybridSecret = KEMHybridSecret ScrubbedBytes

kcbDecrypt :: KEMHybridSecret -> CbNonce -> ByteString -> Either CryptoError ByteString
kcbDecrypt (KEMHybridSecret k) = sbDecrypt_ k

kcbEncrypt :: KEMHybridSecret -> CbNonce -> ByteString -> Int -> Either CryptoError ByteString
kcbEncrypt (KEMHybridSecret k) = sbEncrypt_ k

kemHybridSecret :: PublicKeyX25519 -> PrivateKeyX25519 -> KEMSharedKey -> KEMHybridSecret
kemHybridSecret k pk (KEMSharedKey kem) =
  let DhSecretX25519 dh = C.dh' k pk
   in KEMHybridSecret $ BA.convert (hash $ BA.convert dh <> kem :: Digest SHA3_256)
