package app.zero.core.common.views.onboarding

import android.Manifest
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import app.zero.core.common.model.ChatController.appPrefs
import app.zero.core.common.platform.*
import com.google.accompanist.permissions.*

@Composable
actual fun SetNotificationsModeAdditions() {
  if (Build.VERSION.SDK_INT >= 33) {
    val notificationsPermissionState = rememberPermissionState(Manifest.permission.POST_NOTIFICATIONS)
    LaunchedEffect(notificationsPermissionState.status == PermissionStatus.Granted) {
      val canAsk = appPrefs.canAskToEnableNotifications.get()
      if (notificationsPermissionState.status is PermissionStatus.Denied) {
        if (notificationsPermissionState.status.shouldShowRationale || !canAsk) {
          if (canAsk) {
            appPrefs.canAskToEnableNotifications.set(false)
          }
          Log.w(TAG, "Notifications are disabled and nobody will ask to enable them")
        } else {
          notificationsPermissionState.launchPermissionRequest()
        }
      } else {
        if (!canAsk) {
          appPrefs.canAskToEnableNotifications.set(true)
        }
        ntfManager.androidCreateNtfChannelsMaybeShowAlert()
      }
    }
  } else {
    LaunchedEffect(Unit) {
      ntfManager.androidCreateNtfChannelsMaybeShowAlert()
    }
  }
}
