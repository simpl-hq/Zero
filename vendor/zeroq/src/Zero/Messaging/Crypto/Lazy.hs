{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}

module Zero.Messaging.Crypto.Lazy
  ( sha256Hash,
    sha512Hash,
    pad,
    unPad,
    splitLen,
    sbEncrypt,
    sbDecrypt,
    sbEncryptTailTag,
    kcbEncryptTailTag,
    sbDecryptTailTag,
    kcbDecryptTailTag,
    sbEncryptTailTagNoPad,
    sbDecryptTailTagNoPad,
    fastReplicate,
    secretBox,
    secretBoxTailTag,
    SbState,
    cbInit,
    sbInit,
    kcbInit,
    sbEncryptChunk,
    sbDecryptChunk,
    sbEncryptChunkLazy,
    sbDecryptChunkLazy,
    sbAuth,
    LazyByteString,
  )
where

import qualified Crypto.Cipher.XSalsa as XSalsa
import qualified Crypto.Error as CE
import Crypto.Hash (Digest, hashlazy)
import Crypto.Hash.Algorithms (SHA256, SHA512)
import qualified Crypto.MAC.Poly1305 as Poly1305
import Data.Bifunctor (first)
import Data.ByteArray (ByteArrayAccess)
import qualified Data.ByteArray as BA
import Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy.Char8 as LB
import qualified Data.ByteString.Lazy.Internal as LB
import Data.Composition ((.:.))
import Data.Int (Int64)
import Data.List.NonEmpty (NonEmpty (..))
import Foreign (sizeOf)
import Zero.Messaging.Crypto (CbNonce, CryptoError (..), DhSecret (..), DhSecretX25519, SbKey, SbKeyNonce, pattern CbNonce, pattern SbKey)
import Zero.Messaging.Crypto.SNTRUP761 (KEMHybridSecret (..))
import Zero.Messaging.Encoding

type LazyByteString = LB.ByteString

sha256Hash :: LazyByteString -> ByteString
sha256Hash = BA.convert . (hashlazy :: LazyByteString -> Digest SHA256)

sha512Hash :: LazyByteString -> ByteString
sha512Hash = BA.convert . (hashlazy :: LazyByteString -> Digest SHA512)

pad :: LazyByteString -> Int64 -> Int64 -> Either CryptoError LazyByteString
pad msg len paddedLen
  | padLen >= 0 = Right $ LB.fromStrict encodedLen <> LB.take len msg <> fastReplicate padLen '#'
  | otherwise = Left CryptoLargeMsgError
  where
    encodedLen = smpEncode len
    padLen = paddedLen - len - 8

fastReplicate :: Int64 -> Char -> LazyByteString
fastReplicate n c
  | n <= 0 = LB.empty
  | n < chSize' = LB.fromStrict $ B.replicate (fromIntegral n) c
  | otherwise = LB.fromChunks $ B.replicate (fromIntegral r) c : replicate (fromIntegral q) chPad
  where
    chSize = 65536 - 2 * sizeOf (undefined :: Int)
    chPad = B.replicate chSize c
    chSize' = fromIntegral chSize
    (q, r) = quotRem n chSize'

unPad :: LazyByteString -> Either CryptoError LazyByteString
unPad = fmap snd . splitLen

splitLen :: LazyByteString -> Either CryptoError (Int64, LazyByteString)
splitLen padded
  | LB.length lenStr == 8 = case smpDecode $ LB.toStrict lenStr of
      Right len
        | len < 0 -> Left CryptoInvalidMsgError
        | otherwise -> Right (len, LB.take len rest)
      Left _ -> Left CryptoInvalidMsgError
  | otherwise = Left CryptoInvalidMsgError
  where
    (lenStr, rest) = LB.splitAt 8 padded

