import UserNotifications
import OSLog
import StoreKit
import CallKit
import Zero

let logger = Logger()

let appSuspendingDelay: UInt64 = 2_500_000_000

typealias SuspendSchedule = (delay: TimeInterval, timeout: Int)

let nseSuspendSchedule: SuspendSchedule = (2, 4)

let fastNSESuspendSchedule: SuspendSchedule = (1, 1)

public enum NSENotificationData {
    case connectionEvent(_ user: User, _ connEntity: ConnectionEntity)
    case contactConnected(_ user: any UserLike, _ contact: Contact)
    case contactRequest(_ user: any UserLike, _ contactRequest: UserContactRequest)
    case messageReceived(_ user: any UserLike, _ cInfo: ChatInfo, _ cItem: ChatItem)
    case callInvitation(_ invitation: RcvCallInvitation)
    case msgInfo(NtfMsgAckInfo)
    case noNtf

    @inline(__always)
    var callInvitation: RcvCallInvitation? {
        switch self {
        case let .callInvitation(invitation): invitation
        default: nil
        }
    }

    func notificationContent(_ badgeCount: Int) -> UNMutableNotificationContent {
        return switch self {
        case let .connectionEvent(user, connEntity): createConnectionEventNtf(user, connEntity, badgeCount)
        case let .contactConnected(user, contact): createContactConnectedNtf(user, contact, badgeCount)
        case let .contactRequest(user, contactRequest): createContactRequestNtf(user, contactRequest, badgeCount)
        case let .messageReceived(user, cInfo, cItem): createMessageReceivedNtf(user, cInfo, cItem, badgeCount)
        case let .callInvitation(invitation): createCallInvitationNtf(invitation, badgeCount)
        case .msgInfo: UNMutableNotificationContent()
        case .noNtf: UNMutableNotificationContent()
        }
    }

    @inline(__always)
    var notificationEvent: NSENotificationData? {
        switch self {
        case .connectionEvent: self
        case .contactConnected: self
        case .contactRequest: self
        case .messageReceived: self
        case .callInvitation: self
        case .msgInfo: nil
        case .noNtf: nil
        }
    }

    @inline(__always)
    var newMsgNtf: NSENotificationData? {
        switch self {
        case .messageReceived: self
        default: nil
        }
    }
}

class NSEThreads {
    static let shared = NSEThreads()
    private let queue = DispatchQueue(label: "app.zero.chat.Zero-NSE.notification-threads.lock")
    private var allThreads: Set<UUID> = []
    private var activeThreads: [(threadId: UUID, nse: NotificationService)] = []
    private var droppedNotifications: [(entityId: ChatId, ntf: NSENotificationData)] = []

    @inline(__always)
    private init() {}

    @inline(__always)
    func newThread() -> UUID {
        queue.sync {
            let (_, t) = allThreads.insert(UUID())
            return t
        }
    }

    @inline(__always)
    func startThread(_ t: UUID, _ service: NotificationService) {
        queue.sync {
            if allThreads.contains(t) {
                activeThreads.append((t, service))
            } else {
                logger.warning("NotificationService startThread: thread \(t) was removed before it started")
            }
        }
    }

    @inline(__always)
    func startEntity(_ nse: NotificationService, _ ntfEntity: NotificationEntity) -> Bool {
        queue.sync {
            let canStart = !activeThreads.contains(where: { (tId, otherNSE) in
                tId != nse.threadId
                && otherNSE.notificationEntities.contains(where: { (id, otherEntity) in
                    id == ntfEntity.entityId
                    && otherEntity.expectedMsg != nil
                })
            })
            let id = ntfEntity.entityId
            nse.notificationEntities[id] = ntfEntity
            if canStart {
                nse.notificationEntities[id]?.startedProcessingNewMsgs = true
            }
            return canStart
        }
    }

    @inline(__always)
    func addDroppedNtf(_ id: ChatId, _ ntf: NSENotificationData) {
        queue.sync { droppedNotifications.append((id, ntf)) }
    }

    @inline(__always)
    func takeDroppedNtf(_ ntfEntity: NotificationEntity) -> (entityId: ChatId, ntf: NSENotificationData)? {
        queue.sync {
            if droppedNotifications.isEmpty {
                nil
            } else if let i = droppedNotifications.firstIndex(where: { (id, _) in id == ntfEntity.entityId }) {
                droppedNotifications.remove(at: i)
            } else {
                nil
            }
        }
    }

    @inline(__always)
    func processNotification(_ id: ChatId, _ ntf: NSENotificationData) async -> Void {
        if let (nse, ntfEntity, expectedMsg) = rcvEntityThread(id, ntf) {
            logger.debug("NotificationService processNotification \(id): found nse thread expecting message")
            if nse.processReceivedNtf(ntfEntity, expectedMsg, ntf) {
                nse.finalizeEntity(id)
            }
        }
    }

