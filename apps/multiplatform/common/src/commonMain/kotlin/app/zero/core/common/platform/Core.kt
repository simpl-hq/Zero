package app.zero.core.common.platform

import app.zero.core.common.model.*
import app.zero.core.common.model.ChatController.appPrefs
import app.zero.core.common.model.ChatModel.controller
import app.zero.core.common.model.ChatModel.currentUser
import app.zero.core.common.views.helpers.*
import app.zero.core.common.views.helpers.DatabaseUtils.ksDatabasePassword
import app.zero.core.common.views.helpers.DatabaseUtils.randomDatabasePassword
import app.zero.core.common.views.onboarding.OnboardingStage
import app.zero.core.res.MR
import kotlinx.coroutines.*
import java.io.File
import java.nio.ByteBuffer

external fun zero_core_runtime_init()

fun initHS() = zero_core_runtime_init()
external fun pipeStdOutToSocket(socketName: String) : Int

typealias ChatCtrl = Long
external fun zero_core_runtime_migrate_init(dbPath: String, dbKey: String, confirm: String): Array<Any>
external fun zero_core_runtime_close_store(ctrl: ChatCtrl): String
external fun zero_core_runtime_send_cmd_retry(ctrl: ChatCtrl, msg: String, retryNum: Int): String
external fun zero_core_runtime_send_remote_cmd_retry(ctrl: ChatCtrl, rhId: Int, msg: String, retryNum: Int): String
external fun zero_core_runtime_recv_msg(ctrl: ChatCtrl): String
external fun zero_core_runtime_recv_msg_wait(ctrl: ChatCtrl, timeout: Int): String
external fun zero_core_runtime_parse_markdown(str: String): String
external fun zero_core_runtime_parse_server(str: String): String
external fun zero_core_runtime_parse_uri(str: String, safe: Int): String
external fun zero_core_runtime_password_hash(pwd: String, salt: String): String
external fun zero_core_runtime_valid_name(name: String): String
external fun zero_core_runtime_json_length(str: String): Int
external fun zero_core_runtime_write_file(ctrl: ChatCtrl, path: String, buffer: ByteBuffer): String
external fun zero_core_runtime_read_file(path: String, key: String, nonce: String): Array<Any>
external fun zero_core_runtime_encrypt_file(ctrl: ChatCtrl, fromPath: String, toPath: String): String
external fun zero_core_runtime_decrypt_file(fromPath: String, key: String, nonce: String, toPath: String): String

fun chatMigrateInit(dbPath: String, dbKey: String, confirm: String): Array<Any> = zero_core_runtime_migrate_init(dbPath, dbKey, confirm)

fun chatCloseStore(ctrl: ChatCtrl): String = zero_core_runtime_close_store(ctrl)

fun chatSendCmdRetry(ctrl: ChatCtrl, msg: String, retryNum: Int): String = zero_core_runtime_send_cmd_retry(ctrl, msg, retryNum)

fun chatSendRemoteCmdRetry(ctrl: ChatCtrl, rhId: Int, msg: String, retryNum: Int): String = zero_core_runtime_send_remote_cmd_retry(ctrl, rhId, msg, retryNum)
fun chatRecvMsg(ctrl: ChatCtrl): String = zero_core_runtime_recv_msg(ctrl)

fun chatRecvMsgWait(ctrl: ChatCtrl, timeout: Int): String = zero_core_runtime_recv_msg_wait(ctrl, timeout)
fun chatParseMarkdown(str: String): String = zero_core_runtime_parse_markdown(str)

fun chatParseServer(str: String): String = zero_core_runtime_parse_server(str)

fun chatParseUri(str: String, safe: Int): String = zero_core_runtime_parse_uri(str, safe)
fun chatPasswordHash(pwd: String, salt: String): String = zero_core_runtime_password_hash(pwd, salt)
fun chatValidName(name: String): String = zero_core_runtime_valid_name(name)
fun chatJsonLength(str: String): Int = zero_core_runtime_json_length(str)
fun chatWriteFile(ctrl: ChatCtrl, path: String, buffer: ByteBuffer): String = zero_core_runtime_write_file(ctrl, path, buffer)
fun chatReadFile(path: String, key: String, nonce: String): Array<Any> = zero_core_runtime_read_file(path, key, nonce)
fun chatEncryptFile(ctrl: ChatCtrl, fromPath: String, toPath: String): String = zero_core_runtime_encrypt_file(ctrl, fromPath, toPath)
fun chatDecryptFile(fromPath: String, key: String, nonce: String, toPath: String): String = zero_core_runtime_decrypt_file(fromPath, key, nonce, toPath)

