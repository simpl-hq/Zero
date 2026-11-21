package app.zero.core.common.views.chatlist

// clean home ui view with 4 word phrase card active chats and quick connect

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zero.core.common.model.Chat
import app.zero.core.common.model.ChatController.appPrefs
import app.zero.core.common.model.ChatInfo
import app.zero.core.common.model.ChatModel
import app.zero.core.common.platform.chatModel
import app.zero.core.common.views.helpers.ModalManager
import app.zero.core.common.views.helpers.withBGApi
import app.zero.core.common.views.newchat.AddGroupView
import app.zero.core.common.views.onboarding.openZeroGuidedTutorial
import app.zero.core.common.views.usersettings.networkAndServers.NetworkAndServersView
import app.zero.core.network.ZeroIdentityBridge
import app.zero.core.res.MR
import dev.icerock.moko.resources.compose.painterResource

@Composable
fun ZeroDashboardView(
  userAccountPin: String,
  onAddContactClick: () -> Unit,
  onNavigateToAdvancedSettings: () -> Unit,
  activeChats: List<Chat> = emptyList(),
  onSelectChat: (Chat) -> Unit = {},
  deepLink: String? = null,
  ephemeralCode: String? = null,
  onGenerateInPersonCode: (() -> Unit)? = null,
  onOpenTutorialClick: (() -> Unit)? = null,
  onCreateGroupClick: (() -> Unit)? = null
) {
  val clipboardManager = LocalClipboardManager.current
  var copiedLabel by remember { mutableStateOf<String?>(null) }

  Scaffold(
    topBar = {
      TopAppBar(
        backgroundColor = MaterialTheme.colors.background,
        elevation = 0.dp,
        title = {
          Column(verticalArrangement = Arrangement.spacedBy(0.dp)) {
            Text(
              "Zero",
              style = MaterialTheme.typography.h1,
              fontSize = 21.sp,
              fontWeight = FontWeight.Black,
              letterSpacing = (-0.5).sp,
              color = MaterialTheme.colors.onBackground
            )
            Text(
              "by Simpl",
              fontSize = 10.sp,
              fontWeight = FontWeight.Medium,
              letterSpacing = 0.6.sp,
              color = MaterialTheme.colors.secondary
            )
          }
        },
        actions = {
          if (onOpenTutorialClick != null) {
            IconButton(onClick = onOpenTutorialClick) {
              Icon(
                painter = painterResource(MR.images.ic_help),
                contentDescription = "Quick guide",
                tint = MaterialTheme.colors.primary
              )
            }
          }
          IconButton(onClick = onNavigateToAdvancedSettings) {
            Icon(
              painter = painterResource(MR.images.ic_settings),
              contentDescription = "Network settings",
              tint = MaterialTheme.colors.secondary
            )
          }
        }
      )
    }
  ) { padding ->
    Column(
      modifier = Modifier
        .fillMaxSize()
        .padding(padding)
        .padding(horizontal = 24.dp, vertical = 20.dp)
    ) {
      Text(
        "Private messaging. No phone number. No tracking.",
        style = MaterialTheme.typography.body1,
        color = MaterialTheme.colors.secondary,
        modifier = Modifier.padding(bottom = 20.dp)
      )
      Card(
        modifier = Modifier
          .fillMaxWidth()
          .padding(bottom = 24.dp)
          .clickable(
            onClickLabel = "Copy your private phrase",
            role = Role.Button
          ) {
            clipboardManager.setText(AnnotatedString(userAccountPin))
            copiedLabel = "PHRASE COPIED"
          },
        shape = RoundedCornerShape(20.dp),
        elevation = 0.dp,
        border = BorderStroke(1.dp, MaterialTheme.colors.onSurface.copy(alpha = 0.12f)),
        backgroundColor = MaterialTheme.colors.surface
      ) {
        Column(
          modifier = Modifier.padding(vertical = 24.dp, horizontal = 20.dp),
          horizontalAlignment = Alignment.CenterHorizontally
        ) {
          Text(
            copiedLabel ?: "YOUR PRIVATE PHRASE · TAP TO COPY",
            style = MaterialTheme.typography.caption,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 1.4.sp,
            color = if (copiedLabel != null) MaterialTheme.colors.primary else MaterialTheme.colors.secondary,
            textAlign = TextAlign.Center
          )
          Spacer(Modifier.height(12.dp))
          Text(
            userAccountPin,
            style = MaterialTheme.typography.h1,
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colors.onSurface
          )
          if (!ephemeralCode.isNullOrBlank()) {
            Spacer(Modifier.height(12.dp))
            Text(
              "IN-PERSON CODE · EXPIRES IN 5 MIN",
              fontSize = 10.sp,
              fontFamily = FontFamily.Monospace,
              fontWeight = FontWeight.Medium,
              letterSpacing = 0.8.sp,
              color = MaterialTheme.colors.secondary
            )
            Spacer(Modifier.height(4.dp))
            Text(
              ephemeralCode,
              fontSize = 13.sp,
              fontFamily = FontFamily.Monospace,
              fontWeight = FontWeight.SemiBold,
              color = MaterialTheme.colors.primary
            )
          }
          Spacer(Modifier.height(12.dp))
          Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
          ) {
            if (!deepLink.isNullOrBlank()) {
              OutlinedButton(
                onClick = {
                  clipboardManager.setText(AnnotatedString(deepLink))
                  copiedLabel = "DEEP LINK COPIED"
                },
                modifier = Modifier.weight(1f).height(38.dp),
                shape = RoundedCornerShape(10.dp)
              ) {
                Text("Copy Link", fontSize = 12.sp, maxLines = 1)
              }
            }
            if (onGenerateInPersonCode != null) {
              OutlinedButton(
                onClick = onGenerateInPersonCode,
                modifier = Modifier.weight(1f).height(38.dp),
                shape = RoundedCornerShape(10.dp)
              ) {
                Text("6-Digit Code", fontSize = 12.sp, maxLines = 1)
              }
            }
          }
        }
      }

      if (activeChats.isEmpty()) {
        Box(
          modifier = Modifier.weight(1f).fillMaxWidth(),
          contentAlignment = Alignment.Center
        ) {
          Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
              "Messages",
              style = MaterialTheme.typography.h2,
              fontWeight = FontWeight.SemiBold,
              color = MaterialTheme.colors.onBackground,
              textAlign = TextAlign.Center
            )
          }
        }
      } else {
        Text(
          "CONVERSATIONS",
          style = MaterialTheme.typography.caption,
          fontFamily = FontFamily.Monospace,
          fontWeight = FontWeight.SemiBold,
          letterSpacing = 1.2.sp,
          color = MaterialTheme.colors.secondary,
          modifier = Modifier.padding(bottom = 12.dp)
        )
        LazyColumn(
          modifier = Modifier.weight(1f).fillMaxWidth(),
          verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
          items(activeChats, key = { it.id }) { chat ->
            Surface(
              modifier = Modifier
                .fillMaxWidth()
                .clickable { onSelectChat(chat) },
              shape = RoundedCornerShape(12.dp),
              color = MaterialTheme.colors.surface,
              border = BorderStroke(1.dp, MaterialTheme.colors.onSurface.copy(alpha = 0.1f))
            ) {
              Row(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically
              ) {
                Column(modifier = Modifier.weight(1f)) {
                  Text(
                    text = chat.chatInfo.chatViewName,
                    style = MaterialTheme.typography.subtitle1,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                  )
                  val preview = chat.chatItems.lastOrNull()?.content?.text ?: ""
                  if (preview.isNotEmpty()) {
                    Spacer(Modifier.height(2.dp))
                    Text(
                      text = preview,
                      style = MaterialTheme.typography.body2,
                      color = MaterialTheme.colors.secondary,
                      maxLines = 1,
                      overflow = TextOverflow.Ellipsis
                    )
                  }
                }
              }
            }
          }
        }
      }

      Spacer(Modifier.height(16.dp))

      Button(
        onClick = onAddContactClick,
        modifier = Modifier.fillMaxWidth().height(54.dp),
        shape = RoundedCornerShape(999.dp),
        elevation = ButtonDefaults.elevation(0.dp, 0.dp, 0.dp, 0.dp),
        colors = ButtonDefaults.buttonColors(backgroundColor = MaterialTheme.colors.primary)
      ) {
        Text(
          "New message",
          color = MaterialTheme.colors.onPrimary,
          fontSize = 15.sp,
          fontWeight = FontWeight.Medium
        )
      }
      if (onCreateGroupClick != null) {
        Spacer(Modifier.height(10.dp))
        OutlinedButton(
          onClick = onCreateGroupClick,
          modifier = Modifier.fillMaxWidth().height(48.dp),
          shape = RoundedCornerShape(999.dp),
          border = BorderStroke(1.dp, MaterialTheme.colors.onSurface.copy(alpha = 0.16f))
        ) {
          Text(
            "Start a group",
            color = MaterialTheme.colors.onBackground,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium
          )
        }
      }
    }
  }
}

