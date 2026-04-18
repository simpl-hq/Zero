package app.zero.chat

import android.annotation.SuppressLint
import android.app.*
import android.content.Context
import app.zero.core.common.platform.Log
import android.content.Intent
import android.content.pm.ActivityInfo
import android.os.*
import android.view.View
import androidx.compose.animation.core.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.core.view.ViewCompat
import androidx.lifecycle.*
import androidx.work.*
import app.zero.chat.MainActivity.Companion.OLD_ANDROID_UI_FLAGS
import app.zero.chat.model.NtfManager
import app.zero.chat.model.NtfManager.AcceptCallAction
import app.zero.chat.views.call.CallActivity
import app.zero.core.common.helpers.*
import app.zero.core.common.model.*
import app.zero.core.common.model.ChatController.appPrefs
import app.zero.core.common.platform.*
import app.zero.core.common.ui.theme.*
import app.zero.core.common.views.call.*
import app.zero.core.common.views.database.deleteOldChatArchive
import app.zero.core.common.views.helpers.*
import app.zero.core.common.views.onboarding.OnboardingStage
import com.jakewharton.processphoenix.ProcessPhoenix
import kotlinx.coroutines.*
import java.io.*
import java.util.*
import java.util.concurrent.TimeUnit

const val TAG = "ZERO"

class ZeroApp: Application(), LifecycleEventObserver {
  val chatModel: ChatModel
    get() = chatController.chatModel

  val chatController: ChatController = ChatController

  override fun onCreate() {
    super.onCreate()
    AppContextProvider.initialize(this)
    if (ProcessPhoenix.isPhoenixProcess(this)) {
      return
    } else {
      registerGlobalErrorHandler()
      Handler(Looper.getMainLooper()).post {
        while (true) {
          try {
            Looper.loop()
          } catch (e: Throwable) {
            if (e is UnsatisfiedLinkError || e.message?.startsWith("Unable to start activity") == true) {
              Process.killProcess(Process.myPid())
              break
            } else {
              Thread.getDefaultUncaughtExceptionHandler()?.uncaughtException(Looper.getMainLooper().thread, e)
            }
          }
        }
      }
    }
    context = this
    initHaskell(packageName)
    initMultiplatform()
    reconfigureBroadcastReceivers()
    runMigrations()
    tmpDir.deleteRecursively()
    tmpDir.mkdir()
    deleteOldChatArchive()

    if (chatModel.migrationState.value != null) {
      appPrefs.onboardingStage.set(OnboardingStage.Step1_ZeroInfo)
    } else if (DatabaseUtils.ksAppPassword.get() == null || DatabaseUtils.ksSelfDestructPassword.get() == null) {
      initChatControllerOnStart()
    }
    ProcessLifecycleOwner.get().lifecycle.addObserver(this@ZeroApp)
  }

  override fun onStateChanged(source: LifecycleOwner, event: Lifecycle.Event) {
    Log.d(TAG, "onStateChanged: $event")
    withLongRunningApi {
      when (event) {
        Lifecycle.Event.ON_START -> {
          isAppOnForeground = true
          if (chatModel.chatRunning.value == true) {
            withContext(Dispatchers.Main) {
              kotlin.runCatching {
                val currentUserId = chatModel.currentUser.value?.userId
                val chats = ArrayList(chatController.apiGetChats(chatModel.remoteHostId()))

                if (chatModel.currentUser.value?.userId == currentUserId) {
                  val currentChatId = chatModel.chatId.value
                  val oldStats = if (currentChatId != null) chatModel.getChat(currentChatId)?.chatStats else null
                  if (oldStats != null) {
                    val indexOfCurrentChat = chats.indexOfFirst { it.id == currentChatId }

                    if (indexOfCurrentChat >= 0) chats[indexOfCurrentChat] = chats[indexOfCurrentChat].copy(chatStats = oldStats)
                  }
                  chatModel.chatsContext.updateChats(chats)
                }
              }.onFailure { Log.e(TAG, it.stackTraceToString()) }
            }
          }
        }
        Lifecycle.Event.ON_RESUME -> {
          isAppOnForeground = true
          if (chatModel.controller.appPrefs.onboardingStage.get() == OnboardingStage.OnboardingComplete && chatModel.currentUser.value != null) {
            ZeroService.showBackgroundServiceNoticeIfNeeded()
          }

          if (chatModel.chatRunning.value != false &&
            chatModel.controller.appPrefs.onboardingStage.get() == OnboardingStage.OnboardingComplete &&
            appPrefs.notificationsMode.get() == NotificationsMode.SERVICE &&
            appPrefs.newDatabaseInitialized.get()
          ) {
            ZeroService.start()
          }
        }
        else -> isAppOnForeground = false
      }
    }
  }