sbEncrypt :: SbKey -> CbNonce -> LazyByteString -> Int64 -> Int64 -> Either CryptoError LazyByteString
sbEncrypt (SbKey key) (CbNonce nonce) msg len paddedLen =
  prependTag <$> (secretBox sbEncryptChunk key nonce =<< pad msg len paddedLen)
  where
    prependTag (tag :| cs) = LB.Chunk tag $ LB.fromChunks cs

sbDecrypt :: SbKey -> CbNonce -> LazyByteString -> Either CryptoError LazyByteString
sbDecrypt (SbKey key) (CbNonce nonce) packet
  | LB.length tag' < 16 = Left CBDecryptError
  | otherwise = case secretBox sbDecryptChunk key nonce c of
      Right (tag :| cs)
        | BA.constEq (LB.toStrict tag') tag -> unPad $ LB.fromChunks cs
        | otherwise -> Left CBDecryptError
      Left e -> Left e
  where
    (tag', c) = LB.splitAt 16 packet

secretBox :: ByteArrayAccess key => (SbState -> ByteString -> (ByteString, SbState)) -> key -> ByteString -> LazyByteString -> Either CryptoError (NonEmpty ByteString)
secretBox sbProcess secret nonce msg = run <$> sbInit_ secret nonce
  where
    run state =
      let (!cs, !state') = secretBoxLazy_ sbProcess state msg
       in BA.convert (sbAuth state') :| reverse cs

sbEncryptTailTag :: SbKey -> CbNonce -> LazyByteString -> Int64 -> Int64 -> Either CryptoError LazyByteString
sbEncryptTailTag (SbKey key) = sbEncryptTailTag_ key
{-# INLINE sbEncryptTailTag #-}

kcbEncryptTailTag :: KEMHybridSecret -> CbNonce -> LazyByteString -> Int64 -> Int64 -> Either CryptoError LazyByteString
kcbEncryptTailTag (KEMHybridSecret key) = sbEncryptTailTag_ key
{-# INLINE kcbEncryptTailTag #-}

sbEncryptTailTag_ :: ByteArrayAccess key => key -> CbNonce -> LazyByteString -> Int64 -> Int64 -> Either CryptoError LazyByteString
sbEncryptTailTag_ key (CbNonce nonce) msg len paddedLen =
  LB.fromChunks <$> (secretBoxTailTag sbEncryptChunk key nonce =<< pad msg len paddedLen)

sbEncryptTailTagNoPad :: SbKeyNonce -> LazyByteString -> Either CryptoError LazyByteString
sbEncryptTailTagNoPad (SbKey key, CbNonce nonce) msg =
  LB.fromChunks <$> secretBoxTailTag sbEncryptChunk key nonce msg

sbDecryptTailTag :: SbKey -> CbNonce -> Int64 -> LazyByteString -> Either CryptoError (Bool, LazyByteString)
sbDecryptTailTag (SbKey key) = sbDecryptTailTag_ key
{-# INLINE sbDecryptTailTag #-}

kcbDecryptTailTag :: KEMHybridSecret -> CbNonce -> Int64 -> LazyByteString -> Either CryptoError (Bool, LazyByteString)
kcbDecryptTailTag (KEMHybridSecret key) = sbDecryptTailTag_ key
{-# INLINE kcbDecryptTailTag #-}

sbDecryptTailTag_ :: ByteArrayAccess key => key -> CbNonce -> Int64 -> LazyByteString -> Either CryptoError (Bool, LazyByteString)
sbDecryptTailTag_ key (CbNonce nonce) paddedLen packet =
  case secretBox sbDecryptChunk key nonce c of
    Right (tag :| cs) ->
      let valid = LB.length tag' == 16 && BA.constEq (LB.toStrict tag') tag
       in (valid,) <$> unPad (LB.fromChunks cs)
    Left e -> Left e
  where
    (c, tag') = LB.splitAt paddedLen packet

sbDecryptTailTagNoPad :: SbKeyNonce -> Int64 -> LazyByteString -> Either CryptoError (Bool, LazyByteString)
sbDecryptTailTagNoPad (SbKey key, CbNonce nonce) paddedLen packet =
  result <$> secretBox sbDecryptChunk key nonce c
  where
    result (tag :| cs) =
      let valid = LB.length tag' == 16 && BA.constEq (LB.toStrict tag') tag
       in (valid, LB.fromChunks cs)
    (c, tag') = LB.splitAt paddedLen packet

secretBoxTailTag :: ByteArrayAccess key => (SbState -> ByteString -> (ByteString, SbState)) -> key -> ByteString -> LazyByteString -> Either CryptoError [ByteString]
secretBoxTailTag sbProcess secret nonce msg = run <$> sbInit_ secret nonce
  where
    run state =
      let (cs, state') = secretBoxLazy_ sbProcess state msg
       in reverse $ BA.convert (sbAuth state') : cs

secretBoxLazy_ :: (SbState -> ByteString -> (ByteString, SbState)) -> SbState -> LazyByteString -> ([ByteString], SbState)
secretBoxLazy_ sbProcess state = LB.foldlChunks update ([], state)
  where
    update (cs, st) chunk = let (!c, !st') = sbProcess st chunk in (c : cs, st')

type SbState = (XSalsa.State, Poly1305.State)

cbInit :: DhSecretX25519 -> CbNonce -> Either CryptoError SbState
cbInit (DhSecretX25519 secret) (CbNonce nonce) = sbInit_ secret nonce
{-# INLINE cbInit #-}

sbInit :: SbKey -> CbNonce -> Either CryptoError SbState
sbInit (SbKey secret) (CbNonce nonce) = sbInit_ secret nonce
{-# INLINE sbInit #-}

kcbInit :: KEMHybridSecret -> CbNonce -> Either CryptoError SbState
kcbInit (KEMHybridSecret k) (CbNonce nonce) = sbInit_ k nonce
{-# INLINE kcbInit #-}

sbInit_ :: ByteArrayAccess key => key -> ByteString -> Either CryptoError SbState
sbInit_ secret nonce = (state2,) <$> cryptoPassed (Poly1305.initialize rs)
  where
    zero = B.replicate 16 $ toEnum 0
    (iv0, iv1) = B.splitAt 8 nonce
    state0 = XSalsa.initialize 20 secret (zero `B.append` iv0)
    state1 = XSalsa.derive state0 iv1
    (rs :: ByteString, state2) = XSalsa.generate state1 32

sbEncryptChunkLazy :: SbState -> LazyByteString -> (LazyByteString, SbState)
sbEncryptChunkLazy = sbProcessChunkLazy_ sbEncryptChunk

sbDecryptChunkLazy :: SbState -> LazyByteString -> (LazyByteString, SbState)
sbDecryptChunkLazy = sbProcessChunkLazy_ sbDecryptChunk

sbProcessChunkLazy_ :: (SbState -> ByteString -> (ByteString, SbState)) -> SbState -> LazyByteString -> (LazyByteString, SbState)
sbProcessChunkLazy_ = first (LB.fromChunks . reverse) .:. secretBoxLazy_
{-# INLINE sbProcessChunkLazy_ #-}

sbEncryptChunk :: SbState -> ByteString -> (ByteString, SbState)
sbEncryptChunk (st, authSt) chunk =
  let (!c, !st') = XSalsa.combine st chunk
      !authSt' = Poly1305.update authSt c
   in (c, (st', authSt'))

sbDecryptChunk :: SbState -> ByteString -> (ByteString, SbState)
sbDecryptChunk (st, authSt) chunk =
  let (!s, !st') = XSalsa.combine st chunk
      !authSt' = Poly1305.update authSt chunk
   in (s, (st', authSt'))

sbAuth :: SbState -> Poly1305.Auth
sbAuth = Poly1305.finalize . snd

cryptoPassed :: CE.CryptoFailable b -> Either CryptoError b
cryptoPassed = \case
  CE.CryptoPassed a -> Right a
  CE.CryptoFailed e -> Left $ CryptoPoly1305Error e