val chatModel: ChatModel
  get() = chatController.chatModel

val appPreferences: AppPreferences
  get() = chatController.appPrefs

val chatController: ChatController = ChatController

fun initChatControllerOnStart() {
  withLongRunningApi {
    if (appPreferences.chatStopped.get() && appPreferences.storeDBPassphrase.get() && ksDatabasePassword.get() != null) {
      initChatController(startChat = ::showStartChatAfterRestartAlert)
    } else {
      initChatController()
    }
  }
}

suspend fun initChatController(useKey: String? = null, confirmMigrations: MigrationConfirmation? = null, startChat: () -> CompletableDeferred<Boolean> = { CompletableDeferred(true) }) {
  Log.d(TAG, "initChatController")
  try {
    if (chatModel.ctrlInitInProgress.value) return
    chatModel.ctrlInitInProgress.value = true
    if (!appPrefs.storeDBPassphrase.get() && !appPrefs.initialRandomDBPassphrase.get()) {
      ksDatabasePassword.remove()
    }
    val dbKey = useKey ?: DatabaseUtils.useDatabaseKey()
    val confirm = confirmMigrations ?: if (appPreferences.developerTools.get() && appPreferences.confirmDBUpgrades.get()) MigrationConfirmation.Error else MigrationConfirmation.YesUp
    var migrated: Array<Any> = if (databaseBackend == "postgres") {
      chatMigrateInit("zero_v1", "postgresql://zero@/zero_v1", MigrationConfirmation.Error.value)
    } else {
      chatMigrateInit(dbAbsolutePrefixPath, dbKey, MigrationConfirmation.Error.value)
    }
    var res: DBMigrationResult = runCatching {
      json.decodeFromString<DBMigrationResult>(migrated[0] as String)
    }.getOrElse { DBMigrationResult.Unknown(migrated[0] as String) }
    val rerunMigration = res is DBMigrationResult.ErrorMigration && when (res.migrationError) {
      is MigrationError.Upgrade -> confirm == MigrationConfirmation.YesUp || confirm == MigrationConfirmation.YesUpDown
      is MigrationError.Downgrade ->  confirm == MigrationConfirmation.YesUpDown
      is MigrationError.Error -> false
    }
    if (rerunMigration) {
      chatModel.dbMigrationInProgress.value = true
      migrated = if (databaseBackend == "postgres") {
        chatMigrateInit("zero_v1", "postgresql://zero@/zero_v1", confirm.value)
      } else {
        chatMigrateInit(dbAbsolutePrefixPath, dbKey, confirm.value)
      }
      res = runCatching {
        json.decodeFromString<DBMigrationResult>(migrated[0] as String)
      }.getOrElse { DBMigrationResult.Unknown(migrated[0] as String) }
    }
    val ctrl = if (res is DBMigrationResult.OK) {
      migrated[1] as Long
    } else null
    chatController.setChatCtrl(ctrl)
    chatModel.chatDbEncrypted.value = dbKey != ""
    chatModel.chatDbStatus.value = res
    if (res != DBMigrationResult.OK) {
      Log.d(TAG, "Unable to migrate successfully: $res")
      if (!appPrefs.newDatabaseInitialized.get() && DatabaseUtils.hasOnlyOneDatabase(dataDir.absolutePath)) {
        if (chatModel.incompleteInitializedDbRemoved.value) {
          Log.d(TAG, "Incomplete initialized databases were removed but after repeated migration only one database exists again, not trying to remove again")
        } else {
          val dbPath = dbAbsolutePrefixPath
          File(dbPath + "_chat.db").delete()
          File(dbPath + "_agent.db").delete()
          chatModel.incompleteInitializedDbRemoved.value = true
          Log.d(TAG, "Incomplete initialized databases were removed for the first time, repeating migration")
          chatModel.ctrlInitInProgress.value = false
          initChatController(useKey, confirmMigrations, startChat)
        }
      }
      return
    }
    appPrefs.newDatabaseInitialized.set(true)
    chatModel.incompleteInitializedDbRemoved.value = false
    platform.androidRestartNetworkObserver()
    controller.apiSetAppFilePaths(
      appFilesDir.absolutePath,
      coreTmpDir.absolutePath,
      wallpapersDir.parentFile.absolutePath,
      remoteHostsDir.absolutePath,
      ctrl
    )
    controller.apiSetEncryptLocalFiles(controller.appPrefs.privacyEncryptLocalFiles.get())
    if (appPreferences.encryptionStartedAt.get() != null) appPreferences.encryptionStartedAt.set(null)
    val user = chatController.apiGetActiveUser(null)
    chatModel.currentUser.value = user
    chatModel.conditions.value = chatController.getServerOperators(null) ?: ServerOperatorConditionsDetail.empty
    if (appPrefs.shouldImportAppSettings.get()) {
      try {
        val appSettings = controller.apiGetAppSettings(AppSettings.current.prepareForExport())
        appSettings.importIntoApp()
        appPrefs.shouldImportAppSettings.set(false)
      } catch (e: Exception) {
        Log.e(TAG, "Error while importing app settings: " + e.stackTraceToString())
      }
    }
    if (user == null) {
      chatModel.controller.appPrefs.privacyDeliveryReceiptsSet.set(true)
      chatModel.currentUser.value = null
      chatModel.users.clear()
      if (appPlatform.isDesktop) {

        chatModel.localUserCreated.value = null
        if (chatController.listRemoteHosts()?.isEmpty() == true) {
          chatController.appPrefs.onboardingStage.set(OnboardingStage.Step1_ZeroInfo)
        }
        chatController.startChatWithoutUser()
      } else {
        chatModel.localUserCreated.value = false
        chatController.appPrefs.onboardingStage.set(OnboardingStage.Step1_ZeroInfo)
      }
    } else if (startChat().await()) {
      val savedOnboardingStage = appPreferences.onboardingStage.get()
      val newStage = if (listOf(OnboardingStage.Step1_ZeroInfo, OnboardingStage.Step2_CreateProfile).contains(savedOnboardingStage) && chatModel.users.size == 1) {
        OnboardingStage.Step4_NetworkCommitments
      } else {
        savedOnboardingStage
      }
      if (appPreferences.onboardingStage.get() != newStage) {
        appPreferences.onboardingStage.set(newStage)
      }
      chatController.startChat(user)
      platform.androidChatInitializedAndStarted()
    } else {
      chatController.getUserChatData(null)
      chatModel.localUserCreated.value = currentUser.value != null
      chatModel.chatRunning.value = false
    }
  } finally {
    chatModel.ctrlInitInProgress.value = false
    chatModel.dbMigrationInProgress.value = false
  }
}

