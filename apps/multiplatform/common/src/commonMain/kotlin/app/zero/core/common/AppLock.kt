package app.zero.core.common

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.*
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import app.zero.core.common.model.*
import app.zero.core.common.model.ChatController.appPrefs
import app.zero.core.common.platform.*
import app.zero.core.common.views.helpers.*
import app.zero.core.common.views.localauth.SetAppPasscodeView
import app.zero.core.common.views.usersettings.*
import app.zero.core.res.MR
import kotlinx.coroutines.*

object AppLock {

  val userAuthorized = mutableStateOf<Boolean?>(null)
  val enteredBackground = mutableStateOf<Long?>(null)

  val laFailed = mutableStateOf(false)

  fun clearAuthState() {
    userAuthorized.value = null
    enteredBackground.value = null
  }

  fun showLANotice(laNoticeShown: SharedPreference<Boolean>) {
    Log.d(TAG, "showLANotice")
    if (!laNoticeShown.get() && !appPrefs.performLA.get()) {
      laNoticeShown.set(true)
      AlertManager.shared.showAlertDialog(
        title = generalGetString(MR.strings.la_notice_title_zero_lock),
        text = generalGetString(MR.strings.la_notice_to_protect_your_information_turn_on_zero_lock_you_will_be_prompted_to_complete_authentication_before_this_feature_is_enabled),
        confirmText = generalGetString(MR.strings.la_notice_turn_on),
        onConfirm = {
          laNoticeShown.set(true)
          withBGApi {
            if (appPlatform.isAndroid) {
              showChooseLAMode()
            } else {
              AlertManager.shared.hideAlert()
              setPasscode()
            }
          }
        },
        onDismiss = {
          AlertManager.shared.hideAlert()
        }
      )
    }
  }

  private fun showChooseLAMode() {
    Log.d(TAG, "showLANotice")
    if (appPrefs.performLA.get()) return

    AlertManager.shared.showAlertDialogStacked(
      title = generalGetString(MR.strings.la_lock_mode),
      text = null,
      confirmText = generalGetString(MR.strings.la_lock_mode_passcode),
      dismissText = generalGetString(MR.strings.la_lock_mode_system),
      onConfirm = {
        AlertManager.shared.hideAlert()
        setPasscode()
      },
      onDismiss = {
        AlertManager.shared.hideAlert()
        initialEnableLA()
      }
    )
  }

  private fun initialEnableLA() {
    val m = ChatModel
    val appPrefs = ChatController.appPrefs
    appPrefs.laMode.set(LAMode.default)
    authenticate(
      generalGetString(MR.strings.auth_enable_zero_lock),
      generalGetString(MR.strings.auth_confirm_credential),
      oneTime = true,
      completed = { laResult ->
        when (laResult) {
          LAResult.Success -> {
            m.showAuthScreen.value = true
            appPrefs.performLA.set(true)
            laTurnedOnAlert()
          }
          is LAResult.Failed -> {  }
          is LAResult.Error -> {
            m.showAuthScreen.value = false
            laFailedAlert()
          }
          is LAResult.Unavailable -> {
            m.showAuthScreen.value = false
            appPrefs.performLA.set(false)
            m.showAdvertiseLAUnavailableAlert.value = true
          }
        }
      }
    )
  }

  private fun setPasscode() {
    if (appPrefs.performLA.get()) return

    val appPrefs = ChatController.appPrefs
    ModalManager.fullscreen.showCustomModal { close ->
      Surface(Modifier.fillMaxSize(), color = MaterialTheme.colors.background.copy(1f), contentColor = LocalContentColor.current) {
        SetAppPasscodeView(
          submit = {
            ChatModel.showAuthScreen.value = true
            appPrefs.performLA.set(true)
            appPrefs.laMode.set(LAMode.PASSCODE)
            laTurnedOnAlert()
          },
          cancel = {
            ChatModel.showAuthScreen.value = false
            laPasscodeNotSetAlert()
          },
          close = close
        )
      }
    }
  }

  fun setAuthState() {
    userAuthorized.value = !ChatController.appPrefs.performLA.get()
  }

