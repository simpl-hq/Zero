package app.zero.core.common.platform

import android.media.session.PlaybackState
import android.net.Uri
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.ImageBitmap
import app.zero.core.common.views.helpers.*
import app.zero.core.res.MR
import com.google.android.exoplayer2.*
import com.google.android.exoplayer2.C.*
import com.google.android.exoplayer2.audio.AudioAttributes
import com.google.android.exoplayer2.source.ProgressiveMediaSource
import com.google.android.exoplayer2.upstream.DefaultDataSource
import com.google.android.exoplayer2.upstream.DefaultHttpDataSource
import kotlinx.coroutines.*
import java.io.File
import java.net.URI

actual class VideoPlayer actual constructor(
  override val uri: URI,
  override val gallery: Boolean,
  private val defaultPreview: ImageBitmap,
  defaultDuration: Long,
  soundEnabled: Boolean
): VideoPlayerInterface {
  private val currentVolume: Float

  override val soundEnabled: MutableState<Boolean> = mutableStateOf(soundEnabled)
  override val brokenVideo: MutableState<Boolean> = mutableStateOf(false)
  override val videoPlaying: MutableState<Boolean> = mutableStateOf(false)
  override val progress: MutableState<Long> = mutableStateOf(0L)
  override val duration: MutableState<Long> = mutableStateOf(defaultDuration)
  override val preview: MutableState<ImageBitmap> = mutableStateOf(defaultPreview)

  val player = ExoPlayer.Builder(androidAppContext,
    DefaultRenderersFactory(androidAppContext))

    .setSeekBackIncrementMs(10_000)
    .setSeekForwardIncrementMs(10_000)
    .build()
    .apply {
      repeatMode = Player.REPEAT_MODE_ONE
      currentVolume = volume
      if (!soundEnabled) {
        volume = 0f
      }
      setAudioAttributes(
        AudioAttributes.Builder()
          .setContentType(CONTENT_TYPE_MUSIC)
          .setUsage(USAGE_MEDIA)
          .build(),
        true
      )
    }

  private val listener: MutableState<((position: Long?, state: TrackState) -> Unit)?> = mutableStateOf(null)
  private var progressJob: Job? = null

  enum class TrackState {
    PLAYING, PAUSED, STOPPED
  }

  private fun start(seek: Long? = null, onProgressUpdate: (position: Long?, state: TrackState) -> Unit): Boolean {
    val filepath = if (uri.scheme == "file") uri.toFile().absolutePath else getAppFilePath(uri)
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
        val dataSourceFactory = DefaultDataSource.Factory(androidAppContext, DefaultHttpDataSource.Factory())
        val source = ProgressiveMediaSource.Factory(dataSourceFactory).createMediaSource(MediaItem.fromUri(Uri.parse(uri.toString())))
        player.setMediaSource(source, seek ?: 0L)
      }.onFailure {
        Log.e(TAG, it.stackTraceToString())
        AlertManager.shared.showAlertMsg(generalGetString(MR.strings.unknown_error), it.stackTraceToString())
        brokenVideo.value = true
        return false
      }
    }
    if (player.playbackState == PlaybackState.STATE_NONE || player.playbackState == PlaybackState.STATE_STOPPED) {
      runCatching { player.prepare() }.onFailure {
        Log.e(TAG, it.stackTraceToString())
        AlertManager.shared.showAlertMsg(generalGetString(MR.strings.unknown_error), it.stackTraceToString())
        brokenVideo.value = true
        return false
      }
    }
    if (seek != null) player.seekTo(seek)
    player.play()
    listener.value = onProgressUpdate
    progressJob = CoroutineScope(Dispatchers.Main).launch {
      onProgressUpdate(player.currentPosition, TrackState.PLAYING)
      while (isActive && player.playbackState != Player.STATE_IDLE && player.playWhenReady) {
        if (player.currentPosition == player.duration) {
          onProgressUpdate(player.currentPosition, TrackState.PLAYING)
          break
        }
        delay(50)
        onProgressUpdate(player.currentPosition, TrackState.PLAYING)
      }

      if (isActive) {
        onProgressUpdate(player.duration, TrackState.PAUSED)
      }
      onProgressUpdate(null, TrackState.PAUSED)
    }
    player.addListener(object: Player.Listener{
      override fun onIsPlayingChanged(isPlaying: Boolean) {
        super.onIsPlayingChanged(isPlaying)
        keepScreenOn(isPlaying)
      }
    })

    return true
  }

  override fun stop() {
    player.stop()
    stopListener()
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
    videoPlaying.value = start(progress.value) { pro, _ ->
      if (pro != null) {
        progress.value = pro
      }
      if (pro == null || pro == duration.value) {
        videoPlaying.value = false
        if (pro == duration.value) {
          progress.value = if (resetOnEnd) 0 else duration.value
        }

      }
    }
  }

  override fun enableSound(enable: Boolean): Boolean {
    if (soundEnabled.value == enable) return false
    soundEnabled.value = enable
    player.volume = if (enable) currentVolume else 0f
    return true
  }

  override fun release(remove: Boolean) {
    player.release()
    keepScreenOn(false)
    if (remove) {
      VideoPlayerHolder.players.remove(uri to gallery)
    }
  }

  private fun setPreviewAndDuration() {
    CoroutineScope(Dispatchers.IO).launch {
      val previewAndDuration = VideoPlayerHolder.previewsAndDurations.getOrPut(uri) { getBitmapFromVideo(uri, withAlertOnException = false) }
      withContext(Dispatchers.Main) {
        preview.value = previewAndDuration.preview ?: defaultPreview
        duration.value = (previewAndDuration.duration ?: 0)
      }
    }
  }
}
