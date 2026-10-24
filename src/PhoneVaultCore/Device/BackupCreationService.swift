import Foundation

/// Service for managing backup creation via device tooling or guiding the user through Finder backups.
public final class BackupCreationService: Sendable {

    public static let shared = BackupCreationService()

    public init() {}

    /// Known locations where idevicebackup2 might be installed.
    private static let candidatePaths = [
        "/opt/homebrew/bin/idevicebackup2",
        "/usr/local/bin/idevicebackup2",
        "/usr/bin/idevicebackup2"
    ]

    /// Returns the path to `idevicebackup2` if installed on the system.
    public var idevicebackupPath: String? {
        let fm = FileManager.default
        for path in Self.candidatePaths {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Whether an automated backup utility is available.
    public var canCreateBackupDirectly: Bool {
        idevicebackupPath != nil
    }

    /// Runs `idevicebackup2 backup --full <destination>` for a specific device UDID.
    public func createBackup(
        udid: String,
        destinationURL: URL,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws {
        guard let tool = idevicebackupPath else {
            throw BackupReaderError.manifestQueryFailed("idevicebackup2 is not installed.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["--udid", udid, "backup", "--full", destinationURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let fileHandle = pipe.fileHandleForReading
        var collectedOutput: [String] = []

        try process.run()

        // Read output asynchronously
        for try await line in fileHandle.bytes.lines {
            collectedOutput.append(line)
            onOutput(line)
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            // Check for specific error signatures
            let fullLog = collectedOutput.joined(separator: "\n")
            if fullLog.contains("ErrorCode 105") || fullLog.contains("Insufficient free disk space") {
                throw BackupReaderError.manifestQueryFailed("Insufficient free disk space on your Mac to back up your iPhone. Free up more space or select an external drive.")
            } else if fullLog.contains("Waiting for passcode") {
                throw BackupReaderError.manifestQueryFailed("Passcode was not entered on iPhone. Unlock your iPhone and enter your passcode.")
            } else if let errorLine = collectedOutput.last(where: { $0.contains("Error") || $0.contains("ERROR") }) {
                throw BackupReaderError.manifestQueryFailed(errorLine)
            } else {
                throw BackupReaderError.manifestQueryFailed("Backup tool exited with code \(process.terminationStatus)")
            }
        }
    }
}
