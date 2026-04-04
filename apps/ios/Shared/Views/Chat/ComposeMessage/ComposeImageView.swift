import SwiftUI
import Zero

struct ComposeImageView: View {
    @EnvironmentObject var theme: AppTheme
    let images: [String]
    let cancelImage: (() -> Void)
    let cancelEnabled: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            let imgs: [UIImage] = images.compactMap { image in
                imageFromBase64(image)
            }
            if imgs.count == 0 {
                ProgressView()
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(imgs, id: \.hash) { img in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 80, minHeight: 40, maxHeight: 60)
                        }
                    }
                }
            }
            Spacer()
            if cancelEnabled {
                Button { cancelImage() } label: {
                    Image(systemName: "multiply")
                }
            }
        }
        .padding(.vertical, 1)
        .padding(.trailing, 12)
        .background(theme.appColors.sentMessage)
        .frame(minHeight: 54)
        .frame(maxWidth: .infinity)
    }
}

