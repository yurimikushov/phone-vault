import Testing
import Foundation
import SQLite3
@testable import PhoneVaultCore

// MARK: - BackupReader tests

@Suite("BackupReader")
struct BackupReaderTests {

    let reader = BackupReader()

    // MARK: Validation

    @Test("Rejects a path that is not a directory")
    func rejectNonDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")
        try "x".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        #expect(throws: BackupReaderError.self) {
            try reader.validate(backupURL: tmp)
        }
    }

    @Test("Rejects a directory without Manifest.db")
    func rejectMissingManifestDB() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(throws: BackupReaderError.self) {
            try reader.validate(backupURL: dir)
        }
    }

    @Test("Rejects an encrypted backup")
    func rejectEncryptedBackup() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Write Manifest.plist with IsEncrypted = true
        let plist: NSDictionary = ["IsEncrypted": true, "Version": "10.0"]
        try plist.write(to: dir.appendingPathComponent("Manifest.plist"))
        // Create Manifest.db so the directory-check passes first
        try Data().write(to: dir.appendingPathComponent("Manifest.db"))

        #expect(throws: BackupReaderError.self) {
            try reader.validate(backupURL: dir)
        }
    }

    @Test("Rejects a backup with an unsupported manifest version")
    func rejectOldVersion() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let plist: NSDictionary = ["IsEncrypted": false, "Version": "9.0"]
        try plist.write(to: dir.appendingPathComponent("Manifest.plist"))
        try Data().write(to: dir.appendingPathComponent("Manifest.db"))

        #expect(throws: BackupReaderError.self) {
            try reader.validate(backupURL: dir)
        }
    }

    @Test("Accepts a valid minimal backup")
    func acceptValidBackup() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try BackupFixtures.makeMinimalBackup(at: dir)

        #expect(throws: Never.self) {
            try reader.validate(backupURL: dir)
        }
    }

    // MARK: Reading

    @Test("Reads backup info from Info.plist")
    func readsBackupInfo() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try BackupFixtures.makeMinimalBackup(at: dir)

        let (info, _, _) = try reader.read(backupURL: dir)
        #expect(info.deviceName == "Test iPhone")
        #expect(info.productVersion == "17.4")
        #expect(info.isEncrypted == false)
    }

    @Test("Enumerates files from Manifest.db")
    func enumeratesFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try BackupFixtures.makeMinimalBackup(at: dir)

        let (_, _, files) = try reader.read(backupURL: dir)
        // defaultFiles has 5 entries, one is a directory-skip candidate — actually none are dirs, but one is unavailable
        // We have 5 fixture files total, all flags=1 (regular file)
        #expect(files.count == 5)
    }

    @Test("Reports available and missing files correctly")
    func reportsAvailability() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try BackupFixtures.makeMinimalBackup(at: dir)

        let (info, _, files) = try reader.read(backupURL: dir)
        let available = files.filter(\.isAvailable)
        let missing   = files.filter { !$0.isAvailable }

        // 4 available, 1 missing (com.example.missing)
        #expect(available.count == 4)
        #expect(missing.count == 1)
        #expect(info.availableFileCount == 4)
        #expect(info.totalFileCount == 5)
    }

    @Test("Identifies apps from manifest domains")
    func identifiesApps() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try BackupFixtures.makeMinimalBackup(at: dir)

        let (_, apps, _) = try reader.read(backupURL: dir)
        let bundleIDs = Set(apps.map(\.bundleID))
        #expect(bundleIDs.contains("com.apple.mobilesafari"))
        #expect(bundleIDs.contains("com.apple.mobilenotes"))
        // com.example.missing has no available files but IS present in manifest
        #expect(bundleIDs.contains("com.example.missing"))
        #expect(apps.count == 3)
    }

    @Test("Resolves physical URLs correctly")
    func resolvesPhysicalURLs() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try BackupFixtures.makeMinimalBackup(at: dir)

        let (_, _, files) = try reader.read(backupURL: dir)
        let safariPref = files.first { $0.relativePath.hasSuffix(".plist") && $0.domain.contains("safari") }
        #expect(safariPref != nil)
        #expect(safariPref?.isAvailable == true)
        let physURL = safariPref?.physicalURL
        #expect(physURL != nil)
        #expect(FileManager.default.fileExists(atPath: physURL!.path))
    }

    @Test("Infers FileKind from extension")
    func infersFileKind() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try BackupFixtures.makeMinimalBackup(at: dir)

        let (_, _, files) = try reader.read(backupURL: dir)
        let plistFile  = files.first { $0.relativePath.hasSuffix(".plist") }
        let dbFile     = files.first { $0.relativePath.hasSuffix(".db") }
        let jsonFile   = files.first { $0.relativePath.hasSuffix(".json") }
        #expect(plistFile?.fileType == .plist)
        #expect(dbFile?.fileType == .sqlite)
        #expect(jsonFile?.fileType == .json)
    }
}

