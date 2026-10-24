import Foundation
import SQLite3

/// Reads and parses unencrypted iOS Finder/iTunes-style backups.
///
/// Layout on disk:
/// ```
/// <backup-uuid>/
///   Info.plist          – device metadata
///   Manifest.plist      – backup-level metadata (encrypted flag, version)
///   Manifest.db         – SQLite: Files table with fileID, domain, relativePath, file metadata plist
///   Status.plist        – backup state
///   <aa>/<file-sha1>    – payload blobs stored as SHA1[0:2] / SHA1
/// ```
public final class BackupReader: Sendable {

    public init() {}

    // MARK: - Public API

    /// Validate that the URL looks like a supported backup directory.
    ///
    /// Throws `BackupReaderError` for any structural problem found.
    public func validate(backupURL: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        guard fm.fileExists(atPath: backupURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw BackupReaderError.notADirectory(backupURL)
        }

        let manifestDB = backupURL.appendingPathComponent("Manifest.db")
        guard fm.fileExists(atPath: manifestDB.path) else {
            throw BackupReaderError.missingManifestDB(backupURL)
        }

        // Read Manifest.plist to check version and encryption
        let manifestPlist = backupURL.appendingPathComponent("Manifest.plist")
        if fm.fileExists(atPath: manifestPlist.path) {
            if let dict = NSDictionary(contentsOf: manifestPlist) {
                let isEncrypted = dict["IsEncrypted"] as? Bool ?? false
                if isEncrypted {
                    throw BackupReaderError.encryptedBackup
                }
                let version = dict["Version"] as? String ?? ""
                let major = Int(version.split(separator: ".").first ?? "0") ?? 0
                // Version 10 = iOS 9+, the flat SHA1 layout we support
                if major < 10 {
                    throw BackupReaderError.unsupportedManifestVersion(major)
                }
            }
        }
    }

    /// Read the full backup: validate, parse Info.plist, enumerate files, and return structured data.
    public func read(backupURL: URL) throws -> (info: BackupInfo, apps: [AppRecord], files: [BackupFile]) {
        try validate(backupURL: backupURL)

        let deviceInfo = try readInfoPlist(backupURL: backupURL)
        let (files, apps) = try readManifestDB(backupURL: backupURL)

        let availableCount = files.filter(\.isAvailable).count
        let info = BackupInfo(
            backupURL: backupURL,
            deviceName: deviceInfo["DeviceName"] as? String,
            productVersion: deviceInfo["Product Version"] as? String,
            productType: deviceInfo["Product Type"] as? String,
            uniqueDeviceID: deviceInfo["Unique Identifier"] as? String,
            date: deviceInfo["Last Backup Date"] as? Date,
            isEncrypted: false,
            totalFileCount: files.count,
            availableFileCount: availableCount,
            appCount: apps.count,
            manifestVersion: 10
        )
        return (info, apps, files)
    }

    // MARK: - Info.plist

    private func readInfoPlist(backupURL: URL) throws -> NSDictionary {
        let url = backupURL.appendingPathComponent("Info.plist")
        guard let dict = NSDictionary(contentsOf: url) else {
            // Non-fatal: return empty dict (Info.plist can be absent on older backups)
            return NSDictionary()
        }
        return dict
    }

    // MARK: - Manifest.db (SQLite)

    private func readManifestDB(backupURL: URL) throws -> ([BackupFile], [AppRecord]) {
        let dbURL = backupURL.appendingPathComponent("Manifest.db")
        var db: OpaquePointer?

        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dbURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            throw BackupReaderError.manifestQueryFailed("Cannot open Manifest.db at \(dbURL.path)")
        }
        defer { sqlite3_close(db) }

