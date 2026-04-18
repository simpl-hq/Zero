package app.zero.core.common.platform

import app.zero.core.common.model.*
import app.zero.core.common.zeroWindowState
import app.zero.core.common.views.call.RcvCallInvitation
import app.zero.core.common.views.database.deleteOldChatArchive
import app.zero.core.common.views.helpers.*
import java.util.*
import app.zero.core.res.MR
import java.io.File

actual val appPlatform = AppPlatform.DESKTOP

actual val deviceName = generalGetString(MR.strings.desktop_device)

actual fun isAppVisibleAndFocused() = zeroWindowState.windowFocused.value

@Suppress("ConstantLocale")
val defaultLocale: Locale = Locale.getDefault()

fun initApp() {
  ntfManager = object : NtfManager() {
    override fun notifyCallInvitation(invitation: RcvCallInvitation): Boolean = app.zero.core.common.model.NtfManager.notifyCallInvitation(invitation)
    override fun hasNotificationsForChat(chatId: String): Boolean = app.zero.core.common.model.NtfManager.hasNotificationsForChat(chatId)
    override fun cancelNotificationsForChat(chatId: String) = app.zero.core.common.model.NtfManager.cancelNotificationsForChat(chatId)
    override fun cancelNotificationsForUser(userId: Long) = app.zero.core.common.model.NtfManager.cancelNotificationsForUser(userId)
    override fun displayNotification(user: UserLike, chatId: String, displayName: String, msgText: String, image: String?, actions: List<Pair<NotificationAction, () -> Unit>>) = app.zero.core.common.model.NtfManager.displayNotification(user, chatId, displayName, msgText, image, actions)
    override fun androidCreateNtfChannelsMaybeShowAlert() {}
    override fun cancelCallNotification() {}
    override fun cancelAllNotifications() = app.zero.core.common.model.NtfManager.cancelAllNotifications()
    override fun showMessage(title: String, text: String) = app.zero.core.common.model.NtfManager.showMessage(title, text)
  }
  applyAppLocale()
  deleteOldChatArchive()
  if (DatabaseUtils.ksSelfDestructPassword.get() == null) {
    initChatControllerOnStart()
  }
}

private fun applyAppLocale() {
  val lang = ChatController.appPrefs.appLanguage.get()
  if (lang == null || lang == Locale.getDefault().language) return
  Locale.setDefault(Locale.forLanguageTag(lang))
}