  fun allowToStartServiceAfterAppExit() = with(chatModel.controller) {
    appPrefs.notificationsMode.get() == NotificationsMode.SERVICE &&
        (!NotificationsMode.SERVICE.requiresIgnoringBattery || ZeroService.isBackgroundAllowed())
  }

  private fun allowToStartPeriodically() = with(chatModel.controller) {
    appPrefs.notificationsMode.get() == NotificationsMode.PERIODIC &&
        (!NotificationsMode.PERIODIC.requiresIgnoringBattery || ZeroService.isBackgroundAllowed())
  }

  fun schedulePeriodicServiceRestartWorker() = CoroutineScope(Dispatchers.Default).launch {
    if (!allowToStartServiceAfterAppExit()) {
      getWorkManagerInstance().cancelUniqueWork(ZeroService.SERVICE_START_WORKER_WORK_NAME_PERIODIC)
      return@launch
    }
    val workerVersion = chatController.appPrefs.autoRestartWorkerVersion.get()
    val workPolicy = if (workerVersion == ZeroService.SERVICE_START_WORKER_VERSION) {
      Log.d(TAG, "ServiceStartWorker version matches: choosing KEEP as existing work policy")
      ExistingPeriodicWorkPolicy.KEEP
    } else {
      Log.d(TAG, "ServiceStartWorker version DOES NOT MATCH: choosing REPLACE as existing work policy")
      chatController.appPrefs.autoRestartWorkerVersion.set(ZeroService.SERVICE_START_WORKER_VERSION)
      ExistingPeriodicWorkPolicy.REPLACE
    }
    val work = PeriodicWorkRequestBuilder<ZeroService.ServiceStartWorker>(ZeroService.SERVICE_START_WORKER_INTERVAL_MINUTES, TimeUnit.MINUTES)
      .addTag(ZeroService.TAG)
      .addTag(ZeroService.SERVICE_START_WORKER_WORK_NAME_PERIODIC)
      .build()
    Log.d(TAG, "ServiceStartWorker: Scheduling period work every ${ZeroService.SERVICE_START_WORKER_INTERVAL_MINUTES} minutes")
    getWorkManagerInstance().enqueueUniquePeriodicWork(ZeroService.SERVICE_START_WORKER_WORK_NAME_PERIODIC, workPolicy, work)
  }

  fun schedulePeriodicWakeUp() = CoroutineScope(Dispatchers.Default).launch {
    if (!allowToStartPeriodically()) {
      MessagesFetcherWorker.cancelAll(withLog = false)
      return@launch
    }
    MessagesFetcherWorker.scheduleWork()
  }

  companion object {
    lateinit var context: ZeroApp private set
  }

