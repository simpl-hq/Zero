package app.zero.core.common.platform

import androidx.compose.foundation.combinedClickable
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import app.zero.core.common.model.ChatController.appPrefs
import app.zero.core.common.views.helpers.KeyChangeEffect
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.filter
import java.io.File
import kotlin.math.roundToInt

@Composable
expect fun Modifier.desktopOnExternalDrag(
  enabled: Boolean = true,
  onFiles: (List<File>) -> Unit = {},
  onImage: (File) -> Unit = {},
  onText: (String) -> Unit = {}
): Modifier

expect fun Modifier.onRightClick(action: () -> Unit): Modifier

expect fun Modifier.desktopPointerHoverIconHand(): Modifier

expect fun Modifier.desktopOnHovered(action: (Boolean) -> Unit): Modifier

@Composable
fun Modifier.desktopModifyBlurredState(blurred: MutableState<Boolean>, showMenu: State<Boolean>,): Modifier {
  val blurRadius = remember { appPrefs.privacyMediaBlurRadius.state }
  if (appPlatform.isDesktop) {
    KeyChangeEffect(blurRadius.value) {
      blurred.value = blurRadius.value > 0
    }
  }
  return if (appPlatform.isDesktop && blurRadius.value > 0 && !showMenu.value) {
    var job: Job = remember { Job() }
    LaunchedEffect(Unit) {
      job = launch {
        delay(100)
        blurred.value = true
      }
    }
    this then Modifier.desktopOnHovered { hovered ->
      job.cancel()
      blurred.value = !hovered && !showMenu.value
    }
  } else {
    this
  }
}

@Composable
fun blurHidesMedia(enabled: Boolean, blurred: State<Boolean>): Boolean =
  enabled && blurred.value && remember { appPrefs.privacyMediaBlurRadius.state }.value > 0

@Composable
fun Modifier.privacyBlur(
  fullSize: Boolean,
  preview: ImageBitmap,
  blurred: MutableState<Boolean> = remember { mutableStateOf(appPrefs.privacyMediaBlurRadius.get() > 0) },
  scrollState: State<Boolean>,
  onLongClick: () -> Unit = {}
): Modifier {
  val blurRadius = remember { appPrefs.privacyMediaBlurRadius.state }
  return if (blurHidesMedia(true, blurred)) {
    this then (if (fullSize) {
      val blurredPreview = remember(preview, blurRadius.value) { preview.blurredBy(blurRadius.value) }
      Modifier.drawWithContent { drawImage(blurredPreview, dstSize = IntSize(size.width.roundToInt(), size.height.roundToInt())) }
    } else Modifier.drawWithCache {
      val cropScale = maxOf(size.width / preview.width, size.height / preview.height)
      val croppedSize = IntSize((preview.width * cropScale).roundToInt(), (preview.height * cropScale).roundToInt())
      val blurredCropped = preview.blurredBy(blurRadius.value, croppedSize.width.toDp().value)
      val offset = IntOffset(((size.width - croppedSize.width) / 2).roundToInt(), ((size.height - croppedSize.height) / 2).roundToInt())
      onDrawWithContent { clipRect { drawImage(blurredCropped, dstOffset = offset, dstSize = croppedSize) } }
    })
      .combinedClickable(
        onLongClick = onLongClick,
        onClick = {
          blurred.value = false
        }
      )
  } else if (blurRadius.value > 0 && appPlatform.isAndroid) {
      LaunchedEffect(Unit) {
        snapshotFlow { scrollState.value }
          .filter { it }
          .filter { !blurred.value }
          .collect { blurred.value = true }
      }
      this
    } else {
      this
    }
}

private const val BLURRED_MEDIA_WIDTH_DP = 400
private const val CHAT_MEDIA_WIDTH_DP = 360
private const val RESAMPLE_MEDIA_FROM_SIDE = 512

private fun ImageBitmap.blurredBy(radius: Int, drawnWidthDp: Float = CHAT_MEDIA_WIDTH_DP.toFloat()): ImageBitmap {
  if (width <= 0 || height <= 0) return this
  val w = (BLURRED_MEDIA_WIDTH_DP * drawnWidthDp / CHAT_MEDIA_WIDTH_DP / radius).toInt().coerceIn(1, width)
  val h = (w * height / width).coerceIn(1, BLURRED_MEDIA_WIDTH_DP)
  val longest = maxOf(width, height)
  var image = if (longest > RESAMPLE_MEDIA_FROM_SIDE) {
    val step = RESAMPLE_MEDIA_FROM_SIDE.toFloat() / longest
    scale((width * step).roundToInt().coerceAtLeast(1), (height * step).roundToInt().coerceAtLeast(1))
  } else this
  while (image.width / 2 > w) image = image.scale(image.width / 2, (image.height / 2).coerceAtLeast(1))
  image = image.scale(w, h)
  while (maxOf(image.width, image.height) < BLURRED_MEDIA_WIDTH_DP / 2) image = image.scale(image.width * 2, image.height * 2)
  return image
}
