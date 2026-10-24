import Foundation

/// Access mode supported for an iOS application container over USB.
public enum AppAccessMode: String, Sendable, Codable, CaseIterable {
    /// Full access to the container sandbox (/Documents, /Library, /Library/Application Support, /Library/Preferences, etc.)
    /// Available for development/debug builds signed with get-task-allow.
    case container = "Container (Debug)"
    /// Access to the app's /Documents folder and subfolders.
    /// Available for apps with UIFileSharingEnabled or LSSupportsOpeningDocumentsInPlace.
    case documents = "Documents (File Sharing)"
    /// Standard sandboxed app without file sharing or debug privileges.
    case restricted = "Restricted"
    /// Access level has not yet been determined.
    case unknown = "Unknown"

    public var isAccessible: Bool {
        self == .container || self == .documents
    }
}

/// An iOS application record representing either an app from an iOS backup or a live app on a connected device.
public struct AppRecord: Identifiable, Sendable, Hashable {
    /// The unique identifier (domain string in backups, e.g. "AppDomain-com...", or bundleID for live apps).
    public let id: String
    /// Bundle identifier, e.g. "com.apple.mobilesafari" or "com.example.myapp".
    public let bundleID: String
    /// Human-readable display name.
    public let displayName: String
    /// Number of files enumerated for this app.
    public let fileCount: Int
    /// Number of those files whose payload exists / is available.
    public let availableFileCount: Int
    /// Access mode supported for this app over USB.
    public let accessMode: AppAccessMode
    /// App version string (if available).
    public let version: String?
    /// Whether this is a system app (e.g. MobileSafari, Preferences) or user app.
    public let isSystemApp: Bool

    public init(
        domain: String,
        bundleID: String,
        displayName: String,
        fileCount: Int,
        availableFileCount: Int,
        accessMode: AppAccessMode = .container,
        version: String? = nil,
        isSystemApp: Bool = false
    ) {
        self.id = domain
        self.bundleID = bundleID
        self.displayName = displayName
        self.fileCount = fileCount
        self.availableFileCount = availableFileCount
        self.accessMode = accessMode
        self.version = version
        self.isSystemApp = isSystemApp
    }
}
