package app.zero.core.common

import SectionItemView
import androidx.compose.foundation.layout.*
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.window.*
import app.zero.core.common.model.ChatModel
import app.zero.core.common.model.CloseBehavior
import app.zero.core.common.model.ChatController.appPrefs
import app.zero.core.common.platform.Log
import app.zero.core.common.platform.TAG
import app.zero.core.common.ui.theme.isInDarkTheme
import app.zero.core.common.views.helpers.AlertManager
import app.zero.core.common.views.helpers.generalGetString
import app.zero.core.res.MR
import dev.icerock.moko.resources.compose.painterResource
import dev.icerock.moko.resources.compose.stringResource
import java.awt.AWTException
import java.awt.SystemTray
import java.awt.TrayIcon
import java.awt.image.BufferedImage

val trayIsAvailable: Boolean by lazy {
  if (!SystemTray.isSupported()) return@lazy false
  try {
    val tray = SystemTray.getSystemTray()
    val probe = TrayIcon(BufferedImage(1, 1, BufferedImage.TYPE_INT_ARGB))
    tray.add(probe)
    tray.remove(probe)
    true
  } catch (e: AWTException) {
    Log.w(TAG, "SystemTray probe failed: ${e.stackTraceToString()}")
    false
  } catch (e: SecurityException) {
    Log.w(TAG, "SystemTray probe denied: ${e.stackTraceToString()}")
    false
  }
}

@Composable
fun ApplicationScope.ZeroTray() {
  if (!trayIsAvailable) return
  if (remember { appPrefs.closeBehavior.state }.value != CloseBehavior.MinimizeToTray) return
  val unread by remember {
    derivedStateOf {
      ChatModel.users.sumOf {
        if (!it.user.showNtfs && !it.user.activeUser) 0 else it.unreadCount
      }
    }
  }
  val iconRes = if (unread > 0) {
    if (isInDarkTheme()) MR.images.ic_zero_tray_dot_light else MR.images.ic_zero_tray_dot
  } else {
    if (isInDarkTheme()) MR.images.ic_zero_tray_light else MR.images.ic_zero
  }
  val tooltip =
    if (unread > 0) stringResource(MR.strings.tray_tooltip_unread, unread)
    else stringResource(MR.strings.tray_tooltip)
  Tray(
    icon = painterResource(iconRes),
    tooltip = tooltip,
    onAction = ::showWindow,
    menu = {
      Item(stringResource(MR.strings.tray_show), onClick = ::showWindow)
      Separator()
      Item(stringResource(MR.strings.tray_quit), onClick = { exitApplication() })
    }
  )
}

fun ApplicationScope.requestCloseBehavior() {
  val pref = appPrefs.closeBehavior
  AlertManager.shared.showAlertDialogButtonsColumn(
    title = generalGetString(MR.strings.close_behavior_dialog_title),
    text = AnnotatedString(generalGetString(MR.strings.close_behavior_dialog_text)),
    buttons = {
      Column {
        SectionItemView({
          AlertManager.shared.hideAlert()
          pref.set(CloseBehavior.Quit)
          exitApplication()
        }) {
          Text(
            stringResource(MR.strings.close_behavior_dialog_close),
            Modifier.fillMaxWidth(),
            textAlign = TextAlign.Center,
            color = Color.Red
          )
        }
        SectionItemView({
          AlertManager.shared.hideAlert()
          pref.set(CloseBehavior.MinimizeToTray)
          zeroWindowState.windowVisible.value = false
        }) {
          Text(
            stringResource(MR.strings.close_behavior_dialog_minimize),
            Modifier.fillMaxWidth(),
            textAlign = TextAlign.Center,
            color = MaterialTheme.colors.primary
          )
        }
      }
    }
  )
}
