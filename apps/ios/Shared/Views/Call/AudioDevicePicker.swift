import Foundation
import SwiftUI
import UIKit
import AVKit

struct AudioDevicePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> some UIView {
        let v = AVRoutePickerView(frame: .zero)
        v.activeTintColor = .white
        v.tintColor = .white
        return v
    }

    func updateUIView(_ uiView: UIViewType, context: Context) {

    }
}
