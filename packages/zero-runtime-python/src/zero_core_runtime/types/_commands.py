from __future__ import annotations
import json
from typing import NotRequired, TypedDict
from . import _types as T
from . import _responses as CR

class APICreateMyAddress(TypedDict):
    userId: int

def APICreateMyAddress_cmd_string(self: APICreateMyAddress) -> str:
    return '/_address ' + str(self['userId'])

APICreateMyAddress_Response = CR.UserContactLinkCreated | CR.ChatCmdError

class APIDeleteMyAddress(TypedDict):
    userId: int

def APIDeleteMyAddress_cmd_string(self: APIDeleteMyAddress) -> str:
    return '/_delete_address ' + str(self['userId'])

APIDeleteMyAddress_Response = CR.UserContactLinkDeleted | CR.ChatCmdError

class APIShowMyAddress(TypedDict):
    userId: int

def APIShowMyAddress_cmd_string(self: APIShowMyAddress) -> str:
    return '/_show_address ' + str(self['userId'])

APIShowMyAddress_Response = CR.UserContactLink | CR.ChatCmdError

class APISetProfileAddress(TypedDict):
    userId: int
    enable: bool

def APISetProfileAddress_cmd_string(self: APISetProfileAddress) -> str:
    return '/_profile_address ' + str(self['userId']) + ' ' + ('on' if self['enable'] else 'off')

APISetProfileAddress_Response = CR.UserProfileUpdated | CR.ChatCmdError

class APISetAddressSettings(TypedDict):
    userId: int
    settings: "T.AddressSettings"

def APISetAddressSettings_cmd_string(self: APISetAddressSettings) -> str:
    return '/_address_settings ' + str(self['userId']) + ' ' + json.dumps(self['settings'])

APISetAddressSettings_Response = CR.UserContactLinkUpdated | CR.ChatCmdError

class APISendMessages(TypedDict):
    sendRef: "T.ChatRef"
    liveMessage: bool
    ttl: NotRequired[int]
    signMessages: bool
    composedMessages: list["T.ComposedMessage"]

def APISendMessages_cmd_string(self: APISendMessages) -> str:
    return '/_send ' + T.ChatRef_cmd_string(self['sendRef']) + (' live=on' if self['liveMessage'] else '') + ((' ttl=' + str(self.get('ttl'))) if self.get('ttl') is not None else '') + (' sign=on' if self['signMessages'] else '') + ' json ' + json.dumps(self['composedMessages'])

APISendMessages_Response = CR.NewChatItems | CR.ChatCmdError

class APIUpdateChatItem(TypedDict):
    chatRef: "T.ChatRef"
    chatItemId: int
    liveMessage: bool
    updatedMessage: "T.UpdatedMessage"

def APIUpdateChatItem_cmd_string(self: APIUpdateChatItem) -> str:
    return '/_update item ' + T.ChatRef_cmd_string(self['chatRef']) + ' ' + str(self['chatItemId']) + (' live=on' if self['liveMessage'] else '') + ' json ' + json.dumps(self['updatedMessage'])

APIUpdateChatItem_Response = CR.ChatItemUpdated | CR.ChatItemNotChanged | CR.ChatCmdError

class APIDeleteChatItem(TypedDict):
    chatRef: "T.ChatRef"
    chatItemIds: list[int]
    deleteMode: "T.CIDeleteMode"

def APIDeleteChatItem_cmd_string(self: APIDeleteChatItem) -> str:
    return '/_delete item ' + T.ChatRef_cmd_string(self['chatRef']) + ' ' + ','.join(map(str, self['chatItemIds'])) + ' ' + str(self['deleteMode'])

APIDeleteChatItem_Response = CR.ChatItemsDeleted | CR.ChatCmdError

class APIDeleteMemberChatItem(TypedDict):
    groupId: int
    chatItemIds: list[int]

def APIDeleteMemberChatItem_cmd_string(self: APIDeleteMemberChatItem) -> str:
    return '/_delete member item #' + str(self['groupId']) + ' ' + ','.join(map(str, self['chatItemIds']))

APIDeleteMemberChatItem_Response = CR.ChatItemsDeleted | CR.ChatCmdError

