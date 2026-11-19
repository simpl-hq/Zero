package app.zero.core.common.platform

import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.*
import app.zero.core.common.views.helpers.*
import app.zero.core.res.MR
import kotlinx.coroutines.*
import org.jetbrains.compose.videoplayer.SkiaBitmapVideoSurface
import uk.co.caprica.vlcj.media.Media
import uk.co.caprica.vlcj.media.MediaEventAdapter
import uk.co.caprica.vlcj.media.MediaParsedStatus
import uk.co.caprica.vlcj.media.ParseFlag
import uk.co.caprica.vlcj.media.VideoOrientation
import uk.co.caprica.vlcj.player.base.*
import uk.co.caprica.vlcj.player.component.CallbackMediaPlayerComponent
import uk.co.caprica.vlcj.player.component.EmbeddedMediaPlayerComponent
import uk.co.caprica.vlcj.player.component.MediaPlayerSpecs
import java.awt.Component
import java.awt.image.BufferedImage
import java.io.File
import java.net.URI
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max

actual class VideoPlayer actual constructor(
  override val uri: URI,
  override val gallery: Boolean,
  private val defaultPreview: ImageBitmap,
  defaultDuration: Long,
  soundEnabled: Boolean
): VideoPlayerInterface {
  override val soundEnabled: MutableState<Boolean> = mutableStateOf(false)
  override val brokenVideo: MutableState<Boolean> = mutableStateOf(false)
  override val videoPlaying: MutableState<Boolean> = mutableStateOf(false)
  override val progress: MutableState<Long> = mutableStateOf(0L)
  override val duration: MutableState<Long> = mutableStateOf(defaultDuration)
  override val preview: MutableState<ImageBitmap> = mutableStateOf(defaultPreview)

  val mediaPlayerComponent by lazy { getOrCreatePlayer() }
  val player by lazy { mediaPlayerComponent.mediaPlayer() }

  init {
    setPreviewAndDuration()
  }

  private var isReleased: AtomicBoolean = AtomicBoolean(false)

  private val listener: MutableState<((position: Long?, state: TrackState) -> Unit)?> = mutableStateOf(null)
  private var progressJob: Job? = null

  enum class TrackState {
    PLAYING, PAUSED, STOPPED
  }

  private fun start(seek: Long? = null, onProgressUpdate: (position: Long?, state: TrackState) -> Unit): Boolean {
    val filepath = getAppFilePath(uri)
    if (filepath == null || !File(filepath).exists()) {
      Log.e(TAG, "No such file: $filepath")
      brokenVideo.value = true
      return false
    }

    if (soundEnabled.value)  {
      RecorderInterface.stopRecording?.invoke()
    }
    AudioPlayer.stop()
    VideoPlayerHolder.stopAll()
    if (listener.value == null) {
      runCatching {
        player.media().prepare(uri.toFile().absolutePath)
        if (seek != null) {
          player.seekTo(seek.toInt())
        }
      }.onFailure {
        Log.e(TAG, it.stackTraceToString())
        AlertManager.shared.showAlertMsg(generalGetString(MR.strings.unknown_error), it.stackTraceToString())
        brokenVideo.value = true
        return false
      }
    }
    player.start()
    if (seek != null) player.seekTo(seek.toInt())
    if (!player.isPlaying) {
      AlertManager.shared.showAlertMsg(generalGetString(MR.strings.unknown_error))
      brokenVideo.value = true
      return false
    }
    listener.value = onProgressUpdate
    progressJob = CoroutineScope(Dispatchers.Main).launch {
      onProgressUpdate(player.currentPosition.toLong(), TrackState.PLAYING)
      while (isActive && !isReleased.get() && player.isPlaying) {
        if (player.currentPosition == player.duration) {
          onProgressUpdate(player.currentPosition.toLong(), TrackState.PLAYING)
          break
        }
        delay(50)
        onProgressUpdate(player.currentPosition.toLong(), TrackState.PLAYING)
      }
      if (isActive && !isReleased.get()) {
        onProgressUpdate(player.currentPosition.toLong(), TrackState.PAUSED)
      }
      onProgressUpdate(null, TrackState.PAUSED)
    }

    return true
  }

  override fun stop() {
    if (isReleased.get() || !videoPlaying.value) return
    playerThread.execute {
      player.stop()
      stopListener()
    }
  }

  private fun stopListener() {
    val afterCoroutineCancel: CompletionHandler = {
      listener.value?.invoke(null, TrackState.STOPPED)
    }

    if (progressJob != null) {
      progressJob?.invokeOnCompletion(afterCoroutineCancel)
    } else {
      afterCoroutineCancel(null)
    }
    progressJob?.cancel()
    progressJob = null
  }

  override fun play(resetOnEnd: Boolean) {
    if (progress.value == duration.value) {
      progress.value = 0
    }
    playerThread.execute {
      videoPlaying.value = start(progress.value) { pro, _ ->
        if (pro != null) {
          progress.value = pro
        }
        if ((pro == null || pro == duration.value) && duration.value != 0L) {
          videoPlaying.value = false
          if (pro == duration.value) {
            progress.value = if (resetOnEnd) 0 else duration.value
          }

        }
      }
    }
  }

  override fun enableSound(enable: Boolean): Boolean {
    return false

  }

  override fun release(remove: Boolean) {
    CoroutineScope(playerThread.asCoroutineDispatcher()).launch {
      if (isReleased.get()) return@launch
      isReleased.set(true)
      if (player.isPlaying) {
        player.stop()
      }
      if (usePool) {
        putPlayer(mediaPlayerComponent)
      } else {
        player.release()
      }
      if (remove) {
        VideoPlayerHolder.players.remove(uri to gallery)
      }
    }
  }

  private val MediaPlayer.currentPosition: Int
    get() = if (isReleased.get()) 0 else max(0, status().time().toInt())

  private fun setPreviewAndDuration() {
    CoroutineScope(Dispatchers.IO).launch {
      val previewAndDuration = VideoPlayerHolder.previewsAndDurations.getOrPut(uri) { getBitmapFromVideo(defaultPreview, uri, withAlertOnException = false) }
      withContext(Dispatchers.Main) {
        preview.value = previewAndDuration.preview ?: defaultPreview
        duration.value = (previewAndDuration.duration ?: 0)
      }
    }
  }

  companion object {
    private val usePool = false

    private fun Component.mediaPlayer() = when (this) {
      is CallbackMediaPlayerComponent -> mediaPlayer()
      is EmbeddedMediaPlayerComponent -> mediaPlayer()
      else -> error("mediaPlayer() can only be called on vlcj player components")
    }

    private fun initializeMediaPlayerComponent(): Component {
      return if (desktopPlatform.isMac()) {
        CallbackMediaPlayerComponent(MediaPlayerSpecs.callbackMediaPlayerSpec().apply { withFactory(vlcFactory) })
      } else {
        EmbeddedMediaPlayerComponent(MediaPlayerSpecs.embeddedMediaPlayerSpec().apply { withFactory(vlcFactory) })
      }
    }

    suspend fun getBitmapFromVideo(defaultPreview: ImageBitmap?, uri: URI?, withAlertOnException: Boolean = true): VideoPlayerInterface.PreviewAndDuration = withContext(previewThread.asCoroutineDispatcher()) {
      val mediaComponent = getOrCreateHelperPlayer()
      val player = mediaComponent.mediaPlayer()
      if (uri == null || !uri.toFile().exists()) {
        if (withAlertOnException) showVideoDecodingException()

        return@withContext VideoPlayerInterface.PreviewAndDuration(preview = defaultPreview, timestamp = 0L, duration = 0L)
      }
      val surface = SkiaBitmapVideoSurface()
      player.videoSurface().set(surface)
      player.media().startPaused(uri.toFile().absolutePath)
      val snap = withTimeoutOrNull(1500L) {
        while (surface.bitmap.value == null) delay(50)
        surface.bitmap.value!!.toAwtImage()
      }
      val orientation = player.media().info().videoTracks().firstOrNull()?.orientation()
      if (orientation == null) {
        player.stop()
        putHelperPlayer(mediaComponent)
        if (withAlertOnException) showVideoDecodingException()

        return@withContext VideoPlayerInterface.PreviewAndDuration(preview = defaultPreview, timestamp = 0L, duration = 0L)
      }
      val preview: ImageBitmap? = when (orientation) {
        VideoOrientation.TOP_LEFT -> snap
        VideoOrientation.TOP_RIGHT -> snap?.flip(false, true)
        VideoOrientation.BOTTOM_LEFT -> snap?.flip(true, false)
        VideoOrientation.BOTTOM_RIGHT -> snap?.rotate(180.0)
        VideoOrientation.LEFT_TOP -> snap
        VideoOrientation.LEFT_BOTTOM -> snap?.rotate(-90.0)
        VideoOrientation.RIGHT_TOP -> snap?.rotate(90.0)
        VideoOrientation.RIGHT_BOTTOM -> snap
      }?.toComposeImageBitmap()
      val duration = player.duration.toLong()
      player.stop()
      putHelperPlayer(mediaComponent)
      return@withContext VideoPlayerInterface.PreviewAndDuration(preview = preview, timestamp = 0L, duration = duration)
    }

    private const val PARSE_TIMEOUT_MS = 3000L

    suspend fun hasVideoTrack(uri: URI): Boolean = withContext(previewThread.asCoroutineDispatcher()) {
      if (!uri.toFile().exists()) return@withContext false
      val media = try {
        vlcPreviewFactory.media().newMedia(uri.toFile().absolutePath)
      } catch (e: Exception) {
        Log.e(TAG, "hasVideoTrack unable to create media: ${e.stackTraceToString()}")
        null
      } ?: return@withContext false
      try {
        val parsed = CompletableDeferred<MediaParsedStatus?>()
        media.events().addMediaEventListener(object: MediaEventAdapter() {
          override fun mediaParsedChanged(parsedMedia: Media?, newStatus: MediaParsedStatus?) {
            parsed.complete(newStatus)
          }
        })
        if (!media.parsing().parse(PARSE_TIMEOUT_MS.toInt(), ParseFlag.PARSE_LOCAL)) {
          return@withContext false
        }
        if (withTimeoutOrNull(PARSE_TIMEOUT_MS) { parsed.await() } != MediaParsedStatus.DONE) {
          media.parsing().stop()
          return@withContext false
        }
        media.info().videoTracks().isNotEmpty()
      } catch (e: Exception) {
        Log.e(TAG, "hasVideoTrack error: ${e.stackTraceToString()}")
        false
      } finally {
        media.release()
      }
    }

    val playerThread = Executors.newSingleThreadExecutor()
    private val previewThread = Executors.newSingleThreadExecutor()
    private val playersPool: ArrayList<Component> = ArrayList()
    private val helperPlayersPool: ArrayList<CallbackMediaPlayerComponent> = ArrayList()

    private fun getOrCreatePlayer(): Component = playersPool.removeFirstOrNull() ?: createNew()

    private fun createNew(): Component =
      initializeMediaPlayerComponent().apply {
        mediaPlayer().events().addMediaPlayerEventListener(object: MediaPlayerEventAdapter() {
          override fun mediaPlayerReady(mediaPlayer: MediaPlayer?) {
            playerThread.execute {
              mediaPlayer?.audio()?.isMute = false
            }
          }

          override fun stopped(mediaPlayer: MediaPlayer?) {
          }
        })
      }

    private fun putPlayer(player: Component) = playersPool.add(player)

    private fun getOrCreateHelperPlayer(): CallbackMediaPlayerComponent = helperPlayersPool.removeFirstOrNull() ?: CallbackMediaPlayerComponent(MediaPlayerSpecs.callbackMediaPlayerSpec().apply { withFactory(vlcPreviewFactory) })
    private fun putHelperPlayer(player: CallbackMediaPlayerComponent) = helperPlayersPool.add(player)
  }
}
