package app.zero.chat

import app.zero.core.common.views.helpers.FileTooLargeException
import app.zero.core.common.views.helpers.copyInputStreamToFile
import java.io.ByteArrayInputStream
import java.io.InputStream
import kotlin.io.path.createTempFile
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class UtilsFileCopyTest {
  @Test
  fun testCopyInputStreamAllowsLimitBoundary() {
    val dest = createTempFile().toFile()
    val data = ByteArray(4) { it.toByte() }

    copyInputStreamToFile(ByteArrayInputStream(data), dest, maxBytes = 4)

    assertTrue(dest.exists())
    assertContentEquals(data, dest.readBytes())
    dest.delete()
  }

  @Test
  fun testCopyInputStreamRejectsAndDeletesOversizedOutput() {
    val dest = createTempFile().toFile()
    val data = ByteArray(5) { it.toByte() }

    assertFailsWith<FileTooLargeException> {
      copyInputStreamToFile(ByteArrayInputStream(data), dest, maxBytes = 4)
    }

    assertFalse(dest.exists())
  }

  @Test
  fun testCopyInputStreamCopiesAcrossMultipleReads() {
    val dest = createTempFile().toFile()
    val data = ByteArray(20) { it.toByte() }

    copyInputStreamToFile(chunkedStream(data, 3), dest, maxBytes = 20)

    assertTrue(dest.exists())
    assertContentEquals(data, dest.readBytes())
    dest.delete()
  }

  @Test
  fun testCopyInputStreamRejectsAndDeletesWhenLimitCrossedMidStream() {
    val dest = createTempFile().toFile()
    val data = ByteArray(10) { it.toByte() }

    assertFailsWith<FileTooLargeException> {
      copyInputStreamToFile(chunkedStream(data, 3), dest, maxBytes = 7)
    }

    assertFalse(dest.exists())
  }

  private fun chunkedStream(data: ByteArray, chunkSize: Int): InputStream =
    object : ByteArrayInputStream(data) {
      override fun read(b: ByteArray, off: Int, len: Int): Int = super.read(b, off, minOf(len, chunkSize))
    }
}