class APIChatItemReaction(TypedDict):
    chatRef: "T.ChatRef"
    chatItemId: int
    add: bool
    reaction: "T.MsgReaction"

def APIChatItemReaction_cmd_string(self: APIChatItemReaction) -> str:
    return '/_reaction ' + T.ChatRef_cmd_string(self['chatRef']) + ' ' + str(self['chatItemId']) + ' ' + ('on' if self['add'] else 'off') + ' ' + json.dumps(self['reaction'])

APIChatItemReaction_Response = CR.ChatItemReaction | CR.ChatCmdError

class ReceiveFile(TypedDict):
    fileId: int
    userApprovedRelays: bool
    storeEncrypted: NotRequired[bool]
    fileInline: NotRequired[bool]
    filePath: NotRequired[str]

def ReceiveFile_cmd_string(self: ReceiveFile) -> str:
    return '/freceive ' + str(self['fileId']) + (' approved_relays=on' if self['userApprovedRelays'] else '') + ((' encrypt=' + ('on' if self.get('storeEncrypted') else 'off')) if self.get('storeEncrypted') is not None else '') + ((' inline=' + ('on' if self.get('fileInline') else 'off')) if self.get('fileInline') is not None else '') + ((' ' + self.get('filePath')) if self.get('filePath') is not None else '')

ReceiveFile_Response = CR.RcvFileAccepted | CR.RcvFileAcceptedSndCancelled | CR.ChatCmdError

class CancelFile(TypedDict):
    fileId: int

def CancelFile_cmd_string(self: CancelFile) -> str:
    return '/fcancel ' + str(self['fileId'])

CancelFile_Response = CR.SndFileCancelled | CR.RcvFileCancelled | CR.ChatCmdError

class APIAddMember(TypedDict):
    groupId: int
    contactId: int
    memberRole: "T.GroupMemberRole"

def APIAddMember_cmd_string(self: APIAddMember) -> str:
    return '/_add #' + str(self['groupId']) + ' ' + str(self['contactId']) + ' ' + str(self['memberRole'])

APIAddMember_Response = CR.SentGroupInvitation | CR.ChatCmdError

class APIJoinGroup(TypedDict):
    groupId: int

def APIJoinGroup_cmd_string(self: APIJoinGroup) -> str:
    return '/_join #' + str(self['groupId'])

APIJoinGroup_Response = CR.UserAcceptedGroupSent | CR.ChatCmdError

class APIAcceptMember(TypedDict):
    groupId: int
    groupMemberId: int
    memberRole: "T.GroupMemberRole"

def APIAcceptMember_cmd_string(self: APIAcceptMember) -> str:
    return '/_accept member #' + str(self['groupId']) + ' ' + str(self['groupMemberId']) + ' ' + str(self['memberRole'])

APIAcceptMember_Response = CR.MemberAccepted | CR.ChatCmdError

class APIMembersRole(TypedDict):
    groupId: int
    groupMemberIds: list[int]
    memberRole: "T.GroupMemberRole"

def APIMembersRole_cmd_string(self: APIMembersRole) -> str:
    return '/_member role #' + str(self['groupId']) + ' ' + ','.join(map(str, self['groupMemberIds'])) + ' ' + str(self['memberRole'])

APIMembersRole_Response = CR.MembersRoleUser | CR.ChatCmdError

class APIBlockMembersForAll(TypedDict):
    groupId: int
    groupMemberIds: list[int]
    blocked: bool

def APIBlockMembersForAll_cmd_string(self: APIBlockMembersForAll) -> str:
    return '/_block #' + str(self['groupId']) + ' ' + ','.join(map(str, self['groupMemberIds'])) + ' blocked=' + ('on' if self['blocked'] else 'off')

APIBlockMembersForAll_Response = CR.MembersBlockedForAllUser | CR.ChatCmdError

class APIRemoveMembers(TypedDict):
    groupId: int
    groupMemberIds: list[int]
    withMessages: bool

def APIRemoveMembers_cmd_string(self: APIRemoveMembers) -> str:
    return '/_remove #' + str(self['groupId']) + ' ' + ','.join(map(str, self['groupMemberIds'])) + (' messages=on' if self['withMessages'] else '')

APIRemoveMembers_Response = CR.UserDeletedMembers | CR.ChatCmdError

