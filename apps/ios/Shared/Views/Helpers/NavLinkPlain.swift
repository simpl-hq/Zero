import SwiftUI
import Zero

struct NavLinkPlain<Label: View>: View {
    let chatId: ChatId
    @Binding var selection: ChatId?
    @ViewBuilder var label: () -> Label
    var disabled = false

    var body: some View {
        ZStack {
            Button("") { ItemsModel.shared.loadOpenChat(chatId) }
                .disabled(disabled)
            label()
        }
    }
}

