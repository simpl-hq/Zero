import Foundation
import UIKit

private func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
    .filter { $0.activationState == .foregroundActive }
    .map { $0 as? UIWindowScene }
    .compactMap { $0 }
    .first?.windows
    .filter { $0.isKeyWindow }.first
}

func dismissAllSheets(animated flag: Bool = true, completion: (() -> Void)? = nil) {
    if let c = keyWindow()?.rootViewController {
        c.dismiss(animated: flag, completion: completion)
    } else {
        completion?()
    }
}
