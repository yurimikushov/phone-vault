import Foundation

/// All errors that can be thrown by the backup parsing layer.
public enum BackupReaderError: Error, LocalizedError, Sendable {
    case notADirectory(URL)
    case missingManifestDB(URL)
    case missingInfoPlist(URL)
    case unsupportedManifestVersion(Int)
    case encryptedBackup
    case manifestQueryFailed(String)
    case malformedManifestEntry(fileID: String, reason: String)
    case ioError(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .notADirectory(let url):
            return "The selected path is not a directory: \(url.path)"
        case .missingManifestDB(let url):
            return "Manifest.db not found in: \(url.path)"
        case .missingInfoPlist(let url):
            return "Info.plist not found in: \(url.path)"
        case .unsupportedManifestVersion(let v):
            return "Unsupported manifest version: \(v). Only version 10 (iOS 9+) is supported."
        case .encryptedBackup:
            return "This backup is encrypted. Encrypted backup support is not yet implemented."
        case .manifestQueryFailed(let msg):
            return "Failed to query Manifest.db: \(msg)"
        case .malformedManifestEntry(let id, let reason):
            return "Malformed manifest entry \(id): \(reason)"
        case .ioError(let msg):
            return "I/O error: \(msg)"
        }
    }
}

/// All errors that can be thrown by the export layer.
public enum ExportError: Error, LocalizedError, Sendable {
    case destinationNotADirectory(URL)
    case pathTraversalAttempt(String)
    case sourceUnavailable(BackupFile)
    case ioError(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .destinationNotADirectory(let url):
            return "Export destination is not a directory: \(url.path)"
        case .pathTraversalAttempt(let path):
            return "Rejected unsafe export path: \(path)"
        case .sourceUnavailable(let file):
            return "Source payload missing for: \(file.relativePath)"
        case .ioError(let msg):
            return "Export I/O error: \(msg)"
        }
    }
}

/// All errors that can be thrown by the live device communication layer.
public enum LiveDeviceError: Error, LocalizedError, Sendable {
    case toolingNotFound(String)
    case deviceNotConnected(String)
    case commandFailed(tool: String, code: Int32, message: String)
    case appAccessDenied(bundleID: String, reason: String)
    case fileNotFound(String)
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .toolingNotFound(let tool):
            return "Required tool '\(tool)' was not found. Please install libimobiledevice (brew install libimobiledevice ideviceinstaller)."
        case .deviceNotConnected(let udid):
            return "Device '\(udid)' is not currently reachable over USB."
        case .commandFailed(let tool, let code, let msg):
            return "\(tool) failed with code \(code): \(msg)"
        case .appAccessDenied(let bundleID, let reason):
            return "Access to '\(bundleID)' was denied: \(reason)"
        case .fileNotFound(let path):
            return "File not found on device at path: \(path)"
        case .parseError(let msg):
            return "Failed to parse device response: \(msg)"
        }
    }
}