    @inline(__always)
    private func rcvEntityThread(_ id: ChatId, _ ntf: NSENotificationData) -> (NotificationService, NotificationEntity, NtfMsgInfo)? {
        queue.sync {
            let r = activeThreads.lazy.compactMap({ (_, nse) in
                let ntfEntity = nse.notificationEntities[id]
                return if let ntfEntity, let expectedMsg = ntfEntity.expectedMsg, ntfEntity.shouldProcessNtf {
                    (nse, ntfEntity, expectedMsg)
                } else {
                    nil
                }
            }).first
            if r == nil { droppedNotifications.append((id, ntf)) }
            return r
        }
    }

    @inline(__always)
    func signalNextThread(_ nse: NotificationService, _ id: ChatId) {
        queue.sync {
            nse.notificationEntities[id]?.expectedMsg = nil
            nse.notificationEntities[id]?.shouldProcessNtf = false
            let next = activeThreads.first(where: { (_, nseNext) in
                if let ntfEntity = nseNext.notificationEntities[id] {
                    ntfEntity.expectedMsg != nil && !ntfEntity.startedProcessingNewMsgs
                } else {
                    false
                }
            })
            if let (tNext, nseNext) = next {
                if let t = nse.threadId { logger.debug("NotificationService thread \(t): signalNextThread: signal next thread \(tNext) for entity \(id)") }
                nseNext.notificationEntities[id]?.startedProcessingNewMsgs = true
                nseNext.notificationEntities[id]?.semaphore.signal()
            }
        }
    }

    @inline(__always)
    func endThread(_ t: UUID) -> Bool {
        queue.sync {
            let tActive: UUID? = if let index = activeThreads.firstIndex(where: { $0.0 == t }) {
                activeThreads.remove(at: index).0
            } else {
                nil
            }
            let t = allThreads.remove(t)
            if tActive != nil && activeThreads.isEmpty {
                return true
            }
            if t != nil && allThreads.isEmpty {
                NSEChatState.shared.set(.suspended)
            }
            return false
        }
    }

    @inline(__always)
    var noThreads: Bool {
        allThreads.isEmpty
    }
}

struct NotificationEntity {
    var ntfConn: NtfConn
    var entityId: ChatId

    var expectedMsg: NtfMsgInfo?
    var allowedGetNextAttempts: Int = 3
    var msgBestAttemptNtf: NSENotificationData

    var startedProcessingNewMsgs: Bool = false

    var shouldProcessNtf: Bool = false

    var semaphore: DispatchSemaphore = DispatchSemaphore(value: 0)