  private fun initMultiplatform() {
    androidAppContext = this
    APPLICATION_ID = BuildConfig.APPLICATION_ID
    ntfManager = object : app.zero.core.common.platform.NtfManager() {
      override fun notifyCallInvitation(invitation: RcvCallInvitation): Boolean = NtfManager.notifyCallInvitation(invitation)
      override fun hasNotificationsForChat(chatId: String): Boolean = NtfManager.hasNotificationsForChat(chatId)
      override fun cancelNotificationsForChat(chatId: String) = NtfManager.cancelNotificationsForChat(chatId)
      override fun cancelNotificationsForUser(userId: Long) = NtfManager.cancelNotificationsForUser(userId)
      override fun displayNotification(user: UserLike, chatId: String, displayName: String, msgText: String, image: String?, actions: List<Pair<NotificationAction, () -> Unit>>) = NtfManager.displayNotification(user, chatId, displayName, msgText, image, actions.map { it.first })
      override fun androidCreateNtfChannelsMaybeShowAlert() = NtfManager.createNtfChannelsMaybeShowAlert()
      override fun cancelCallNotification() = NtfManager.cancelCallNotification()
      override fun cancelAllNotifications() = NtfManager.cancelAllNotifications()
      override fun showMessage(title: String, text: String) = NtfManager.showMessage(title, text)
    }
    platform = object : PlatformInterface {
      override suspend fun androidServiceStart() {
        ZeroService.start()
      }

      override fun androidServiceSafeStop() {
        ZeroService.safeStopService()
      }

      override fun androidCallServiceSafeStop() {
        CallService.stopService()
      }

      override fun androidNotificationsModeChanged(mode: NotificationsMode) {
        if (mode.requiresIgnoringBattery && !ZeroService.isBackgroundAllowed()) {
          appPrefs.backgroundServiceNoticeShown.set(false)
        }
        ZeroService.StartReceiver.toggleReceiver(mode == NotificationsMode.SERVICE)
        ZeroService.AppUpdateReceiver.toggleReceiver(mode == NotificationsMode.SERVICE)
        CoroutineScope(Dispatchers.Default).launch {
          if (mode == NotificationsMode.SERVICE) {
            ZeroService.start()
            delay(2000)
            if (!ZeroService.isServiceStarted && appPrefs.notificationsMode.get() == NotificationsMode.SERVICE) {
              Log.i(TAG, "Service tried to start but destroyed by system, repeating once more")
              ZeroService.start()
            }
          } else {
            ZeroService.safeStopService()
          }
        }
        if (mode != NotificationsMode.SERVICE) {
          getWorkManagerInstance().cancelUniqueWork(ZeroService.SERVICE_START_WORKER_WORK_NAME_PERIODIC)
        }
        if (mode != NotificationsMode.PERIODIC) {
          MessagesFetcherWorker.cancelAll()
        }
        ZeroService.showBackgroundServiceNoticeIfNeeded(showOffAlert = false)
      }

      override fun androidChatStartedAfterBeingOff() {
        ZeroService.cancelPassphraseNotification()
        when (appPrefs.notificationsMode.get()) {
          NotificationsMode.SERVICE -> CoroutineScope(Dispatchers.Default).launch { platform.androidServiceStart() }
          NotificationsMode.PERIODIC -> ZeroApp.context.schedulePeriodicWakeUp()
          NotificationsMode.OFF -> {}
        }
      }

      override fun androidChatStopped() {
        getWorkManagerInstance().cancelUniqueWork(ZeroService.SERVICE_START_WORKER_WORK_NAME_PERIODIC)
        ZeroService.safeStopService()
        MessagesFetcherWorker.cancelAll()
      }

      override fun androidChatInitializedAndStarted() {
        if (chatModel.controller.appPrefs.onboardingStage.get() == OnboardingStage.OnboardingComplete) {
          ZeroService.showBackgroundServiceNoticeIfNeeded()
          if (appPrefs.notificationsMode.get() == NotificationsMode.SERVICE)
            withBGApi {
              platform.androidServiceStart()
            }
        }
      }

      override fun androidIsBackgroundCallAllowed(): Boolean = !ZeroService.isBackgroundRestricted()

      override fun androidSetNightModeIfSupported() {
        if (Build.VERSION.SDK_INT < 31) return
        val light = if (CurrentColors.value.name == DefaultTheme.SYSTEM_THEME_NAME) {
          null
        } else {
          CurrentColors.value.colors.isLight
        }
        val mode = when (light) {
          null -> UiModeManager.MODE_NIGHT_AUTO
          true -> UiModeManager.MODE_NIGHT_NO
          false -> UiModeManager.MODE_NIGHT_YES
        }
        val uiModeManager = androidAppContext.getSystemService(UI_MODE_SERVICE) as UiModeManager
        uiModeManager.setApplicationNightMode(mode)
      }

      override fun androidSetStatusAndNavigationBarAppearance(isLightStatusBar: Boolean, isLightNavBar: Boolean, blackNavBar: Boolean, themeBackgroundColor: Color) {
        val window = mainActivity.get()?.window ?: return
        @Suppress("DEPRECATION")
        val statusLight = isLightStatusBar && chatModel.activeCall.value == null
        val navBarLight = isLightNavBar || windowOrientation() == WindowOrientation.LANDSCAPE
        val windowInsetController = ViewCompat.getWindowInsetsController(window.decorView)
        if (windowInsetController?.isAppearanceLightStatusBars != statusLight) {
          windowInsetController?.isAppearanceLightStatusBars = statusLight
        }
        window.navigationBarColor = Color.Transparent.toArgb()
        if (windowInsetController?.isAppearanceLightNavigationBars != navBarLight) {
          windowInsetController?.isAppearanceLightNavigationBars = navBarLight
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
          window.decorView.systemUiVisibility = if (statusLight && navBarLight) {
            View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR or OLD_ANDROID_UI_FLAGS
          } else if (statusLight) {
            View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or OLD_ANDROID_UI_FLAGS
          } else if (navBarLight) {
            View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR or OLD_ANDROID_UI_FLAGS
          } else {
            OLD_ANDROID_UI_FLAGS
          }
          window.navigationBarColor = if (blackNavBar) Color.Black.toArgb() else themeBackgroundColor.toArgb()
        } else {
          window.navigationBarColor = Color.Transparent.toArgb()
        }
      }

      override fun androidStartCallActivity(acceptCall: Boolean, remoteHostId: Long?, chatId: ChatId?) {
        val context = mainActivity.get() ?: return
        val intent = Intent(context, CallActivity::class.java)
          .addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
        if (acceptCall) {
          intent.setAction(AcceptCallAction)
            .putExtra("remoteHostId", remoteHostId)
            .putExtra("chatId", chatId)
        }
        intent.flags += Intent.FLAG_ACTIVITY_BROUGHT_TO_FRONT
        context.startActivity(intent)
      }

      override fun androidPictureInPictureAllowed(): Boolean {
        val appOps = androidAppContext.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        return appOps.checkOpNoThrow(AppOpsManager.OPSTR_PICTURE_IN_PICTURE, Process.myUid(), packageName) == AppOpsManager.MODE_ALLOWED
      }

      override fun androidCallEnded() {
        activeCallDestroyWebView()
      }

      override fun androidRestartNetworkObserver() {
        NetworkObserver.shared.restartNetworkObserver()
      }

      override fun androidIsXiaomiDevice(): Boolean = setOf("xiaomi", "redmi", "poco").contains(Build.BRAND.lowercase())

      override fun androidLoadPlayStoreCountry() = loadPlayStoreCountry()

      @SuppressLint("SourceLockedOrientationActivity")
      @Composable
      override fun androidLockPortraitOrientation() {
        val context = LocalContext.current
        DisposableEffect(Unit) {
          val activity = context as? Activity ?: return@DisposableEffect onDispose {}
          activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
          onDispose {
            activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
          }
        }
      }

      override suspend fun androidAskToAllowBackgroundCalls(): Boolean {
        if (ZeroService.isBackgroundRestricted()) {
          val userChoice: CompletableDeferred<Boolean> = CompletableDeferred()
          ZeroService.showBGRestrictedInCall {
            userChoice.complete(it)
          }
          return userChoice.await()
        }
        return true
      }

      override fun androidCreateActiveCallState(): Closeable = ActiveCallState()

      override val androidApiLevel: Int get() = Build.VERSION.SDK_INT

      override val androidIsPlayStoreBuild: Boolean get() = BuildConfig.PLAY_STORE
    }
  }

  private fun reconfigureBroadcastReceivers() {
    val mode = appPrefs.notificationsMode.get()
    ZeroService.StartReceiver.toggleReceiver(mode == NotificationsMode.SERVICE)
    ZeroService.AppUpdateReceiver.toggleReceiver(mode == NotificationsMode.SERVICE)}
}