fun chatInitTemporaryDatabase(dbPath: String, key: String? = null, confirmation: MigrationConfirmation = MigrationConfirmation.Error): Pair<DBMigrationResult, ChatCtrl?> {
  val dbKey = key ?: randomDatabasePassword()
  Log.d(TAG, "chatInitTemporaryDatabase path: $dbPath")
  val migrated = chatMigrateInit(dbPath, dbKey, confirmation.value)
  val res = runCatching {
    json.decodeFromString<DBMigrationResult>(migrated[0] as String)
  }.getOrElse { DBMigrationResult.Unknown(migrated[0] as String) }

  return res to migrated[1] as ChatCtrl
}

fun chatInitControllerRemovingDatabases() {
  val dbPath = dbAbsolutePrefixPath
  File(dbPath + "_chat.db").delete()
  File(dbPath + "_agent.db").delete()

  val dbKey = randomDatabasePassword()
  Log.d(TAG, "chatInitControllerRemovingDatabases path: $dbPath")
  val migrated = chatMigrateInit(dbPath, dbKey, MigrationConfirmation.Error.value)
  val res = runCatching {
    json.decodeFromString<DBMigrationResult>(migrated[0] as String)
  }.getOrElse { DBMigrationResult.Unknown(migrated[0] as String) }

  val ctrl = migrated[1] as Long
  chatController.setChatCtrl(ctrl)
  File(dbPath + "_chat.db").delete()
  File(dbPath + "_agent.db").delete()
}

fun showStartChatAfterRestartAlert(): CompletableDeferred<Boolean> {
  val deferred = CompletableDeferred<Boolean>()
  AlertManager.shared.showAlertDialog(
    title = generalGetString(MR.strings.start_chat_question),
    text = generalGetString(MR.strings.chat_is_stopped_you_should_transfer_database),
    onConfirm = { deferred.complete(true) },
    onDismiss = { deferred.complete(false) },
    onDismissRequest = { deferred.complete(false) }
  )
  return deferred
}
