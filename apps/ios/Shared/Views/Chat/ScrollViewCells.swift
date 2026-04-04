import SwiftUI

protocol ReusableView {
    func prepareForReuse()
}

final class HostingCell<Hosted: View>: UIView, ReusableView {
    private let hostingController = UIHostingController<Hosted?>(rootView: nil)

    func set(content: Hosted, parent: UIViewController) {
        hostingController.view.backgroundColor = .clear
        hostingController.rootView = content
        if let hostingView = hostingController.view {
            hostingView.invalidateIntrinsicContentSize()
            if hostingController.parent != parent { parent.addChild(hostingController) }
            if !subviews.contains(hostingController.view) {
                addSubview(hostingController.view)
                hostingView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    hostingView.leadingAnchor
                        .constraint(equalTo: leadingAnchor),
                    hostingView.trailingAnchor
                        .constraint(equalTo: trailingAnchor),
                    hostingView.topAnchor
                        .constraint(equalTo: topAnchor),
                    hostingView.bottomAnchor
                        .constraint(equalTo: bottomAnchor)
                ])
            }
            if hostingController.parent != parent { hostingController.didMove(toParent: parent) }
        } else {
            fatalError("Hosting View not loaded \(hostingController)")
        }
    }

    func prepareForReuse() {
        hostingController.rootView = nil
    }
}
