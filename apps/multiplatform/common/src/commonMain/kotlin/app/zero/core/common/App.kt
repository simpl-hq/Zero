package app.zero.core.common

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.*
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.*
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.dp
import app.zero.core.common.views.usersettings.SetDeliveryReceiptsView
import app.zero.core.common.model.*
import app.zero.core.common.model.ChatController.appPrefs
import app.zero.core.common.platform.*
import app.zero.core.common.ui.theme.*
import app.zero.core.common.views.CreateFirstProfile
import app.zero.core.common.views.helpers.SimpleButton
import app.zero.core.common.views.SplashView
import app.zero.core.common.views.call.*
import app.zero.core.common.views.chat.ChatView
import app.zero.core.common.views.chatlist.*
import app.zero.core.common.views.database.DatabaseErrorView
import app.zero.core.common.views.helpers.*
import app.zero.core.common.views.helpers.ModalManager.Companion.fromEndToStartTransition
import app.zero.core.common.views.helpers.ModalManager.Companion.fromStartToEndTransition
import app.zero.core.common.views.localauth.VerticalDivider
import app.zero.core.common.views.newchat.*
import app.zero.core.common.views.onboarding.*
import app.zero.core.common.views.usersettings.*
import app.zero.core.res.MR
import dev.icerock.moko.resources.compose.painterResource
import dev.icerock.moko.resources.compose.stringResource
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

@Composable
fun AppScreen() {
  AppBarHandler.appBarMaxHeightPx = with(LocalDensity.current) { AppBarHeight.roundToPx() }
  ZeroTheme {
    Surface(color = MaterialTheme.colors.background, contentColor = LocalContentColor.current) {
      val direction = LocalLayoutDirection.current
      val safePadding = WindowInsets.safeDrawing.asPaddingValues()
      val cutout = WindowInsets.displayCutout.asPaddingValues()
      val cutoutStart = cutout.calculateStartPadding(direction)
      val cutoutEnd = cutout.calculateEndPadding(direction)
      val cutoutMax = maxOf(cutoutStart, cutoutEnd)
      val paddingStartUntouched = safePadding.calculateStartPadding(direction)
      val paddingStart = paddingStartUntouched - cutoutStart
      val paddingEndUntouched = safePadding.calculateEndPadding(direction)
      val paddingEnd = paddingEndUntouched - cutoutEnd
      Box {
        val fullscreenGallery = remember { chatModel.fullscreenGalleryVisible }
        Box(Modifier.padding(start = paddingStart + cutoutMax, end = paddingEnd + cutoutMax).consumeWindowInsets(PaddingValues(start = paddingStartUntouched, end = paddingEndUntouched))) {
          Box(Modifier.drawBehind {
            if (fullscreenGallery.value) {
              drawRect(Color.Black,  topLeft = Offset(-(paddingStart + cutoutMax).toPx(), 0f), Size(size.width + (paddingStart + cutoutMax).toPx() + (paddingEnd + cutoutMax).toPx(), size.height))
            }
          }) {
            MainScreen()
          }
        }
      }
    }
  }
}

