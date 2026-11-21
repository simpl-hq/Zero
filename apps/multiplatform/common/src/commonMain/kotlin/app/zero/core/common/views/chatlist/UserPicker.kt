package app.zero.core.common.views.chatlist

import SectionItemView
import TextIconSpaced
import androidx.compose.foundation.*
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.*
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.draw.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import dev.icerock.moko.resources.compose.painterResource
import androidx.compose.ui.text.capitalize
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.intl.Locale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import app.zero.core.common.model.*
import app.zero.core.common.model.ChatController.appPrefs
import app.zero.core.common.model.ChatController.stopRemoteHostAndReloadHosts
import app.zero.core.common.model.ChatModel.controller
import app.zero.core.common.ui.theme.*
import app.zero.core.common.views.helpers.*
import app.zero.core.common.platform.*
import app.zero.core.common.views.CreateProfile
import app.zero.core.common.views.localauth.VerticalDivider
import app.zero.core.common.views.remote.*
import app.zero.core.common.views.usersettings.*
import app.zero.core.common.views.usersettings.AppearanceScope.ColorModeSwitcher
import app.zero.core.res.MR
import dev.icerock.moko.resources.compose.stringResource
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlin.random.Random

private val USER_PICKER_SECTION_SPACING = 32.dp

@Composable
fun UserPicker(
  chatModel: ChatModel,
  userPickerState: MutableStateFlow<AnimatedViewState>,
  setPerformLA: (Boolean) -> Unit,
) {
  var newChat by remember { mutableStateOf(userPickerState.value) }
  if (newChat.isVisible()) {
    BackHandler {
      userPickerState.value = AnimatedViewState.HIDING
    }
  }
  val users by remember {
    derivedStateOf {
      chatModel.users
        .filter { u -> u.user.activeUser || !u.user.hidden }
        .sortedByDescending { it.user.activeOrder }
    }
  }
  val remoteHosts by remember {
    derivedStateOf {
      chatModel.remoteHosts
        .sortedBy { it.hostDeviceName }
    }
  }

  val view = LocalMultiplatformView()
  LaunchedEffect(Unit) {
    launch {
      userPickerState.collect {
        newChat = it
        if (it.isVisible()) {
          hideKeyboard(view)
        }
        launch {
          if (newChat.isHiding()) userPickerState.value = AnimatedViewState.GONE
        }
      }
    }
  }

  LaunchedEffect(Unit) {
    launch {
      snapshotFlow { ModalManager.start.modalCount.value }
        .filter { it > 0 }
        .collect {
          closePicker(userPickerState)
        }
    }
  }

  LaunchedEffect(Unit) {
    snapshotFlow { newChat.isVisible() }
      .distinctUntilChanged()
      .filter { it }
      .collect {
        try {
          val updatedUsers = chatModel.controller.listUsers(chatModel.remoteHostId()).sortedByDescending { it.user.activeUser }
          var same = users.size == updatedUsers.size
          if (same) {
            for (i in 0 until minOf(users.size, updatedUsers.size)) {
              val prev = updatedUsers[i].user
              val next = users[i].user
              if (prev.userId != next.userId || prev.activeUser != next.activeUser || prev.chatViewName != next.chatViewName || prev.image != next.image) {
                same = false
                break
              }
            }
          }
          if (!same) {
            chatModel.users.clear()
            chatModel.users.addAll(updatedUsers)
          }
        } catch (e: Exception) {
          Log.e(TAG, "Error updating users ${e.stackTraceToString()}")
        }
        if (!appPlatform.isDesktop) return@collect
        try {
          val updatedHosts = chatModel.controller.listRemoteHosts()?.sortedBy { it.hostDeviceName } ?: emptyList()
          if (remoteHosts != updatedHosts) {
            chatModel.remoteHosts.clear()
            chatModel.remoteHosts.addAll(updatedHosts)
          }
        } catch (e: Exception) {
          Log.e(TAG, "Error updating remote hosts ${e.stackTraceToString()}")
        }
      }
  }
  LaunchedEffect(Unit) {
    if (controller.hasChatCtrl()) {
      withBGApi {
        controller.reloadRemoteHosts()
      }
    }
  }

  val oneHandUI = remember { appPrefs.oneHandUI.state }
  val iconColor = MaterialTheme.colors.secondaryVariant
  val background = if (appPlatform.isAndroid) MaterialTheme.colors.background.mixWith(MaterialTheme.colors.onBackground, alpha = 1 - userPickerAlpha()) else MaterialTheme.colors.surface
  PlatformUserPicker(
    modifier = Modifier
      .height(IntrinsicSize.Min)
      .fillMaxWidth()
      .then(if (newChat.isVisible()) Modifier.shadow(8.dp, clip = true, ambientColor = background) else Modifier)
      .padding(top = if (appPlatform.isDesktop && oneHandUI.value) 7.dp else 0.dp)
      .background(background)
      .padding(bottom = USER_PICKER_SECTION_SPACING - DEFAULT_MIN_SECTION_ITEM_PADDING_VERTICAL),
    pickerState = userPickerState
  ) {
    val showCustomModal: (@Composable() (ModalData.(ChatModel, () -> Unit) -> Unit)) -> () -> Unit = { modalView ->
      {
        ModalManager.start.showCustomModal { close -> modalView(chatModel, close) }
      }
    }
    val stopped = remember { chatModel.chatRunning }.value == false
    val onUserClicked: (user: User) -> Unit = { user ->
      if (!user.activeUser) {
        userPickerState.value = AnimatedViewState.HIDING
        withBGApi {
          controller.showProgressIfNeeded {
            ModalManager.closeAllModalsEverywhere()
            chatModel.controller.changeActiveUser(user.remoteHostId, user.userId, null)
          }
        }
      } else {
        showCustomModal { chatModel, close -> UserProfileView(chatModel, close) }()
        withBGApi {
          closePicker(userPickerState)
        }
      }
    }

    @Composable
    fun FirstSection() {
      if (remoteHosts.isNotEmpty()) {
        val currentRemoteHost = remember { chatModel.currentRemoteHost }.value
        val localDeviceActive = currentRemoteHost == null && chatModel.localUserCreated.value == true

        DevicePickerRow(
          localDeviceActive = localDeviceActive,
          remoteHosts = remoteHosts,
          onRemoteHostClick = { h, connecting ->
            userPickerState.value = AnimatedViewState.HIDING
            switchToRemoteHost(h, connecting)
          },
          onLocalDeviceClick = {
            userPickerState.value = AnimatedViewState.HIDING
            switchToLocalDevice()
          },
          onRemoteHostActionButtonClick = { h ->
            userPickerState.value = AnimatedViewState.HIDING
            stopRemoteHostAndReloadHosts(h, true)
          }
        )
      }
      val currentUser = remember { chatModel.currentUser }.value
      if (currentUser != null) {
        SectionItemView({ onUserClicked(currentUser) }, 80.dp, padding = PaddingValues(start = 16.dp, end = DEFAULT_PADDING), disabled = stopped) {
          ProfilePreview(currentUser.profile, iconColor = iconColor, stopped = stopped, badge = currentUser.profile.localBadge)
        }
      }
    }

    @Composable
    fun SecondSection() {
      UserPickerOptionRow(
        painterResource(MR.images.ic_qr_code),
        if (chatModel.userAddress.value != null) generalGetString(MR.strings.your_zero_contact_address) else generalGetString(MR.strings.create_zero_address),
        showCustomModal { it, close -> UserAddressView(it, shareViaProfile = it.currentUser.value!!.addressShared, close = close) }, disabled = stopped
      )
      UserPickerOptionRow(
        painterResource(MR.images.ic_toggle_on),
        stringResource(MR.strings.chat_preferences),
        click = if (stopped) null else ({
          showCustomModal { m, close ->
            PreferencesView(m, m.currentUser.value ?: return@showCustomModal, close)
          }()
        }),
        disabled = stopped
      )
      val currentUser = remember { chatModel.currentUser }.value
      val parentUserId = remember(currentUser?.userId) { DatabaseUtils.ksDisposableParentUserId.get()?.toLongOrNull() }
      val hasDisposableParent = parentUserId != null && currentUser != null && currentUser.userId != parentUserId && users.any { it.user.userId == parentUserId }
      if (hasDisposableParent && parentUserId != null) {
        UserPickerOptionRow(
          painterResource(MR.images.ic_delete_forever),
          "Burn identity",
          click = {
            AlertManager.shared.showAlertDialog(
              title = "Burn identity?",
              text = "This burner identity, its chats, and its address will be permanently deleted, and you will return to your main identity.",
              confirmText = "Burn",
              onConfirm = {
                userPickerState.value = AnimatedViewState.HIDING
                burnDisposableIdentity(chatModel, parentUserId)
              },
              destructive = true
            )
          },
          disabled = stopped,
          iconTint = MaterialTheme.colors.error,
          textColor = MaterialTheme.colors.error,
        )
      }
      if (!chatModel.desktopNoUserNoRemote && currentUser != null) {
        UserPickerOptionRow(
          painterResource(MR.images.ic_refresh),
          "New identity",
          click = {
            showNewIdentityDialog(chatModel, userPickerState)
          },
          disabled = stopped
        )
      }
    }

    if (appPlatform.isDesktop || windowOrientation() == WindowOrientation.PORTRAIT) {
      Column {
        FirstSection()
        SecondSection()
        GlobalSettingsSection(
          userPickerState = userPickerState,
          setPerformLA = setPerformLA,
        )
      }
    } else {
      Column {
        FirstSection()
        Row {
          Box(Modifier.weight(1f)) {
            Column {
              SecondSection()
            }
          }
          VerticalDivider()
          Box(Modifier.weight(1f)) {
            Column {
              GlobalSettingsSection(
                userPickerState = userPickerState,
                setPerformLA = setPerformLA,
              )
            }
          }
        }
      }
    }
  }
}