    var connMsgReq: ConnMsgReq? {
        if let expectedMsg {
            ConnMsgReq(msgConnId: ntfConn.agentConnId, msgDbQueueId: ntfConn.agentDbQueueId, msgTs: expectedMsg.msgTs)
        } else {
            nil
        }
    }
}

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var serviceBestAttemptNtf: UNMutableNotificationContent?
    var badgeCount: Int = 0
    var threadId: UUID? = NSEThreads.shared.newThread()
    var notificationEntities: Dictionary<String, NotificationEntity> = [:]
    var appSubscriber: AppSubscriber?
    var returnedSuspension = false

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        logger.debug("DEBUGGING: NotificationService.didReceive")
        let receivedNtf = if let ntf_ = request.content.mutableCopy() as? UNMutableNotificationContent { ntf_ } else { UNMutableNotificationContent() }
        setServiceBestAttemptNtf(receivedNtf)
        self.contentHandler = contentHandler
        registerGroupDefaults()
        let appState = appStateGroupDefault.get()
        logger.debug("NotificationService: app is \(appState.rawValue)")
        switch appState {
        case .stopped:
            setBadgeCount()
            contentHandler(createAppStoppedNtf(badgeCount))
        case .suspended:
            setExpirationTimer()
            receiveNtfMessages(request)
        case .suspending:
            setExpirationTimer()
            Task {
                let state: AppState = await withCheckedContinuation { cont in
                    appSubscriber = appStateSubscriber { s in
                        if s == .suspended { appSuspension(s) }
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + Double(appSuspendTimeout) + 1) {
                        logger.debug("NotificationService: appSuspension timeout")
                        appSuspension(appStateGroupDefault.get())
                    }

                    @Sendable
                    func appSuspension(_ s: AppState) {
                        if !self.returnedSuspension {
                            self.returnedSuspension = true
                            self.appSubscriber = nil
                            cont.resume(returning: s)
                        }
                    }
                }
                logger.debug("NotificationService: app state is now \(state.rawValue)")
                if state.inactive && self.contentHandler != nil {
                    receiveNtfMessages(request)
                } else {
                    contentHandler(receivedNtf)
                }
            }
        case .active: contentHandler(receivedNtf)
        case .activating: contentHandler(receivedNtf)
        case .bgRefresh: contentHandler(receivedNtf)
        }
    }

    @inline(__always)
    private func setExpirationTimer() -> Void {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            self.deliverBestAttemptNtf(urgent: true)
        }
    }

    @inline(__always)
    private func ntfRequestData(_ request: UNNotificationRequest) -> (nonce: String, encNtfInfo: String)? {
        if let ntfData = request.content.userInfo["notificationData"] as? [AnyHashable : Any],
           let nonce = ntfData["nonce"] as? String,
           let encNtfInfo = ntfData["message"] as? String {
            (nonce, encNtfInfo)
        } else {
            nil
        }
    }

    func receiveNtfMessages(_ request: UNNotificationRequest) {
        logger.debug("NotificationService: receiveNtfMessages")
        if case .documents = dbContainerGroupDefault.get() {
            deliverBestAttemptNtf()
            return
        }
        if let nrData = ntfRequestData(request),
           appStateGroupDefault.get().inactive {
            guard let t = threadId else { return }
            NSEThreads.shared.startThread(t, self)
            let dbStatus = startChat()
            if case .ok = dbStatus,
               let ntfConns = apiGetNtfConns(nonce: nrData.nonce, encNtfInfo: nrData.encNtfInfo) {
                logger.debug("NotificationService: receiveNtfMessages: apiGetNtfConns ntfConns count = \(ntfConns.count)")

                let ntfEntities = ntfConns.compactMap(mkNotificationEntity)

                let msgReqs: [(chatId: String, connMsgReq: ConnMsgReq)] = ntfEntities.compactMap { ntfEntity -> (chatId: String, connMsgReq: ConnMsgReq)? in
                    let id = ntfEntity.entityId
                    if let expectedMsg = ntfEntity.expectedMsg {
                        if NSEThreads.shared.startEntity(self, ntfEntity) {
                            let completed = processDroppedNotifications(ntfEntity, expectedMsg)
                            return if !completed, let connMsgReq = notificationEntities[id]?.connMsgReq {
                                (id, connMsgReq)
                            } else {
                                nil
                            }
                        } else {
                            logger.debug("NotificationService thread \(t, privacy: .private): receiveNtfMessages: entity \(id, privacy: .private) waiting on semaphore")
                            notificationEntities[id]?.semaphore.wait()
                            logger.debug("NotificationService thread \(t, privacy: .private): receiveNtfMessages: entity \(id, privacy: .private) proceeding after semaphore")
                            Task {
                                let completed = processDroppedNotifications(ntfEntity, expectedMsg)
                                if !completed, let connMsgReq = notificationEntities[id]?.connMsgReq,
                                   let rcvMsg = getConnNtfMessage(connMsgReq: connMsgReq),
                                   rcvMsg.noMsg {
                                    finalizeEntity(id)
                                }
                            }
                            return nil
                        }
                    } else {
                        notificationEntities[id] = ntfEntity
                        return nil
                    }
                }

                if !msgReqs.isEmpty,
                   let rcvMsgs = apiGetConnNtfMessages(connMsgReqs: msgReqs.map { $0.connMsgReq }) {
                    for i in 0 ..< min(msgReqs.count, rcvMsgs.count) {
                        if rcvMsgs[i].noMsg {
                            finalizeEntity(msgReqs[i].chatId)
                        }
                    }
                }
            } else if let dbStatus = dbStatus {
                setServiceBestAttemptNtf(createErrorNtf(dbStatus, badgeCount))
            }
        }
        deliverBestAttemptNtf()
    }

    @inline(__always)
    func mkNotificationEntity(ntfConn: NtfConn) -> NotificationEntity? {
        if let rcvEntityId = ntfConn.connEntity.id {
            let expectedMsg: NtfMsgInfo? = if ntfConn.user.showNotifications { ntfConn.expectedMsg_ } else { nil }
            return NotificationEntity(
                ntfConn: ntfConn,
                entityId: rcvEntityId,
                expectedMsg: expectedMsg,
                msgBestAttemptNtf: defaultBestAttemptNtf(ntfConn)
            )
        }
        return nil
    }

    func processDroppedNotifications(_ ntfEntity: NotificationEntity, _ expectedMsg: NtfMsgInfo) -> Bool {
        var completed = false
        while !completed {
            if let dropped = NSEThreads.shared.takeDroppedNtf(ntfEntity) {
                completed = processReceivedNtf(ntfEntity, expectedMsg, dropped.ntf)
            } else {
                break
            }
        }
        if completed {
            finalizeEntity(ntfEntity.entityId)
        } else {
            notificationEntities[ntfEntity.entityId]?.shouldProcessNtf = true
        }
        return completed
    }

    override func serviceExtensionTimeWillExpire() {
        logger.debug("DEBUGGING: NotificationService.serviceExtensionTimeWillExpire")
        deliverBestAttemptNtf(urgent: true)
    }

    @inline(__always)
    var expectingMoreMessages: Bool {
        notificationEntities.contains { $0.value.expectedMsg != nil }
    }

    func processReceivedNtf(_ ntfEntity: NotificationEntity, _ expectedMsg: NtfMsgInfo, _ ntf: NSENotificationData) -> Bool {
        let id = ntfEntity.entityId
        if case let .msgInfo(info) = ntf {
            if info.msgId == expectedMsg.msgId {
                logger.debug("NotificationService processNtf: msgInfo msgId = \(info.msgId, privacy: .private): expected")
                return true
            } else if let msgTs = info.msgTs_, msgTs > expectedMsg.msgTs {
                logger.debug("NotificationService processNtf: msgInfo msgId = \(info.msgId, privacy: .private): unexpected msgInfo, let other instance to process it, stopping this one")
                NSEThreads.shared.addDroppedNtf(id, ntf)
                return true
            } else if ntfEntity.allowedGetNextAttempts > 0, let connMsgReq = ntfEntity.connMsgReq {
                logger.debug("NotificationService processNtf: msgInfo msgId = \(info.msgId, privacy: .private): unexpected msgInfo, get next message")
                notificationEntities[id]?.allowedGetNextAttempts -= 1
                let receivedMsg = getConnNtfMessage(connMsgReq: connMsgReq)
                if case let .info(msg) = receivedMsg, let msg {
                    logger.debug("NotificationService processNtf, on getConnNtfMessage: msgInfo msgId = \(info.msgId, privacy: .private), receivedMsg msgId = \(msg.msgId, privacy: .private)")
                    return false
                } else {
                    logger.debug("NotificationService processNtf, on getConnNtfMessage: msgInfo msgId = \(info.msgId, privacy: .private): no next message, deliver best attempt")
                    return true
                }
            } else {
                logger.debug("NotificationService processNtf: msgInfo msgId = \(info.msgId, privacy: .private): unknown message, let other instance to process it")
                return true
            }
        } else if ntfEntity.ntfConn.user.showNotifications {
            logger.debug("NotificationService processNtf: setting best attempt")
            if ntf.notificationEvent != nil {
                setBadgeCount()
            }
            if ntfEntity.msgBestAttemptNtf.callInvitation == nil || ntf.callInvitation != nil {
                notificationEntities[id]?.msgBestAttemptNtf = ntf
            }
            return false
        } else {
            return true
        }
    }

    func finalizeEntity(_ entityId: ChatId) {
        if let t = threadId { logger.debug("NotificationService thread \(t): entityReady: entity \(entityId)") }
        NSEThreads.shared.signalNextThread(self, entityId)
        deliverBestAttemptNtf()
    }

    func setBadgeCount() {
        badgeCount = ntfBadgeCountGroupDefault.get() + 1
        ntfBadgeCountGroupDefault.set(badgeCount)
    }

    @inline(__always)
    func setServiceBestAttemptNtf(_ ntf: UNMutableNotificationContent) {
        logger.debug("NotificationService.setServiceBestAttemptNtf")
        serviceBestAttemptNtf = ntf
    }

    private func deliverBestAttemptNtf(urgent: Bool = false) {
        logger.debug("NotificationService.deliverBestAttemptNtf urgent: \(urgent) expectingMoreMessages: \(self.expectingMoreMessages)")
        if let handler = contentHandler, urgent || !expectingMoreMessages {
            if urgent {
                contentHandler = nil
            }
            logger.debug("NotificationService.deliverBestAttemptNtf")
            for (key, _) in notificationEntities {
                notificationEntities[key]?.shouldProcessNtf = false
            }

            let suspend: Bool
            if let t = threadId {
                threadId = nil
                suspend = NSEThreads.shared.endThread(t) && NSEThreads.shared.noThreads
            } else {
                suspend = false
            }
            deliverCallkitOrNotification(urgent: urgent, suspend: suspend, handler: handler)
        }
    }

    @inline(__always)
    private func deliverCallkitOrNotification(urgent: Bool, suspend: Bool = false, handler: @escaping (UNNotificationContent) -> Void) {
        let callInv = notificationEntities.lazy.compactMap({ $0.value.msgBestAttemptNtf.callInvitation }).first
        if callInv != nil && useCallKit() {
            logger.debug("NotificationService.deliverCallkitOrNotification: will suspend, callkit")
            if urgent {
                suspendChat(0)
                deliverNotification(handler, callInv)
            } else {
                DispatchQueue.global().asyncAfter(deadline: .now() + fastNSESuspendSchedule.delay) {
                    suspendChat(fastNSESuspendSchedule.timeout)
                    DispatchQueue.global().asyncAfter(deadline: .now() + Double(fastNSESuspendSchedule.timeout)) {
                        self.deliverNotification(handler, callInv)
                    }
                }
            }
        } else {
            if suspend {
                logger.debug("NotificationService.deliverCallkitOrNotification: will suspend")
                if urgent {
                    suspendChat(0)
                } else {
                    DispatchQueue.global().asyncAfter(deadline: .now() + nseSuspendSchedule.delay) {
                        if NSEThreads.shared.noThreads {
                            suspendChat(nseSuspendSchedule.timeout)
                        }
                    }
                }
            }
            deliverNotification(handler, callInv)
        }
    }

    private func deliverNotification(_ handler: @escaping (UNNotificationContent) -> Void, _ callInv: RcvCallInvitation?) {
        if let serviceNtf = serviceBestAttemptNtf {
            serviceBestAttemptNtf = nil
            contentHandler = nil
            if let callInv {
                if useCallKit() {
                    logger.debug("NotificationService reportNewIncomingVoIPPushPayload for \(callInv.contact.id)")
                    CXProvider.reportNewIncomingVoIPPushPayload([
                        "displayName": callInv.contact.displayName,
                        "contactId": callInv.contact.id,
                        "callUUID": callInv.callUUID ?? "",
                        "media": callInv.callType.media.rawValue,
                        "callTs": callInv.callTs.timeIntervalSince1970
                    ]) { error in
                        logger.debug("reportNewIncomingVoIPPushPayload result: \(error)")
                        handler(error == nil ? UNMutableNotificationContent() : createCallInvitationNtf(callInv, self.badgeCount))
                    }
                } else {
                    handler(createCallInvitationNtf(callInv, badgeCount))
                }
            } else if notificationEntities.isEmpty {
                handler(serviceNtf)
            } else {
                handler(prepareNotification())
            }
        }
    }

    @inline(__always)
    private func prepareNotification() -> UNMutableNotificationContent {
        let ntfs = notificationEntities.compactMap { $0.value.msgBestAttemptNtf.notificationEvent }
        let newMsgNtfs = ntfs.compactMap({ $0.newMsgNtf })
        let useNtfs = if newMsgNtfs.isEmpty { ntfs } else { newMsgNtfs }
        return createNtf(useNtfs)

        func createNtf(_ ntfs: [NSENotificationData]) -> UNMutableNotificationContent {
            logger.debug("NotificationService prepareNotification: \(ntfs.count) events")
            return switch ntfs.count {
            case 0: UNMutableNotificationContent()
            case 1: ntfs[0].notificationContent(badgeCount)
            default: createJointNtf(ntfs)
            }
        }
    }

    @inline(__always)
    private func createJointNtf(_ ntfs: [NSENotificationData]) -> UNMutableNotificationContent {
        let previewMode = ntfPreviewModeGroupDefault.get()
        logger.debug("NotificationService.createJointNtf ntfs: \(ntfs.count)")
        let (userId, chatsNames) = newMsgsChatsNames(ntfs)
        if !chatsNames.isEmpty, let userId {
            let body = if previewMode == .hidden {
                String.localizedStringWithFormat(NSLocalizedString("From %d chat(s)", comment: "notification body"), chatsNames.count)
            } else {
                String.localizedStringWithFormat(NSLocalizedString("From: %@", comment: "notification body"), newMsgsChatsNamesStr(chatsNames))
            }
            return createNotification(
                categoryIdentifier: ntfCategoryManyEvents,
                title: NSLocalizedString("New messages", comment: "notification"),
                body: body,
                userInfo: ["userId": userId],
                badgeCount: badgeCount
            )
        } else {
            return createNotification(
                categoryIdentifier: ntfCategoryManyEvents,
                title: NSLocalizedString("New events", comment: "notification"),
                body: String.localizedStringWithFormat(NSLocalizedString("%d new events", comment: "notification body"), ntfs.count),
                badgeCount: badgeCount
            )
        }
    }

    @inline(__always)
    private func newMsgsChatsNames(_ ntfs: [NSENotificationData]) ->  (Int64?, [String]) {
        var seenChatIds = Set<ChatId>()
        var chatsNames: [String] = []
        var userId: Int64?
        for ntf in ntfs {
            switch ntf {
            case let .messageReceived(user, chat, _):
                if seenChatIds.isEmpty { userId = user.userId }
                if !seenChatIds.contains(chat.id) {
                    seenChatIds.insert(chat.id)
                    chatsNames.append(chat.chatViewName)
                }
            default: ()
            }
        }
        return (userId, chatsNames)
    }

    @inline(__always)
    private func newMsgsChatsNamesStr(_ names: [String]) -> String {
        return switch names.count {
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        case 3: "\(names[0] + ", " + names[1]) and \(names[2])"
        default:
            names.count > 3
            ? "\(names[0]), \(names[1]) and \(names.count - 2) other chats"
            : ""
        }
    }
}

