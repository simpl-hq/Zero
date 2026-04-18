package app.zero.core.common.views.chat.item

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.graphics.painter.Painter
import app.zero.core.common.model.CIFile
import app.zero.core.common.platform.*
import app.zero.core.common.views.helpers.ModalManager

@Composable
actual fun SimpleAndAnimatedImageView(
  data: ByteArray,
  imageBitmap: ImageBitmap,
  file: CIFile?,
  imageProvider: () -> ImageGalleryProvider,
  smallView: Boolean,
  ImageView: @Composable (painter: Painter, onClick: () -> Unit) -> Unit
) {
  ImageView(BitmapPainter(imageBitmap)) {
    if (getLoadedFilePath(file) != null) {
      ModalManager.fullscreen.showCustomModal(animated = false) { close ->
        ImageFullScreenView(imageProvider, close)
      }
    }
  }
}