// MARK: - SQLiteInspector tests

@Suite("SQLiteInspector")
struct SQLiteInspectorTests {

    let inspector = SQLiteInspector()

    @Test("Lists tables and row counts from a valid SQLite file")
    func listsTablesAndCounts() throws {
        let dbURL = try writeTempSQLite()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let tables = try inspector.schema(at: dbURL)
        #expect(!tables.isEmpty)
        let t = tables.first { $0.name == "t" }
        #expect(t != nil)
        #expect(t?.rowCount == 1)
        #expect(t?.isView == false)
    }

    @Test("Fetches first page of rows")
    func fetchesFirstPage() throws {
        let dbURL = try writeTempSQLite()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let result = try inspector.fetchPage(at: dbURL, tableName: "t", page: 0, pageSize: 10)
        guard case .sqliteTablePage(let name, let columns, let rows, let page, let hasMore) = result else {
            Issue.record("Expected .sqliteTablePage, got \(result)")
            return
        }
        #expect(name == "t")
        #expect(columns.contains("id"))
        #expect(columns.contains("name"))
        #expect(rows.count == 1)
        #expect(page == 0)
        #expect(hasMore == false)
    }

    @Test("Returns error for unknown table name")
    func rejectsUnknownTable() throws {
        let dbURL = try writeTempSQLite()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let result = try inspector.fetchPage(at: dbURL, tableName: "nonexistent_table", page: 0)
        guard case .error = result else {
            Issue.record("Expected .error result for unknown table, got \(result)")
            return
        }
    }

    @Test("Paginates correctly")
    func paginates() throws {
        let dbURL = try writePaginationDB(rowCount: 25)
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let page0 = try inspector.fetchPage(at: dbURL, tableName: "items", page: 0, pageSize: 10)
        let page2 = try inspector.fetchPage(at: dbURL, tableName: "items", page: 2, pageSize: 10)

        guard case .sqliteTablePage(_, _, let rows0, _, let hasMore0) = page0 else {
            Issue.record("page0 not a table page"); return
        }
        guard case .sqliteTablePage(_, _, let rows2, _, let hasMore2) = page2 else {
            Issue.record("page2 not a table page"); return
        }
        #expect(rows0.count == 10)
        #expect(hasMore0 == true)
        #expect(rows2.count == 5)
        #expect(hasMore2 == false)
    }

    // MARK: Helpers

    private func writeTempSQLite() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        var db: OpaquePointer?
        sqlite3_open(url.path, &db)
        sqlite3_exec(db, "CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT); INSERT INTO t VALUES(1,'hello');", nil, nil, nil)
        sqlite3_close(db)
        return url
    }

    private func writePaginationDB(rowCount: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        var db: OpaquePointer?
        sqlite3_open(url.path, &db)
        sqlite3_exec(db, "CREATE TABLE items(id INTEGER PRIMARY KEY);", nil, nil, nil)
        for i in 1 ... rowCount {
            sqlite3_exec(db, "INSERT INTO items VALUES(\(i));", nil, nil, nil)
        }
        sqlite3_close(db)
        return url
    }
}

// MARK: - PlistInspector tests

@Suite("PlistInspector")
struct PlistInspectorTests {

    @Test("Decodes a dictionary plist")
    func decodesDictionary() throws {
        let data = BackupFixtures.samplePlistData()
        let inspector = PlistInspector()
        let node = try inspector.decode(data: data)

        guard case .dictionary(let pairs) = node else {
            Issue.record("Expected dictionary, got \(node)"); return
        }
        let keys = pairs.map(\.key)
        #expect(keys.contains("hello"))
        #expect(keys.contains("count"))
    }