class NSEChatState {
    static let shared = NSEChatState()
    private var value_ = NSEState.created

    @inline(__always)
    var value: NSEState { value_ }

    func set(_ state: NSEState) {
        nseStateGroupDefault.set(state)
        sendNSEState(state)
        value_ = state
    }

    private init() {
        set(.created)
    }
}

var appSubscriber: AppSubscriber = appStateSubscriber { state in
    logger.debug("NotificationService: appSubscriber")
    if state.running && NSEChatState.shared.value.canSuspend {
        logger.debug("NotificationService: appSubscriber app state \(state.rawValue), suspending")
        suspendChat(fastNSESuspendSchedule.timeout)
    }
}

func appStateSubscriber(onState: @escaping (AppState) -> Void) -> AppSubscriber {
    appMessageSubscriber { msg in
        if case let .state(state) = msg {
            logger.debug("NotificationService: appStateSubscriber \(state.rawValue)")
            onState(state)
        }
    }
}

let seSubscriber = seMessageSubscriber {
    switch $0 {
    case let .state(state):
        if state == .sendingMessage && NSEChatState.shared.value.canSuspend {
            logger.debug("NotificationService: seSubscriber app state \(state.rawValue), suspending")
            suspendChat(fastNSESuspendSchedule.timeout)
        }
    }
}

