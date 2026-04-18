package app.zero.core.common.platform

import androidx.compose.animation.core.*
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import app.zero.core.common.model.ChatId
import app.zero.core.common.model.NotificationsMode
import app.zero.core.common.ui.theme.CurrentColors
import kotlinx.coroutines.Job
import java.io.Closeable

interface PlatformInterface {
  suspend fun androidServiceStart() {}
  fun androidServiceSafeStop() {}
  fun androidCallServiceSafeStop() {}
  fun androidNotificationsModeChanged(mode: NotificationsMode) {}
  fun androidChatStartedAfterBeingOff() {}
  fun androidChatStopped() {}
  fun androidChatInitializedAndStarted() {}
  fun androidIsBackgroundCallAllowed(): Boolean = true
  fun androidSetNightModeIfSupported() {}
  fun androidSetStatusAndNavigationBarAppearance(isLightStatusBar: Boolean, isLightNavBar: Boolean, blackNavBar: Boolean = false, themeBackgroundColor: Color = CurrentColors.value.colors.background) {}
  fun androidStartCallActivity(acceptCall: Boolean, remoteHostId: Long? = null, chatId: ChatId? = null) {}
  fun androidPictureInPictureAllowed(): Boolean = true
  fun androidCallEnded() {}
  fun androidRestartNetworkObserver() {}
  fun androidCreateActiveCallState(): Closeable = Closeable { }
  fun androidIsXiaomiDevice(): Boolean = false
  fun androidLoadPlayStoreCountry() {}
  val androidApiLevel: Int? get() = null
  val androidIsPlayStoreBuild: Boolean get() = false
  @Composable fun androidLockPortraitOrientation() {}
  suspend fun androidAskToAllowBackgroundCalls(): Boolean = true
  @Composable fun desktopShowAppUpdateNotice() {}
}

var platform: PlatformInterface = object : PlatformInterface {}
