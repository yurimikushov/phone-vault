import SwiftUI
import AppKit

struct ImagePreviewView: View {

    let url: URL
    @State private var image: NSImage?
    @State private var imageSize: CGSize?

    var body: some View {
        VStack(spacing: 0) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 280)
                    .padding(8)

                if let size = imageSize {
                    Divider()
                    Text("\(Int(size.width)) × \(Int(size.height)) px")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            } else {
                ProgressView()
                    .padding()
            }
        }
        .task {
            guard let loaded = NSImage(contentsOf: url) else { return }
            image = loaded
            imageSize = loaded.size
        }
    }
}
