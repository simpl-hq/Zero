package app.zero.chat

import app.zero.core.common.views.helpers.decodeBoundedBufferedImage
import app.zero.core.common.views.helpers.imageSampleSize
import app.zero.core.common.views.helpers.sourceDimensionsWithinLimits
import java.awt.image.BufferedImage
import java.io.ByteArrayOutputStream
import java.io.IOException
import javax.imageio.ImageIO
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ImageDecodeBoundsTest {
  @Test
  fun testSampleSizeKeepsSmallerSideAtTarget() {
    assertEquals(1, imageSampleSize(4320, 4320, 4320))
    assertEquals(1, imageSampleSize(1179, 2556, 1000))
    assertEquals(1, imageSampleSize(4321, 100, 4320))
    assertEquals(2, imageSampleSize(8640, 8640, 4320))
    assertEquals(4, imageSampleSize(4000, 4000, 1000))
  }

  @Test
  fun testSampleSizeCapsDecodedPixelsForExtremeAspectRatios() {
    assertEquals(2, imageSampleSize(16384, 1999, 1000))
    assertEquals(4, imageSampleSize(16384, 8639, 4320))
    assertEquals(4, imageSampleSize(16384, 16384, 4320))
  }

  @Test
  fun testSourceDimensionsRejectAbsurdSizes() {
    assertTrue(sourceDimensionsWithinLimits(16384, 16384))
    assertFalse(sourceDimensionsWithinLimits(16385, 1))
    assertFalse(sourceDimensionsWithinLimits(0, 1))
  }

  @Test
  fun testDecodeRejectsImageExceedingSourceLimit() {
    assertFailsWith<IOException> { decodeBoundedBufferedImage(encodePng(16385, 1), 4320) }
  }

  @Test
  fun testDecodeAcceptsElongatedImageWithinSourceLimit() {
    val image = decodeBoundedBufferedImage(encodePng(16384, 8), 4320)
    assertEquals(16384, image.width)
  }

  @Test
  fun testDecodeDownsamplesLargeImageInsteadOfRejecting() {
    val image = decodeBoundedBufferedImage(encodePng(2400, 2400), 1000)
    assertTrue(image.width < 2400, "expected downsampled width, got ${image.width}")
    assertTrue(image.width >= 1000, "expected smaller side kept at or above target, got ${image.width}")
  }

  private fun encodePng(width: Int, height: Int): ByteArray {
    val image = BufferedImage(width, height, BufferedImage.TYPE_INT_RGB)
    return ByteArrayOutputStream().use { out ->
      ImageIO.write(image, "png", out)
      out.toByteArray()
    }
  }
}
