import {CC, CEvt, ChatEvent, ChatResponse, T} from "@zero-runtime/types"
import * as core from "./core"
import * as util from "./util"

export class ChatCommandError extends Error {
  constructor(public message: string, public response: ChatResponse) {
    super(message)
  }
}

export enum ConnReqType {
  Invitation = "invitation",
  Contact = "contact",
}

export interface BotAddressSettings {

  autoAccept?: boolean

  welcomeMessage?: T.MsgContent | string | undefined

  businessAddress?: boolean
}

export const defaultBotAddressSettings: BotAddressSettings = {
  autoAccept: true,
  welcomeMessage: undefined,
  businessAddress: false
}

export type EventSubscriberFunc<K extends CEvt.Tag> = (event: ChatEvent & {type: K}) => void | Promise<void>

export type EventSubscribers = {[K in CEvt.Tag]?: EventSubscriberFunc<K>}

interface EventSubscriber<K extends CEvt.Tag> {
  subscriber: EventSubscriberFunc<K>
  once: boolean
}

export type DbConfig =
  | {

      type: "sqlite"

      filePrefix: string

      encryptionKey?: string
    }
  | {

      type: "postgres"

      schemaPrefix?: string

      connectionString: string
    }

function dbConfigToMigrateArgs(db: DbConfig): [string, string] {
  switch (db.type) {
    case "sqlite":
      return [db.filePrefix, db.encryptionKey ?? ""]
    case "postgres":
      return [db.schemaPrefix ?? "", db.connectionString]
    default:
      throw new Error(`Invalid DbConfig: ${JSON.stringify(db satisfies never)}`)
  }
}

export class ChatApi {
  private receiveEvents = false
  private eventsLoop: Promise<void> | undefined = undefined
  private subscribers: {[K in CEvt.Tag]?: EventSubscriber<K>[]} = {}
  private receivers: EventSubscriberFunc<CEvt.Tag>[] = []

  private constructor(protected ctrl_: bigint | undefined) {}

  static async init(
    db: DbConfig,
    confirm = core.MigrationConfirmation.YesUp
  ): Promise<ChatApi> {
    const [path, key] = dbConfigToMigrateArgs(db)
    const ctrl = await core.chatMigrateInit(path, key, confirm)
    return new ChatApi(ctrl)
  }

  async startChat(): Promise<void> {
    this.receiveEvents = true
    this.eventsLoop = this.runEventsLoop()
    const r = await this.sendChatCmd(CC.StartChat.cmdString({mainApp: true, enableSndFiles: true}))
    if (r.type !== "chatStarted" && r.type !== "chatRunning") {
      throw new ChatCommandError("error starting chat", r)
    }
  }

  async stopChat(): Promise<void> {
    const r = await this.sendChatCmd("/_stop")
    if (r.type !== "chatStopped") throw new ChatCommandError("error starting chat", r)
    this.receiveEvents = false
    if (this.eventsLoop) await this.eventsLoop
    this.eventsLoop = undefined
  }

  async close(): Promise<void> {
    this.receiveEvents = false
    if (this.eventsLoop) await this.eventsLoop
    this.eventsLoop = undefined
    await core.chatCloseStore(this.ctrl)
    this.ctrl_ = undefined
  }

  private async runEventsLoop(): Promise<void> {
    while (this.receiveEvents) {
      try {
        const event = await this.recvChatEvent()
        if (!event) continue
        const subs = this.subscribers[event.type]
        if (subs) {
          for (const {subscriber, once} of [...subs]) {
            try {
              const p = (subscriber as EventSubscriberFunc<typeof event.type>)(event)
              if (p instanceof Promise) await p
            } catch(e) {
              console.log(`${event.type} event processing error`, e)
            }
            if (once) this.off(event.type, subscriber as EventSubscriberFunc<typeof event.type>)
          }
        }
        for (const r of [...this.receivers]) {
          try {
            const p = r(event)
            if (p instanceof Promise) await p
          } catch(e) {
            console.log(`${event.type} event processing error`, e)
          }
        }
      } catch(err) {
        const e = err as core.ChatAPIError
        if ("chatError" in e) {
          console.log("Chat error", e.chatError)
        } else {
          console.log("Invalid event", e)
        }
      }
    }
  }

