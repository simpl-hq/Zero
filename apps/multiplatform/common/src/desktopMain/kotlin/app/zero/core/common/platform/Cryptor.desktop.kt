package app.zero.core.common.platform

actual val cryptor: CryptorInterface = object : CryptorInterface {
  override fun decryptData(data: ByteArray, iv: ByteArray, alias: String): String? {
    return String(data)
  }

  override fun encryptText(text: String, alias: String): Pair<ByteArray, ByteArray> {
    return text.toByteArray() to text.toByteArray()
  }

  override fun deleteKey(alias: String) {
  }
}
