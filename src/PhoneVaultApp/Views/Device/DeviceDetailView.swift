import SwiftUI
import AppKit
import PhoneVaultCore

struct DeviceDetailView: View {

    let device: ConnectedDevice
    @Environment(BackupViewModel.self) private var vm

    @State private var appSearch = ""
    @State private var filterAccessibleOnly = false
    @State private var copiedUDID = false
    @State private var copiedBrewCmd = false
    @State private var showingErrorDetails = false
    @State private var copiedErrorLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Device Hero Banner
                deviceHero

                Divider()

                // Live Apps Section (The Core Feature!)
                liveAppsSection

                Divider()

                // Offline Backup Options (Secondary / Advanced)
                offlineBackupsSection
            }
            .padding(24)
        }
        .navigationTitle(device.name)
        .onAppear {
            vm.loadLiveAppsIfNeeded(forUDID: device.id)
        }
    }

    // MARK: - Device Hero

    private var deviceHero: some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 72, height: 72)
                Image(systemName: "iphone")
                    .font(.system(size: 38))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(device.name)
                        .font(.title2.bold())
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("Connected via \(device.connectionType)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                }

                Text("\(device.marketingName) • iOS \(device.productVersion.isEmpty ? "Detected" : device.productVersion)")
                    .font(.body)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Text("UDID: \(device.id)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(device.id, forType: .string)
                        copiedUDID = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copiedUDID = false
                        }
                    } label: {
                        Image(systemName: copiedUDID ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .help("Copy UDID to clipboard")
                }
            }
        }
    }

    // MARK: - Live Apps Section

    private var liveAppsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Inspect Apps & Databases")
                            .font(.title3.bold())
                        if !vm.liveApps.isEmpty {
                            Text("\(filteredApps.count)")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                    }
                    Text("Direct USB inspection without full backups. Inspect SQLite DBs, plists, and containers live.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    vm.fetchLiveApps(udid: device.id)
                } label: {
                    Label("Refresh Apps", systemImage: "arrow.clockwise")
                }
                .disabled(vm.isLoadingLiveApps)
            }

            if !LiveDeviceService.shared.isToolingAvailable {
                toolingMissingBanner
            }

            // Search & filter bar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                    TextField("Search installed apps by name or bundle ID…", text: $appSearch)
                        .textFieldStyle(.plain)
                    if !appSearch.isEmpty {
                        Button {
                            appSearch = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                Toggle(isOn: $filterAccessibleOnly) {
                    Text("Accessible Only")
                        .font(.callout)
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: Binding(
                    get: { vm.includeSystemApps },
                    set: { newValue in
                        vm.fetchLiveApps(udid: device.id, includeSystem: newValue)
                    }
                )) {
                    Text("System Apps")
                        .font(.callout)
                }
                .toggleStyle(.checkbox)
            }

            if vm.isLoadingLiveApps {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(vm.includeSystemApps ? "Enumerating all apps (including system) over USB…" : "Enumerating user apps over USB…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .center)
            } else if let error = vm.liveAppsError {
                errorCard(error: error)
            } else if filteredApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text(appSearch.isEmpty ? "No apps found" : "No apps match \"\(appSearch)\"")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if !appSearch.isEmpty {
                        Button("Clear Search") { appSearch = "" }
                            .buttonStyle(.link)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredApps) { app in
                        liveAppRow(app)
                    }
                }
            }
        }
    }

    private func liveAppRow(_ app: AppRecord) -> some View {
        HStack(spacing: 14) {
            // App initial badge
            RoundedRectangle(cornerRadius: 8)
                .fill(appBadgeColor(for: app))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(String(app.displayName.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.displayName)
                        .font(.body.weight(.medium))
                    if let ver = app.version {
                        Text("v\(ver)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Access mode badge
            accessModeBadge(app.accessMode)

            // Browse button
            if app.accessMode.isAccessible {
                Button {
                    vm.selectLiveApp(app, on: device)
                } label: {
                    Label("Browse Files", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button {
                    // Try to inspect anyway to test container access
                    vm.selectLiveApp(app, on: device)
                } label: {
                    Text("Try Access")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("This app might require a debug build or UIFileSharingEnabled in its Info.plist.")
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func accessModeBadge(_ mode: AppAccessMode) -> some View {
        switch mode {
        case .container:
            HStack(spacing: 4) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("Container (Debug)")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.12))
            .clipShape(Capsule())

        case .documents:
            HStack(spacing: 4) {
                Circle().fill(.blue).frame(width: 6, height: 6)
                Text("Documents (Sharing)")
                    .font(.caption2.bold())
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.12))
            .clipShape(Capsule())

        case .restricted:
            HStack(spacing: 4) {
                Circle().fill(.secondary).frame(width: 6, height: 6)
                Text("Restricted")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .clipShape(Capsule())

        case .unknown:
            HStack(spacing: 4) {
                Circle().fill(.orange).frame(width: 6, height: 6)
                Text("Untested")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.1))
            .clipShape(Capsule())
        }
    }

    private func errorCard(error: String) -> some View {
        let firstLine = error.components(separatedBy: .newlines).first ?? error
        let isLong = error.count > 120 || error.contains("\n")

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Device App Query Notice")
                        .font(.headline)

                    Text(firstLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button("Retry") {
                    vm.fetchLiveApps(udid: device.id)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("• Ensure iPhone is unlocked with your passcode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("• Note: iOS does not re-prompt 'Trust This Computer' if your Mac was already paired.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("• User Apps mode is significantly faster than querying all system apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isLong {
                Divider()

                HStack {
                    Button {
                        showingErrorDetails.toggle()
                    } label: {
                        Label(showingErrorDetails ? "Hide Log Details" : "Show Log Details",
                              systemImage: showingErrorDetails ? "chevron.up" : "chevron.down")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if showingErrorDetails {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(error, forType: .string)
                            copiedErrorLog = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedErrorLog = false
                            }
                        } label: {
                            Label(copiedErrorLog ? "Copied Log" : "Copy Log",
                                  systemImage: copiedErrorLog ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                        }
                        .controlSize(.small)
                    }
                }

                if showingErrorDetails {
                    ScrollView {
                        Text(error)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 120)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                }
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
    }

    private var toolingMissingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("libimobiledevice Recommended", systemImage: "terminal.fill")
                .font(.headline)
            Text("To browse app containers and internal databases live over USB without full backups, install `libimobiledevice` and `ideviceinstaller` via Homebrew:")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("brew install libimobiledevice ideviceinstaller")
                    .font(.caption.monospaced())
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew install libimobiledevice ideviceinstaller", forType: .string)
                    copiedBrewCmd = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedBrewCmd = false
                    }
                } label: {
                    Label(copiedBrewCmd ? "Copied" : "Copy", systemImage: copiedBrewCmd ? "checkmark" : "doc.on.doc")
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(10)
    }

    private var filteredApps: [AppRecord] {
        var list = vm.liveApps
        if filterAccessibleOnly {
            list = list.filter { $0.accessMode.isAccessible }
        }
        if !appSearch.isEmpty {
            list = list.filter {
                $0.displayName.localizedCaseInsensitiveContains(appSearch) ||
                $0.bundleID.localizedCaseInsensitiveContains(appSearch)
            }
        }
        return list
    }

    private func appBadgeColor(for app: AppRecord) -> Color {
        let hash = abs(app.bundleID.hashValue)
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .red, .orange, .teal, .cyan]
        return palette[hash % palette.count]
    }

    // MARK: - Offline Backup Section

    private var offlineBackupsSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                backupCard
                openBackupCard
                sampleBackupCard
                pairingGuidanceCard
            }
            .padding(.top, 8)
        } label: {
            Text("Offline Backups & Snapshots")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Full iPhone Backup")
                        .font(.subheadline.bold())
                    Text("Creates a full local backup on your Mac (slower, requires large disk space).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    vm.createBackupForDevice(device)
                } label: {
                    Label(vm.isCreatingBackup ? "Backing up…" : "Back Up Now…", systemImage: "arrow.down.circle")
                }
                .controlSize(.small)
                .disabled(vm.isCreatingBackup)
            }

            if vm.isCreatingBackup || !vm.backupProgressLog.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(vm.backupProgressLog)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .frame(height: 100)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }

    private var openBackupCard: some View {
        HStack {
            Image(systemName: "folder.badge.gearshape.fill")
                .font(.title3)
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 1) {
                Text("Open Existing Backup Folder")
                    .font(.subheadline.bold())
                Text("Browse a backup previously saved with Finder, iTunes, or PhoneVault.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Choose Backup…") {
                vm.presentOpenPanel()
            }
            .controlSize(.small)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }

    private var sampleBackupCard: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 1) {
                Text("Try Demo Sample Data")
                    .font(.subheadline.bold())
                Text("Test-drive inspection with built-in Safari & Notes sample databases.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Load Demo") {
                Task { await vm.loadSampleBackup() }
            }
            .controlSize(.small)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }

    private var pairingGuidanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("USB Connection & Trust Tips")
                .font(.subheadline.bold())
            Text("• Ensure iPhone is unlocked and you tapped 'Trust This Computer'.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("• For debug apps, install via Xcode or Ad-Hoc provisioning to enable full container access.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("• For user apps, add UIFileSharingEnabled to Info.plist to expose the Documents folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(10)
    }
}
