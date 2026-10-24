import Foundation
import AppKit
import Observation
import PhoneVaultCore

@Observable
@MainActor
final class BackupViewModel {

    // MARK: - Device state
    var connectedDevices: [ConnectedDevice] = []
    var isCreatingBackup = false
    var backupProgressLog = ""
    private var monitorTask: Task<Void, Never>?

    // MARK: - Live Device App Inspection state
    var liveApps: [AppRecord] = []
    var isLoadingLiveApps = false
    var liveAppsError: String?
    var includeSystemApps = false
    var activeLiveApp: AppRecord?
    var activeLiveDeviceUDID: String?

    var isLiveSession: Bool {
        activeLiveApp != nil
    }

    // MARK: - Backup state
    var backupURL: URL?
    var backupInfo: BackupInfo?
    var apps: [AppRecord] = []
    private(set) var allFiles: [BackupFile] = []
    var isLoading = false
    var loadError: String?

    // MARK: - Sidebar selection
    enum SidebarSelection: Hashable {
        case device(String)
        case liveApp(udid: String, bundleID: String)
        case allFiles
        case app(String)
    }

    var sidebarSelection: SidebarSelection? = nil {
        didSet {
            handleSidebarSelectionChange()
        }
    }

    var selectedDevice: ConnectedDevice? {
        switch sidebarSelection {
        case .device(let id):
            return connectedDevices.first(where: { $0.id == id })
        case .liveApp(let udid, _):
            return connectedDevices.first(where: { $0.id == udid })
        default:
            return nil
        }
    }

    var selectedAppID: String? {
        switch sidebarSelection {
        case .app(let id):
            return id
        case .liveApp(_, let bundleID):
            return bundleID
        default:
            return nil
        }
    }

    // MARK: - File browser
    var currentPath: String = ""
    var searchText: String = ""
    var sortKey: SortKey = .name
    var sortAscending: Bool = true
    var selectedItemIDs: Set<BrowserItem.ID> = []

    // MARK: - Inspector / preview
    var previewResult: PreviewResult?
    var isLoadingPreview = false

    // MARK: - Export
    var isExporting = false
    var exportResult: ExportResult?
    var showExportSummary = false

    // MARK: - Lifecycle

    init() {
        startDeviceMonitoring()
    }

    func startDeviceMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                let devices = await DeviceMonitor.shared.fetchConnectedDevices()
                if let self {
                    let wasEmpty = self.connectedDevices.isEmpty
                    self.connectedDevices = devices

                    if case .device(let id) = self.sidebarSelection {
                        if !devices.contains(where: { $0.id == id }) {
                            self.sidebarSelection = self.backupInfo != nil ? .allFiles : nil
                        }
                    } else if case .liveApp(let udid, _) = self.sidebarSelection {
                        if !devices.contains(where: { $0.id == udid }) {
                            self.sidebarSelection = self.backupInfo != nil ? .allFiles : nil
                        }
                    } else if (self.sidebarSelection == nil || wasEmpty) && self.backupInfo == nil && !devices.isEmpty {
                        self.sidebarSelection = .device(devices[0].id)
                    }
                }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    private func handleSidebarSelectionChange() {
        switch sidebarSelection {
        case .device(let id):
            activeLiveApp = nil
            currentPath = ""
            selectedItemIDs = []
            previewResult = nil
            loadLiveAppsIfNeeded(forUDID: id)

        case .liveApp(let udid, let bundleID):
            let app = liveApps.first(where: { $0.bundleID == bundleID }) ?? AppRecord(
                domain: bundleID,
                bundleID: bundleID,
                displayName: bundleID.components(separatedBy: ".").last ?? bundleID,
                fileCount: 0,
                availableFileCount: 0,
                accessMode: .unknown,
                version: nil,
                isSystemApp: false
            )
            activeLiveApp = app
            activeLiveDeviceUDID = udid
            currentPath = ""
            selectedItemIDs = []
            previewResult = nil
            loadLiveAppFiles(udid: udid, app: app)

        case .allFiles, .app:
            activeLiveApp = nil
            currentPath = ""
            selectedItemIDs = []
            previewResult = nil

        case nil:
            break
        }
    }

