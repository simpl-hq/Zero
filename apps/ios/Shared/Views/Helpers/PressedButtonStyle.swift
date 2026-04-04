import SwiftUI

struct PressedButtonStyle: ButtonStyle {
    var defaultColor: Color
    var pressedColor: Color
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
        .background(configuration.isPressed ? pressedColor : defaultColor)
    }
}