@Composable
fun ZeroConnectByPinDialog(
  onDismiss: () -> Unit,
  onConnectPin: (String) -> Unit
) {
  var targetText by rememberSaveable { mutableStateOf("") }
  var errorText by rememberSaveable { mutableStateOf<String?>(null) }

  AlertDialog(
    onDismissRequest = onDismiss,
    shape = RoundedCornerShape(16.dp),
    title = {
      Text(
        "New message",
        fontWeight = FontWeight.SemiBold,
        fontSize = 18.sp
      )
    },
    text = {
      Column {
        Text(
          "Enter a 4-word phrase, deep link, or 6-digit in-person code.",
          fontSize = 13.sp,
          color = MaterialTheme.colors.secondary,
          modifier = Modifier.padding(bottom = 10.dp)
        )
        OutlinedTextField(
          value = targetText,
          onValueChange = { input ->
            targetText = input.take(180)
            errorText = null
          },
          placeholder = { Text("Crimson-Velvet-Horizon-Echo or 482-911") },
          singleLine = true,
          keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
          shape = RoundedCornerShape(12.dp),
          modifier = Modifier.fillMaxWidth()
        )
        AnimatedVisibility(visible = errorText != null) {
          Text(
            text = errorText ?: "",
            color = MaterialTheme.colors.error,
            fontSize = 12.sp,
            modifier = Modifier.padding(top = 6.dp)
          )
        }
      }
    },
    confirmButton = {
      TextButton(
        onClick = {
          val resolved = ZeroIdentityBridge.extractResolveTarget(targetText)
          if (resolved.isBlank()) {
            errorText = "Enter a valid 4-word phrase, deep link, or 6-digit code"
          } else {
            onConnectPin(resolved)
          }
        }
      ) {
        Text("Connect", color = MaterialTheme.colors.primary, fontWeight = FontWeight.SemiBold)
      }
    },
    dismissButton = {
      TextButton(onClick = onDismiss) {
        Text("Cancel", color = MaterialTheme.colors.secondary)
      }
    }
  )
}

