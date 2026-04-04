import SwiftUI
import Zero

struct CIEventView: View {
    var eventText: Text

    var body: some View {
        eventText
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .textSelection(.disabled)
        .lineLimit(4)
    }
}

struct CIEventView_Previews: PreviewProvider {
    static var previews: some View {
        CIEventView(eventText: Text("event happened"))
    }
}