@Composable
fun MainScreen() {
  val chatModel = ChatModel
  var showChatDatabaseError by rememberSaveable {
    mutableStateOf(chatModel.chatDbStatus.value != DBMigrationResult.OK && chatModel.chatDbStatus.value != null)
  }
  LaunchedEffect(chatModel.chatDbStatus.value) {
    showChatDatabaseError = chatModel.chatDbStatus.value != DBMigrationResult.OK && chatModel.chatDbStatus.value != null
  }
  var showAdvertiseLAAlert by remember { mutableStateOf(false) }
  LaunchedEffect(showAdvertiseLAAlert) {
    if (
      !chatModel.controller.appPrefs.laNoticeShown.get()
      && !appPrefs.performLA.get()
      && showAdvertiseLAAlert
      && chatModel.controller.appPrefs.onboardingStage.get() == OnboardingStage.OnboardingComplete
      && chatModel.chats.size > 3
      && chatModel.activeCallInvitation.value == null
    ) {
      AppLock.showLANotice(ChatModel.controller.appPrefs.laNoticeShown) }
  }
  LaunchedEffect(chatModel.showAdvertiseLAUnavailableAlert.value) {
    if (chatModel.showAdvertiseLAUnavailableAlert.value) {
      laUnavailableInstructionAlert()
    }
  }
  platform.desktopShowAppUpdateNotice()
  LaunchedEffect(chatModel.clearOverlays.value) {
    if (chatModel.clearOverlays.value) {
      ModalManager.closeAllModalsEverywhere()
      chatModel.clearOverlays.value = false
    }
  }

  @Composable
  fun AuthView() {
    Surface(color = MaterialTheme.colors.background.copy(1f), contentColor = LocalContentColor.current) {
      Box(
        Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
      ) {
        SimpleButton(
          stringResource(MR.strings.auth_unlock),
          icon = painterResource(MR.images.ic_lock),
          click = {
            AppLock.laFailed.value = false
            AppLock.runAuthenticate()
          }
        )
      }
    }
  }

  Box {
    val unauthorized = remember { derivedStateOf { AppLock.userAuthorized.value != true } }
    val onboarding by remember { chatModel.controller.appPrefs.onboardingStage.state }
    val localUserCreated = chatModel.localUserCreated.value
    var showInitializationView by remember { mutableStateOf(false) }
    when {
      onboarding == OnboardingStage.Step1_ZeroInfo && chatModel.migrationState.value != null -> {
        if (appPlatform.isDesktop) DesktopOnboarding(onboarding, chatModel)
        else ZeroInfo(chatModel, onboarding = true)
      }
      chatModel.dbMigrationInProgress.value -> DefaultProgressView(stringResource(MR.strings.database_migration_in_progress))
      chatModel.chatDbStatus.value == null && showInitializationView -> DefaultProgressView(stringResource(MR.strings.opening_database))
      showChatDatabaseError -> {
        if (!unauthorized.value && chatModel.chatDbStatus.value != null) {
          DatabaseErrorView(chatModel.chatDbStatus, chatModel.controller.appPrefs)
        }
      }
      remember { chatModel.chatDbEncrypted }.value == null || localUserCreated == null -> SplashView()
      onboarding == OnboardingStage.OnboardingComplete -> {
        Box {
          showAdvertiseLAAlert = true
          val userPickerState by rememberSaveable(stateSaver = AnimatedViewState.saver()) { mutableStateOf(MutableStateFlow(if (chatModel.desktopNoUserNoRemote()) AnimatedViewState.VISIBLE else AnimatedViewState.GONE)) }
          KeyChangeEffect(chatModel.desktopNoUserNoRemote) {
            if (chatModel.desktopNoUserNoRemote() && !ModalManager.start.hasModalsOpen()) {
              userPickerState.value = AnimatedViewState.VISIBLE
            }
          }
          if (appPlatform.isAndroid) {
            AndroidWrapInCallLayout {
              AndroidScreen(userPickerState)
            }
          } else {
            DesktopScreen(userPickerState)
          }
        }
      }
      else -> {
        if (appPlatform.isDesktop) {
          DesktopOnboarding(onboarding, chatModel)
        } else {
          AnimatedContent(targetState = onboarding,
            transitionSpec = {
              if (targetState > initialState) {
                fromEndToStartTransition()
              } else {
                fromStartToEndTransition()
              }.using(SizeTransform(clip = false))
            }
          ) { state ->
            when (state) {
              OnboardingStage.OnboardingComplete -> {}
              OnboardingStage.LinkAMobile -> LinkAMobile()
              else -> ZeroInfo(chatModel, onboarding = true)
            }
          }
        }
      }
    }
    if (appPlatform.isAndroid) {
      AndroidWrapInCallLayout {
        ModalManager.fullscreen.showInView()
      }
      SwitchingUsersView()
    }

    if (unauthorized.value && !(chatModel.activeCallViewIsVisible.value && chatModel.showCallView.value)) {
      LaunchedEffect(Unit) {
        if (!(androidIsFinishingMainActivity() && chatModel.controller.appPrefs.laMode.get() == LAMode.SYSTEM)) {
          AppLock.runAuthenticate()
        }
      }
      if (chatModel.controller.appPrefs.performLA.get() && AppLock.laFailed.value) {
        AuthView()
      } else {
        SplashView(true)
        ModalManager.fullscreen.showPasscodeInView()
      }
    } else {
      if (chatModel.showCallView.value) {
        if (appPlatform.isAndroid) {
          LaunchedEffect(Unit) {
            if (!chatModel.activeCallViewIsCollapsed.value) {
              platform.androidStartCallActivity(false)
            }
          }
        } else {
          ActiveCallView()
        }
      }
      ModalManager.fullscreen.showOneTimePasscodeInView()
      AlertManager.privacySensitive.showInView()
      if (onboarding == OnboardingStage.OnboardingComplete) {
        LaunchedEffect(chatModel.chatRunning.value, chatModel.currentUser.value, chatModel.appOpenUrl.value) {
          val (rhId, url) = chatModel.appOpenUrl.value ?: (null to null)
          if (url != null && chatModel.chatRunning.value == true) {
            chatModel.appOpenUrl.value = null
            connectIfOpenedViaUri(rhId, url, chatModel)
          }
        }
      }
    }
    val invitation = chatModel.activeCallInvitation.value
    if (invitation != null) IncomingCallAlertView(invitation, chatModel)
    AlertManager.shared.showInView()

    LaunchedEffect(Unit) {
      delay(1000)
      if (chatModel.chatDbStatus.value == null) {
        showInitializationView = true
      }
    }
  }

  DisposableEffectOnRotate {
    if (chatModel.controller.appPrefs.laLockDelay.get() == 0) {
      AppLock.enteredBackground.value = AppLock.elapsedRealtime() + 3000
    }
  }
}