class APILeaveGroup(TypedDict):
    groupId: int

def APILeaveGroup_cmd_string(self: APILeaveGroup) -> str:
    return '/_leave #' + str(self['groupId'])

APILeaveGroup_Response = CR.LeftMemberUser | CR.ChatCmdError

class APIListMembers(TypedDict):
    groupId: int

def APIListMembers_cmd_string(self: APIListMembers) -> str:
    return '/_members #' + str(self['groupId'])

APIListMembers_Response = CR.GroupMembers | CR.ChatCmdError

class APINewGroup(TypedDict):
    userId: int
    incognito: bool
    groupProfile: "T.GroupProfile"

def APINewGroup_cmd_string(self: APINewGroup) -> str:
    return '/_group ' + str(self['userId']) + (' incognito=on' if self['incognito'] else '') + ' ' + json.dumps(self['groupProfile'])

APINewGroup_Response = CR.GroupCreated | CR.ChatCmdError

class APINewPublicGroup(TypedDict):
    userId: int
    incognito: bool
    relayIds: list[int]
    groupProfile: "T.GroupProfile"

def APINewPublicGroup_cmd_string(self: APINewPublicGroup) -> str:
    return '/_public group ' + str(self['userId']) + (' incognito=on' if self['incognito'] else '') + ' ' + ','.join(map(str, self['relayIds'])) + ' ' + json.dumps(self['groupProfile'])

APINewPublicGroup_Response = CR.PublicGroupCreated | CR.PublicGroupCreationFailed | CR.ChatCmdError

class APIGetGroupRelays(TypedDict):
    groupId: int

def APIGetGroupRelays_cmd_string(self: APIGetGroupRelays) -> str:
    return '/_get relays #' + str(self['groupId'])

APIGetGroupRelays_Response = CR.GroupRelays | CR.ChatCmdError

class APIAddGroupRelays(TypedDict):
    groupId: int
    relayIds: list[int]

def APIAddGroupRelays_cmd_string(self: APIAddGroupRelays) -> str:
    return '/_add relays #' + str(self['groupId']) + ' ' + ','.join(map(str, self['relayIds']))

APIAddGroupRelays_Response = CR.GroupRelaysAdded | CR.GroupRelaysAddFailed | CR.ChatCmdError

class APIAllowRelayGroup(TypedDict):
    groupId: int

def APIAllowRelayGroup_cmd_string(self: APIAllowRelayGroup) -> str:
    return '/_relay allow #' + str(self['groupId'])

APIAllowRelayGroup_Response = CR.RelayGroupAllowed | CR.ChatCmdError

class APIUpdateGroupProfile(TypedDict):
    groupId: int
    groupProfile: "T.GroupProfile"

def APIUpdateGroupProfile_cmd_string(self: APIUpdateGroupProfile) -> str:
    return '/_group_profile #' + str(self['groupId']) + ' ' + json.dumps(self['groupProfile'])

APIUpdateGroupProfile_Response = CR.GroupUpdated | CR.ChatCmdError

class APICreateGroupLink(TypedDict):
    groupId: int
    memberRole: "T.GroupMemberRole"

def APICreateGroupLink_cmd_string(self: APICreateGroupLink) -> str:
    return '/_create link #' + str(self['groupId']) + ' ' + str(self['memberRole'])

APICreateGroupLink_Response = CR.GroupLinkCreated | CR.ChatCmdError

class APIGroupLinkMemberRole(TypedDict):
    groupId: int
    memberRole: "T.GroupMemberRole"

def APIGroupLinkMemberRole_cmd_string(self: APIGroupLinkMemberRole) -> str:
    return '/_set link role #' + str(self['groupId']) + ' ' + str(self['memberRole'])

APIGroupLinkMemberRole_Response = CR.GroupLink | CR.ChatCmdError

class APIDeleteGroupLink(TypedDict):
    groupId: int

def APIDeleteGroupLink_cmd_string(self: APIDeleteGroupLink) -> str:
    return '/_delete link #' + str(self['groupId'])

APIDeleteGroupLink_Response = CR.GroupLinkDeleted | CR.ChatCmdError

class APIGetGroupLink(TypedDict):
    groupId: int