var receiverStarted = false
let startLock = DispatchSemaphore(value: 1)
let suspendLock = DispatchSemaphore(value: 1)
var networkConfig: NetCfg = getNetCfg()

func startChat() -> DBMigrationResult? {
    logger.debug("NotificationService: startChat")
    if case .active = NSEChatState.shared.value, hasChatCtrl() { return .ok }

    startLock.wait()
    defer { startLock.signal() }

    if hasChatCtrl() {
        return switch NSEChatState.shared.value {
        case .created: doStartChat()
        case .starting: .ok
        case .active: .ok
        case .suspending: activateChat()
        case .suspended: activateChat()
        }
    } else {
        NSEChatState.shared.set(.created)
        return doStartChat()
    }
}

func doStartChat() -> DBMigrationResult? {
    logger.debug("NotificationService: doStartChat")
    haskell_init_nse()
    let (_, dbStatus) = chatMigrateInit(confirmMigrations: defaultMigrationConfirmation(), backgroundMode: true)
    logger.debug("NotificationService: doStartChat \(String(describing: dbStatus))")
    if dbStatus != .ok {
        resetChatCtrl()
        NSEChatState.shared.set(.created)
        return dbStatus
    }
    let state = NSEChatState.shared.value
    NSEChatState.shared.set(.starting)
    if let user = apiGetActiveUser() {
        logger.debug("NotificationService active user \(user.displayName)")
        do {
            try setNetworkConfig(networkConfig)
            try apiSetAppFilePaths(filesFolder: getAppFilesDirectory().path, tempFolder: getTempFilesDirectory().path, assetsFolder: getWallpaperDirectory().deletingLastPathComponent().path)
            try apiSetEncryptLocalFiles(privacyEncryptLocalFilesGroupDefault.get())
            suspendLock.wait()
            defer { suspendLock.signal() }
            if NSEChatState.shared.value == .starting {
                updateNetCfg()
                let justStarted = try apiStartChat()
                NSEChatState.shared.set(.active)
                if justStarted {
                    chatLastStartGroupDefault.set(Date.now)
                    Task {
                        if !receiverStarted {
                            receiverStarted = true
                            await receiveMessages()
                        }
                    }
                }
                return .ok
            }
        } catch {
            logger.error("NotificationService startChat error: \(responseError(error))")
        }
    } else {
        logger.debug("NotificationService: no active user")
    }
    if NSEChatState.shared.value == .starting { NSEChatState.shared.set(state) }
    return nil
}

