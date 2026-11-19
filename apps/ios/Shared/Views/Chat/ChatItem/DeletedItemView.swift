import SwiftUI
import Zero

struct DeletedItemView: View {
    @EnvironmentObject var theme: AppTheme
    @ObservedObject var chat: Chat
    var chatItem: ChatItem

    var body: some View {
        let bubbleColor = chatItemFrameColor(chatItem, theme)
        let bubbleInk = bubbleColor.onSurfaceInk
        let bubbleSecondaryInk = bubbleColor.onSurfaceSecondaryInk
        HStack(alignment: .bottom, spacing: 0) {
            Text(chatItem.content.text)
                .foregroundColor(bubbleSecondaryInk)
                .italic()
            CIMetaView(chat: chat, chatItem: chatItem, metaColor: bubbleSecondaryInk, primaryColor: bubbleInk)
                .padding(.horizontal, 12)
        }
        .padding(.leading, 12)
        .padding(.vertical, 6)
        .background(bubbleColor)
        .textSelection(.disabled)
    }
}

struct DeletedItemView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DeletedItemView(chat: Chat.sampleData, chatItem: ChatItem.getDeletedContentSample())
            DeletedItemView(chat: Chat.sampleData, chatItem: ChatItem.getDeletedContentSample(dir: .groupRcv(groupMember: GroupMember.sampleData)))
        }
        .previewLayout(.fixed(width: 360, height: 200))
    }
}