def APIGetGroupLink_cmd_string(self: APIGetGroupLink) -> str:
    return '/_get link #' + str(self['groupId'])

APIGetGroupLink_Response = CR.GroupLink | CR.ChatCmdError

class APIAddContact(TypedDict):
    userId: int
    incognito: bool

def APIAddContact_cmd_string(self: APIAddContact) -> str:
    return '/_connect ' + str(self['userId']) + (' incognito=on' if self['incognito'] else '')

APIAddContact_Response = CR.Invitation | CR.ChatCmdError

class APIConnectPlan(TypedDict):
    userId: int
    connectTarget: NotRequired[str]
    resolveMode: "T.PlanResolveMode"
    linkOwnerSig: NotRequired["T.LinkOwnerSig"]

def APIConnectPlan_cmd_string(self: APIConnectPlan) -> str:
    return '/_connect plan ' + str(self['userId']) + ' ' + self.get('connectTarget')

APIConnectPlan_Response = CR.ConnectionPlan | CR.ChatCmdError

class APIConnect(TypedDict):
    userId: int
    incognito: bool
    preparedLink_: NotRequired["T.CreatedConnLink"]

def APIConnect_cmd_string(self: APIConnect) -> str:
    return '/_connect ' + str(self['userId']) + ((' ' + T.CreatedConnLink_cmd_string(self.get('preparedLink_'))) if self.get('preparedLink_') is not None else '')

APIConnect_Response = CR.SentConfirmation | CR.ContactAlreadyExists | CR.SentInvitation | CR.ChatCmdError

class Connect(TypedDict):
    incognito: bool
    connTarget_: NotRequired[str]

def Connect_cmd_string(self: Connect) -> str:
    return '/connect' + ((' ' + self.get('connTarget_')) if self.get('connTarget_') is not None else '')

Connect_Response = CR.SentConfirmation | CR.ContactAlreadyExists | CR.SentInvitation | CR.ChatCmdError

class APIAcceptContact(TypedDict):
    contactReqId: int

def APIAcceptContact_cmd_string(self: APIAcceptContact) -> str:
    return '/_accept ' + str(self['contactReqId'])

APIAcceptContact_Response = CR.AcceptingContactRequest | CR.ChatCmdError

class APIRejectContact(TypedDict):
    contactReqId: int

def APIRejectContact_cmd_string(self: APIRejectContact) -> str:
    return '/_reject ' + str(self['contactReqId'])

APIRejectContact_Response = CR.ContactRequestRejected | CR.ChatCmdError

class APIListContacts(TypedDict):
    userId: int

def APIListContacts_cmd_string(self: APIListContacts) -> str:
    return '/_contacts ' + str(self['userId'])

APIListContacts_Response = CR.ContactsList | CR.ChatCmdError

class APIListGroups(TypedDict):
    userId: int
    contactId_: NotRequired[int]
    search: NotRequired[str]

def APIListGroups_cmd_string(self: APIListGroups) -> str:
    return '/_groups ' + str(self['userId']) + ((' @' + str(self.get('contactId_'))) if self.get('contactId_') is not None else '') + ((' ' + self.get('search')) if self.get('search') is not None else '')

APIListGroups_Response = CR.GroupsList | CR.ChatCmdError

class APIGetChats(TypedDict):
    userId: int
    pendingConnections: bool
    pagination: "T.PaginationByTime"
    query: "T.ChatListQuery"

def APIGetChats_cmd_string(self: APIGetChats) -> str:
    return '/_get chats ' + str(self['userId']) + (' pcc=on' if self['pendingConnections'] else '') + ' ' + T.PaginationByTime_cmd_string(self['pagination']) + ' ' + json.dumps(self['query'])

APIGetChats_Response = CR.ApiChats | CR.ChatCmdError

class APIDeleteChat(TypedDict):
    chatRef: "T.ChatRef"
    chatDeleteMode: "T.ChatDeleteMode"

def APIDeleteChat_cmd_string(self: APIDeleteChat) -> str:
    return '/_delete ' + T.ChatRef_cmd_string(self['chatRef']) + ' ' + T.ChatDeleteMode_cmd_string(self['chatDeleteMode'])

APIDeleteChat_Response = CR.ContactDeleted | CR.ContactConnectionDeleted | CR.GroupDeletedUser | CR.ChatCmdError

