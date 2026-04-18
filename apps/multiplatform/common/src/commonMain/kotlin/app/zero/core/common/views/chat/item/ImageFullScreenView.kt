package app.zero.core.common.views.chat.item

import androidx.compose.foundation.*
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.*
import androidx.compose.ui.input.pointer.*
import androidx.compose.ui.layout.onGloballyPositioned
import app.zero.core.common.model.CryptoFile
import app.zero.core.common.platform.*
import app.zero.core.common.ui.theme.CurrentColors
import app.zero.core.common.views.chat.ProviderMedia
import app.zero.core.common.views.helpers.*
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import java.net.URI
import kotlin.math.absoluteValue

interface ImageGalleryProvider {
  val initialIndex: Int
  val totalMediaSize: MutableState<Int>
  fun getMedia(index: Int): ProviderMedia?
  fun currentPageChanged(index: Int)
  fun scrollToStart()
  fun onDismiss(index: Int)
}

@Composable
fun ImageFullScreenView(imageProvider: () -> ImageGalleryProvider, close: () -> Unit) {
  val provider = remember { imageProvider() }
  val pagerState = rememberPagerState(
    initialPage = provider.initialIndex,
    initialPageOffsetFraction = 0f
  ) {
    provider.totalMediaSize.value
  }
  val firstValidPageBeforeScrollingToStart = remember { mutableStateOf(0) }
  val goBack = { provider.onDismiss(pagerState.currentPage); close() }
  BackHandler(onBack = goBack)
  LaunchedEffect(Unit) {
    if (provider.getMedia(provider.initialIndex - 1) == null) {
      firstValidPageBeforeScrollingToStart.value = provider.initialIndex
      provider.scrollToStart()
      pagerState.scrollToPage(0)
      firstValidPageBeforeScrollingToStart.value = 0
    }
  }
  val scope = rememberCoroutineScope()
  val playersToRelease = rememberSaveable { mutableSetOf<URI>() }
  DisposableEffectOnGone(
    always = {
      platform.androidSetStatusAndNavigationBarAppearance(false, false, blackNavBar = true)
      chatModel.fullscreenGalleryVisible.value = true
    },
    whenDispose = {
      val c = CurrentColors.value.colors
      platform.androidSetStatusAndNavigationBarAppearance(c.isLight, c.isLight)
      chatModel.fullscreenGalleryVisible.value = false
    },
    whenGone = {
      playersToRelease.forEach { VideoPlayerHolder.release(it, true, true) }
    }
  )

  @Composable
  fun Content(index: Int) {
    val index = index - firstValidPageBeforeScrollingToStart.value
    Column(
      Modifier
        .fillMaxSize()
        .background(Color.Black)
        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = goBack)
    ) {
      var settledCurrentPage by remember { mutableStateOf(pagerState.currentPage) }
      LaunchedEffect(pagerState) {
        snapshotFlow {
          if (!pagerState.isScrollInProgress) pagerState.currentPage else settledCurrentPage
        }.collect {
          settledCurrentPage = it
        }
      }
      LaunchedEffect(settledCurrentPage) {
        if (settledCurrentPage != provider.initialIndex)
          provider.currentPageChanged(index)
      }
      val media = provider.getMedia(index)
      if (media == null) {
        SideEffect {
          scope.launch {
            when (settledCurrentPage) {
              index - 1 -> provider.totalMediaSize.value = settledCurrentPage + 1
              index + 1 -> {
                provider.scrollToStart()
                pagerState.scrollToPage(0)
              }
              index -> close()
            }
          }
        }
      } else {
        var scale by remember { mutableStateOf(1f) }
        var translationX by remember { mutableStateOf(0f) }
        var translationY by remember { mutableStateOf(0f) }
        var viewWidth by remember { mutableStateOf(0) }
        var allowTranslate by remember { mutableStateOf(true) }
        LaunchedEffect(settledCurrentPage) {
          scale = 1f
          translationX = 0f
          translationY = 0f
        }
        val modifier = Modifier
          .onGloballyPositioned {
            viewWidth = it.size.width
          }
          .graphicsLayer(
            scaleX = scale,
            scaleY = scale,
            translationX = translationX,
            translationY = translationY,
          )
          .pointerInput(Unit) {
            detectTransformGestures(
              { allowTranslate },
              onGesture = { _, pan, gestureZoom, _ ->
                scale = (scale * gestureZoom).coerceIn(1f, 20f)
                allowTranslate = viewWidth * (scale - 1f) - ((translationX + pan.x * scale).absoluteValue * 2) > 0
                if (scale > 1 && allowTranslate) {
                  translationX += pan.x * scale
                  translationY += pan.y * scale
                } else if (allowTranslate) {
                  translationX = 0f
                  translationY = 0f
                }
              }
            )
          }
          .fillMaxSize()
        if (media is ProviderMedia.Image) {
          val (data: ByteArray, imageBitmap: ImageBitmap) = media
          FullScreenImageView(modifier, data, imageBitmap)
        } else if (media is ProviderMedia.Video) {
          val preview = remember(media.uri.path) { base64ToBitmap(media.preview) }
          val uriDecrypted = remember(media.uri.path) { mutableStateOf(if (media.fileSource?.cryptoArgs == null) media.uri else media.fileSource.decryptedGet()) }
          val decrypted = uriDecrypted.value
          if (decrypted != null) {
            val isCurrentPage = index == pagerState.currentPage && kotlin.math.abs(pagerState.currentPageOffsetFraction) < 0.3f
            VideoView(modifier, decrypted, preview, isCurrentPage, close)
            DisposableEffect(Unit) {
              onDispose { playersToRelease.add(decrypted) }
            }
          } else if (media.fileSource != null) {
            VideoViewEncrypted(uriDecrypted, media.fileSource, preview, close)
          }
        }
      }
    }
  }
  if (appPlatform.isAndroid) {
    HorizontalPager(state = pagerState) { index -> Content(index) }
  } else {
    Content(pagerState.currentPage)
  }
}

@Composable
expect fun FullScreenImageView(modifier: Modifier, data: ByteArray, imageBitmap: ImageBitmap)

@Composable
private fun VideoViewEncrypted(uriUnencrypted: MutableState<URI?>, fileSource: CryptoFile, defaultPreview: ImageBitmap, close: () -> Unit) {
  LaunchedEffect(Unit) {
    withBGApi {
      uriUnencrypted.value = fileSource.decryptedGetOrCreate()
      if (uriUnencrypted.value == null) {
        close()
      }
    }
  }
  Box(contentAlignment = Alignment.Center) {
    VideoPreviewImageViewFullScreen(defaultPreview, {}, {})
    VideoDecryptionProgress() {}
  }
}

@Composable
private fun VideoView(modifier: Modifier, uri: URI, defaultPreview: ImageBitmap, currentPage: Boolean, close: () -> Unit) {
  val player = remember(uri) { VideoPlayerHolder.getOrCreate(uri, true, defaultPreview, 0L, true) }
  val isCurrentPage = rememberUpdatedState(currentPage)
  val play = {
    player.play(true)
  }
  val stop = {
    player.stop()
  }
  LaunchedEffect(Unit) {
    snapshotFlow { isCurrentPage.value }
      .distinctUntilChanged()
      .collect {
        if (it) play() else stop()
        player.enableSound(true)
      }
  }

  Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
    FullScreenVideoView(player, modifier, close)
  }
}

@Composable
expect fun FullScreenVideoView(player: VideoPlayer, modifier: Modifier, close: () -> Unit)
