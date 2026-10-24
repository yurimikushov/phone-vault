import SwiftUI
import PhoneVaultCore

struct SidebarView: View {

    @Environment(BackupViewModel.self) private var vm
    @State private var appSearch = ""

    var body: some View {
        @Bindable var vm = vm
        List(selection: $vm.sidebarSelection) {
            Section("Connected Devices") {
                if vm.connectedDevices.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "cable.connector")
                            .foregroundStyle(.tertiary)
                        Text("No devices connected via USB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                } else {
                    ForEach(vm.connectedDevices) { device in
                        Label {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.callout.weight(.medium))
                                    Text("\(device.marketingName) • \(device.connectionType)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Circle().fill(.green).frame(width: 7, height: 7)
                            }
                        } icon: {
                            Image(systemName: "iphone")
                                .font(.title3)
                                .foregroundStyle(.blue)
                        }
                        .tag(BackupViewModel.SidebarSelection.device(device.id))
                    }
                }
            }

            // Live Apps on Selected Device
            if let device = vm.selectedDevice, !vm.liveApps.isEmpty {
                Section("Live Apps on \(device.name)") {
                    ForEach(filteredLiveApps) { app in
                        LiveAppRowView(app: app)
                            .tag(BackupViewModel.SidebarSelection.liveApp(udid: device.id, bundleID: app.bundleID))
                    }
                }
            }

            // Offline Backup (if loaded)
            if let info = vm.backupInfo {
                Section("Backup") {
                    backupInfoCard(info)
                }

                Section("Backup Apps (\(vm.apps.count))") {
                    // "All Files" row
                    Label {
                        HStack {
                            Text("All Files")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(vm.allFiles.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "tray.full")
                            .foregroundStyle(.blue)
                    }
                    .tag(BackupViewModel.SidebarSelection.allFiles)

                    // Per-app rows
                    ForEach(filteredBackupApps) { app in
                        AppRowView(app: app)
                            .tag(BackupViewModel.SidebarSelection.app(app.id))
                    }
                }
            }

            // Fallback for empty workspace when no device or backup is present
            if vm.connectedDevices.isEmpty && vm.backupInfo == nil {
                if vm.isLoading {
                    loadingState
                } else {
                    emptyState
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $appSearch, prompt: "Search apps")
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        .navigationTitle("PhoneVault")
    }

    // MARK: - Subviews

    private func backupInfoCard(_ info: BackupInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(info.deviceName ?? "Unknown Device", systemImage: "iphone")
                .fontWeight(.semibold)
                .lineLimit(1)

            if let ios = info.productVersion {
                infoRow(icon: "gear", text: "iOS \(ios)")
            }
            if let date = info.date {
                infoRow(icon: "clock", text: date.formatted(date: .abbreviated, time: .shortened))
            }

            Divider().padding(.vertical, 2)

            HStack {
                statBadge(value: info.totalFileCount, label: "Total")
                statBadge(value: info.availableFileCount, label: "Available", color: .green)
                statBadge(value: info.totalFileCount - info.availableFileCount, label: "Missing", color: .secondary)
            }

            if info.isEncrypted {
                Label("Encrypted", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
    }

    private func infoRow(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func statBadge(value: Int, label: String, color: Color = .primary) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .listRowBackground(Color.clear)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No device connected")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Connect an iPhone via USB to inspect apps, or open an existing backup.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }

    // MARK: - Helpers

    private var filteredLiveApps: [AppRecord] {
        let apps = vm.liveApps.filter { $0.accessMode.isAccessible }
        guard !appSearch.isEmpty else { return apps }
        return apps.filter {
            $0.displayName.localizedCaseInsensitiveContains(appSearch) ||
            $0.bundleID.localizedCaseInsensitiveContains(appSearch)
        }
    }

    private var filteredBackupApps: [AppRecord] {
        guard !appSearch.isEmpty else { return vm.apps }
        return vm.apps.filter {
            $0.displayName.localizedCaseInsensitiveContains(appSearch) ||
            $0.bundleID.localizedCaseInsensitiveContains(appSearch)
        }
    }
}

// MARK: - Live App Row

struct LiveAppRowView: View {
    let app: AppRecord

    var body: some View {
        HStack(spacing: 8) {
            appIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(app.displayName)
                    .font(.callout)
                    .lineLimit(1)
                Text(app.bundleID)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            accessIndicator
        }
        .padding(.vertical, 2)
    }

    private var appIcon: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(iconColor)
            .frame(width: 28, height: 28)
            .overlay(
                Text(String(app.displayName.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }

    @ViewBuilder
    private var accessIndicator: some View {
        if app.accessMode == .container {
            Circle().fill(.green).frame(width: 6, height: 6)
                .help("Container Access (Debug)")
        } else if app.accessMode == .documents {
            Circle().fill(.blue).frame(width: 6, height: 6)
                .help("Documents Access (File Sharing)")
        }
    }

    private var iconColor: Color {
        let hash = abs(app.bundleID.hashValue)
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .red, .orange, .yellow, .green, .teal, .cyan]
        return palette[hash % palette.count]
    }
}

// MARK: - Backup App Row

struct AppRowView: View {
    let app: AppRecord

    var body: some View {
        HStack(spacing: 8) {
            appIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(app.displayName)
                    .font(.callout)
                    .lineLimit(1)
                Text(app.bundleID)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(app.availableFileCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if app.availableFileCount < app.fileCount {
                    Text("\(app.fileCount - app.availableFileCount) ⚠︎")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var appIcon: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(iconColor)
            .frame(width: 28, height: 28)
            .overlay(
                Text(String(app.displayName.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }

    private var iconColor: Color {
        let hash = abs(app.bundleID.hashValue)
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .red, .orange, .yellow, .green, .teal, .cyan]
        return palette[hash % palette.count]
    }
}
