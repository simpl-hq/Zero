{-# LANGUAGE ForeignFunctionInterface #-}

module Zero.Messaging.Crypto.SNTRUP761.Bindings.FFI
  ( c_sntrup761_keypair,
    c_sntrup761_enc,
    c_sntrup761_dec,
  ) where

import Foreign
import Foreign.C
import Zero.Messaging.Crypto.SNTRUP761.Bindings.RNG (RNGContext, RNGFunc)

foreign import ccall "sntrup761_keypair"
  c_sntrup761_keypair :: Ptr Word8 -> Ptr Word8 -> Ptr RNGContext -> FunPtr RNGFunc -> IO ()

foreign import ccall "sntrup761_enc"
  c_sntrup761_enc :: Ptr Word8 -> Ptr Word8 -> Ptr Word8 -> Ptr RNGContext -> FunPtr RNGFunc -> IO ()

foreign import ccall "sntrup761_dec"
  c_sntrup761_dec :: Ptr Word8 -> Ptr Word8 -> Ptr Word8 -> IO ()