    func selectDevice(_ device: ConnectedDevice?) {
        if let device {
            sidebarSelection = .device(device.id)
        } else {
            sidebarSelection = backupInfo != nil ? .allFiles : nil
        }
    }

    func selectApp(_ appID: String?) {
        if let appID {
            sidebarSelection = .app(appID)
        } else {
            sidebarSelection = .allFiles
        }
        navigate(to: "")
    }

    // MARK: - Live App Selection & Loading

    func loadLiveAppsIfNeeded(forUDID udid: String) {
        if activeLiveDeviceUDID == udid && !liveApps.isEmpty { return }
        fetchLiveApps(udid: udid, includeSystem: includeSystemApps)
    }

    func fetchLiveApps(udid: String, includeSystem: Bool? = nil) {
        let include = includeSystem ?? includeSystemApps
        includeSystemApps = include
        isLoadingLiveApps = true
        liveAppsError = nil
        activeLiveDeviceUDID = udid

        Task { [weak self] in
            do {
                let apps = try await LiveDeviceService.shared.fetchInstalledApps(
                    udid: udid,
                    includeSystemApps: include
                )
                self?.liveApps = apps
            } catch {
                self?.liveAppsError = error.localizedDescription
                self?.liveApps = []
            }
            self?.isLoadingLiveApps = false
        }
    }

    func selectLiveApp(_ app: AppRecord, on device: ConnectedDevice) {
        if sidebarSelection == .liveApp(udid: device.id, bundleID: app.bundleID) {
            activeLiveApp = app
            activeLiveDeviceUDID = device.id
            currentPath = ""
            selectedItemIDs = []
            previewResult = nil
            loadLiveAppFiles(udid: device.id, app: app)
        } else {
            sidebarSelection = .liveApp(udid: device.id, bundleID: app.bundleID)
        }
    }

    private var liveDirectoryCache: [String: [BackupFile]] = [:]

    func loadLiveAppFiles(udid: String, app: AppRecord) {
        isLoading = true
        loadError = nil
        currentPath = ""
        liveDirectoryCache.removeAll()
        allFiles = []

        Task { [weak self] in
            guard let self else { return }
            do {
                // Verify or refine access mode
                let verifiedMode = await LiveDeviceService.shared.resolveAccessMode(
                    udid: udid,
                    bundleID: app.bundleID,
                    hint: app.accessMode
                )

                if !verifiedMode.isAccessible {
                    self.loadError = "Cannot access '\(app.displayName)': iOS sandbox restricts direct file access for this app. Ensure your iPhone is unlocked. Direct USB file browsing requires UIFileSharingEnabled or a developer/debug build."
                    self.isLoading = false
                    return
                }

                let updatedApp = AppRecord(
                    domain: app.id,
                    bundleID: app.bundleID,
                    displayName: app.displayName,
                    fileCount: 0,
                    availableFileCount: 0,
                    accessMode: verifiedMode,
                    version: app.version,
                    isSystemApp: app.isSystemApp
                )
                self.activeLiveApp = updatedApp

                // Load root directory contents lazily on demand (~1s)
                await self.loadLiveDirectory(path: "")
            }
            self.isLoading = false
        }
    }