fun userPickerAlpha(): Float {
  return when (CurrentColors.value.base) {
    DefaultTheme.LIGHT -> 0.05f
    DefaultTheme.DARK -> 0.05f
    DefaultTheme.BLACK -> 0.075f
    DefaultTheme.ZERO -> 0.035f
  }
}

@Composable
private fun GlobalSettingsSection(
  userPickerState: MutableStateFlow<AnimatedViewState>,
  setPerformLA: (Boolean) -> Unit,
) {
  val stopped = remember { chatModel.chatRunning }.value == false

  if (appPlatform.isAndroid) {
    val text = generalGetString(MR.strings.settings_section_title_use_from_desktop).lowercase().capitalize(Locale.current)

    UserPickerOptionRow(
      painterResource(MR.images.ic_desktop),
      text,
      click = {
        ModalManager.start.showCustomModal { close ->
          ConnectDesktopView(close)
        }
      },
      disabled = stopped
    )
  } else {
    UserPickerOptionRow(
      icon = painterResource(MR.images.ic_smartphone_300),
      text = stringResource(if (remember { app.zero.core.common.platform.chatModel.remoteHosts }.isEmpty()) MR.strings.link_a_mobile else MR.strings.linked_mobiles),
      click = {
        userPickerState.value = AnimatedViewState.HIDING
        ModalManager.start.showModal {
          ConnectMobileView()
        }
      },
      disabled = stopped
    )
  }

  SectionItemView(
    click = {
      ModalManager.start.showModalCloseable(cardScreen = true) { close ->
        SettingsView(chatModel, setPerformLA, close)
      }
    },
    padding = if (appPlatform.isDesktop) PaddingValues(start = DEFAULT_PADDING * 1.7f, end = DEFAULT_PADDING + 2.dp) else PaddingValues(start = DEFAULT_PADDING, end = DEFAULT_PADDING_HALF)
  ) {
    val text = generalGetString(MR.strings.settings_section_title_settings).lowercase().capitalize(Locale.current)
    Icon(painterResource(MR.images.ic_settings), text, tint = MaterialTheme.colors.secondary)
    TextIconSpaced()
    Text(text, color = Color.Unspecified)
    Spacer(Modifier.weight(1f))
    ColorModeSwitcher()
  }
}

