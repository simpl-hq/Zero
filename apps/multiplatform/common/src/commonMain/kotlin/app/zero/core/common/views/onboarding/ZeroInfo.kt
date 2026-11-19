package app.zero.core.common.views.onboarding

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.desktop.ui.tooling.preview.Preview
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.*
import app.zero.core.common.model.*
import app.zero.core.common.model.ChatController.appPrefs
import app.zero.core.common.platform.*
import app.zero.core.common.ui.theme.*
import app.zero.core.common.views.helpers.*
import app.zero.core.common.views.migration.MigrateToDeviceView
import app.zero.core.common.views.migration.MigrationToState
import app.zero.core.network.ZeroIdentityBridge
import app.zero.core.res.MR
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import dev.icerock.moko.resources.StringResource
import dev.icerock.moko.resources.compose.painterResource
import dev.icerock.moko.resources.compose.stringResource
import java.security.SecureRandom
import kotlin.math.ceil
import kotlin.math.floor

private enum class ZeroPinMode {
  INITIAL,
  PROVISIONING,
  CREATED_PIN,
  GUIDED_TUTORIAL,
  ENTER_EXISTING_PIN
}

private suspend fun ensureSeamlessProfileAndNetwork(chatModel: ChatModel): User? {
  var user = chatModel.currentUser.value ?: chatModel.controller.apiGetActiveUser(null)
  if (user == null) {
    val suffix = (1000 + SecureRandom().nextInt(9000)).toString()
    user = chatModel.controller.apiCreateActiveUser(null, Profile("zero_$suffix", "", null, null))
    if (user != null) {
      chatModel.currentUser.value = user
      chatModel.localUserCreated.value = true
      chatModel.controller.appPrefs.privacyShowEncryption.set(false)
      chatModel.controller.appPrefs.privacyDeliveryReceiptsSet.set(true)
      chatModel.setDeliveryReceipts.value = false
      chatModel.controller.startChat(user)
    }
  }
  prepareChatBeforeFinishingOnboarding()
  val defaultOps = chatModel.conditions.value.serverOperators
    .filter { it.enabled }
    .map { it.operatorId }
    .toSet()
    .ifEmpty { chatModel.conditions.value.serverOperators.map { it.operatorId }.toSet() }
  if (defaultOps.isNotEmpty()) {
    val conditionsId = chatModel.conditions.value.currentConditions.conditionsId
    val r = chatController.acceptConditions(chatModel.remoteHostId(), conditionsId = conditionsId, operatorIds = defaultOps.toList())
    if (r != null) {
      chatModel.conditions.value = r
    }
  }
  return user
}

@Composable
fun ZeroInfo(chatModel: ChatModel, onboarding: Boolean = true) {
  if (onboarding) {
    CompositionLocalProvider(LocalAppBarHandler provides rememberAppBarHandler()) {
      ModalView({}, showClose = false, showAppBar = false) {
        MinimalistZeroOnboarding(chatModel)
      }
    }
    LaunchedEffect(Unit) {
      if (chatModel.migrationState.value != null && !ModalManager.fullscreen.hasModalsOpen()) {
        ModalManager.fullscreen.showCustomModal(animated = false) { close -> MigrateToDeviceView(close) }
      }
    }
  } else {
    AboutZeroView()
  }
}