    @Test("Formats a plist node to string")
    func formatsToString() throws {
        let data = BackupFixtures.samplePlistData()
        let inspector = PlistInspector()
        let node = try inspector.decode(data: data)
        let formatted = PlistFormatter().format(node)
        #expect(formatted.contains("hello"))
        #expect(formatted.contains("world"))
    }

    @Test("Handles malformed data gracefully")
    func handlesMalformedData() {
        let inspector = PlistInspector()
        #expect(throws: (any Error).self) {
            try inspector.decode(data: Data("not a plist".utf8))
        }
    }
}

// MARK: - ExportService tests

@Suite("ExportService")
struct ExportServiceTests {

    let service = ExportService()
    let reader  = BackupReader()

    @Test("Exports a single available file")
    func exportsSingleFile() async throws {
        let src = try makeTempDir()
        let dst = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }
        try BackupFixtures.makeMinimalBackup(at: src)
        let (_, _, files) = try reader.read(backupURL: src)
        let available = files.filter(\.isAvailable).first!

        let request = ExportRequest(
            selection: .single(available),
            destinationURL: dst,
            preserveRelativePaths: true
        )
        let result = try await service.export(request)
        #expect(result.succeeded.count == 1)
        #expect(result.failed.isEmpty)

        let dest = result.succeeded[0].destinationURL!
        #expect(FileManager.default.fileExists(atPath: dest.path))
    }

    @Test("Reports failure for an unavailable file")
    func reportsFailureForMissingFile() async throws {
        let src = try makeTempDir()
        let dst = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }
        try BackupFixtures.makeMinimalBackup(at: src)
        let (_, _, files) = try reader.read(backupURL: src)
        let missing = files.first { !$0.isAvailable }!

        let request = ExportRequest(selection: .single(missing), destinationURL: dst)
        let result = try await service.export(request)
        #expect(result.failed.count == 1)
        #expect(result.succeeded.isEmpty)
    }

    @Test("Rejects path traversal in relative path")
    func rejectsPathTraversal() async throws {
        let dst = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dst) }

        // Craft a file with a traversal path
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "data".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let evil = BackupFile(
            id: "evil",
            domain: "AppDomain-com.evil",
            relativePath: "../../etc/passwd",
            fileType: .text,
            fileSize: 4,
            modificationDate: nil,
            physicalURL: tmp,
            isAvailable: true
        )
        let request = ExportRequest(selection: .single(evil), destinationURL: dst)
        let result = try await service.export(request)
        #expect(result.failed.count == 1)
        let err = result.failed[0].error as? ExportError
        if case .pathTraversalAttempt = err { } else {
            Issue.record("Expected pathTraversalAttempt error, got \(String(describing: err))")
        }
    }

    @Test("Handles filename collisions safely")
    func handlesCollisions() async throws {
        let src = try makeTempDir()
        let dst = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }
        try BackupFixtures.makeMinimalBackup(at: src)
        let (_, _, files) = try reader.read(backupURL: src)
        let available = files.filter(\.isAvailable).first!

        let request = ExportRequest(selection: .single(available), destinationURL: dst)
        // Export twice
        let r1 = try await service.export(request)
        let r2 = try await service.export(request)
        #expect(r1.succeeded.count == 1)
        #expect(r2.succeeded.count == 1)

        // Verify the two destinations are different
        let url1 = r1.succeeded[0].destinationURL!
        let url2 = r2.succeeded[0].destinationURL!
        #expect(url1 != url2)
    }

    @Test("Preserves file bytes on export")
    func preservesBytes() async throws {
        let src = try makeTempDir()
        let dst = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }
        try BackupFixtures.makeMinimalBackup(at: src)
        let (_, _, files) = try reader.read(backupURL: src)
        let available = files.filter(\.isAvailable).first!

        let request = ExportRequest(selection: .single(available), destinationURL: dst)
        let result = try await service.export(request)
        #expect(result.succeeded.count == 1)

        let exportedData = try Data(contentsOf: result.succeeded[0].destinationURL!)
        let sourceData   = try Data(contentsOf: available.physicalURL!)
        #expect(exportedData == sourceData)
    }
}

// MARK: - FileKind tests

@Suite("FileKind")
struct FileKindTests {
    @Test("Infers sqlite from .db and .sqlite extensions")
    func infersSQLite() {
        #expect(FileKind.infer(from: "db") == .sqlite)
        #expect(FileKind.infer(from: "sqlite") == .sqlite)
        #expect(FileKind.infer(from: "sqlite3") == .sqlite)
        #expect(FileKind.infer(from: "DB") == .sqlite)
    }

