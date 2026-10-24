import Foundation

/// Top-level metadata about an iOS backup folder.
public struct BackupInfo: Identifiable, Sendable {
    public let id: UUID
    /// Absolute path to the backup folder on disk.
    public let backupURL: URL
    /// Device name as stored in the backup (e.g. "Yuri's iPhone").
    public let deviceName: String?
    /// iOS version string (e.g. "17.4").
    public let productVersion: String?
    /// Device model identifier (e.g. "iPhone15,3").
    public let productType: String?
    /// UDID of the source device.
    public let uniqueDeviceID: String?
    /// Date of the backup.
    public let date: Date?
    /// Whether the backup is encrypted.
    public let isEncrypted: Bool
    /// Total number of file records found in the manifest.
    public let totalFileCount: Int
    /// Number of file records whose physical payload exists on disk.
    public let availableFileCount: Int
    /// Number of distinct application domains found.
    public let appCount: Int
    /// Manifest version string.
    public let manifestVersion: Int?

    public init(
        id: UUID = .init(),
        backupURL: URL,
        deviceName: String?,
        productVersion: String?,
        productType: String?,
        uniqueDeviceID: String?,
        date: Date?,
        isEncrypted: Bool,
        totalFileCount: Int,
        availableFileCount: Int,
        appCount: Int,
        manifestVersion: Int?
    ) {
        self.id = id
        self.backupURL = backupURL
        self.deviceName = deviceName
        self.productVersion = productVersion
        self.productType = productType
        self.uniqueDeviceID = uniqueDeviceID
        self.date = date
        self.isEncrypted = isEncrypted
        self.totalFileCount = totalFileCount
        self.availableFileCount = availableFileCount
        self.appCount = appCount
        self.manifestVersion = manifestVersion
    }
}
