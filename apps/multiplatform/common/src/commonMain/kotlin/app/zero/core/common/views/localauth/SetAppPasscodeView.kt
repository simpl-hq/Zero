package app.zero.core.common.views.localauth

import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import app.zero.core.common.platform.BackHandler
import app.zero.core.common.views.helpers.DatabaseUtils
import app.zero.core.common.views.helpers.DatabaseUtils.ksAppPassword
import app.zero.core.common.views.helpers.DatabaseUtils.ksSelfDestructPassword
import app.zero.core.common.views.helpers.generalGetString
import app.zero.core.res.MR

@Composable
fun SetAppPasscodeView(
  passcodeKeychain: DatabaseUtils.KeyStoreItem = ksAppPassword,
  prohibitedPasscodeKeychain: DatabaseUtils.KeyStoreItem = ksSelfDestructPassword,
  title: String = generalGetString(MR.strings.new_passcode),
  reason: String? = null,
  submit: () -> Unit,
  cancel: () -> Unit,
  close: () -> Unit
) {
  val passcode = rememberSaveable { mutableStateOf("") }
  var enteredPassword by rememberSaveable { mutableStateOf("") }
  var confirming by rememberSaveable { mutableStateOf(false) }

  @Composable
  fun SetPasswordView(title: String, submitLabel: String, submitEnabled: (((String) -> Boolean))? = null, submit: () -> Unit) {
    BackHandler {
      close()
      cancel()
    }
    PasscodeView(passcode, title = title, reason = reason, submitLabel = submitLabel, submitEnabled = submitEnabled, submit = submit) {
      close()
      cancel()
    }
  }

  if (confirming) {
    SetPasswordView(
      generalGetString(MR.strings.confirm_passcode),
      generalGetString(MR.strings.confirm_verb),
      submitEnabled = { pwd -> pwd == enteredPassword }
    ) {
      if (passcode.value == enteredPassword) {
        passcodeKeychain.set(passcode.value)
        enteredPassword = ""
        passcode.value = ""
        close()
        submit()
      }
    }
  } else {
    SetPasswordView(title, generalGetString(MR.strings.save_verb),
      submitEnabled = { pwd -> pwd != prohibitedPasscodeKeychain.get() }) {
      enteredPassword = passcode.value
      passcode.value = ""
      confirming = true
    }
  }
}