@Composable
fun UserProfilePickerItem(
  u: User,
  unreadCount: Int = 0,
  enabled: Boolean = remember { chatModel.chatRunning }.value == true || chatModel.connectedToRemote,
  onLongClick: () -> Unit = {},
  openSettings: () -> Unit = {},
  onClick: () -> Unit
) {
  Row(
    Modifier
      .fillMaxWidth()
      .sizeIn(minHeight = DEFAULT_MIN_SECTION_ITEM_HEIGHT)
      .combinedClickable(
        enabled = enabled,
        onClick = if (u.activeUser) openSettings else onClick,
        onLongClick = onLongClick,
        interactionSource = remember { MutableInteractionSource() },
        indication = if (!u.activeUser) LocalIndication.current else null
      )
      .onRightClick { if (enabled) onLongClick() }
      .padding(start = DEFAULT_PADDING_HALF, end = DEFAULT_PADDING),
    horizontalArrangement = Arrangement.SpaceBetween,
    verticalAlignment = Alignment.CenterVertically
  ) {
    UserProfileRow(u, enabled)
    if (u.activeUser) {
      Icon(painterResource(MR.images.ic_done_filled), null, Modifier.size(20.dp), tint = MaterialTheme.colors.onBackground)
    } else {
      Row(verticalAlignment = Alignment.CenterVertically) {
        if (unreadCount > 0) {
          val badgeBg = if (u.showNtfs) MaterialTheme.colors.primaryVariant else MaterialTheme.colors.secondary
          Box(
            contentAlignment = Alignment.Center,
          ) {
            Text(
              unreadCountStr(unreadCount),
              color = badgeBg.onSurfaceInk(),
              fontSize = 10.sp,
              fontWeight = FontWeight.SemiBold,
              modifier = Modifier
                .background(badgeBg, shape = CircleShape)
                .padding(2.dp)
                .badgeLayout()
            )
          }

          if (u.hidden) {
            Spacer(Modifier.width(8.dp))
            Icon(painterResource(MR.images.ic_lock), null, Modifier.size(20.dp), tint = MaterialTheme.colors.secondary)
          }
        } else if (u.hidden) {
          Icon(painterResource(MR.images.ic_lock), null, Modifier.size(20.dp), tint = MaterialTheme.colors.secondary)
        } else if (!u.showNtfs) {
          Icon(painterResource(MR.images.ic_notifications_off), null, Modifier.size(20.dp), tint = MaterialTheme.colors.secondary)
        } else {
          Box(Modifier.size(20.dp))
        }
      }
    }
  }
}

