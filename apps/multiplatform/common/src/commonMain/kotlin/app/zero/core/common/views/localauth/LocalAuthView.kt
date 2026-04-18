package app.zero.core.common.views.localauth

import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import app.zero.core.common.model.*
import app.zero.core.common.model.ChatModel.controller
import dev.icerock.moko.resources.compose.stringResource
import app.zero.core.common.views.helpers.*
import app.zero.core.common.views.helpers.DatabaseUtils.ksSelfDestructPassword
import app.zero.core.common.views.helpers.DatabaseUtils.ksAppPassword
import app.zero.core.common.views.onboarding.OnboardingStage
import app.zero.core.common.platform.*
import app.zero.core.common.views.database.*
import app.zero.core.res.MR
import kotlinx.coroutines.delay

@Composable
fun LocalAuthView(m: ChatModel, authRequest: LocalAuthRequest) {
  val passcode = rememberSaveable { mutableStateOf("") }
  val allowToReact = rememberSaveable { mutableStateOf(true) }
  if (!allowToReact.value) {
    BackHandler {
    }
  }
  PasscodeView(passcode, authRequest.title ?: stringResource(MR.strings.la_enter_app_passcode), authRequest.reason, stringResource(MR.strings.submit_passcode), buttonsEnabled = allowToReact,
    submit = {
      val sdPassword = ksSelfDestructPassword.get()
      if (sdPassword == passcode.value && authRequest.selfDestruct) {
        allowToReact.value = false
        deleteStorageAndRestart(m, sdPassword) { r ->
          authRequest.completed(r)
        }
      } else {
        val r: LAResult = if (passcode.value == authRequest.password) {
          if (authRequest.selfDestruct && sdPassword != null && controller.getChatCtrl() == -1L) {
            initChatControllerOnStart()
          }
          LAResult.Success
        } else {
          LAResult.Error(generalGetString(MR.strings.incorrect_passcode))
        }
        authRequest.completed(r)
      }
    },
    cancel = {
      authRequest.completed(LAResult.Error(generalGetString(MR.strings.authentication_cancelled)))
    })
}

private fun deleteStorageAndRestart(m: ChatModel, password: String, completed: (LAResult) -> Unit) {
  withLongRunningApi {
    try {

      while (m.ctrlInitInProgress.value) {
        delay(50)
      }
      if (m.chatRunning.value == true) {
        stopChatAsync(m)
      }
      val ctrl = m.controller.getChatCtrl()
      if (ctrl != null && ctrl != -1L) {

        chatCloseStore(ctrl)
      }
      deleteChatDatabaseFilesAndState()
      ksAppPassword.set(password)
      ksSelfDestructPassword.remove()
      ntfManager.cancelAllNotifications()
      val selfDestructPref = m.controller.appPrefs.selfDestruct
      val displayNamePref = m.controller.appPrefs.selfDestructDisplayName
      val displayName = displayNamePref.get()
      selfDestructPref.set(false)
      displayNamePref.set(null)
      reinitChatController()
      if (m.currentUser.value != null) {
        return@withLongRunningApi
      }
      var profile: Profile? = null
      if (!displayName.isNullOrEmpty()) {
        profile = Profile(displayName = displayName, fullName = "", shortDescr = null)
      }
      val createdUser = m.controller.apiCreateActiveUser(null, profile, pastTimestamp = true)
      m.currentUser.value = createdUser
      m.controller.appPrefs.onboardingStage.set(OnboardingStage.OnboardingComplete)
      if (createdUser != null) {
        m.controller.startChat(createdUser)
      }
      ModalManager.closeAllModalsEverywhere()
      AlertManager.shared.hideAllAlerts()
      AlertManager.privacySensitive.hideAllAlerts()
      completed(LAResult.Success)
    } catch (e: Exception) {
      Log.e(TAG, "Unable to delete storage: ${e.stackTraceToString()}")
      completed(LAResult.Error(generalGetString(MR.strings.incorrect_passcode)))
    }
  }
}

suspend fun reinitChatController() {
  chatModel.chatDbChanged.value = true
  chatModel.chatDbStatus.value = null
  try {
    initChatController()
  } catch (e: Exception) {
    Log.d(TAG, "initializeChat ${e.stackTraceToString()}")
  }
  chatModel.chatDbChanged.value = false
}