@Composable
private fun DesktopOnboarding(onboarding: OnboardingStage, chatModel: ChatModel) {
  if (onboarding == OnboardingStage.LinkAMobile) {
    LinkAMobile()
    ModalManager.fullscreen.showInView()
  } else {
    DesktopOnboardingShell(onboarding) {
      when (onboarding) {
        OnboardingStage.OnboardingComplete -> {}
        else -> ZeroInfo(chatModel, onboarding = true)
      }
    }
  }
}

val ANDROID_CALL_TOP_PADDING = 40.dp

@Composable
fun AndroidWrapInCallLayout(content: @Composable () -> Unit) {
  val call = remember { chatModel.activeCall}.value
  val showCallArea = call != null && call.callState != CallState.WaitCapabilities && call.callState != CallState.InvitationAccepted
  Box {
    Box(Modifier.padding(top = if (showCallArea) ANDROID_CALL_TOP_PADDING else 0.dp)) {
      content()
    }
    if (call != null && showCallArea) {
      ActiveCallInteractiveArea(call)
    }
  }
}

@Composable
fun AndroidScreen(userPickerState: MutableStateFlow<AnimatedViewState>) {
  BoxWithConstraints {
    val currentChatId = remember { mutableStateOf(chatModel.chatId.value) }
    val offset = remember { Animatable(if (chatModel.chatId.value == null) 0f else maxWidth.value) }
    val cutout = WindowInsets.displayCutout.only(WindowInsetsSides.Horizontal).asPaddingValues()
    val direction = LocalLayoutDirection.current
    val hasCutout = cutout.calculateStartPadding(direction) + cutout.calculateEndPadding(direction) > 0.dp
    Box(
      Modifier
        .then(if (hasCutout) Modifier.clip(RectangleShape) else Modifier)
        .graphicsLayer {
          translationX = -minOf(offset.value.dp, maxWidth).toPx()
        }
    ) {
      StartPartOfScreen(userPickerState)
    }
    val scope = rememberCoroutineScope()
    val onComposed: suspend (chatId: String?) -> Unit = { chatId ->
      scope.launch {
        offset.animateTo(
          if (chatId == null) 0f else maxWidth.value,
          chatListAnimationSpec()
        )
      }.join()
    }
    LaunchedEffect(Unit) {
      launch {
        snapshotFlow { chatModel.chatId.value }
          .distinctUntilChanged()
          .collect {
            if (it == null) onComposed(null)
            currentChatId.value = it
          }
      }
    }
    Box(Modifier
      .then(if (hasCutout) Modifier.clip(RectangleShape) else Modifier)
      .graphicsLayer { translationX = maxWidth.toPx() - minOf(offset.value.dp, maxWidth).toPx() }
    ) Box2@{
      currentChatId.value?.let {
        ChatView(chatsCtx = chatModel.chatsContext, currentChatId, onComposed = onComposed)
      }
    }
  }
}

@Composable
fun StartPartOfScreen(userPickerState: MutableStateFlow<AnimatedViewState>) {
  if (chatModel.setDeliveryReceipts.value) {
    CompositionLocalProvider(LocalAppBarHandler provides rememberAppBarHandler()) {
      SetDeliveryReceiptsView(chatModel)
    }
  } else {
    val stopped = chatModel.chatRunning.value == false
    if (chatModel.sharedContent.value == null) {
      CompositionLocalProvider(LocalAppBarHandler provides rememberAppBarHandler()) {
        ChatListView(chatModel, userPickerState, AppLock::setPerformLA, stopped)
      }
    } else {
      CompositionLocalProvider(LocalAppBarHandler provides rememberAppBarHandler(keyboardCoversBar = false)) {
        ShareListView(chatModel, stopped)
      }
    }
  }
}