class APISetGroupCustomData(TypedDict):
    groupId: int
    customData: NotRequired[dict[str, object]]

def APISetGroupCustomData_cmd_string(self: APISetGroupCustomData) -> str:
    return '/_set custom #' + str(self['groupId']) + ((' ' + json.dumps(self.get('customData'))) if self.get('customData') is not None else '')

APISetGroupCustomData_Response = CR.CmdOk | CR.ChatCmdError

class APISetContactCustomData(TypedDict):
    contactId: int
    customData: NotRequired[dict[str, object]]

def APISetContactCustomData_cmd_string(self: APISetContactCustomData) -> str:
    return '/_set custom @' + str(self['contactId']) + ((' ' + json.dumps(self.get('customData'))) if self.get('customData') is not None else '')

APISetContactCustomData_Response = CR.CmdOk | CR.ChatCmdError

class APISetUserAutoAcceptMemberContacts(TypedDict):
    userId: int
    onOff: bool

def APISetUserAutoAcceptMemberContacts_cmd_string(self: APISetUserAutoAcceptMemberContacts) -> str:
    return '/_set accept member contacts ' + str(self['userId']) + ' ' + ('on' if self['onOff'] else 'off')

APISetUserAutoAcceptMemberContacts_Response = CR.CmdOk | CR.ChatCmdError

class ShowActiveUser(TypedDict):
    pass

def ShowActiveUser_cmd_string(self: ShowActiveUser) -> str:
    return '/user'

ShowActiveUser_Response = CR.ActiveUser | CR.ChatCmdError

class CreateActiveUser(TypedDict):
    newUser: "T.NewUser"

def CreateActiveUser_cmd_string(self: CreateActiveUser) -> str:
    return '/_create user ' + json.dumps(self['newUser'])

CreateActiveUser_Response = CR.ActiveUser | CR.ChatCmdError

class ListUsers(TypedDict):
    pass

def ListUsers_cmd_string(self: ListUsers) -> str:
    return '/users'

ListUsers_Response = CR.UsersList | CR.ChatCmdError

class APISetActiveUser(TypedDict):
    userId: int
    viewPwd: NotRequired[str]

def APISetActiveUser_cmd_string(self: APISetActiveUser) -> str:
    return '/_user ' + str(self['userId']) + ((' ' + json.dumps(self.get('viewPwd'))) if self.get('viewPwd') is not None else '')

APISetActiveUser_Response = CR.ActiveUser | CR.ChatCmdError

class APIDeleteUser(TypedDict):
    userId: int
    delSMPQueues: bool
    viewPwd: NotRequired[str]

def APIDeleteUser_cmd_string(self: APIDeleteUser) -> str:
    return '/_delete user ' + str(self['userId']) + ' del_smp=' + ('on' if self['delSMPQueues'] else 'off') + ((' ' + json.dumps(self.get('viewPwd'))) if self.get('viewPwd') is not None else '')

APIDeleteUser_Response = CR.CmdOk | CR.ChatCmdError

class APIUpdateProfile(TypedDict):
    userId: int
    profile: "T.Profile"

def APIUpdateProfile_cmd_string(self: APIUpdateProfile) -> str:
    return '/_profile ' + str(self['userId']) + ' ' + json.dumps(self['profile'])

APIUpdateProfile_Response = CR.UserProfileUpdated | CR.UserProfileNoChange | CR.ChatCmdError

class APISetContactPrefs(TypedDict):
    contactId: int
    preferences: "T.Preferences"

def APISetContactPrefs_cmd_string(self: APISetContactPrefs) -> str:
    return '/_set prefs @' + str(self['contactId']) + ' ' + json.dumps(self['preferences'])

APISetContactPrefs_Response = CR.ContactPrefsUpdated | CR.ChatCmdError

class StartChat(TypedDict):
    mainApp: bool
    enableSndFiles: bool

def StartChat_cmd_string(self: StartChat) -> str:
    return '/_start'

StartChat_Response = CR.ChatStarted | CR.ChatRunning

class APIStopChat(TypedDict):
    pass

def APIStopChat_cmd_string(self: APIStopChat) -> str:
    return '/_stop'

APIStopChat_Response = CR.ChatStopped

