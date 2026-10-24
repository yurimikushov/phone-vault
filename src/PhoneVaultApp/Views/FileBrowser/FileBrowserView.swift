import SwiftUI
import PhoneVaultCore

struct FileBrowserView: View {

    @Environment(BackupViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            breadcrumbBar
            Divider()
            if vm.backupInfo == nil && !vm.isLiveSession {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "No App or Backup Selected",
                    message: "Select an app from a connected device or open an existing backup."
                )
            } else if vm.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading files from device…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.browserItems.isEmpty && !vm.searchText.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Results",
                    message: "No files match \"\(vm.searchText)\"."
                )
            } else if vm.browserItems.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: "Empty Folder",
                    message: "This container contains no files in this path."
                )
            } else {
                fileTable
            }
        }
        .searchable(text: $vm.searchText, prompt: "Search files")
        .navigationSplitViewColumnWidth(min: 320, ideal: 500)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if vm.isLiveSession {
                    Button {
                        vm.refreshLiveApp()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh files live from device")
                }

                sortMenu

                if !vm.currentPath.isEmpty {
                    Button {
                        vm.exportCurrentFolder()
                    } label: {
                        Label("Export Folder", systemImage: "folder.badge.gearshape")
                    }
                    .help("Export all files in the current folder")
                    .disabled(vm.isExporting)
                }
                if vm.selectedAppID != nil {
                    Button {
                        vm.exportCurrentApp()
                    } label: {
                        Label("Export App", systemImage: "arrow.down.to.line.compact")
                    }
                    .help("Export all available files for this app")
                    .disabled(vm.isExporting)
                }
            }
        }
        .navigationTitle(navigationTitle)
    }

    // MARK: - Breadcrumb bar

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                // Root breadcrumb
                Button {
                    vm.navigate(to: "")
                } label: {
                    Label(rootLabel, systemImage: "folder")
                        .font(.callout)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(vm.pathComponents.isEmpty ? .primary : .secondary)

                ForEach(Array(vm.pathComponents.enumerated()), id: \.offset) { idx, component in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Button {
                        let path = vm.pathComponents[...idx].joined(separator: "/")
                        vm.navigate(to: path)
                    } label: {
                        Text(component)
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(idx == vm.pathComponents.count - 1 ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(.bar)
    }

    // MARK: - File table

    private var fileTable: some View {
        Table(vm.browserItems, selection: Binding(get: { vm.selectedItemIDs }, set: { newIDs in
            vm.selectedItemIDs = newIDs
            // Navigate into directory on single selection
            if newIDs.count == 1, let id = newIDs.first {
                if let item = vm.browserItems.first(where: { $0.id == id }), case .directory(_, let path, _, _) = item {
                    vm.navigate(to: path)
                    return
                }
                // File selected: load preview
                if let file = vm.selectedFile {
                    vm.loadPreview(for: file)
                }
            } else {
                vm.previewResult = nil
            }
        })) {
            TableColumn("Name") { item in
                BrowserItemRow(item: item)
            }
            .width(min: 160, ideal: 220)

            TableColumn("Path") { item in
                Text(item.sortPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 100, ideal: 180)

            TableColumn("Size") { item in
                if case .file(let f) = item {
                    Text(f.fileSize.map { formatBytes($0) } ?? "—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if case .directory(_, _, let count, _) = item {
                    Text("\(count) items")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .width(70)

            TableColumn("Modified") { item in
                if case .file(let f) = item, let date = f.modificationDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .width(90)

            TableColumn("Status") { item in
                availabilityBadge(for: item)
            }
            .width(70)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: BrowserItem.ID.self) { ids in
            if !ids.isEmpty {
                Button("Export Selected…") { vm.exportSelected() }
            }
        }
    }

    @ViewBuilder
    private func availabilityBadge(for item: BrowserItem) -> some View {
        switch item {
        case .directory(_, _, let total, let avail):
            if avail < total {
                Text("⚠︎ \(total - avail) missing")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        case .file(let f):
            if f.isAvailable {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Label("Missing", systemImage: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .labelStyle(.iconOnly)
            }
        }
    }

    // MARK: - Sort menu

    private var sortMenu: some View {
        @Bindable var vm = vm
        return Menu {
            Picker("Sort by", selection: $vm.sortKey) {
                ForEach(BackupViewModel.SortKey.allCases) { key in
                    Text(key.rawValue).tag(key)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Toggle("Ascending", isOn: $vm.sortAscending)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Change sort order")
    }

    // MARK: - Helpers

    private var navigationTitle: String {
        if let liveApp = vm.activeLiveApp {
            return "\(liveApp.displayName) (\(liveApp.accessMode.rawValue))"
        }
        if let appID = vm.selectedAppID,
           let app = vm.apps.first(where: { $0.id == appID }) {
            return app.displayName
        }
        return "All Files"
    }

    private var rootLabel: String {
        if let liveApp = vm.activeLiveApp {
            return liveApp.displayName
        }
        if let appID = vm.selectedAppID,
           let app = vm.apps.first(where: { $0.id == appID }) {
            return app.displayName
        }
        return "Root"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useBytes]
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Browser Item Row

struct BrowserItemRow: View {
    let item: BrowserItem

    var body: some View {
        HStack(spacing: 8) {
            itemIcon
            Text(item.sortName)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var itemIcon: some View {
        switch item {
        case .directory:
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
                .font(.body)
        case .file(let f):
            Image(systemName: iconName(for: f.fileType))
                .foregroundStyle(iconColor(for: f.fileType))
                .font(.body)
        }
    }

    private func iconName(for kind: FileKind) -> String {
        switch kind {
        case .sqlite:    return "cylinder.split.1x2.fill"
        case .plist:     return "list.bullet.rectangle"
        case .json:      return "curlybraces"
        case .text:      return "doc.text"
        case .image:     return "photo"
        case .audio:     return "waveform"
        case .video:     return "film"
        case .binary:    return "doc"
        case .directory: return "folder.fill"
        }
    }

    private func iconColor(for kind: FileKind) -> Color {
        switch kind {
        case .sqlite:  return .indigo
        case .plist:   return .orange
        case .json:    return .yellow
        case .text:    return .gray
        case .image:   return .green
        case .audio:   return .pink
        case .video:   return .purple
        default:       return .secondary
        }
    }
}