func activateChat() -> DBMigrationResult? {
    logger.debug("NotificationService: activateChat")
    let state = NSEChatState.shared.value
    NSEChatState.shared.set(.active)
    if apiActivateChat() {
        logger.debug("NotificationService: activateChat: after apiActivateChat")
        return .ok
    } else {
        NSEChatState.shared.set(state)
        return nil
    }
}

func suspendChat(_ timeout: Int) {
    logger.debug("NotificationService: suspendChat")
    let state = NSEChatState.shared.value
    if !state.canSuspend {
        logger.error("NotificationService suspendChat called, current state: \(state.rawValue)")
    } else if hasChatCtrl() {
        suspendLock.wait()
        defer { suspendLock.signal() }

        NSEChatState.shared.set(.suspending)
        if apiSuspendChat(timeoutMicroseconds: timeout * 1000000) {
            logger.debug("NotificationService: suspendChat: after apiSuspendChat")
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(timeout) + 1, execute: chatSuspended)
        } else {
            NSEChatState.shared.set(state)
        }
    }
}

func chatSuspended() {
    logger.debug("NotificationService chatSuspended")
    if case .suspending = NSEChatState.shared.value {
        NSEChatState.shared.set(.suspended)
        chatCloseStore()
        logger.debug("NotificationService chatSuspended: suspended")
    }
}

func receiveMessages() async {
    logger.debug("NotificationService receiveMessages")
    while true {
        switch NSEChatState.shared.value {
        case .created: await delayWhenInactive()
        case .starting: await delayWhenInactive()
        case .active: await receiveMsg()
        case .suspending: await receiveMsg()
        case .suspended: await delayWhenInactive()
        }
    }

    func receiveMsg() async {
        switch await chatRecvMsg() {
        case let .result(msg):
            logger.debug("NotificationService receiveMsg: message")
            if let (id, ntf) = await receivedMsgNtf(msg) {
                logger.debug("NotificationService receiveMsg: notification")
                await NSEThreads.shared.processNotification(id, ntf)
            }
        case let .error(err):
            logger.error("NotificationService receivedMsgNtf error: \(String(describing: err))")
        case let .invalid(type, _):
            logger.error("NotificationService receivedMsgNtf invalid: \(type)")
        case .none: ()
        }
    }

    func delayWhenInactive() async {
        logger.debug("NotificationService delayWhenInactive")
        _ = try? await Task.sleep(nanoseconds: 1000_000000)
    }
}