    @Test("Infers plist from .plist extension")
    func infersPlist() {
        #expect(FileKind.infer(from: "plist") == .plist)
    }

    @Test("Falls back to binary for unknown extensions")
    func infersBinaryForUnknown() {
        #expect(FileKind.infer(from: "xyz123") == .binary)
        #expect(FileKind.infer(from: "") == .binary)
    }
}

// MARK: - JSONInspector tests

@Suite("JSONInspector")
struct JSONInspectorTests {

    let inspector = JSONInspector()

    @Test("Pretty prints valid JSON")
    func formatsJSON() throws {
        let jsonStr = #"{"name":"iPhone","count":2}"#
        let data = Data(jsonStr.utf8)
        let result = try inspector.format(data: data)
        guard case .json(let text) = result else {
            Issue.record("Expected .json preview result")
            return
        }
        #expect(text.contains("\"name\" : \"iPhone\""))
        #expect(text.contains("\"count\" : 2"))
    }

    @Test("Rejects malformed JSON")
    func rejectsMalformedJSON() {
        let badData = Data("this is not json".utf8)
        #expect(throws: (any Error).self) {
            try inspector.format(data: badData)
        }
    }
}

// MARK: - TextInspector tests

@Suite("TextInspector")
struct TextInspectorTests {

    @Test("Reads full text within limit")
    func readsSmallText() throws {
        let inspector = TextInspector(limit: 1024)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try "Hello World\nLine 2".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = try inspector.read(url: tmp)
        guard case .text(let content, let truncated) = result else {
            Issue.record("Expected .text preview result")
            return
        }
        #expect(content == "Hello World\nLine 2")
        #expect(truncated == false)
    }

    @Test("Truncates text exceeding limit")
    func truncatesLargeText() throws {
        let inspector = TextInspector(limit: 10)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try "0123456789ABCDEF".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = try inspector.read(url: tmp)
        guard case .text(let content, let truncated) = result else {
            Issue.record("Expected .text preview result")
            return
        }
        #expect(content.count == 10)
        #expect(truncated == true)
    }
}

// MARK: - DeviceMonitor and ConnectedDevice tests

@Suite("ConnectedDevice")
struct ConnectedDeviceTests {

    @Test("Maps product type identifiers to friendly marketing names")
    func mapsMarketingNames() {
        #expect(ConnectedDevice.friendlyModel(for: "iPhone14,7") == "iPhone 14")
        #expect(ConnectedDevice.friendlyModel(for: "iPhone15,3") == "iPhone 14 Pro Max")
        #expect(ConnectedDevice.friendlyModel(for: "iPhone16,1") == "iPhone 15 Pro")
        #expect(ConnectedDevice.friendlyModel(for: "iPhone17,1") == "iPhone 16 Pro")
        #expect(ConnectedDevice.friendlyModel(for: "iPad14,3") == "iPad Pro 11-inch (4th gen)")
        #expect(ConnectedDevice.friendlyModel(for: "UnknownGadget") == "UnknownGadget")
    }

    @Test("Handles missing socket path gracefully")
    func handlesMissingSocket() async {
        let monitor = DeviceMonitor(socketPath: "/nonexistent/path/to/usbmuxd")
        let devices = await monitor.fetchConnectedDevices()
        #expect(devices.isEmpty)
    }

    @Test("Fetches connected devices safely")
    func queriesSystemDevices() async {
        let monitor = DeviceMonitor.shared
        // On macOS this talks to /var/run/usbmuxd; should not throw or crash
        let devices = await monitor.fetchConnectedDevices()
        // If a physical device is connected, verify basic invariants and no duplicates
        let ids = devices.map(\.id)
        #expect(Set(ids).count == ids.count, "Device IDs should be unique (no duplicates for USB + Network)")
        for dev in devices {
            #expect(!dev.id.isEmpty)
            #expect(!dev.name.isEmpty)
        }
    }

