package app.zero.core.common.views.usersettings

import SectionBottomSpacer
import SectionDividerSpaced
import SectionItemView
import SectionItemViewSpaceBetween
import SectionTextFooter
import SectionView
import androidx.compose.foundation.layout.*
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.*
import androidx.compose.ui.unit.*
import app.zero.core.common.platform.*
import app.zero.core.common.ui.theme.*
import app.zero.core.common.views.*
import app.zero.core.common.views.chat.item.openBrowserAlert
import app.zero.core.common.views.helpers.*
import app.zero.core.res.MR
import dev.icerock.moko.resources.compose.painterResource
import dev.icerock.moko.resources.compose.stringResource
import kotlinx.coroutines.*
import kotlinx.datetime.*

private val zeroNameLabelRegex = Regex("[A-Za-z0-9]+(-[A-Za-z0-9]+)*")

private const val ZERO_DOMAINS_URL = "https://simpl.global/zero/domain"

@Composable
fun SetZeroDomainView(
  title: String,
  footer: String,
  placeholder: String,
  zeroName: String,
  registerBackgroundClose: Boolean = false,
  broadcastWarning: String? = null,
  save: suspend (String?) -> Boolean,
  close: () -> Unit
) {
  val name = rememberSaveable { mutableStateOf(zeroName) }
  val saving = remember { mutableStateOf(false) }
  val editing = rememberSaveable { mutableStateOf(zeroName.isBlank()) }
  val uriHandler = LocalUriHandler.current
  val clipboard = LocalClipboardManager.current

  fun addZeroTLD(s: String): String {
    return if (s.contains(".")) s else "$s.zero"
  }

  fun normalized(s: String): String? {
    val t = s.trim()
    return when {
      t.isEmpty() -> null
      t.startsWith("@") || t.startsWith("#") -> addZeroTLD(t.substring(1).lowercase())
      else -> addZeroTLD(t.lowercase())
    }
  }

  fun isValidName(s: String): Boolean {
    val n = normalized(s) ?: return true
    if (n.length > 253) return false
    val labels = n.split(".")
    if (labels.size < 2) return false
    return labels.all { it.length in 1..63 && zeroNameLabelRegex.matches(it) }
  }

  val unchanged = normalized(name.value) == normalized(zeroName)
  val isValid = isValidName(name.value)

  fun doSave(close: () -> Unit) {
    withBGApi {
      saving.value = true
      val ok = try { save(normalized(name.value)) } catch (e: Exception) {
        Log.e(TAG, "SetZeroDomainView save: ${e.stackTraceToString()}")
        AlertManager.shared.showAlertMsg(generalGetString(MR.strings.error_saving_zero_name), e.message ?: "")
        false
      }
      saving.value = false
      if (ok) withContext(Dispatchers.Main) {
        if (registerBackgroundClose) chatModel.centerPanelBackgroundClickHandler = null
        close()
      }
    }
  }

  fun onClose(close: () -> Unit): Boolean {
    val valid = isValidName(name.value)
    val changed = normalized(name.value) != normalized(zeroName)
    return if (changed && valid) {
      AlertManager.shared.showAlertDialog(
        title = generalGetString(MR.strings.save_zero_name_question),
        text = broadcastWarning,
        confirmText = generalGetString(MR.strings.save_verb),
        onConfirm = { doSave(close) },
        dismissText = generalGetString(MR.strings.exit_without_saving),
        onDismiss = {
          if (registerBackgroundClose) chatModel.centerPanelBackgroundClickHandler = null
          close()
        }
      )
      true
    } else {
      if (registerBackgroundClose) chatModel.centerPanelBackgroundClickHandler = null
      close()
      false
    }
  }

  DisposableEffect(Unit) {
    if (registerBackgroundClose) {
      chatModel.centerPanelBackgroundClickHandler = {
        onClose(close = { ModalManager.start.closeModals() })
      }
    }
    onDispose {
      if (registerBackgroundClose) chatModel.centerPanelBackgroundClickHandler = null
    }
  }

  ModalView(close = { onClose(close) }, cardScreen = true) {
    ColumnWithScrollBar {
      AppBarTitle(title)
      SectionView {
        if (editing.value) {
          val focusRequester = remember { FocusRequester() }
          LaunchedEffect(Unit) {
            delay(300)
            focusRequester.requestFocus()
          }
          SectionItemViewSpaceBetween(click = { focusRequester.requestFocus() }) {
            Box(Modifier.weight(1f)) {
              PlainTextEditor(name, placeholder = placeholder, contentPadding = PaddingValues(), focusRequester = focusRequester)
            }
            if (!isValid) {
              Icon(painterResource(MR.images.ic_error), null, tint = MaterialTheme.colors.error)
            }
          }
        } else {
          SectionItemViewSpaceBetween(click = {
            clipboard.setText(AnnotatedString(name.value))
            showToast(generalGetString(MR.strings.copied))
          }) {
            Text(name.value)
            Icon(painterResource(MR.images.ic_content_copy), stringResource(MR.strings.copy_verb), tint = MaterialTheme.colors.secondary)
          }
        }
      }
      SectionTextFooter(footer)
      SectionDividerSpaced()
      SectionView {
        if (editing.value) {
          SettingsActionItem(
            painterResource(MR.images.ic_open_in_new),
            stringResource(MR.strings.register_test_name),
            { openBrowserAlert(ZERO_DOMAINS_URL, uriHandler) },
            textColor = MaterialTheme.colors.primary,
            iconColor = MaterialTheme.colors.primary
          )
          SectionItemView({ if (broadcastWarning != null && !unchanged) AlertManager.shared.showAlertDialog(title = broadcastWarning, confirmText = generalGetString(MR.strings.save_verb), onConfirm = { doSave(close) }) else doSave(close) }, disabled = unchanged || saving.value || !isValid) {
            Text(
              stringResource(MR.strings.save_verb),
              color = if (unchanged || saving.value || !isValid) MaterialTheme.colors.secondary else MaterialTheme.colors.primary
            )
          }
        } else {
          SectionItemView({ name.value = ""; editing.value = true }) {
            Text(stringResource(MR.strings.remove_name), color = MaterialTheme.colors.primary)
          }
        }
      }
      SectionDividerSpaced()
      SectionView("Zero Domain Registration") {
        SectionItemView {
          Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Registration in Progress", style = MaterialTheme.typography.subtitle1)
            Text(
              "Decentralized Zero domain verification is currently being deployed. Public registration ETA is to be announced.",
              color = MaterialTheme.colors.secondary,
              fontSize = 12.sp
            )
          }
        }
      }
      SectionTextFooter(buildAnnotatedString {
        append("Learn more and track rollout updates at")
        append(" ")
        withLink(LinkAnnotation.Url(ZERO_DOMAINS_URL) { uriHandler.openUriCatching(ZERO_DOMAINS_URL) }) {
          withStyle(SpanStyle(color = MaterialTheme.colors.primary)) {
            append("simpl.global/zero/domain")
          }
        }
      })
      SectionBottomSpacer()
    }
  }
}