func chatRecvMsg() async -> APIResult<NSEChatEvent>? {
    await withCheckedContinuation { cont in
        let resp: APIResult<NSEChatEvent>? = recvZeroMsg()
        cont.resume(returning: resp)
    }
}

private let isInChina = SKStorefront().countryCode == "CHN"

@inline(__always)
private func useCallKit() -> Bool { !isInChina && callKitEnabledGroupDefault.get() }

@inline(__always)
func receivedMsgNtf(_ res: NSEChatEvent) async -> (String, NSENotificationData)? {
    logger.debug("NotificationService receivedMsgNtf: \(res.responseType)")
    switch res {
    case let .contactConnected(user, contact, _):
        return (contact.id, .contactConnected(user, contact))
    case let .receivedContactRequest(user, contactRequest):
        if let userContactLinkId = contactRequest.userContactLinkId_ {
            return (UserContact(userContactLinkId: userContactLinkId).id, .contactRequest(user, contactRequest))
        } else {
            return nil
        }
    case let .newChatItems(user, chatItems):
        if let chatItem = chatItems.first {
            let cInfo = chatItem.chatInfo
            var cItem = chatItem.chatItem
            if let file = cItem.autoReceiveFile() {
                cItem = autoReceiveFile(file) ?? cItem
            }
            let ntf: NSENotificationData = (cInfo.ntfsEnabled(chatItem: cItem) && cItem.showNotification) ? .messageReceived(user, cInfo, cItem) : .noNtf
            let chatIdOrMemberId = if case let .groupRcv(groupMember) = chatItem.chatItem.chatDir {
                groupMember.id
            } else {
                chatItem.chatInfo.id
            }
            return (chatIdOrMemberId, ntf)
        } else {
            return nil
        }
    case let .rcvFileSndCancelled(_, aChatItem, _):
        cleanupFile(aChatItem)
        return nil
    case let .sndFileComplete(_, aChatItem, _):
        cleanupDirectFile(aChatItem)
        return nil
    case let .sndFileRcvCancelled(_, aChatItem, _):
        if let aChatItem = aChatItem {
            cleanupDirectFile(aChatItem)
        }
        return nil
    case let .callInvitation(invitation):
        return (invitation.contact.id, .callInvitation(invitation))
    case let .ntfMessage(_, connEntity, ntfMessage):
        return if let id = connEntity.id { (id, .msgInfo(ntfMessage)) } else { nil }
    case .chatSuspended:
        chatSuspended()
        return nil
    }
}

@inline(__always)
func updateNetCfg() {
    let newNetConfig = getNetCfg()
    if newNetConfig != networkConfig {
        logger.debug("NotificationService applying changed network config")
        do {
            try setNetworkConfig(networkConfig)
            networkConfig = newNetConfig
        } catch {
            logger.error("NotificationService apply changed network config error: \(responseError(error))")
        }
    }
}

func apiGetActiveUser() -> User? {
    let r: APIResult<NSEChatResponse> = sendZeroCmd(NSEChatCommand.showActiveUser)
    logger.debug("apiGetActiveUser sendZeroCmd response: \(r.responseType)")
    switch r {
    case let .result(.activeUser(user)): return user
    case .error(.error(.noActiveUser)):
        logger.debug("apiGetActiveUser sendZeroCmd no active user")
        return nil
    case let .error(err):
        logger.debug("apiGetActiveUser sendZeroCmd error: \(String(describing: err))")
        return nil
    default:
        logger.error("NotificationService apiGetActiveUser unexpected response: \(String(describing: r))")
        return nil
    }
}

func apiStartChat() throws -> Bool {
    let r: APIResult<NSEChatResponse> = sendZeroCmd(NSEChatCommand.startChat(mainApp: false, enableSndFiles: false))
    switch r {
    case .result(.chatStarted): return true
    case .result(.chatRunning): return false
    default: throw r.unexpected
    }
}

func apiActivateChat() -> Bool {
    chatReopenStore()
    let r: APIResult<NSEChatResponse> = sendZeroCmd(NSEChatCommand.apiActivateChat(restoreChat: false))
    if case .result(.cmdOk) = r { return true }
    logger.error("NotificationService apiActivateChat error: \(String(describing: r))")
    return false
}

func apiSuspendChat(timeoutMicroseconds: Int) -> Bool {
    let r: APIResult<NSEChatResponse> = sendZeroCmd(NSEChatCommand.apiSuspendChat(timeoutMicroseconds: timeoutMicroseconds))
    if case .result(.cmdOk) = r { return true }
    logger.error("NotificationService apiSuspendChat error: \(String(describing: r))")
    return false
}

func apiSetAppFilePaths(filesFolder: String, tempFolder: String, assetsFolder: String) throws {
    let r: APIResult<NSEChatResponse> = sendZeroCmd(NSEChatCommand.apiSetAppFilePaths(filesFolder: filesFolder, tempFolder: tempFolder, assetsFolder: assetsFolder))
    if case .result(.cmdOk) = r { return }
    throw r.unexpected
}