  on<K extends CEvt.Tag>(subscribers: EventSubscribers): void

  on<K extends CEvt.Tag>(event: K, subscriber: EventSubscriberFunc<K>): void
  on<K extends CEvt.Tag>(events: K | EventSubscribers, subscriber?: EventSubscriberFunc<K>): void {
    if (typeof events === "string" && subscriber) {
      this.on_(events, subscriber)
    } else {
      const eventEntries = Object.entries(events) as [CEvt.Tag, EventSubscriberFunc<CEvt.Tag> | undefined][]
      for (const [event, subscriber] of eventEntries) {
        if (subscriber) this.on_(event, subscriber)
      }
    }
  }

  private on_<K extends CEvt.Tag>(event: K, subscriber: EventSubscriberFunc<K>, once: boolean = false): void {
    const subs: EventSubscriber<K>[] = this.subscribers[event] || (this.subscribers[event] = [])
    if (subs.some(s => s.subscriber === subscriber)) throw Error(`this function is already subscribed to ${event}`)
    subs.push({subscriber, once})
  }

  onAny(receiver: EventSubscriberFunc<CEvt.Tag>): void {
    if (this.receivers.some(s => s === receiver)) throw Error("this function is already subscribed")
    this.receivers.push(receiver)
  }

  once<K extends CEvt.Tag>(event: K, subscriber: EventSubscriberFunc<K>): void {
    this.on_(event, subscriber, true)
  }

  wait<K extends CEvt.Tag>(event: K): Promise<ChatEvent & {type: K}>
  wait<K extends CEvt.Tag>(event: K, predicate: ((event: ChatEvent & {type: K}) => boolean) | undefined): Promise<ChatEvent & {type: K}>
  wait<K extends CEvt.Tag>(event: K, timeout: number): Promise<ChatEvent & {type: K} | undefined>
  wait<K extends CEvt.Tag>(event: K, predicate: ((event: ChatEvent & {type: K}) => boolean) | undefined, timeout: number): Promise<ChatEvent & {type: K} | undefined>
  wait<K extends CEvt.Tag>(
    event: K,
    predicate: ((event: ChatEvent & {type: K}) => boolean) | undefined | number = undefined,
    timeout: number = 0
  ): Promise<ChatEvent & {type: K} | undefined> {
    if (typeof predicate === "number") {
      timeout = predicate
      predicate = undefined
    }
    return new Promise((resolve, reject) => {
      let done = false
      const cleanup = () => {
        done = true
        this.off(event, subscriber)
      }
      const subscriber: EventSubscriberFunc<K> = async (evt: ChatEvent & {type: K}) => {
        if (done) return
        if (predicate) {
          try { if (!predicate(evt)) return }
          catch(e) { cleanup(); reject(e); return }
        }
        cleanup()
        resolve(evt)
      }
      this.on(event, subscriber)
      if (timeout > 0) {
        setTimeout(() => { if (!done) { cleanup(); resolve(undefined) } }, timeout)
      }
    })
  }

  off<K extends CEvt.Tag>(event: K, subscriber: EventSubscriberFunc<K> | undefined = undefined): void {
    if (subscriber) {
      const subs = this.subscribers[event]
      if (subs) {
        const i = subs.findIndex(s => s.subscriber === subscriber)
        if (i >= 0) subs.splice(i, 1)
      }
    } else {
      delete this.subscribers[event]
    }
  }

  offAny(receiver: EventSubscriberFunc<CEvt.Tag> | undefined = undefined): void {
    if (receiver) {
      const i = this.receivers.findIndex(r => r === receiver)
      if (i >= 0) this.receivers.splice(i, 1)
    } else {
      this.receivers = []
    }
  }

  get initialized(): boolean {
    return typeof this.ctrl_ === "bigint"
  }

  get started(): boolean {
    return this.receiveEvents && this.eventsLoop !== undefined
  }

