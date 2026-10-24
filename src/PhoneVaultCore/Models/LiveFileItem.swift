import Foundation

/// A file or directory located directly on a connected iOS device container.
public struct LiveFileItem: Identifiable, Sendable, Hashable {
    /// Remote path used as identity, e.g. "/Documents/notes.sqlite".
    public let id: String
    /// Base name of the file or directory.
    public let name: String
    /// Path relative to the app container or documents root.
    public let remotePath: String
    /// True if this item is a directory.
    public let isDirectory: Bool
    /// Size in bytes (nil for directories or unknown).
    public let size: Int64?
    /// Last modification date if reported by device.
    public let modificationDate: Date?

    public init(
        name: String,
        remotePath: String,
        isDirectory: Bool,
        size: Int64? = nil,
        modificationDate: Date? = nil
    ) {
        self.id = remotePath
        self.name = name
        self.remotePath = remotePath
        self.isDirectory = isDirectory
        self.size = size
        self.modificationDate = modificationDate
    }

    /// Converts this live item into a `BackupFile` representation for unified browsing & inspection.
    public func toBackupFile(bundleID: String, localCachedURL: URL? = nil) -> BackupFile {
        let cleanPath = remotePath.hasPrefix("/") ? String(remotePath.dropFirst()) : remotePath
        let ext = (name as NSString).pathExtension
        let kind: FileKind = isDirectory ? .directory : FileKind.infer(from: ext)
        return BackupFile(
            id: "\(bundleID):\(cleanPath)",
            domain: bundleID,
            relativePath: cleanPath,
            fileType: kind,
            fileSize: size,
            modificationDate: modificationDate,
            physicalURL: localCachedURL,
            isAvailable: true
        )
    }
}
