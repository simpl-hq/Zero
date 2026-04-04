import SwiftUI
import Zero

private let fontCapHeightRatio: CGFloat = 0.85
private let badgeBaselineOffsetRatio: CGFloat = 0.05

struct NameWithBadge: View {
    let name: Text
    var badge: LocalBadge?
    var textStyle: UIFont.TextStyle = .body
    var onTap: (() -> Void)? = nil

    init(_ name: Text, _ badge: LocalBadge?, _ textStyle: UIFont.TextStyle = .body, onTap: (() -> Void)? = nil) {
        self.name = name
        self.badge = badge
        self.textStyle = textStyle
        self.onTap = onTap
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            name
            NameBadge(badge, textStyle, onTap: onTap)
        }
    }
}

struct NameBadge: View {
    var badge: LocalBadge?
    var textStyle: UIFont.TextStyle = .body
    var onTap: (() -> Void)? = nil

    init(_ badge: LocalBadge?, _ textStyle: UIFont.TextStyle = .body, onTap: (() -> Void)? = nil) {
        self.badge = badge
        self.textStyle = textStyle
        self.onTap = onTap
    }

    var body: some View {
        if let badge, badge.status != .expiredOld {
            let v = glyph(badge)
                .frame(height: badgeHeight)
                .alignmentGuide(.firstTextBaseline) { $0.height * (1 - badgeBaselineOffsetRatio) }
                .padding(.leading, badgeGap)
            if let onTap {
                v.onTapGesture(perform: onTap)
            } else {
                v
            }
        }
    }

    private var badgeHeight: CGFloat {
        UIFont.preferredFont(forTextStyle: textStyle).pointSize * fontCapHeightRatio
    }

    private var badgeGap: CGFloat {
        let font = UIFont.preferredFont(forTextStyle: textStyle)
        return (" " as NSString).size(withAttributes: [.font: font]).width
    }

    @ViewBuilder private func glyph(_ badge: LocalBadge) -> some View {
        switch badge.status {
        case .failed, .unknownKey:
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable().scaledToFit()
                .foregroundColor(.orange)
        default:
            Image(badgeImageName(badge.badge.badgeType))
                .resizable().scaledToFit()
                .opacity(badge.status == .expired ? 0.4 : 1)
        }
    }
}

private func badgeImageName(_ t: BadgeType) -> String {
    switch t {
    case .legend: "badge-legend"
    case .investor: "badge-investor"
    default: "badge-supporter"
    }
}

func nameBadgeAttachment(_ badge: LocalBadge?, font: UIFont) -> NSAttributedString? {
    guard let badge, badge.status != .expiredOld else { return nil }
    var image: UIImage?
    switch badge.status {
    case .failed, .unknownKey:
        image = UIImage(systemName: "exclamationmark.triangle.fill")?
            .withTintColor(.systemOrange, renderingMode: .alwaysOriginal)
    default:
        image = UIImage(named: badgeImageName(badge.badge.badgeType))
        if badge.status == .expired, let img = image {
            image = UIGraphicsImageRenderer(size: img.size).image { _ in
                img.draw(at: .zero, blendMode: .normal, alpha: 0.4)
            }
        }
    }
    guard let image else { return nil }
    let attachment = NSTextAttachment()
    attachment.image = image
    let h = font.pointSize * fontCapHeightRatio
    attachment.bounds = CGRect(x: 0, y: -h * badgeBaselineOffsetRatio, width: h * image.size.width / image.size.height, height: h)
    let s = NSMutableAttributedString(string: " ")
    s.append(NSAttributedString(attachment: attachment))
    return s
}

func showBadgeInfoAlert(_ name: String, _ badge: LocalBadge) {
    switch badge.status {
    case .failed:
        showAlert(
            NSLocalizedString("Unverified badge", comment: "badge alert title"),
            message: NSLocalizedString("This badge could not be verified and may not be genuine.", comment: "badge alert")
        )
    case .unknownKey:
        showAlert(
            NSLocalizedString("Badge cannot be verified", comment: "badge alert title"),
            message: NSLocalizedString("The badge is signed with a key that this version of the app does not recognize. Update the app to verify this badge.", comment: "badge alert")
        )
    default:
        let t = badge.badge.badgeType.text
        let title = t.prefix(1).uppercased() + t.dropFirst()
        if case .investor = badge.badge.badgeType {
            let message = String.localizedStringWithFormat(NSLocalizedString("%@ supports open-source Zero development.", comment: "badge alert"), name)
            showAlert(title, message: message) {
                [ UIAlertAction(title: NSLocalizedString("Learn more", comment: "badge alert button"), style: .default) { _ in
                    if let url = URL(string: "https://simpl.global/donate") {
                        UIApplication.shared.open(url)
                    }
                  },
                  okAlertAction ]
            }
        } else {
            let supports =
                if badge.status == .expired, let expiry = badge.badge.badgeExpiry {
                    String.localizedStringWithFormat(NSLocalizedString("%1$@ supported Zero. The badge expired on %2$@.", comment: "badge alert"), name, expiry.formatted(date: .abbreviated, time: .omitted))
                } else {
                    String.localizedStringWithFormat(NSLocalizedString("%@ supports Zero.", comment: "badge alert"), name)
                }
            let v7 = NSLocalizedString("You can support Zero starting from v1.0 of the app.", comment: "badge alert")
            showAlert(title, message: supports + "\n\n" + v7)
        }
    }
}