        return try queryFiles(db: db, backupURL: backupURL)
    }

    private func queryFiles(db: OpaquePointer, backupURL: URL) throws -> ([BackupFile], [AppRecord]) {
        // The Files table schema (iOS 9+ / Manifest version 10):
        //   fileID  TEXT PRIMARY KEY,
        //   domain  TEXT,
        //   relativePath TEXT,
        //   flags   INTEGER,   -- 1=file, 2=directory, 4=symlink
        //   file    BLOB       -- bplist encoding of MBFile metadata (size, mtime, etc.)
        let sql = "SELECT fileID, domain, relativePath, flags, file FROM Files"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw BackupReaderError.manifestQueryFailed(msg)
        }
        defer { sqlite3_finalize(stmt) }

        var files: [BackupFile] = []
        var domainCounts: [String: (total: Int, available: Int)] = [:]

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let fileIDCStr = sqlite3_column_text(stmt, 0),
                let domainCStr  = sqlite3_column_text(stmt, 1)
            else { continue }

            let fileID       = String(cString: fileIDCStr)
            let domain       = String(cString: domainCStr)
            let relativePath = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let flags        = sqlite3_column_int(stmt, 3)

            // flags: 1=regular file, 2=directory, 4=symlink.  Skip directories.
            let isDirectory = flags == 2
            if isDirectory { continue }

            // Decode the metadata bplist stored in the `file` column.
            var fileSize: Int64?
            var modDate: Date?
            if let blobPtr = sqlite3_column_blob(stmt, 4) {
                let blobLen = Int(sqlite3_column_bytes(stmt, 4))
                let data = Data(bytes: blobPtr, count: blobLen)
                (fileSize, modDate) = decodeMBFileBlob(data)
            }

            // Resolve physical file path: backupURL/<aa>/<fileID>
            let physicalURL = resolvePayloadURL(backupURL: backupURL, fileID: fileID)
            let isAvailable = FileManager.default.fileExists(atPath: physicalURL.path)

            let ext = (relativePath as NSString).pathExtension
            let kind = FileKind.infer(from: ext)

            let file = BackupFile(
                id: fileID,
                domain: domain,
                relativePath: relativePath,
                fileType: kind,
                fileSize: fileSize,
                modificationDate: modDate,
                physicalURL: isAvailable ? physicalURL : nil,
                isAvailable: isAvailable
            )
            files.append(file)

            // Track per-domain counts for AppRecord building
            var counts = domainCounts[domain] ?? (0, 0)
            counts.total += 1
            if isAvailable { counts.available += 1 }
            domainCounts[domain] = counts
        }

        let apps = buildAppRecords(from: domainCounts)
        return (files, apps)
    }

    // MARK: - MBFile blob decoding

    /// The `file` blob in each manifest row is a binary plist encoding an NSDictionary.
    /// The dictionary contains an "$objects" array (NSKeyedArchiver format).
    /// We use PropertyListSerialization and look for size / last-modified values.
    private func decodeMBFileBlob(_ data: Data) -> (size: Int64?, modDate: Date?) {
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = plist as? NSDictionary
        else { return (nil, nil) }

        // NSKeyedArchiver layout
        if let objects = dict["$objects"] as? NSArray {
            var size: Int64?
            var modDate: Date?
            for obj in objects {
                if let d = obj as? NSDictionary {
                    if let s = d["Size"] as? NSNumber {
                        size = s.int64Value
                    }
                    if let t = d["LastModified"] as? NSNumber {
                        // Core Data stores seconds since Jan 1 2001 (Mac epoch)
                        let interval = t.doubleValue
                        if interval > 0 {
                            modDate = Date(timeIntervalSinceReferenceDate: interval)
                        }
                    }
                }
            }
            return (size, modDate)
        }

        // Flat (non-keyed-archived) fallback
        if let size = dict["Size"] as? NSNumber {
            return (size.int64Value, nil)
        }
        return (nil, nil)
    }

    // MARK: - Physical path resolution

    /// iOS backups store payloads at <backupDir>/<first-two-chars-of-sha1>/<sha1>
    public func resolvePayloadURL(backupURL: URL, fileID: String) -> URL {
        let prefix = String(fileID.prefix(2))
        return backupURL
            .appendingPathComponent(prefix)
            .appendingPathComponent(fileID)
    }

    // MARK: - App domain parsing

    private func buildAppRecords(from domainCounts: [String: (total: Int, available: Int)]) -> [AppRecord] {
        var records: [AppRecord] = []
        for (domain, counts) in domainCounts {
            guard let bundleID = parseBundleID(from: domain) else { continue }
            let displayName = displayName(from: bundleID)
            records.append(AppRecord(
                domain: domain,
                bundleID: bundleID,
                displayName: displayName,
                fileCount: counts.total,
                availableFileCount: counts.available
            ))
        }
        return records.sorted { $0.displayName < $1.displayName }
    }

    /// Extract bundle ID from manifest domain strings.
    ///
    /// Supported formats:
    ///  - `AppDomain-com.example.app`
    ///  - `AppDomainGroup-com.example.group`
    ///  - `AppDomainPlugin-com.example.extension`
    private func parseBundleID(from domain: String) -> String? {
        let prefixes = ["AppDomain-", "AppDomainGroup-", "AppDomainPlugin-"]
        for prefix in prefixes {
            if domain.hasPrefix(prefix) {
                return String(domain.dropFirst(prefix.count))
            }
        }
        return nil
    }

    private func displayName(from bundleID: String) -> String {
        // Simple heuristic: last two components, title-cased
        let parts = bundleID.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return bundleID }
        let last = parts.last ?? bundleID
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}