    @Test("Deduplicates multiple connection types preferring USB over Network")
    func deduplicatesDevicesPreferringUSB() {
        let entries: [[String: Any]] = [
            [
                "DeviceID": 875,
                "MessageType": "Attached",
                "Properties": [
                    "ConnectionType": "Network",
                    "DeviceID": 875,
                    "SerialNumber": "00008110-001E21D90E88201E"
                ]
            ],
            [
                "DeviceID": 878,
                "MessageType": "Attached",
                "Properties": [
                    "ConnectionType": "USB",
                    "DeviceID": 878,
                    "SerialNumber": "00008110-001E21D90E88201E"
                ]
            ],
            [
                "DeviceID": 901,
                "MessageType": "Attached",
                "Properties": [
                    "ConnectionType": "USB",
                    "DeviceID": 901,
                    "SerialNumber": "OTHER-DEVICE-UDID-123"
                ]
            ]
        ]

        let candidates = DeviceMonitor.deduplicateDeviceEntries(entries)
        #expect(candidates.count == 2)
        #expect(candidates[0].serial == "00008110-001E21D90E88201E")
        #expect(candidates[0].connType == "USB")
        #expect(candidates[0].devID == 878)
        #expect(candidates[1].serial == "OTHER-DEVICE-UDID-123")
        #expect(candidates[1].connType == "USB")
    }

    @Test("Preserves USB when USB appears before Network")
    func preservesUSBWhenFirst() {
        let entries: [[String: Any]] = [
            [
                "DeviceID": 878,
                "Properties": [
                    "ConnectionType": "USB",
                    "DeviceID": 878,
                    "SerialNumber": "00008110-001E21D90E88201E"
                ]
            ],
            [
                "DeviceID": 875,
                "Properties": [
                    "ConnectionType": "Network",
                    "DeviceID": 875,
                    "SerialNumber": "00008110-001E21D90E88201E"
                ]
            ]
        ]

        let candidates = DeviceMonitor.deduplicateDeviceEntries(entries)
        #expect(candidates.count == 1)
        #expect(candidates[0].connType == "USB")
        #expect(candidates[0].devID == 878)
    }
}

@Suite("LiveDevice")
struct LiveDeviceTests {