  get ctrl(): bigint {
    if (typeof this.ctrl_ === "bigint") return this.ctrl_
    else throw Error("chat api controller not initialized")
  }

  async sendChatCmd(cmd: string): Promise<ChatResponse> {
    return await core.chatSendCmd(this.ctrl, cmd)
  }

  async recvChatEvent(wait: number = 5_000_000): Promise<ChatEvent | undefined> {
    return await core.chatRecvMsgWait(this.ctrl, wait)
  }

  async apiCreateUserAddress(userId: number): Promise<T.CreatedConnLink> {
    const r = await this.sendChatCmd(CC.APICreateMyAddress.cmdString({userId}))
    if (r.type === "userContactLinkCreated") return r.connLinkContact
    throw new ChatCommandError("error creating user address", r)
  }

  async apiDeleteUserAddress(userId: number): Promise<void> {
    const r = await this.sendChatCmd(CC.APIDeleteMyAddress.cmdString({userId}))
    if (r.type === "userContactLinkDeleted") return
    throw new ChatCommandError("error deleting user address", r)
  }

  async apiGetUserAddress(userId: number): Promise<T.UserContactLink | undefined> {
    try {
      const r = await this.sendChatCmd(CC.APIShowMyAddress.cmdString({userId}))
      switch (r.type) {
        case "userContactLink": return r.contactLink
        default: throw new ChatCommandError("error loading user address", r)
      }
    } catch (err) {
      const e = err as any
      if (e.chatError?.type === "errorStore" && e.chatError.storeError?.type === "userContactLinkNotFound") return undefined
      throw e
    }
  }

  async apiSetProfileAddress(userId: number, enable: boolean): Promise<T.UserProfileUpdateSummary> {
    const r = await this.sendChatCmd(CC.APISetProfileAddress.cmdString({userId, enable}))
    switch (r.type) {
      case "userProfileUpdated":
        return r.updateSummary
      default:
        throw new ChatCommandError("error loading user address", r)
    }
  }

  async apiSetAddressSettings(userId: number, {autoAccept, welcomeMessage, businessAddress}: BotAddressSettings): Promise<void> {
    const autoReply = welcomeMessage || defaultBotAddressSettings.welcomeMessage
    const settings: T.AddressSettings = {
      autoAccept: (autoAccept === undefined ? defaultBotAddressSettings.autoAccept : autoAccept) ? {acceptIncognito: false} : undefined,
      autoReply: typeof autoReply === "string" ? {type: "text", text: autoReply} : autoReply,
      businessAddress: businessAddress || defaultBotAddressSettings.businessAddress || false
    }
    const r = await this.sendChatCmd(CC.APISetAddressSettings.cmdString({userId, settings}))
    if (r.type !== "userContactLinkUpdated") {
      throw new ChatCommandError("error changing user contact address settings", r)
    }
  }

  async apiSendMessages(chat: [T.ChatType, number] | T.ChatRef | T.ChatInfo, messages: T.ComposedMessage[], liveMessage = false): Promise<T.AChatItem[]> {
    const sendRef = Array.isArray(chat)
                    ? {chatType: chat[0], chatId: chat[1]}
                    : "chatType" in chat
                    ? chat
                    : util.chatInfoRef(chat)
    if (!sendRef) throw Error("apiSendMessages: can't send messages to this chat")
    const r = await this.sendChatCmd(
      CC.APISendMessages.cmdString({
        sendRef,
        composedMessages: messages,
        liveMessage,
        signMessages: false
      })
    )
    if (r.type === "newChatItems") return r.chatItems
    throw new ChatCommandError("unexpected response", r)
  }

  async apiSendTextMessage(chat: [T.ChatType, number] | T.ChatRef | T.ChatInfo, text: string, inReplyTo?: number): Promise<T.AChatItem[]> {
    return this.apiSendMessages(chat, [{msgContent: {type: "text", text}, mentions: {}, quotedItemId: inReplyTo}])
  }

  async apiSendTextReply(chatItem: T.AChatItem, text: string): Promise<T.AChatItem[]> {
    return this.apiSendTextMessage(chatItem.chatInfo, text, chatItem.chatItem.meta.itemId)
  }

