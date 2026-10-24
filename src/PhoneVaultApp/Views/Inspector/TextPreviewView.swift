import SwiftUI

enum PreviewLanguage { case json, plain }

struct TextPreviewView: View {

    let content: String
    let language: PreviewLanguage
    let truncated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if truncated {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Preview truncated — export the file to see all content.")
                }
                .font(.caption2)
                .foregroundStyle(.orange)
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.08))
                Divider()
            }

            ScrollView {
                Text(content)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 400)
        }
    }
}
