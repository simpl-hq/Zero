import SwiftUI

extension View {
    @ViewBuilder
    func invertedForegroundStyle(enabled: Bool = true) -> some View {
        if enabled {
            foregroundStyle(Material.ultraThin)
                .environment(\.colorScheme, .dark)
                .grayscale(1)
                .contrast(-20)
        } else { self }
    }
}