// shows about summary phrase card and guided tutorial launcher inside settings
@Composable
private fun AboutZeroView() {
  val savedPhrase by remember { appPrefs.zeroAccountPin.state }
  val clipboardManager = LocalClipboardManager.current
  var copied by rememberSaveable { mutableStateOf(false) }

  Column(
    modifier = Modifier
      .fillMaxSize()
      .verticalScroll(rememberScrollState())
      .padding(horizontal = 24.dp, vertical = 20.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.spacedBy(14.dp)
  ) {
    Spacer(Modifier.statusBarsPadding().padding(top = AppBarHeight * fontSizeSqrtMultiplier))
    Box(
      modifier = Modifier.widthIn(max = 156.dp).padding(top = 8.dp),
      contentAlignment = Alignment.Center
    ) {
      ZeroLogo()
    }
    Text(
      text = "Privacy Should Be Effortless.",
      style = MaterialTheme.typography.h2,
      fontWeight = FontWeight.SemiBold,
      textAlign = TextAlign.Center
    )
    Text(
      text = "Post-quantum Double Ratchet encryption over unidirectional queues, 2-hop private onion routing, XFTP media transfers, and local SQLCipher storage.",
      style = MaterialTheme.typography.body2,
      color = MaterialTheme.colors.secondary,
      textAlign = TextAlign.Center,
      modifier = Modifier.widthIn(max = 460.dp)
    )

    if (!savedPhrase.isNullOrBlank()) {
      Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colors.surface,
        border = BorderStroke(1.dp, MaterialTheme.colors.secondary.copy(alpha = 0.2f)),
        modifier = Modifier
          .widthIn(max = 420.dp)
          .fillMaxWidth()
          .clip(RoundedCornerShape(16.dp))
          .clickable {
            clipboardManager.setText(AnnotatedString(savedPhrase ?: ""))
            copied = true
          }
      ) {
        Column(
          modifier = Modifier.padding(16.dp),
          horizontalAlignment = Alignment.CenterHorizontally,
          verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
          Text(
            if (copied) "4-WORD PHRASE COPIED" else "YOUR 4-WORD ZERO PHRASE",
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (copied) MaterialTheme.colors.primary else MaterialTheme.colors.secondary
          )
          Text(
            savedPhrase ?: "",
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colors.primary,
            textAlign = TextAlign.Center
          )
        }
      }
    }

    Button(
      onClick = { openZeroGuidedTutorial(allowSettingsShortcuts = true) },
      shape = RoundedCornerShape(999.dp),
      elevation = ButtonDefaults.elevation(0.dp, 0.dp, 0.dp, 0.dp),
      colors = ButtonDefaults.buttonColors(backgroundColor = MaterialTheme.colors.primary),
      modifier = Modifier.widthIn(max = 320.dp).fillMaxWidth().height(50.dp)
    ) {
      Text("Start Quick Setup Guide", color = MaterialTheme.colors.onPrimary, fontWeight = FontWeight.SemiBold)
    }
  }
}