  async apiUpdateChatItem(chatType: T.ChatType, chatId: number, chatItemId: number, msgContent: T.MsgContent, liveMessage: false): Promise<T.ChatItem> {
    const r = await this.sendChatCmd(
      CC.APIUpdateChatItem.cmdString({
        chatRef: {chatType, chatId},
        chatItemId,
        liveMessage,
        updatedMessage: {msgContent, mentions: {}},
      })
    )
    if (r.type === "chatItemUpdated") return r.chatItem.chatItem
    throw new ChatCommandError("error updating chat item", r)
  }

  async apiDeleteChatItems(
    chatType: T.ChatType,
    chatId: number,
    chatItemIds: number[],
    deleteMode: T.CIDeleteMode
  ): Promise<T.ChatItemDeletion[]> {
    const r = await this.sendChatCmd(CC.APIDeleteChatItem.cmdString({chatRef: {chatType, chatId}, chatItemIds, deleteMode}))
    if (r.type === "chatItemsDeleted") return r.chatItemDeletions
    throw new ChatCommandError("error deleting chat item", r)
  }

  async apiDeleteMemberChatItem(groupId: number, chatItemIds: number[]): Promise<T.ChatItemDeletion[]> {
    const r = await this.sendChatCmd(CC.APIDeleteMemberChatItem.cmdString({groupId, chatItemIds}))
    if (r.type === "chatItemsDeleted") return r.chatItemDeletions
    throw new ChatCommandError("error deleting member chat item", r)
  }

  async apiChatItemReaction(
    chatType: T.ChatType,
    chatId: number,
    chatItemId: number,
    add: boolean,
    reaction: T.MsgReaction
  ) {
    const r = await this.sendChatCmd(CC.APIChatItemReaction.cmdString({chatRef: {chatType, chatId}, chatItemId, add, reaction}))
    if (r.type === "chatItemsDeleted") return r.chatItemDeletions
    throw new ChatCommandError("error setting item reaction", r)
  }

  async apiReceiveFile(fileId: number): Promise<T.AChatItem> {
    const r = await this.sendChatCmd(CC.ReceiveFile.cmdString({fileId, userApprovedRelays: true}))
    if (r.type === "rcvFileAccepted") return r.chatItem
    throw new ChatCommandError("error receiving file", r)
  }

  async apiCancelFile(fileId: number): Promise<void> {
    const r = await this.sendChatCmd(CC.CancelFile.cmdString({fileId}))
    if (r.type === "sndFileCancelled" || r.type === "rcvFileCancelled") return
    throw new ChatCommandError("error canceling file", r)
  }

  async apiAddMember(groupId: number, contactId: number, memberRole: T.GroupMemberRole): Promise<T.GroupMember> {
    const r = await this.sendChatCmd(CC.APIAddMember.cmdString({groupId, contactId, memberRole}))
    if (r.type === "sentGroupInvitation") return r.member
    throw new ChatCommandError("error adding member", r)
  }

  async apiJoinGroup(groupId: number): Promise<T.GroupInfo> {
    const r = await this.sendChatCmd(CC.APIJoinGroup.cmdString({groupId}))
    if (r.type === "userAcceptedGroupSent") return r.groupInfo
    throw new ChatCommandError("error joining group", r)
  }

  async apiAcceptMember(groupId: number, groupMemberId: number, memberRole: T.GroupMemberRole): Promise<T.GroupMember> {
    const r = await this.sendChatCmd(CC.APIAcceptMember.cmdString({groupId, groupMemberId, memberRole}))
    if (r.type === "memberAccepted") return r.member
    throw new ChatCommandError("error accepting member", r)
  }

  async apiSetMembersRole(groupId: number, groupMemberIds: number[], memberRole: T.GroupMemberRole): Promise<void> {
    const r = await this.sendChatCmd(CC.APIMembersRole.cmdString({groupId, groupMemberIds, memberRole}))
    if (r.type === "membersRoleUser") return
    throw new ChatCommandError("error setting members role", r)
  }