@Composable
fun ZeroAccountPinBannerCard(model: ChatModel = chatModel) {
  val clipboardManager = LocalClipboardManager.current
  val savedPhrase by remember { appPrefs.zeroAccountPin.state }
  var deepLink by rememberSaveable { mutableStateOf<String?>(null) }
  var ephemeralCode by rememberSaveable { mutableStateOf<String?>(null) }
  var showConnectDialog by rememberSaveable { mutableStateOf(false) }
  var copiedLabel by remember { mutableStateOf<String?>(null) }
  val identityBridge = remember { ZeroIdentityBridge() }

  LaunchedEffect(savedPhrase) {
    if (savedPhrase.isNullOrBlank()) {
      withBGApi {
        val connLink = model.controller.apiCreateOrGetSilentUserAddress(model.remoteHostId())
        val inviteUrl = connLink?.connShortLink ?: connLink?.connFullLink ?: "zero:/contact"
        val res = runCatching {
          identityBridge.provisionPhraseAndDeepLink(inviteUrl)
        }.getOrNull()
        if (res != null) {
          deepLink = res.deepLink
          appPrefs.zeroAccountPin.set(res.phrase)
        }
      }
    }
  }

  val displayPhrase = savedPhrase ?: "••••-••••-••••-••••"

  Card(
    modifier = Modifier.fillMaxWidth(),
    shape = RoundedCornerShape(16.dp),
    elevation = 0.dp,
    border = BorderStroke(1.dp, MaterialTheme.colors.secondary.copy(alpha = 0.2f)),
    backgroundColor = MaterialTheme.colors.surface
  ) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .padding(16.dp),
      horizontalAlignment = Alignment.CenterHorizontally
    ) {
      Box(modifier = Modifier.fillMaxWidth()) {
        Column(
          modifier = Modifier
            .fillMaxWidth()
            .clickable {
              if (!savedPhrase.isNullOrBlank()) {
                clipboardManager.setText(AnnotatedString(displayPhrase))
                copiedLabel = "4-WORD PHRASE COPIED"
              }
            }
            .padding(vertical = 4.dp),
          horizontalAlignment = Alignment.CenterHorizontally
        ) {
          Text(
            copiedLabel ?: "YOUR 4-WORD PHRASE",
            style = MaterialTheme.typography.caption,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 1.2.sp,
            color = if (copiedLabel != null) MaterialTheme.colors.primary else MaterialTheme.colors.secondary
          )
          Spacer(Modifier.height(6.dp))
          Text(
            displayPhrase,
            style = MaterialTheme.typography.h1,
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colors.onSurface
          )
          if (!ephemeralCode.isNullOrBlank()) {
            Spacer(Modifier.height(6.dp))
            Text(
              "In-Person (5m): $ephemeralCode",
              fontSize = 13.sp,
              fontFamily = FontFamily.Monospace,
              fontWeight = FontWeight.SemiBold,
              color = MaterialTheme.colors.primary
            )
          }
        }
        IconButton(
          onClick = { openZeroGuidedTutorial(allowSettingsShortcuts = true) },
          modifier = Modifier.align(Alignment.TopEnd).size(28.dp)
        ) {
          Icon(
            painterResource(MR.images.ic_help),
            contentDescription = "Setup & Quick Guide",
            tint = MaterialTheme.colors.primary,
            modifier = Modifier.size(18.dp)
          )
        }
      }
      Spacer(Modifier.height(10.dp))
      Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
      ) {
        OutlinedButton(
          onClick = {
            val link = deepLink ?: savedPhrase?.let {
              "${ZeroIdentityBridge.DEEP_LINK_PREFIX}${it.lowercase().replace("-", "")}"
            }
            if (link != null) {
              clipboardManager.setText(AnnotatedString(link))
              copiedLabel = "DEEP LINK COPIED"
            } else {
              copiedLabel = "BROKER OFFLINE — USE QR"
            }
          },
          modifier = Modifier.weight(1f).height(40.dp),
          shape = RoundedCornerShape(10.dp)
        ) {
          Text("Copy Link", fontSize = 13.sp)
        }
        OutlinedButton(
          onClick = {
            withBGApi {
              val connLink = model.controller.apiCreateOrGetSilentUserAddress(model.remoteHostId())
              val inviteUrl = connLink?.connShortLink ?: connLink?.connFullLink ?: "zero:/contact"
              val code = runCatching {
                identityBridge.provisionEphemeral6DigitCode(inviteUrl).code
              }.getOrNull()
              if (code != null) {
                ephemeralCode = code
              } else {
                copiedLabel = "BROKER OFFLINE — USE QR"
              }
            }
          },
          modifier = Modifier.weight(1f).height(40.dp),
          shape = RoundedCornerShape(10.dp)
        ) {
          Text("6-Digit Code", fontSize = 13.sp)
        }
      }
      Spacer(Modifier.height(10.dp))
      Button(
        onClick = { showConnectDialog = true },
        modifier = Modifier.fillMaxWidth().height(48.dp),
        shape = RoundedCornerShape(999.dp),
        elevation = ButtonDefaults.elevation(0.dp, 0.dp, 0.dp, 0.dp),
        colors = ButtonDefaults.buttonColors(backgroundColor = MaterialTheme.colors.primary)
      ) {
        Text(
          "Connect (Phrase, Link, or 6-Digit Code)",
          color = MaterialTheme.colors.onPrimary,
          fontSize = 14.sp,
          fontWeight = FontWeight.Medium
        )
      }
    }
  }

  if (showConnectDialog) {
    ZeroConnectByPinDialog(
      onDismiss = { showConnectDialog = false },
      onConnectPin = { target ->
        showConnectDialog = false
        withBGApi {
          val inviteUrl = runCatching {
            identityBridge.resolveIdentity(target)
          }.getOrNull()
          if (inviteUrl != null) {
            connectIfOpenedViaUri(model.remoteHostId(), inviteUrl, model)
          }
        }
      }
    )
  }
}