@Composable
private fun MinimalistZeroOnboarding(chatModel: ChatModel) {
  var mode by rememberSaveable { mutableStateOf(ZeroPinMode.INITIAL) }
  var assignedPin by rememberSaveable { mutableStateOf("") }
  var existingPinInput by rememberSaveable { mutableStateOf("") }
  var statusError by rememberSaveable { mutableStateOf<String?>(null) }
  var copiedCreatedPhrase by rememberSaveable { mutableStateOf(false) }
  val clipboardManager = LocalClipboardManager.current
  val identityBridge = remember { ZeroIdentityBridge() }

  if (mode == ZeroPinMode.GUIDED_TUTORIAL) {
    ZeroGuidedTutorialView(
      allowSettingsShortcuts = false,
      initialPhrase = assignedPin,
      model = chatModel,
      onComplete = {
        appPrefs.onboardingStage.set(OnboardingStage.OnboardingComplete)
      }
    )
    return
  }

  Box(
    modifier = Modifier
      .fillMaxSize()
      .background(MaterialTheme.colors.background)
      .systemBarsPadding()
      .padding(horizontal = 32.dp),
    contentAlignment = Alignment.Center
  ) {
    Column(
      modifier = Modifier.widthIn(max = 380.dp).fillMaxWidth(),
      horizontalAlignment = Alignment.CenterHorizontally,
      verticalArrangement = Arrangement.Center
    ) {
      Box(
        modifier = Modifier.widthIn(max = 188.dp).padding(bottom = 4.dp),
        contentAlignment = Alignment.Center
      ) {
        ZeroLogo()
      }

      Spacer(Modifier.height(40.dp))

      when (mode) {
        ZeroPinMode.INITIAL -> {
          Button(
            onClick = {
              statusError = null
              mode = ZeroPinMode.PROVISIONING
              withBGApi {
                ensureSeamlessProfileAndNetwork(chatModel)
                val connLink = chatModel.controller.apiCreateOrGetSilentUserAddress(chatModel.remoteHostId())
                val inviteUrl = connLink?.connShortLink ?: connLink?.connFullLink ?: "zero:/contact"
                val phrase = runCatching {
                  identityBridge.provisionPhraseAndDeepLink(inviteUrl).phrase
                }.getOrNull()
                if (phrase == null) {
                  statusError = "Unable to reach Zero identity broker. Check your connection and try again."
                  mode = ZeroPinMode.INITIAL
                  return@withBGApi
                }
                appPrefs.zeroAccountPin.set(phrase)
                assignedPin = phrase
                mode = ZeroPinMode.CREATED_PIN
              }
            },
            modifier = Modifier.fillMaxWidth().height(54.dp),
            shape = RoundedCornerShape(999.dp),
            elevation = ButtonDefaults.elevation(0.dp, 0.dp, 0.dp, 0.dp),
            colors = ButtonDefaults.buttonColors(backgroundColor = MaterialTheme.colors.primary)
          ) {
            Text(
              "Create Zero Identity",
              color = MaterialTheme.colors.onPrimary,
              fontSize = 17.sp,
              fontWeight = FontWeight.Medium
            )
          }

          Spacer(Modifier.height(16.dp))

          OutlinedButton(
            onClick = {
              statusError = null
              mode = ZeroPinMode.ENTER_EXISTING_PIN
            },
            modifier = Modifier.fillMaxWidth().height(54.dp),
            shape = RoundedCornerShape(999.dp),
            border = BorderStroke(1.dp, MaterialTheme.colors.secondary.copy(alpha = 0.35f)),
            colors = ButtonDefaults.outlinedButtonColors(
              backgroundColor = Color.Transparent,
              contentColor = MaterialTheme.colors.onBackground
            )
          ) {
            Text(
              "I Already Have a Phrase",
              fontSize = 17.sp,
              fontWeight = FontWeight.Medium
            )
          }

          AnimatedVisibility(visible = statusError != null) {
            Text(
              text = statusError ?: "",
              color = MaterialTheme.colors.error,
              fontSize = 13.sp,
              textAlign = TextAlign.Center,
              modifier = Modifier.padding(top = 12.dp)
            )
          }
        }

        ZeroPinMode.PROVISIONING -> {
          CircularProgressIndicator(
            modifier = Modifier.size(32.dp),
            color = MaterialTheme.colors.primary,
            strokeWidth = 2.5.dp
          )
          Spacer(Modifier.height(16.dp))
          Text(
            "Securing your Zero identity (Argon2id)…",
            style = MaterialTheme.typography.body2,
            color = MaterialTheme.colors.secondary,
            textAlign = TextAlign.Center
          )
        }

        ZeroPinMode.CREATED_PIN -> {
          Surface(
            shape = RoundedCornerShape(16.dp),
            border = BorderStroke(1.dp, MaterialTheme.colors.secondary.copy(alpha = 0.25f)),
            color = MaterialTheme.colors.surface,
            modifier = Modifier
              .fillMaxWidth()
              .clip(RoundedCornerShape(16.dp))
              .clickable {
                clipboardManager.setText(AnnotatedString(assignedPin))
                copiedCreatedPhrase = true
              }
          ) {
            Column(
              modifier = Modifier.padding(vertical = 22.dp, horizontal = 20.dp),
              horizontalAlignment = Alignment.CenterHorizontally
            ) {
              Text(
                if (copiedCreatedPhrase) "4-WORD PHRASE COPIED" else "YOUR 4-WORD PHRASE",
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 1.5.sp,
                color = if (copiedCreatedPhrase) MaterialTheme.colors.primary else MaterialTheme.colors.secondary
              )
              Spacer(Modifier.height(10.dp))
              Text(
                assignedPin,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colors.onSurface
              )
              Spacer(Modifier.height(6.dp))
              Text(
                "Tap to copy",
                fontSize = 12.sp,
                color = MaterialTheme.colors.primary
              )
            }
          }

          Spacer(Modifier.height(22.dp))

          Button(
            onClick = {
              mode = ZeroPinMode.GUIDED_TUTORIAL
            },
            modifier = Modifier.fillMaxWidth().height(54.dp),
            shape = RoundedCornerShape(999.dp),
            elevation = ButtonDefaults.elevation(0.dp, 0.dp, 0.dp, 0.dp),
            colors = ButtonDefaults.buttonColors(backgroundColor = MaterialTheme.colors.primary)
          ) {
            Text(
              "Start Quick Setup Guide",
              color = MaterialTheme.colors.onPrimary,
              fontSize = 17.sp,
              fontWeight = FontWeight.Medium
            )
          }

          Spacer(Modifier.height(10.dp))

          TextButton(
            onClick = {
              appPrefs.onboardingStage.set(OnboardingStage.OnboardingComplete)
            }
          ) {
            Text(
              "Skip to Zero",
              color = MaterialTheme.colors.secondary,
              fontWeight = FontWeight.Medium
            )
          }
        }

        ZeroPinMode.GUIDED_TUTORIAL -> {}

        ZeroPinMode.ENTER_EXISTING_PIN -> {
          OutlinedTextField(
            value = existingPinInput,
            onValueChange = { input ->
              existingPinInput = input.take(120)
              statusError = null
            },
            placeholder = { Text("Crimson-Velvet-Horizon-Echo") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
            shape = RoundedCornerShape(14.dp),
            modifier = Modifier.fillMaxWidth()
          )

          AnimatedVisibility(visible = statusError != null) {
            Text(
              text = statusError ?: "",
              color = MaterialTheme.colors.error,
              fontSize = 13.sp,
              modifier = Modifier.padding(top = 8.dp)
            )
          }

          Spacer(Modifier.height(20.dp))

          Button(
            onClick = {
              val normalized = runCatching {
                ZeroIdentityBridge.normalizePhrase(existingPinInput)
              }.getOrNull()
              if (normalized == null) {
                statusError = "Enter your 4-word phrase (e.g. Crimson-Velvet-Horizon-Echo)"
                return@Button
              }
              mode = ZeroPinMode.PROVISIONING
              withBGApi {
                val resolved = runCatching { identityBridge.resolveIdentity(normalized) }.isSuccess
                if (!resolved) {
                  statusError = "We couldn't find that 4-word phrase. Check it and try again."
                  mode = ZeroPinMode.ENTER_EXISTING_PIN
                  return@withBGApi
                }
                appPrefs.zeroAccountPin.set(normalized)
                withContext(Dispatchers.Main) {
                  if (chatModel.migrationState.value == null) {
                    chatModel.migrationState.value = MigrationToState.PasteOrScanLink
                  }
                  mode = ZeroPinMode.ENTER_EXISTING_PIN
                  ModalManager.fullscreen.showCustomModal(animated = false, forceAnimated = appPlatform.isDesktop) { close ->
                    MigrateToDeviceView(close)
                  }
                }
              }
            },
            modifier = Modifier.fillMaxWidth().height(54.dp),
            shape = RoundedCornerShape(999.dp),
            elevation = ButtonDefaults.elevation(0.dp, 0.dp, 0.dp, 0.dp),
            colors = ButtonDefaults.buttonColors(backgroundColor = MaterialTheme.colors.primary)
          ) {
            Text(
              "Continue with Phrase",
              color = MaterialTheme.colors.onPrimary,
              fontSize = 17.sp,
              fontWeight = FontWeight.Medium
            )
          }

          Spacer(Modifier.height(8.dp))

          TextButton(onClick = {
            statusError = null
            mode = ZeroPinMode.INITIAL
          }) {
            Text("Back", color = MaterialTheme.colors.secondary)
          }
        }
      }
    }
  }
}

@Composable
fun ZeroInfoLayout(
  user: User?,
  onboardingStage: SharedPreference<OnboardingStage>?
) {
  MinimalistZeroOnboarding(ChatModel)
}

@Composable
fun ZeroLogo() {
  Image(
    painter = painterResource(if (isInDarkTheme()) MR.images.logo_light else MR.images.logo),
    contentDescription = stringResource(MR.strings.image_descr_zero_logo),
    contentScale = ContentScale.FillWidth,
    modifier = Modifier
      .padding(bottom = 10.dp)
      .fillMaxWidth()
  )
}

@Composable
expect fun OnboardingActionButton(user: User?, onboardingStage: SharedPreference<OnboardingStage>, onclick: (() -> Unit)? = null)

@Composable
fun OnboardingActionButton(
  modifier: Modifier = Modifier,
  labelId: StringResource,
  onboarding: OnboardingStage?,
  enabled: Boolean = true,
  icon: Painter? = null,
  iconColor: Color = MaterialTheme.colors.onPrimary,
  onclick: (() -> Unit)?
) {
  Button(
    onClick = {
      onclick?.invoke()
      if (onboarding != null) {
        appPrefs.onboardingStage.set(onboarding)
      }
    },
    modifier = modifier,
    shape = CircleShape,
    enabled = enabled,
    contentPadding = PaddingValues(horizontal = if (icon == null) DEFAULT_PADDING * 2 else DEFAULT_PADDING * 1.5f, vertical = 17.dp),
    colors = ButtonDefaults.buttonColors(MaterialTheme.colors.primary, disabledBackgroundColor = MaterialTheme.colors.secondary)
  ) {
    if (icon != null) {
      Icon(icon, stringResource(labelId), Modifier.padding(end = DEFAULT_PADDING_HALF), tint = iconColor)
    }
    Text(stringResource(labelId), style = MaterialTheme.typography.h2, color = MaterialTheme.colors.onPrimary, fontSize = 18.sp, fontWeight = FontWeight.Medium)
  }
}

@Composable
fun TextButtonBelowOnboardingButton(text: String, onClick: (() -> Unit)?, icon: Painter? = null) {
  val state = getKeyboardState()
  val enabled = onClick != null
  val topPadding by animateDpAsState(if (appPlatform.isAndroid && state.value == KeyboardState.Opened) 0.dp else 7.5.dp)
  val bottomPadding by animateDpAsState(if (appPlatform.isAndroid && state.value == KeyboardState.Opened) 0.dp else 7.5.dp)
  if ((appPlatform.isAndroid && state.value == KeyboardState.Closed) || topPadding > 0.dp) {
    TextButton({ onClick?.invoke() }, Modifier.padding(top = topPadding, bottom = bottomPadding).clip(CircleShape), enabled = enabled) {
      if (icon != null) {
        Icon(icon, null, tint = MaterialTheme.colors.primary)
        Spacer(Modifier.width(4.dp))
      }
      Text(
        text,
        Modifier.padding(vertical = 5.dp),
        color = if (enabled) MaterialTheme.colors.primary else MaterialTheme.colors.secondary,
        fontWeight = FontWeight.Medium,
        textAlign = TextAlign.Center
      )
    }
  } else {
    Spacer(Modifier.height(DEFAULT_PADDING * 2))
  }
}

@Composable
fun OnboardingInformationButton(
  text: String,
  onClick: () -> Unit,
) {
  Box(
    modifier = Modifier
      .clip(CircleShape)
      .clickable { onClick() }
  ) {
    Row(Modifier.padding(8.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
      Icon(
        painterResource(MR.images.ic_info),
        null,
        tint = MaterialTheme.colors.primary
      )
      var textLayoutResult: TextLayoutResult? by remember { mutableStateOf(null) }
      Text(
        text,
        Modifier
          .layout { measurable, constraints ->
            val placeable = measurable.measure(constraints)
            val newTextLayoutResult = textLayoutResult

            if (newTextLayoutResult == null || newTextLayoutResult.lineCount == 0) {
              layout(placeable.width, placeable.height) {
                placeable.placeRelative(0, 0)
              }
            } else {
              val minX = (0 until newTextLayoutResult.lineCount).minOf(newTextLayoutResult::getLineLeft)
              val maxX = (0 until newTextLayoutResult.lineCount).maxOf(newTextLayoutResult::getLineRight)

              layout(ceil(maxX - minX).toInt(), placeable.height) {
                placeable.place(-floor(minX).toInt(), 0)
              }
            }
          },
        onTextLayout = {
          textLayoutResult = it
        },
        style = MaterialTheme.typography.button,
        fontWeight = FontWeight.Medium,
        color = MaterialTheme.colors.primary
      )
    }
  }
}

@Preview
@Composable
fun PreviewZeroInfo() {
  ZeroTheme {
    ZeroInfoLayout(
      user = null,
      onboardingStage = null
    )
  }
}