    func loadLiveDirectory(path: String) async {
        guard let app = activeLiveApp, let udid = activeLiveDeviceUDID else { return }
        if let cached = liveDirectoryCache[path] {
            mergeLiveFiles(cached)
            return
        }

        isLoading = true
        do {
            let items = try await LiveDeviceService.shared.listDirectory(
                udid: udid,
                bundleID: app.bundleID,
                accessMode: app.accessMode,
                remotePath: path
            )

            let files = items.map { $0.toBackupFile(bundleID: app.bundleID) }
            liveDirectoryCache[path] = files
            mergeLiveFiles(files)
        } catch {
            self.loadError = "Failed to load folder: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func mergeLiveFiles(_ files: [BackupFile]) {
        var merged = self.allFiles.filter { existing in
            !files.contains(where: { $0.relativePath == existing.relativePath })
        }
        merged.append(contentsOf: files)
        self.allFiles = merged
    }

    func refreshLiveApp() {
        guard activeLiveApp != nil, activeLiveDeviceUDID != nil else { return }
        liveDirectoryCache.removeValue(forKey: currentPath)
        Task { [weak self] in
            await self?.loadLiveDirectory(path: self?.currentPath ?? "")
        }
    }

    // MARK: - Sort key enum

    enum SortKey: String, CaseIterable, Identifiable {
        case name   = "Name"
        case path   = "Path"
        case size   = "Size"
        case date   = "Date"
        var id: String { rawValue }
    }

    // MARK: - Computed: scoped file list

    var filesForSelectedApp: [BackupFile] {
        if isLiveSession {
            return allFiles
        }
        guard let appID = selectedAppID else { return allFiles }
        return allFiles.filter { $0.domain == appID }
    }

    var browserItems: [BrowserItem] {
        let raw = BrowserItem.items(from: filesForSelectedApp, at: currentPath, matching: searchText)
        return sorted(raw)
    }

    var selectedFile: BackupFile? {
        guard let id = selectedItemIDs.first else { return nil }
        for item in browserItems {
            if case .file(let f) = item, f.id == id { return f }
        }
        return nil
    }

    var pathComponents: [String] {
        currentPath.isEmpty ? [] : currentPath.split(separator: "/").map(String.init)
    }

    var totalStats: (total: Int, available: Int) {
        let files = filesForSelectedApp
        return (files.count, files.filter(\.isAvailable).count)
    }

    // MARK: - Sort helpers

    private func sorted(_ items: [BrowserItem]) -> [BrowserItem] {
        items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let result: Bool
            switch sortKey {
            case .name: result = a.sortName.localizedCaseInsensitiveCompare(b.sortName) == .orderedAscending
            case .path: result = a.sortPath < b.sortPath
            case .size: result = a.sortSize < b.sortSize
            case .date: result = a.sortDate < b.sortDate
            }
            return sortAscending ? result : !result
        }
    }

    // MARK: - Navigation

    func navigate(to path: String) {
        currentPath = path
        selectedItemIDs = []
        previewResult = nil

        if isLiveSession {
            Task { [weak self] in
                await self?.loadLiveDirectory(path: path)
            }
        }
    }

    func navigateUp() {
        let components = pathComponents
        guard !components.isEmpty else { return }
        let parent = components.dropLast().joined(separator: "/")
        navigate(to: parent)
    }

    // MARK: - Device Backup Creation

    func createBackupForDevice(_ device: ConnectedDevice) {
        if BackupCreationService.shared.canCreateBackupDirectly {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Choose a destination folder for the new backup"
            panel.prompt = "Start Backup"
            guard panel.runModal() == .OK, let destURL = panel.url else { return }

            isCreatingBackup = true
            backupProgressLog = "Starting backup for \(device.name) (\(device.id))...\n"

            Task { [weak self] in
                do {
                    try await BackupCreationService.shared.createBackup(
                        udid: device.id,
                        destinationURL: destURL
                    ) { line in
                        Task { @MainActor in
                            self?.backupProgressLog += line + "\n"
                        }
                    }
                    self?.backupProgressLog += "\nBackup completed successfully! Opening backup...\n"
                    let backupCandidate = destURL.appendingPathComponent(device.id)
                    let targetURL = FileManager.default.fileExists(atPath: backupCandidate.path) ? backupCandidate : destURL
                    await self?.loadBackup(url: targetURL)
                } catch {
                    self?.backupProgressLog += "\nBackup error: \(error.localizedDescription)\n"
                    self?.loadError = "Backup failed: \(error.localizedDescription)"
                }
                self?.isCreatingBackup = false
            }
        } else {
            let alert = NSAlert()
            alert.messageText = "Create Backup via macOS Finder"
            alert.informativeText = """
                Your iPhone '\(device.name)' is connected!

                To create a backup:
                1. Open Finder and click '\(device.name)' in the Locations sidebar.
                2. In the General tab, ensure 'Encrypt local backup' is unchecked.
                3. Click 'Back Up Now'.
                4. When finished, click 'Open Backup' in PhoneVault!
                """
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
        }
    }