@Composable
fun ZeroIntegratedDashboard(
  userAccountPin: String = "",
  model: ChatModel = chatModel
) {
  var showConnectDialog by rememberSaveable { mutableStateOf(false) }
  var deepLink by rememberSaveable { mutableStateOf<String?>(null) }
  var ephemeralCode by rememberSaveable { mutableStateOf<String?>(null) }
  val savedPhrase by remember { appPrefs.zeroAccountPin.state }
  val identityBridge = remember { ZeroIdentityBridge() }

  LaunchedEffect(userAccountPin, savedPhrase) {
    if (userAccountPin.isBlank() && savedPhrase.isNullOrBlank()) {
      withBGApi {
        val connLink = model.controller.apiCreateOrGetSilentUserAddress(model.remoteHostId())
        val inviteUrl = connLink?.connShortLink ?: connLink?.connFullLink ?: "zero:/contact"
        val res = runCatching {
          identityBridge.provisionPhraseAndDeepLink(inviteUrl)
        }.getOrNull()
        if (res != null) {
          deepLink = res.deepLink
          appPrefs.zeroAccountPin.set(res.phrase)
        }
      }
    }
  }

  val effectivePhrase = userAccountPin.ifBlank { savedPhrase ?: "••••-••••-••••-••••" }
  val visibleChats = model.chats.value.filter { it.chatInfo !is ChatInfo.Local }

  ZeroDashboardView(
    userAccountPin = effectivePhrase,
    activeChats = visibleChats,
    deepLink = deepLink,
    ephemeralCode = ephemeralCode,
    onGenerateInPersonCode = {
      withBGApi {
        val connLink = model.controller.apiCreateOrGetSilentUserAddress(model.remoteHostId())
        val inviteUrl = connLink?.connShortLink ?: connLink?.connFullLink ?: "zero:/contact"
        val code = runCatching {
          identityBridge.provisionEphemeral6DigitCode(inviteUrl).code
        }.getOrNull()
        if (code != null) {
          ephemeralCode = code
        }
      }
    },
    onSelectChat = { chat ->
      model.chatId.value = chat.id
    },
    onAddContactClick = {
      showConnectDialog = true
    },
    onNavigateToAdvancedSettings = {
      ModalManager.start.showCustomModal { close ->
        NetworkAndServersView(close)
      }
    },
    onOpenTutorialClick = {
      openZeroGuidedTutorial(allowSettingsShortcuts = true)
    },
    onCreateGroupClick = {
      ModalManager.start.showModalCloseable { close ->
        AddGroupView(model, model.currentRemoteHost.value, close = close, closeAll = close)
      }
    }
  )

  if (showConnectDialog) {
    ZeroConnectByPinDialog(
      onDismiss = { showConnectDialog = false },
      onConnectPin = { target ->
        showConnectDialog = false
        withBGApi {
          val inviteUrl = runCatching {
            identityBridge.resolveIdentity(target)
          }.getOrNull()
          if (inviteUrl != null) {
            connectIfOpenedViaUri(model.remoteHostId(), inviteUrl, model)
          }
        }
      }
    )
  }
}