@Composable
fun UserProfileRow(u: User, enabled: Boolean = remember { chatModel.chatRunning }.value == true || chatModel.connectedToRemote) {
  Row(
    Modifier
      .widthIn(max = windowWidth() * 0.7f)
      .padding(vertical = 8.dp),
    verticalAlignment = Alignment.CenterVertically
  ) {
    ProfileImage(
      image = u.image,
      size = 54.dp * fontSizeSqrtMultiplier
    )
    NameWithBadge(
      u.displayName,
      u.profile.localBadge,
      Modifier.padding(start = 10.dp, end = 8.dp),
      color = if (enabled) MenuTextColor else MaterialTheme.colors.secondary,
      fontWeight = if (u.activeUser) FontWeight.Medium else FontWeight.Normal
    )
  }
}

@Composable
fun UserPickerOptionRow(
  icon: Painter,
  text: String,
  click: (() -> Unit)? = null,
  disabled: Boolean = false,
  iconTint: Color? = null,
  textColor: Color? = null,
) {
  SectionItemView(click, disabled = disabled, extraPadding = appPlatform.isDesktop) {
    Icon(icon, text, tint = if (disabled) MaterialTheme.colors.secondary else (iconTint ?: MaterialTheme.colors.secondary))
    TextIconSpaced()
    Text(text = text, color = if (disabled) MaterialTheme.colors.secondary else (textColor ?: Color.Unspecified))
  }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DevicePickerRow(
  localDeviceActive: Boolean,
  remoteHosts: List<RemoteHostInfo>,
  onLocalDeviceClick: () -> Unit,
  onRemoteHostClick: (rh: RemoteHostInfo, connecting: MutableState<Boolean>) -> Unit,
  onRemoteHostActionButtonClick: (rh: RemoteHostInfo) -> Unit,
) {
  FlowRow(
    Modifier
      .fillMaxWidth()
      .sizeIn(minHeight = DEFAULT_MIN_SECTION_ITEM_HEIGHT)
      .padding(start = DEFAULT_PADDING, end = DEFAULT_PADDING, bottom = DEFAULT_PADDING, top = DEFAULT_PADDING + DEFAULT_MIN_SECTION_ITEM_PADDING_VERTICAL),
    horizontalArrangement = Arrangement.spacedBy(12.dp),
    verticalArrangement = Arrangement.spacedBy(12.dp)
  ) {
    val activeHost = remoteHosts.firstOrNull { h -> h.activeHost }

    if (activeHost != null) {
      val connecting = rememberSaveable { mutableStateOf(false) }

      DevicePill(
        active = true,
        icon = painterResource(MR.images.ic_smartphone_300),
        text = activeHost.hostDeviceName,
        actionButtonVisible = activeHost.sessionState is RemoteHostSessionState.Connected,
        onActionButtonClick = { onRemoteHostActionButtonClick(activeHost) }
      ) {
        onRemoteHostClick(activeHost, connecting)
      }
    }

    DevicePill(
      active = localDeviceActive,
      icon = painterResource(MR.images.ic_desktop),
      text = stringResource(MR.strings.this_device),
      actionButtonVisible = false
    ) {
      onLocalDeviceClick()
    }

    remoteHosts.filter { h -> h.sessionState is RemoteHostSessionState.Connected && !h.activeHost }.forEach { h ->
      val connecting = rememberSaveable { mutableStateOf(false) }

      DevicePill(
        active = h.activeHost,
        icon = painterResource(MR.images.ic_smartphone_300),
        text = h.hostDeviceName,
        actionButtonVisible = h.sessionState is RemoteHostSessionState.Connected,
        onActionButtonClick = { onRemoteHostActionButtonClick(h) }
      ) {
        onRemoteHostClick(h, connecting)
      }
    }
  }
}

@Composable
expect fun UserPickerUsersSection(
  users: List<UserInfo>,
  iconColor: Color,
  stopped: Boolean,
  onUserClicked: (user: User) -> Unit,
)

@Composable
expect fun PlatformUserPicker(
  modifier: Modifier,
  pickerState: MutableStateFlow<AnimatedViewState>,
  content: @Composable () -> Unit
)

@Composable
fun DevicePill(
  active: Boolean,
  icon: Painter,
  text: String,
  actionButtonVisible: Boolean,
  onActionButtonClick: (() -> Unit)? = null,
  onClick: () -> Unit) {
  Row(
    Modifier
      .clip(RoundedCornerShape(8.dp))
      .border(
        BorderStroke(1.dp, MaterialTheme.colors.secondaryVariant),
        shape = RoundedCornerShape(8.dp)
      )
      .background(if (active) MaterialTheme.colors.secondaryVariant else Color.Transparent)
      .clickable(
        enabled = !active,
        onClick = onClick,
        interactionSource = remember { MutableInteractionSource() },
        indication = LocalIndication.current
      ),
    verticalAlignment = Alignment.CenterVertically
  ) {
    Row(
      Modifier.padding(horizontal = 6.dp, vertical = 4.dp),
      verticalAlignment = Alignment.CenterVertically
    ) {
      Icon(
        icon,
        text,
        Modifier.size(16.dp * fontSizeSqrtMultiplier),
        tint = MaterialTheme.colors.onSurface
      )
      Spacer(Modifier.width(DEFAULT_SPACE_AFTER_ICON * fontSizeSqrtMultiplier))
      Text(
        text,
        color = MaterialTheme.colors.onSurface,
        fontSize = 12.sp,
        overflow = TextOverflow.Ellipsis,
        maxLines = 1,
        modifier = if (onActionButtonClick != null && actionButtonVisible) Modifier.widthIn(max = 300.dp * fontSizeSqrtMultiplier) else Modifier
      )
      if (onActionButtonClick != null && actionButtonVisible) {
        val interactionSource = remember { MutableInteractionSource() }
        val hovered = interactionSource.collectIsHoveredAsState().value
        Spacer(Modifier.width(DEFAULT_SPACE_AFTER_ICON * fontSizeSqrtMultiplier))
        IconButton(onActionButtonClick, Modifier.requiredSize(16.dp * fontSizeSqrtMultiplier)) {
          Icon(
            painterResource(if (hovered) MR.images.ic_wifi_off else MR.images.ic_wifi),
            null,
            Modifier.size(16.dp * fontSizeSqrtMultiplier).hoverable(interactionSource),
            tint = if (hovered) WarningOrange else MaterialTheme.colors.onBackground
          )
        }
      }
    }
  }
}

@Composable
fun HostDisconnectButton(onClick: (() -> Unit)?) {
  val interactionSource = remember { MutableInteractionSource() }
  val hovered = interactionSource.collectIsHoveredAsState().value
  IconButton(onClick ?: {}, Modifier.requiredSize(20.dp * fontSizeSqrtMultiplier), enabled = onClick != null) {
    Icon(
      painterResource(if (onClick == null) MR.images.ic_desktop else if (hovered) MR.images.ic_wifi_off else MR.images.ic_wifi),
      null,
      Modifier.size(20.dp).hoverable(interactionSource),
      tint = if (hovered && onClick != null) WarningOrange else MaterialTheme.colors.onBackground
    )
  }
}

@Composable
fun BoxScope.userUnreadBadge(unreadCount: Int, userMuted: Boolean, hasPadding: Boolean) {
  val badgeBg = if (userMuted) MaterialTheme.colors.primaryVariant else MaterialTheme.colors.secondary
  Text(
    if (unreadCount > 0) unreadCountStr(unreadCount) else "",
    color = badgeBg.onSurfaceInk(),
    fontSize = 10.sp,
    fontWeight = FontWeight.SemiBold,
    style = TextStyle(textAlign = TextAlign.Center),
    modifier = Modifier
      .offset(y = if (hasPadding) 3.sp.toDp() else -4.sp.toDp(), x = if (hasPadding) 0.dp else 4.sp.toDp())
      .background(badgeBg, shape = CircleShape)
      .badgeLayout()
      .padding(horizontal = 2.sp.toDp())
      .padding(vertical = 2.sp.toDp())
      .align(Alignment.TopEnd)
  )
}

private suspend fun closePicker(userPickerState: MutableStateFlow<AnimatedViewState>) {
  delay(500)
  userPickerState.value = AnimatedViewState.HIDING
}

private fun switchToLocalDevice() {
  withBGApi {
    chatController.switchUIRemoteHost(null)
  }
}

private fun switchToRemoteHost(h: RemoteHostInfo, connecting: MutableState<Boolean>) {
  if (!h.activeHost()) {
    withBGApi {
      ModalManager.closeAllModalsEverywhere()
      if (h.sessionState != null) {
        chatModel.controller.switchUIRemoteHost(h.remoteHostId)
      } else {
        connectMobileDevice(h, connecting)
      }
    }
  } else {
    connectMobileDevice(h, connecting)
  }
}

private fun randomIdentitySuffix(): String {
  val hex = "0123456789abcdef"
  return buildString(6) {
    repeat(6) { append(hex[Random.nextInt(hex.length)]) }
  }
}

private fun showNewIdentityDialog(chatModel: ChatModel, userPickerState: MutableStateFlow<AnimatedViewState>) {
  AlertManager.shared.showAlertDialogButtonsColumn(
    title = "New identity",
    text = AnnotatedString("Start a temporary burner session you can destroy anytime, or permanently replace your current identity."),
    buttons = {
      Column {
        SectionItemView({
          AlertManager.shared.hideAlert()
          userPickerState.value = AnimatedViewState.HIDING
          rotateZeroIdentity(chatModel, disposable = true)
        }) {
          Text("Burner identity", Modifier.fillMaxWidth(), textAlign = TextAlign.Center, color = MaterialTheme.colors.primary)
        }
        SectionItemView({
          AlertManager.shared.hideAlert()
          userPickerState.value = AnimatedViewState.HIDING
          rotateZeroIdentity(chatModel, disposable = false)
        }) {
          Text("New identity", Modifier.fillMaxWidth(), textAlign = TextAlign.Center, color = MaterialTheme.colors.error)
        }
        SectionItemView({
          AlertManager.shared.hideAlert()
        }) {
          Text(generalGetString(MR.strings.cancel_verb), Modifier.fillMaxWidth(), textAlign = TextAlign.Center, color = MaterialTheme.colors.secondary)
        }
      }
    }
  )
}

private fun rotateZeroIdentity(chatModel: ChatModel, disposable: Boolean) {
  withBGApi {
    controller.showProgressIfNeeded {
      val rhId = chatModel.remoteHostId()
      val prevUser = chatModel.currentUser.value
      val existingParentId = DatabaseUtils.ksDisposableParentUserId.get()?.toLongOrNull()
      val suffix = randomIdentitySuffix()
      val prefix = if (disposable) "anon" else "zero"
      val newUser = chatModel.controller.apiCreateActiveUser(rhId, Profile("${prefix}_$suffix", "", null, null))
        ?: return@showProgressIfNeeded
      runCatching { chatModel.controller.apiCreateUserAddress(rhId) }
      ModalManager.closeAllModalsEverywhere()
      chatModel.controller.changeActiveUser_(rhId, newUser.userId, null)
      if (disposable) {
        if (existingParentId == null && prevUser != null) {
          DatabaseUtils.ksDisposableParentUserId.set(prevUser.userId.toString())
        } else if (existingParentId != null && prevUser != null && prevUser.userId != existingParentId) {
          runCatching { chatModel.controller.apiDeleteUser(prevUser, delSMPQueues = true, viewPwd = null) }
        }
      } else {
        DatabaseUtils.ksDisposableParentUserId.remove()
        if (prevUser != null && prevUser.userId != newUser.userId) {
          runCatching { chatModel.controller.apiDeleteUser(prevUser, delSMPQueues = true, viewPwd = null) }
        }
        if (existingParentId != null && existingParentId != prevUser?.userId && existingParentId != newUser.userId) {
          val parentUser = chatModel.users.firstOrNull { it.user.userId == existingParentId }?.user
          if (parentUser != null) {
            runCatching { chatModel.controller.apiDeleteUser(parentUser, delSMPQueues = true, viewPwd = null) }
          }
        }
      }
    }
  }
}

private fun burnDisposableIdentity(chatModel: ChatModel, parentUserId: Long) {
  withBGApi {
    controller.showProgressIfNeeded {
      val rhId = chatModel.remoteHostId()
      val disposableUser = chatModel.currentUser.value
      ModalManager.closeAllModalsEverywhere()
      chatModel.controller.changeActiveUser_(rhId, parentUserId, null)
      DatabaseUtils.ksDisposableParentUserId.remove()
      if (disposableUser != null && disposableUser.userId != parentUserId) {
        runCatching { chatModel.controller.apiDeleteUser(disposableUser, delSMPQueues = true, viewPwd = null) }
      }
    }
  }
}