  fun runAuthenticate() {
    val m = ChatModel
    setAuthState()
    if (userAuthorized.value == false) {
      CoroutineScope(Dispatchers.Default).launch {
        delay(50)
        withContext(Dispatchers.Main) {
          authenticate(
            if (m.controller.appPrefs.laMode.get() == LAMode.SYSTEM)
              generalGetString(MR.strings.auth_unlock)
            else
              generalGetString(MR.strings.la_enter_app_passcode),
            if (m.controller.appPrefs.laMode.get() == LAMode.SYSTEM)
              generalGetString(MR.strings.auth_log_in_using_credential)
            else
              generalGetString(MR.strings.auth_unlock),
            selfDestruct = true,
            oneTime = false,
            completed = { laResult ->
              when (laResult) {
                LAResult.Success ->
                  userAuthorized.value = true
                is LAResult.Failed -> {  }
                is LAResult.Error -> {
                  laFailed.value = true
                  if (m.controller.appPrefs.laMode.get() == LAMode.PASSCODE) {
                    laFailedAlert()
                  }
                }
                is LAResult.Unavailable -> {
                  userAuthorized.value = true
                  m.showAuthScreen.value = false
                  m.controller.appPrefs.performLA.set(false)
                  laUnavailableTurningOffAlert()
                }
              }
            }
          )
        }
      }
    }
  }

  fun setPerformLA(on: Boolean) {
    ChatController.appPrefs.laNoticeShown.set(true)
    if (on) {
      enableLA()
    } else {
      disableLA()
    }
  }

  private fun enableLA() {
    val m = ChatModel
    authenticate(
      if (m.controller.appPrefs.laMode.get() == LAMode.SYSTEM)
        generalGetString(MR.strings.auth_enable_zero_lock)
      else
        generalGetString(MR.strings.new_passcode),
      if (m.controller.appPrefs.laMode.get() == LAMode.SYSTEM)
        generalGetString(MR.strings.auth_confirm_credential)
      else
        "",
      oneTime = true,
      completed = { laResult ->
        val prefPerformLA = m.controller.appPrefs.performLA
        when (laResult) {
          LAResult.Success -> {
            m.showAuthScreen.value = true
            prefPerformLA.set(true)
            laTurnedOnAlert()
          }
          is LAResult.Failed -> {  }
          is LAResult.Error -> {
            m.showAuthScreen.value = false
            prefPerformLA.set(false)
            laFailedAlert()
          }
          is LAResult.Unavailable -> {
            m.showAuthScreen.value = false
            prefPerformLA.set(false)
            laUnavailableInstructionAlert()
          }
        }
      }
    )
  }

  private fun disableLA() {
    val m = ChatModel
    authenticate(
      if (m.controller.appPrefs.laMode.get() == LAMode.SYSTEM)
        generalGetString(MR.strings.auth_disable_zero_lock)
      else
        generalGetString(MR.strings.la_enter_app_passcode),
      if (m.controller.appPrefs.laMode.get() == LAMode.SYSTEM)
        generalGetString(MR.strings.auth_confirm_credential)
      else
        generalGetString(MR.strings.auth_disable_zero_lock),
      oneTime = true,
      completed = { laResult ->
        val prefPerformLA = m.controller.appPrefs.performLA
        val selfDestructPref = m.controller.appPrefs.selfDestruct
        when (laResult) {
          LAResult.Success -> {
            m.showAuthScreen.value = false
            prefPerformLA.set(false)
            DatabaseUtils.ksAppPassword.remove()
            selfDestructPref.set(false)
            DatabaseUtils.ksSelfDestructPassword.remove()
          }
          is LAResult.Failed -> {  }
          is LAResult.Error -> {
            m.showAuthScreen.value = true
            prefPerformLA.set(true)
            laFailedAlert()
          }
          is LAResult.Unavailable -> {
            m.showAuthScreen.value = false
            prefPerformLA.set(false)
            laUnavailableTurningOffAlert()
          }
        }
      }
    )
  }

  fun elapsedRealtime(): Long = System.nanoTime() / 1_000_000

  fun recheckAuthState() {
    val enteredBackgroundVal = enteredBackground.value
    val delay = ChatController.appPrefs.laLockDelay.get()
    if (enteredBackgroundVal == null || elapsedRealtime() - enteredBackgroundVal >= delay * 1000) {
      if (userAuthorized.value != false) {

        setAuthState()
      } else if (!ChatModel.activeCallViewIsVisible.value) {
        runAuthenticate()
      }
    }
  }
  fun appWasHidden() {
    enteredBackground.value = elapsedRealtime()
  }
}