  async apiBlockMembersForAll(groupId: number, groupMemberIds: number[], blocked: boolean): Promise<void> {
    const r = await this.sendChatCmd(CC.APIBlockMembersForAll.cmdString({groupId, groupMemberIds, blocked}))
    if (r.type === "membersBlockedForAllUser") return
    throw new ChatCommandError("error blocking members", r)
  }

  async apiRemoveMembers(groupId: number, memberIds: number[], withMessages = false): Promise<T.GroupMember[]> {
    const r = await this.sendChatCmd(CC.APIRemoveMembers.cmdString({groupId, groupMemberIds: memberIds, withMessages}))
    if (r.type === "userDeletedMembers") return r.members
    throw new ChatCommandError("error removing member", r)
  }

  async apiLeaveGroup(groupId: number): Promise<T.GroupInfo> {
    const r = await this.sendChatCmd(CC.APILeaveGroup.cmdString({groupId}))
    if (r.type === "leftMemberUser") return r.groupInfo
    throw new ChatCommandError("error leaving group", r)
  }

  async apiListMembers(groupId: number): Promise<T.GroupMember[]> {
    const r = await this.sendChatCmd(CC.APIListMembers.cmdString({groupId}))
    if (r.type === "groupMembers") return r.group.members
    throw new ChatCommandError("error getting group members", r)
  }

  async apiNewGroup(userId: number, groupProfile: T.GroupProfile): Promise<T.GroupInfo> {
    const r = await this.sendChatCmd(CC.APINewGroup.cmdString({userId, groupProfile, incognito: false}))
    if (r.type === "groupCreated") return r.groupInfo
    throw new ChatCommandError("error creating group", r)
  }

  async apiUpdateGroupProfile(groupId: number, groupProfile: T.GroupProfile): Promise<T.GroupInfo> {
    const r = await this.sendChatCmd(CC.APIUpdateGroupProfile.cmdString({groupId, groupProfile}))
    if (r.type === "groupUpdated") return r.toGroup
    throw new ChatCommandError("error updating group", r)
  }

  async apiCreateGroupLink(groupId: number, memberRole: T.GroupMemberRole): Promise<string> {
    const r = await this.sendChatCmd(CC.APICreateGroupLink.cmdString({groupId, memberRole}))
    if (r.type === "groupLinkCreated") {
      const link = r.groupLink.connLinkContact
      return link.connShortLink || link.connFullLink
    }
    throw new ChatCommandError("error creating group link", r)
  }

  async apiSetGroupLinkMemberRole(groupId: number, memberRole: T.GroupMemberRole): Promise<void> {
    const r = await this.sendChatCmd(CC.APIGroupLinkMemberRole.cmdString({groupId, memberRole}))
    if (r.type !== "groupLink") throw new ChatCommandError("error setting group link member role", r)
  }

  async apiDeleteGroupLink(groupId: number): Promise<void> {
    const r = await this.sendChatCmd(CC.APIDeleteGroupLink.cmdString({groupId}))
    if (r.type !== "groupLinkDeleted") throw new ChatCommandError("error deleting group link", r)
  }

  async apiGetGroupLink(groupId: number): Promise<T.GroupLink> {
    const r = await this.sendChatCmd(CC.APIGetGroupLink.cmdString({groupId}))
    if (r.type === "groupLink") return r.groupLink
    throw new ChatCommandError("error getting group link", r)
  }

  async apiGetGroupLinkStr(groupId: number): Promise<string> {
    const link = (await this.apiGetGroupLink(groupId)).connLinkContact
    return link.connShortLink || link.connFullLink
  }

  async apiCreateLink(userId: number): Promise<string> {
    const r = await this.sendChatCmd(CC.APIAddContact.cmdString({userId, incognito: false}))
    if (r.type === "invitation") {
      const link = r.connLinkInvitation
      return link.connShortLink || link.connFullLink
    }
    throw new ChatCommandError("error creating link", r)
  }

