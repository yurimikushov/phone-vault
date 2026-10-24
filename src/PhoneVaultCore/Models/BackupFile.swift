import Foundation

/// A single file record resolved from the iOS backup manifest.
public struct BackupFile: Identifiable, Sendable {
    /// The SHA-1 hash used as the file identifier in the backup (the manifest's fileID).
    public let id: String
    /// The iOS domain the file belongs to, e.g. "AppDomain-com.apple.mobilesafari".
    public let domain: String
    /// The original relative path within the app container, e.g. "Library/Preferences/com.apple.mobilesafari.plist".
    public let relativePath: String
    /// Detected file type based on extension and content sniff.
    public let fileType: FileKind
    /// File size in bytes, if available from the manifest.
    public let fileSize: Int64?
    /// Last modification date, if available from the manifest.
    public let modificationDate: Date?
    /// Absolute URL to the physical file inside the backup folder (nil when the payload is missing).
    public let physicalURL: URL?
    /// Whether the physical payload file exists on disk.
    public let isAvailable: Bool

    public init(
        id: String,
        domain: String,
        relativePath: String,
        fileType: FileKind,
        fileSize: Int64?,
        modificationDate: Date?,
        physicalURL: URL?,
        isAvailable: Bool
    ) {
        self.id = id
        self.domain = domain
        self.relativePath = relativePath
        self.fileType = fileType
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.physicalURL = physicalURL
        self.isAvailable = isAvailable
    }

    /// Filename component of the relative path.
    public var filename: String {
        (relativePath as NSString).lastPathComponent
    }

    /// Directory component of the relative path (empty string for root-level files).
    public var directory: String {
        (relativePath as NSString).deletingLastPathComponent
    }
}

/// Broad categories used for icon selection, filtering, and preview routing.
public enum FileKind: String, Sendable, CaseIterable {
    case sqlite
    case plist
    case json
    case text
    case image
    case audio
    case video
    case binary
    case directory

    /// Infer kind from a file extension.
    public static func infer(from pathExtension: String) -> FileKind {
        switch pathExtension.lowercased() {
        case "db", "sqlite", "sqlite3":
            return .sqlite
        case "plist":
            return .plist
        case "json":
            return .json
        case "txt", "log", "csv", "xml", "html", "htm", "css", "js", "md", "yaml", "yml":
            return .text
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "bmp", "tiff", "tif", "webp":
            return .image
        case "mp3", "aac", "m4a", "wav", "aiff", "flac", "ogg":
            return .audio
        case "mp4", "mov", "m4v", "avi", "mkv":
            return .video
        default:
            return .binary
        }
    }
}