    @Test("Parses app list XML plist and detects sharing and debug access")
    func parsesAppListPlist() throws {
        let xmlPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array>
            <dict>
                <key>CFBundleIdentifier</key>
                <string>com.example.debugapp</string>
                <key>CFBundleDisplayName</key>
                <string>Debug App</string>
                <key>CFBundleShortVersionString</key>
                <string>1.2.0</string>
                <key>SignerIdentity</key>
                <string>Apple Development: John Doe</string>
                <key>ApplicationType</key>
                <string>User</string>
            </dict>
            <dict>
                <key>CFBundleIdentifier</key>
                <string>com.example.sharingapp</string>
                <key>CFBundleDisplayName</key>
                <string>File Sharing App</string>
                <key>UIFileSharingEnabled</key>
                <true/>
                <key>ApplicationType</key>
                <string>User</string>
            </dict>
            <dict>
                <key>CFBundleIdentifier</key>
                <string>com.apple.Preferences</string>
                <key>CFBundleDisplayName</key>
                <string>Settings</string>
                <key>ApplicationType</key>
                <string>System</string>
            </dict>
        </array>
        </plist>
        """

        let data = xmlPlist.data(using: .utf8)!
        let apps = try LiveDeviceParser.parseAppsPlist(data: data)

        #expect(apps.count == 3)

        let debugApp = try #require(apps.first(where: { $0.bundleID == "com.example.debugapp" }))
        #expect(debugApp.displayName == "Debug App")
        #expect(debugApp.accessMode == .container)
        #expect(debugApp.version == "1.2.0")

        let sharingApp = try #require(apps.first(where: { $0.bundleID == "com.example.sharingapp" }))
        #expect(sharingApp.displayName == "File Sharing App")
        #expect(sharingApp.accessMode == .documents)

        let systemApp = try #require(apps.first(where: { $0.bundleID == "com.apple.Preferences" }))
        #expect(systemApp.isSystemApp == true)
        #expect(systemApp.accessMode == .restricted)
    }

    @Test("Parses afcclient ls -l output and strips ANSI color codes")
    func parsesAFCListOutput() {
        let sampleOutput = """
        \u{001B}[0;34mdrwxr-xr-x\u{001B}[0m mobile         160 24 Oct 2026 14:00:00 Documents
        \u{001B}[0;34mdrwxr-xr-x\u{001B}[0m mobile         160 24 Oct 2026 14:00:00 Library
        -rw-r--r-- mobile      122880 24 Oct 2026 14:02:15 AppData.sqlite
        -rw-r--r-- mobile        1024 24 Oct 2026 14:01:00 User Notes 2026.txt
        """

        let items = LiveDeviceParser.parseAFCListOutput(sampleOutput, basePath: "/")
        #expect(items.count == 4)

        let docs = items.first(where: { $0.name == "Documents" })
        #expect(docs?.isDirectory == true)

        let db = items.first(where: { $0.name == "AppData.sqlite" })
        #expect(db?.isDirectory == false)
        #expect(db?.size == 122880)
        #expect(db?.remotePath == "AppData.sqlite")

        let notes = items.first(where: { $0.name == "User Notes 2026.txt" })
        #expect(notes?.name == "User Notes 2026.txt")
        #expect(notes?.size == 1024)
    }

    @Test("Parses POSIX 10-column afcclient ls -l output accurately")
    func parsesPOSIX10ColumnAFCListOutput() {
        let realAfcOutput = """
        drwxr-xr-x    3 mobile mobile         96 21 Sep 2024 23:21:49 RTPhotos
        -rw-r--r--    1 mobile mobile   15106048 24 Oct 2026 11:58:15 MEDB.db
        -rw-r--r--    1 mobile mobile       1628 21 Sep 2024 23:20:26 voices.plist
        -rw-r--r--    1 mobile mobile          2 24 Oct 2026 11:47:33 ActivePartnerConnections_P4CPC9UPL5BYQ1DI
        drwxr-xr-x    2 mobile mobile        160 21 Sep 2024 23:21:49 RTSportActivities
        """

        let items = LiveDeviceParser.parseAFCListOutput(realAfcOutput, basePath: "Documents")
        #expect(items.count == 5)

        let photos = items.first(where: { $0.name == "RTPhotos" })
        #expect(photos?.isDirectory == true)
        #expect(photos?.remotePath == "Documents/RTPhotos")
        #expect(photos?.size == nil)

        let medb = items.first(where: { $0.name == "MEDB.db" })
        #expect(medb?.isDirectory == false)
        #expect(medb?.remotePath == "Documents/MEDB.db")
        #expect(medb?.size == 15106048)
        #expect(medb?.modificationDate != nil)

        let plist = items.first(where: { $0.name == "voices.plist" })
        #expect(plist?.isDirectory == false)
        #expect(plist?.remotePath == "Documents/voices.plist")
        #expect(plist?.size == 1628)
    }

    @Test("Normalizes remote paths correctly for documents and container modes")
    func normalizesRemotePaths() {
        let service = LiveDeviceService.shared

        // Documents mode: always rooted at /Documents
        #expect(service.normalizeRemotePath(path: "", accessMode: .documents) == "/Documents")
        #expect(service.normalizeRemotePath(path: "/", accessMode: .documents) == "/Documents")
        #expect(service.normalizeRemotePath(path: "Documents", accessMode: .documents) == "/Documents")
        #expect(service.normalizeRemotePath(path: "/Documents", accessMode: .documents) == "/Documents")
        #expect(service.normalizeRemotePath(path: "Documents/MEDB.db", accessMode: .documents) == "/Documents/MEDB.db")
        #expect(service.normalizeRemotePath(path: "/Documents/MEDB.db", accessMode: .documents) == "/Documents/MEDB.db")
        #expect(service.normalizeRemotePath(path: "MEDB.db", accessMode: .documents) == "/Documents/MEDB.db")
        #expect(service.normalizeRemotePath(path: "RTPhotos/photo.jpg", accessMode: .documents) == "/Documents/RTPhotos/photo.jpg")

        // Container mode: rooted at /
        #expect(service.normalizeRemotePath(path: "", accessMode: .container) == "/")
        #expect(service.normalizeRemotePath(path: "/", accessMode: .container) == "/")
        #expect(service.normalizeRemotePath(path: "Documents", accessMode: .container) == "/Documents")
        #expect(service.normalizeRemotePath(path: "Library/Preferences/app.plist", accessMode: .container) == "/Library/Preferences/app.plist")
    }

    @Test("Detects local device tooling availability safely")
    func detectsTooling() {
        let service = LiveDeviceService.shared
        // On this Mac with Homebrew, afcclient and ideviceinstaller are found
        #expect(service.ideviceinstallerPath != nil)
        #expect(service.afcclientPath != nil)
        #expect(service.isToolingAvailable == true)
    }
}

// MARK: - Shared helpers

private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