  async apiConnectPlan(userId: number, connectionLink: string): Promise<[T.ConnectionPlan, T.CreatedConnLink]> {
    const r = await this.sendChatCmd(CC.APIConnectPlan.cmdString({userId, connectTarget: connectionLink, resolveMode: T.PlanResolveMode.Unknown}))
    if (r.type === "connectionPlan") return [r.connectionPlan, r.connLink]
    throw new ChatCommandError("error getting connect plan", r)
  }

  async apiConnect(userId: number, incognito: boolean, preparedLink?: T.CreatedConnLink): Promise<ConnReqType> {
    const r = await this.sendChatCmd(CC.APIConnect.cmdString({userId, incognito, preparedLink_: preparedLink}))
    return this.handleConnectResult(r)
  }

  async apiConnectActiveUser(connLink: string): Promise<ConnReqType> {
    const r = await this.sendChatCmd(CC.Connect.cmdString({incognito: false, connTarget_: connLink}))
    return this.handleConnectResult(r)
  }

  private handleConnectResult(r: ChatResponse): ConnReqType {
    switch (r.type) {
      case "sentConfirmation":
        return ConnReqType.Invitation
      case "sentInvitation":
        return ConnReqType.Contact
      case "contactAlreadyExists":
        throw new ChatCommandError("contact already exists", r)
      default:
        throw new ChatCommandError("connection error", r)
    }
  }

  async apiAcceptContactRequest(contactReqId: number): Promise<T.Contact> {
    const r = await this.sendChatCmd(CC.APIAcceptContact.cmdString({contactReqId}))
    if (r.type === "acceptingContactRequest") return r.contact
    throw new ChatCommandError("error accepting contact request", r)
  }

  async apiRejectContactRequest(contactReqId: number): Promise<void> {
    const r = await this.sendChatCmd(CC.APIRejectContact.cmdString({contactReqId}))
    if (r.type === "contactRequestRejected") return
    throw new ChatCommandError("error rejecting contact request", r)
  }

  async apiListContacts(userId: number): Promise<T.Contact[]> {
    const r = await this.sendChatCmd(CC.APIListContacts.cmdString({userId}))
    if (r.type === "contactsList") return r.contacts
    throw new ChatCommandError("error listing contacts", r)
  }

  async apiListGroups(userId: number, contactId?: number, search?: string): Promise<T.GroupInfo[]> {
    const r = await this.sendChatCmd(CC.APIListGroups.cmdString({userId, contactId_: contactId, search}))
    if (r.type === "groupsList") return r.groups
    throw new ChatCommandError("error listing groups", r)
  }

  async apiGetChats(
    userId: number,
    pagination: T.PaginationByTime,
    query: T.ChatListQuery = {type: "filters", favorite: false, unread: false},
    pendingConnections = false,
  ): Promise<T.AChat[]> {
    const r = await this.sendChatCmd(CC.APIGetChats.cmdString({userId, pendingConnections, pagination, query}))
    if (r.type === "apiChats") return r.chats
    throw new ChatCommandError("error getting chats", r)
  }

  async apiDeleteChat(chatType: T.ChatType, chatId: number, deleteMode: T.ChatDeleteMode = {type: "full", notify: true}): Promise<void> {
    const r = await this.sendChatCmd(CC.APIDeleteChat.cmdString({chatRef: {chatType, chatId}, chatDeleteMode: deleteMode}))
    switch (chatType) {
      case T.ChatType.Direct:
        if (r.type === "contactDeleted") return
        break
      case T.ChatType.Group:
        if (r.type === "groupDeletedUser") return
        break
    }
    throw new ChatCommandError("error deleting chat", r)
  }

  async apiSetGroupCustomData(groupId: number, customData?: object): Promise<void> {
    const r = await this.sendChatCmd(CC.APISetGroupCustomData.cmdString({groupId, customData}))
    if (r.type === "cmdOk") return
    throw new ChatCommandError("error setting group custom data", r)
  }

  async apiSetContactCustomData(contactId: number, customData?: object): Promise<void> {
    const r = await this.sendChatCmd(CC.APISetContactCustomData.cmdString({contactId, customData}))
    if (r.type === "cmdOk") return
    throw new ChatCommandError("error setting contact custom data", r)
  }