func apiSetEncryptLocalFiles(_ enable: Bool) throws {
    let r: APIResult<NSEChatResponse> = sendZeroCmd(NSEChatCommand.apiSetEncryptLocalFiles(enable: enable))
    if case .result(.cmdOk) = r { return }
    throw r.unexpected
}

func apiGetNtfConns(nonce: String, encNtfInfo: String) -> [NtfConn]? {
    guard apiGetActiveUser() != nil else {
        logger.debug("NotificationService: no active user")
        return nil
    }
    let r: APIResult<NSEChatResponse> = sendZeroCmd(NSEChatCommand.apiGetNtfConns(nonce: nonce, encNtfInfo: encNtfInfo))
    if case let .result(.ntfConns(ntfConns)) = r {
        logger.debug("NotificationService apiGetNtfConns response ntfConns: \(ntfConns.count) conections")
        return ntfConns
    } else if case let .error(error) = r {
        logger.debug("NotificationService apiGetNtfMessage error response: \(String.init(describing: error))")
    } else {
        logger.debug("NotificationService apiGetNtfMessage ignored response: \(r.responseType) \(String.init(describing: r))")
    }
    return nil
}

func apiGetConnNtfMessages(connMsgReqs: [ConnMsgReq]) -> [RcvNtfMsgInfo]? {
    guard apiGetActiveUser() != nil else {
        logger.debug("no active user")
        return nil
    }
    logger.debug("NotificationService apiGetConnNtfMessages requests: \(connMsgReqs.count)")
    let r: APIResult<NSEChatResponse> = sendZeroCmd(NSEChatCommand.apiGetConnNtfMessages(connMsgReqs: connMsgReqs))
    if case let .result(.connNtfMessages(msgs)) = r {
        logger.debug("NotificationService apiGetConnNtfMessages responses: total \(msgs.count), expecting messages \(msgs.count { !$0.noMsg }), errors \(msgs.count { $0.isError })")
        return msgs
    }
    logger.debug("NotificationService apiGetConnNtfMessages error: \(responseError(r.unexpected))")
    return nil
}

func getConnNtfMessage(connMsgReq: ConnMsgReq) -> RcvNtfMsgInfo? {
    let r = apiGetConnNtfMessages(connMsgReqs: [connMsgReq])
    return if let r, r.count > 0 { r[0] } else { nil }
}

func apiReceiveFile(fileId: Int64, encrypted: Bool, inline: Bool? = nil) -> AChatItem? {
    let userApprovedRelays = !privacyAskToApproveRelaysGroupDefault.get()
    let r: APIResult<NSEChatResponse> = sendZeroCmd(NSEChatCommand.receiveFile(fileId: fileId, userApprovedRelays: userApprovedRelays, encrypted: encrypted, inline: inline))
    if case let .result(.rcvFileAccepted(_, chatItem)) = r { return chatItem }
    logger.error("receiveFile error: \(responseError(r.unexpected))")
    return nil
}

func apiSetFileToReceive(fileId: Int64, encrypted: Bool) {
    let userApprovedRelays = !privacyAskToApproveRelaysGroupDefault.get()
    let r: APIResult<NSEChatResponse> = sendZeroCmd(NSEChatCommand.setFileToReceive(fileId: fileId, userApprovedRelays: userApprovedRelays, encrypted: encrypted))
    if case .result(.cmdOk) = r { return }
    logger.error("setFileToReceive error: \(responseError(r.unexpected))")
}

func autoReceiveFile(_ file: CIFile) -> ChatItem? {
    let encrypted = privacyEncryptLocalFilesGroupDefault.get()
    switch file.fileProtocol {
    case .smp:
        return apiReceiveFile(fileId: file.fileId, encrypted: encrypted)?.chatItem
    case .xftp:
        apiSetFileToReceive(fileId: file.fileId, encrypted: encrypted)
        return nil
    case .local:
        return nil
    }
}

func setNetworkConfig(_ cfg: NetCfg) throws {
    let r: APIResult<NSEChatResponse> = sendZeroCmd(NSEChatCommand.apiSetNetworkConfig(networkConfig: cfg))
    if case .result(.cmdOk) = r { return }
    throw r.unexpected
}

func defaultBestAttemptNtf(_ ntfConn: NtfConn) -> NSENotificationData {
    let user = ntfConn.user
    let connEntity = ntfConn.connEntity
    return if !user.showNotifications {
        .noNtf
    } else {
        switch ntfConn.connEntity {
        case let .rcvDirectMsgConnection(_, contact):
            contact?.chatSettings.enableNtfs == .all
            ? .connectionEvent(user, connEntity)
            : .noNtf
        case let .rcvGroupMsgConnection(_, groupInfo, _):
            groupInfo.chatSettings.enableNtfs == .all
            ? .connectionEvent(user, connEntity)
            : .noNtf
        case let .userContactConnection(_, userContact):
            userContact.groupId == nil
            ? .connectionEvent(user, connEntity)
            : .noNtf
        }
    }
}
