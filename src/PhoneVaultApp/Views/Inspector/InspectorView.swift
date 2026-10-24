import SwiftUI
import PhoneVaultCore

struct InspectorView: View {

    @Environment(BackupViewModel.self) private var vm

    var body: some View {
        Group {
            if let file = vm.selectedFile {
                fileInspector(file)
            } else {
                EmptyStateView(
                    icon: "sidebar.right",
                    title: "No File Selected",
                    message: "Select a file in the browser to inspect it."
                )
            }
        }
        .frame(minWidth: 280)
        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 440)
    }

    // MARK: - File inspector

    @ViewBuilder
    private func fileInspector(_ file: BackupFile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                fileHeader(file)

                Divider()

                // Metadata
                Group {
                    metadataSection(file)
                    Divider()
                    previewSection(file)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private func fileHeader(_ file: BackupFile) -> some View {
        HStack(spacing: 12) {
            fileTypeIcon(file.fileType)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .font(.headline)
                    .lineLimit(2)
                Text(file.fileType.rawValue.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func fileTypeIcon(_ kind: FileKind) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(iconBackground(kind))
            .overlay(
                Image(systemName: iconSymbol(kind))
                    .font(.title3)
                    .foregroundStyle(.white)
            )
    }

    // MARK: - Metadata section

    private func metadataSection(_ file: BackupFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Metadata")
            VStack(spacing: 0) {
                MetadataRow(label: "Path", value: file.relativePath)
                MetadataRow(label: "Domain", value: file.domain)
                if let size = file.fileSize {
                    MetadataRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                }
                if let date = file.modificationDate {
                    MetadataRow(label: "Modified", value: date.formatted(date: .complete, time: .shortened))
                }
                MetadataRow(label: "Available", value: file.isAvailable ? "Yes" : "No — payload missing")
                if let url = file.physicalURL {
                    MetadataRow(label: "Backup Path", value: url.path)
                }
            }

            if file.isAvailable {
                Button {
                    exportFile(file)
                } label: {
                    Label("Export File…", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
    }

    // MARK: - Preview section

    @ViewBuilder
    private func previewSection(_ file: BackupFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Preview")

            if !file.isAvailable {
                UnavailablePreview()
            } else if vm.isLoadingPreview {
                HStack {
                    Spacer()
                    ProgressView("Loading preview…").padding()
                    Spacer()
                }
            } else if let result = vm.previewResult {
                previewContent(result, file: file)
            } else {
                Color.clear.frame(height: 1)   // triggers nothing — preview loaded on selection
            }
        }
    }

    @ViewBuilder
    private func previewContent(_ result: PreviewResult, file: BackupFile) -> some View {
        switch result {
        case .sqliteSchema(let tables):
            SQLitePreviewView(tables: tables, file: file)
        case .sqliteTablePage(let table, let columns, let rows, let page, let hasMore):
            SQLiteTablePageView(tableName: table, columns: columns, rows: rows, page: page, hasMore: hasMore, file: file)
        case .plist(let root):
            PlistPreviewView(root: root)
        case .json(let text):
            TextPreviewView(content: text, language: .json, truncated: false)
        case .text(let content, let truncated):
            TextPreviewView(content: content, language: .plain, truncated: truncated)
        case .image(let url):
            ImagePreviewView(url: url)
        case .unsupported:
            UnsupportedPreview(file: file)
        case .error(let msg):
            ErrorPreview(message: msg)
        }
    }

    // MARK: - Export

    private func exportFile(_ file: BackupFile) {
        vm.selectedItemIDs = [file.id]
        vm.exportSelected()
    }

    // MARK: - Icon helpers

    private func iconSymbol(_ kind: FileKind) -> String {
        switch kind {
        case .sqlite:  return "cylinder.split.1x2.fill"
        case .plist:   return "list.bullet.rectangle.fill"
        case .json:    return "curlybraces"
        case .text:    return "doc.text.fill"
        case .image:   return "photo.fill"
        case .audio:   return "waveform"
        case .video:   return "film.fill"
        default:       return "doc.fill"
        }
    }

    private func iconBackground(_ kind: FileKind) -> LinearGradient {
        let colors: (Color, Color)
        switch kind {
        case .sqlite:  colors = (.indigo, .purple)
        case .plist:   colors = (.orange, .red)
        case .json:    colors = (.yellow, .orange)
        case .text:    colors = (.gray, .secondary)
        case .image:   colors = (.green, .teal)
        case .audio:   colors = (.pink, .purple)
        case .video:   colors = (.purple, .indigo)
        default:       colors = (.gray, .secondary)
        }
        return LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Shared inspector components

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.caption.uppercaseSmallCaps())
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }
}

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(4)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        Divider().padding(.leading, 88)
    }
}

struct UnavailablePreview: View {
    var body: some View {
        Label("Payload file not present in this backup.", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .padding()
    }
}

struct UnsupportedPreview: View {
    let file: BackupFile
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Preview not available for this file type.", systemImage: "eye.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Use Export File to save a copy you can open with another application.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}

struct ErrorPreview: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "xmark.circle")
            .font(.caption)
            .foregroundStyle(.red)
            .padding()
    }
}