  async apiSetAutoAcceptMemberContacts(userId: number, onOff: boolean): Promise<void> {
    const r = await this.sendChatCmd(CC.APISetUserAutoAcceptMemberContacts.cmdString({userId, onOff}))
    if (r.type === "cmdOk") return
    throw new ChatCommandError("error setting auto-accept member contacts", r)
  }

  async apiGetChat(chatType: T.ChatType, chatId: number, count: number): Promise<any> {
    const r: any = await this.sendChatCmd(`/_get chat ${T.ChatType.cmdString(chatType)}${chatId} count=${count}`)
    if (r.type === "apiChat") return r.chat
    throw new ChatCommandError("error getting chat", r)
  }

  async apiGetActiveUser(): Promise<T.User | undefined> {
    try {
      const r = await this.sendChatCmd(CC.ShowActiveUser.cmdString({}))
      switch (r.type) {
        case "activeUser":
          return r.user
        default:
          throw new ChatCommandError("unexpected response", r)
      }
    } catch (err) {
      const e = err as core.ChatAPIError
      if (e.chatError?.type === "error" && e.chatError.errorType.type === "noActiveUser") return undefined
      throw err
    }
  }

  async apiCreateActiveUser(profile?: T.Profile): Promise<T.User> {
    const r = await this.sendChatCmd(CC.CreateActiveUser.cmdString({newUser: {profile, pastTimestamp: false, userChatRelay: false, clientService: false}}))
    if (r.type === "activeUser") return r.user
    throw new ChatCommandError("unexpected response", r)
  }

  async apiListUsers(): Promise<T.UserInfo[]> {
    const r = await this.sendChatCmd(CC.ListUsers.cmdString({}))
    if (r.type === "usersList") return r.users
    throw new ChatCommandError("error listing users", r)
  }

  async apiSetActiveUser(userId: number, viewPwd?: string): Promise<T.User> {
    const r = await this.sendChatCmd(CC.APISetActiveUser.cmdString({userId, viewPwd}))
    if (r.type === "activeUser") return r.user
    throw new ChatCommandError("error setting active user", r)
  }

  async apiDeleteUser(userId: number, delSMPQueues: boolean, viewPwd?: string): Promise<void> {
    const r = await this.sendChatCmd(CC.APIDeleteUser.cmdString({userId, delSMPQueues, viewPwd}))
    if (r.type === "cmdOk") return
    throw new ChatCommandError("error deleting user", r)
  }

  async apiUpdateProfile(userId: number, profile: T.Profile): Promise<T.UserProfileUpdateSummary | undefined> {
    const r = await this.sendChatCmd(CC.APIUpdateProfile.cmdString({userId, profile}))
    switch (r.type) {
      case "userProfileNoChange":
        return undefined
      case "userProfileUpdated":
        return r.updateSummary
      default:
        throw new ChatCommandError("error updating profile", r)
    }
  }

  async apiSetContactPrefs(contactId: number, preferences: T.Preferences): Promise<void> {
    const r = await this.sendChatCmd(CC.APISetContactPrefs.cmdString({contactId, preferences}))
    if (r.type !== "contactPrefsUpdated") throw new ChatCommandError("error setting contact prefs", r)
  }

  async apiCreateMemberContact(groupId: number, groupMemberId: number): Promise<T.Contact> {
    const r: any = await this.sendChatCmd(`/_create member contact #${groupId} ${groupMemberId}`)
    if (r.type === "newMemberContact") return r.contact
    throw new ChatCommandError("error creating member contact", r)
  }

  async apiSendMemberContactInvitation(contactId: number, message?: T.MsgContent | string): Promise<T.Contact> {
    let cmd = `/_invite member contact @${contactId}`
    if (message !== undefined) {
      if (typeof message === "string") {
        cmd += ` text ${message}`
      } else {
        cmd += ` json ${JSON.stringify(message)}`
      }
    }
    const r: any = await this.sendChatCmd(cmd)
    if (r.type === "newMemberContactSentInv") return r.contact
    throw new ChatCommandError("error sending member contact invitation", r)
  }
}