    // MARK: - Open backup

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose an iTunes / Finder backup folder"
        panel.prompt = "Open Backup"

        let defaultBackupPath = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/MobileSync/Backup")
        if FileManager.default.fileExists(atPath: defaultBackupPath.path) {
            panel.directoryURL = defaultBackupPath
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await loadBackup(url: url) }
    }

    func loadSampleBackup() async {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhoneVaultDemoBackup")
        try? FileManager.default.removeItem(at: tmpDir)
        do {
            try BackupFixtures.makeMinimalBackup(at: tmpDir)
            await loadBackup(url: tmpDir)
        } catch {
            loadError = "Failed to create sample backup: \(error.localizedDescription)"
        }
    }

    func loadBackup(url: URL) async {
        isLoading = true
        loadError = nil
        backupURL = url
        activeLiveApp = nil
        sidebarSelection = .allFiles
        currentPath = ""
        selectedItemIDs = []
        previewResult = nil
        backupInfo = nil
        apps = []
        allFiles = []

        do {
            let reader = BackupReader()
            let (info, appList, files) = try reader.read(backupURL: url)
            backupInfo = info
            apps = appList
            allFiles = files
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    func refresh() async {
        if isLiveSession {
            refreshLiveApp()
        } else if let url = backupURL {
            await loadBackup(url: url)
        }
    }

    // MARK: - Preview loading

    func loadPreview(for file: BackupFile) {
        isLoadingPreview = true
        previewResult = nil

        Task { [weak self] in
            guard let self else { return }

            var physicalURL = file.physicalURL

            // If in live mode and file not yet cached locally, download on demand
            if physicalURL == nil, let liveApp = self.activeLiveApp, let udid = self.activeLiveDeviceUDID {
                do {
                    let localURL = try await LiveDeviceService.shared.downloadFile(
                        udid: udid,
                        bundleID: liveApp.bundleID,
                        accessMode: liveApp.accessMode,
                        remotePath: file.relativePath
                    )
                    physicalURL = localURL

                    // Cache local URL in allFiles
                    if let idx = self.allFiles.firstIndex(where: { $0.id == file.id }) {
                        let updated = BackupFile(
                            id: file.id,
                            domain: file.domain,
                            relativePath: file.relativePath,
                            fileType: file.fileType,
                            fileSize: file.fileSize,
                            modificationDate: file.modificationDate,
                            physicalURL: localURL,
                            isAvailable: true
                        )
                        self.allFiles[idx] = updated
                    }
                } catch {
                    self.previewResult = .error("Failed to fetch file from device: \(error.localizedDescription)")
                    self.isLoadingPreview = false
                    return
                }
            }

            guard let url = physicalURL else {
                self.previewResult = .error("File payload not available.")
                self.isLoadingPreview = false
                return
            }

            let result: PreviewResult
            do {
                switch file.fileType {
                case .sqlite:
                    let inspector = SQLiteInspector()
                    let tables = try inspector.schema(at: url)
                    result = .sqliteSchema(tables: tables)
                case .plist:
                    let inspector = PlistInspector()
                    let node = try inspector.read(url: url)
                    result = .plist(root: node)
                case .json:
                    let inspector = JSONInspector()
                    result = try inspector.read(url: url)
                case .text:
                    let inspector = TextInspector()
                    result = try inspector.read(url: url)
                case .image:
                    result = .image(url: url)
                default:
                    result = .unsupported(mimeType: nil)
                }
            } catch {
                result = .error(error.localizedDescription)
            }

            self.isLoadingPreview = false
            self.previewResult = result
        }
    }

    func loadSQLiteTablePage(url: URL, table: String, page: Int) {
        isLoadingPreview = true
        Task {
            let result: PreviewResult
            do {
                let inspector = SQLiteInspector()
                result = try inspector.fetchPage(at: url, tableName: table, page: page, pageSize: 200)
            } catch {
                result = .error(error.localizedDescription)
            }
            isLoadingPreview = false
            previewResult = result
        }
    }

    // MARK: - Export

    func exportSelected() {
        guard !selectedItemIDs.isEmpty else { return }
        var filesToExport: [BackupFile] = []
        var seenIDs = Set<String>()

        for id in selectedItemIDs {
            guard let item = browserItems.first(where: { $0.id == id }) else { continue }
            switch item {
            case .file(let f):
                if seenIDs.insert(f.id).inserted {
                    filesToExport.append(f)
                }
            case .directory(_, let dirPath, _, _):
                let prefix = dirPath + "/"
                let dirFiles = filesForSelectedApp.filter { $0.relativePath == dirPath || $0.relativePath.hasPrefix(prefix) }
                for f in dirFiles {
                    if seenIDs.insert(f.id).inserted {
                        filesToExport.append(f)
                    }
                }
            }
        }
        guard !filesToExport.isEmpty else { return }
        presentExportPanel(for: .multiple(filesToExport))
    }

    func exportCurrentFolder() {
        guard !currentPath.isEmpty else { return }
        let prefix = currentPath + "/"
        let files = filesForSelectedApp.filter { $0.relativePath == currentPath || $0.relativePath.hasPrefix(prefix) }
        guard !files.isEmpty else { return }
        presentExportPanel(for: .folder(domain: selectedAppID ?? "All", folderPath: currentPath, files: files))
    }

    func exportCurrentApp() {
        if let liveApp = activeLiveApp, let udid = activeLiveDeviceUDID {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Choose destination folder to export '\(liveApp.displayName)'"
            panel.prompt = "Export App"
            guard panel.runModal() == .OK, let destURL = panel.url else { return }

            isExporting = true
            Task { [weak self] in
                do {
                    try await LiveDeviceService.shared.exportRemote(
                        udid: udid,
                        bundleID: liveApp.bundleID,
                        accessMode: liveApp.accessMode,
                        remotePath: "/",
                        destinationURL: destURL
                    )
                    let exportedItems = (self?.allFiles ?? []).map {
                        ExportResult.Item(file: $0, destinationURL: destURL.appendingPathComponent($0.relativePath))
                    }
                    self?.exportResult = ExportResult(items: exportedItems)
                    self?.showExportSummary = true
                } catch {
                    self?.loadError = "Export failed: \(error.localizedDescription)"
                }
                self?.isExporting = false
            }
            return
        }

        guard let appID = selectedAppID else { return }
        guard let app = apps.first(where: { $0.id == appID }) else { return }
        let files = filesForSelectedApp
        presentExportPanel(for: .app(app, files: files))
    }

    private func presentExportPanel(for selection: ExportRequest.Selection) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the export destination folder"
        panel.prompt = "Export Here"
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        isExporting = true
        Task {
            do {
                // If live session, ensure selected files are downloaded first
                if let liveApp = self.activeLiveApp, let udid = self.activeLiveDeviceUDID {
                    let files: [BackupFile]
                    switch selection {
                    case .single(let f): files = [f]
                    case .multiple(let fs): files = fs
                    case .folder(_, _, let fs): files = fs
                    case .app(_, let fs): files = fs
                    }

                    for file in files where file.physicalURL == nil {
                        let localURL = try await LiveDeviceService.shared.downloadFile(
                            udid: udid,
                            bundleID: liveApp.bundleID,
                            accessMode: liveApp.accessMode,
                            remotePath: file.relativePath
                        )
                        if let idx = self.allFiles.firstIndex(where: { $0.id == file.id }) {
                            self.allFiles[idx] = BackupFile(
                                id: file.id,
                                domain: file.domain,
                                relativePath: file.relativePath,
                                fileType: file.fileType,
                                fileSize: file.fileSize,
                                modificationDate: file.modificationDate,
                                physicalURL: localURL,
                                isAvailable: true
                            )
                        }
                    }
                }

                let service = ExportService()
                let request = ExportRequest(selection: selection, destinationURL: destURL, preserveRelativePaths: true)
                exportResult = try await service.export(request)
                showExportSummary = true
            } catch {
                loadError = "Export failed: \(error.localizedDescription)"
            }
            isExporting = false
        }
    }
}