@Composable
fun CenterPartOfScreen() {
  val currentChatId = remember { ChatModel.chatId }
  LaunchedEffect(Unit) {
    snapshotFlow { currentChatId.value }
      .distinctUntilChanged()
      .collect {
        if (it != null) {
          ModalManager.center.closeModals()
        }
      }
  }
  when (currentChatId.value) {
    null -> {
      if (rememberUpdatedState(ModalManager.center.hasModalsOpen()).value) {
        ModalManager.center.showInView()
      } else if (shouldShowOnboarding()) {
        ConnectOnboardingView()
      } else {
        Box(
          Modifier
            .fillMaxSize()
            .background(MaterialTheme.colors.background),
          contentAlignment = Alignment.Center
        ) {
          Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
          ) {
            Image(
              painterResource(if (isInDarkTheme()) MR.images.logo_light else MR.images.logo),
              contentDescription = "Zero",
              contentScale = ContentScale.Fit,
              modifier = Modifier.height(34.dp)
            )
            Text(
              stringResource(if (chatModel.desktopNoUserNoRemote) MR.strings.no_connected_mobile else MR.strings.no_selected_chat),
              color = MaterialTheme.colors.secondary
            )
            OutlinedButton(
              onClick = { openZeroGuidedTutorial(allowSettingsShortcuts = true) },
              shape = RoundedCornerShape(999.dp),
              border = BorderStroke(1.dp, MaterialTheme.colors.secondary.copy(alpha = 0.35f))
            ) {
              Text("Open Setup & Quick Guide")
            }
          }
        }
      }
    }
    else -> ChatView(chatsCtx = chatModel.chatsContext, currentChatId) {}
  }
}

@Composable
fun EndPartOfScreen() {
  ModalManager.end.showInView()
}

@Composable
fun DesktopScreen(userPickerState: MutableStateFlow<AnimatedViewState>) {
  Box(Modifier.width(DEFAULT_START_MODAL_WIDTH * fontSizeSqrtMultiplier)) {
    StartPartOfScreen(userPickerState)
    tryOrShowError("UserPicker", error = {}) {
      UserPicker(chatModel, userPickerState, setPerformLA = AppLock::setPerformLA)
    }
  }
  Box(Modifier.widthIn(max = DEFAULT_START_MODAL_WIDTH * fontSizeSqrtMultiplier)) {
    ModalManager.start.showInView()
    SwitchingUsersView()
  }
  Row(Modifier.padding(start = DEFAULT_START_MODAL_WIDTH * fontSizeSqrtMultiplier).clipToBounds()) {
    Box(Modifier.widthIn(min = DEFAULT_MIN_CENTER_MODAL_WIDTH).weight(1f)) {
      CenterPartOfScreen()
    }
    if (ModalManager.end.hasModalsOpen()) {
      VerticalDivider()
    }
    Box(Modifier.widthIn(max = DEFAULT_END_MODAL_WIDTH * fontSizeSqrtMultiplier).clipToBounds()) {
      EndPartOfScreen()
    }
  }
  if (userPickerState.collectAsState().value.isVisible() || (ModalManager.start.hasModalsOpen && !ModalManager.center.hasModalsOpen)) {
    Box(
      Modifier
        .fillMaxSize()
        .padding(start = DEFAULT_START_MODAL_WIDTH * fontSizeSqrtMultiplier)
        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = {
          if (chatModel.centerPanelBackgroundClickHandler == null || chatModel.centerPanelBackgroundClickHandler?.invoke() == false) {
            ModalManager.start.closeModals()
            userPickerState.value = AnimatedViewState.HIDING
          }
        })
    )
  }
  VerticalDivider(Modifier.padding(start = DEFAULT_START_MODAL_WIDTH * fontSizeSqrtMultiplier))
  ModalManager.fullscreen.showInView()
}

@Composable
private fun SwitchingUsersView() {
  if (remember { chatModel.switchingUsersAndHosts }.value) {
    Box(
      Modifier.fillMaxSize().clickable(enabled = false, onClick = {}),
      contentAlignment = Alignment.Center
    ) {
      ProgressIndicator()
    }
  }
}

@Composable
private fun ProgressIndicator() {
  CircularProgressIndicator(
    Modifier
      .padding(horizontal = 2.dp)
      .size(30.dp),
    color = MaterialTheme.colors.secondary,
    strokeWidth = 2.5.dp
  )
}
