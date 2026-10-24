import Foundation
import SQLite3

// SQLITE_TRANSIENT is defined as ((sqlite3_destructor_type)-1) in C headers.
// In Swift, we must recreate it.
private let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Creates in-memory or on-disk synthetic iOS backup fixtures for testing.
/// These fixtures mimic the exact on-disk layout produced by Finder/iTunes backups.
public enum BackupFixtures {

    // MARK: - Fixture builder

    /// Create a minimal valid unencrypted backup at `rootURL`.
    ///
    /// The returned URLs are the paths of the payload files that were created.
    @discardableResult
    public static func makeMinimalBackup(
        at rootURL: URL,
        files: [FixtureFile] = Self.defaultFiles
    ) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)

        // ---- Info.plist ----
        let infoPlist: NSDictionary = [
            "DeviceName": "Test iPhone",
            "Product Version": "17.4",
            "Product Type": "iPhone15,3",
            "Unique Identifier": "TEST-UDID-0001",
            "Last Backup Date": Date(timeIntervalSinceReferenceDate: 760000000),
        ]
        let infoPlistURL = rootURL.appendingPathComponent("Info.plist")
        try infoPlist.write(to: infoPlistURL)

        // ---- Manifest.plist ----
        let manifestPlist: NSDictionary = [
            "IsEncrypted": false,
            "Version": "10.0",
        ]
        let manifestPlistURL = rootURL.appendingPathComponent("Manifest.plist")
        try manifestPlist.write(to: manifestPlistURL)

        // ---- Manifest.db ----
        let manifestDBURL = rootURL.appendingPathComponent("Manifest.db")
        try createManifestDB(at: manifestDBURL, files: files)

        // ---- Payload blobs ----
        var createdURLs: [URL] = []
        for fixture in files where fixture.isAvailable {
            let prefix = String(fixture.fileID.prefix(2))
            let dir = rootURL.appendingPathComponent(prefix)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let payloadURL = dir.appendingPathComponent(fixture.fileID)
            try fixture.content.write(to: payloadURL)
            createdURLs.append(payloadURL)
        }
        return createdURLs
    }

    // MARK: - Manifest.db creation

    private static func createManifestDB(at url: URL, files: [FixtureFile]) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw NSError(domain: "BackupFixtures", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create fixture DB"])
        }
        defer { sqlite3_close(db) }

        let create = """
            CREATE TABLE IF NOT EXISTS Files (
                fileID       TEXT PRIMARY KEY,
                domain       TEXT,
                relativePath TEXT,
                flags        INTEGER,
                file         BLOB
            );
            """
        var errPtr: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, create, nil, nil, &errPtr)

        for fixture in files {
            let insert = "INSERT INTO Files (fileID, domain, relativePath, flags, file) VALUES (?,?,?,?,?)"
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, insert, -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, fixture.fileID, -1, SQLITE_TRANSIENT_DESTRUCTOR)
            sqlite3_bind_text(stmt, 2, fixture.domain, -1, SQLITE_TRANSIENT_DESTRUCTOR)
            sqlite3_bind_text(stmt, 3, fixture.relativePath, -1, SQLITE_TRANSIENT_DESTRUCTOR)
            sqlite3_bind_int(stmt,  4, 1) // 1 = regular file
            // Minimal file blob: just a null blob for simplicity in tests
            sqlite3_bind_null(stmt, 5)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Default fixture files

    public static let defaultFiles: [FixtureFile] = [
        // Safari preferences
        FixtureFile(
            fileID: "aabbcc1100000000000000000000000000000001",
            domain: "AppDomain-com.apple.mobilesafari",
            relativePath: "Library/Preferences/com.apple.mobilesafari.plist",
            content: samplePlistData(),
            isAvailable: true
        ),
        // Safari history DB
        FixtureFile(
            fileID: "aabbcc1100000000000000000000000000000002",
            domain: "AppDomain-com.apple.mobilesafari",
            relativePath: "Library/Safari/History.db",
            content: sampleSQLiteData(),
            isAvailable: true
        ),
        // A file whose payload is missing
        FixtureFile(
            fileID: "aabbcc1100000000000000000000000000000003",
            domain: "AppDomain-com.example.missing",
            relativePath: "Documents/data.json",
            content: Data(),
            isAvailable: false
        ),
        // Notes app DB
        FixtureFile(
            fileID: "aabbcc1100000000000000000000000000000004",
            domain: "AppDomain-com.apple.mobilenotes",
            relativePath: "Library/Group Containers/group.com.apple.notes/NoteStore.sqlite",
            content: sampleSQLiteData(),
            isAvailable: true
        ),
        // JSON file
        FixtureFile(
            fileID: "aabbcc1100000000000000000000000000000005",
            domain: "AppDomain-com.apple.mobilenotes",
            relativePath: "Documents/export.json",
            content: Data(#"{"version":1,"items":["a","b","c"]}"#.utf8),
            isAvailable: true
        ),
    ]

    // MARK: - Sample content helpers

    /// A minimal binary plist encoding {"hello":"world"}.
    public static func samplePlistData() -> Data {
        let dict: NSDictionary = ["hello": "world", "count": 42]
        return (try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)) ?? Data()
    }

    /// A tiny valid SQLite database with one table.
    public static func sampleSQLiteData() -> Data {
        // Create in a temp path, read back, delete
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var db: OpaquePointer?
        sqlite3_open(tmp.path, &db)
        sqlite3_exec(db, "CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT); INSERT INTO t VALUES(1,'test');", nil, nil, nil)
        sqlite3_close(db)
        return (try? Data(contentsOf: tmp)) ?? Data()
    }
}

// MARK: - FixtureFile

/// Describes a single file to include in a synthetic backup fixture.
public struct FixtureFile: Sendable {
    public let fileID: String
    public let domain: String
    public let relativePath: String
    public let content: Data
    /// If false, the payload file is recorded in the manifest but not created on disk.
    public let isAvailable: Bool

    public init(fileID: String, domain: String, relativePath: String, content: Data, isAvailable: Bool) {
        self.fileID = fileID
        self.domain = domain
        self.relativePath = relativePath
        self.content = content
        self.isAvailable = isAvailable
    }
}
