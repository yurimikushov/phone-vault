import Foundation

/// Service for inspecting and downloading iOS app containers and documents live over USB without full device backups.
public final class LiveDeviceService: Sendable {

    public static let shared = LiveDeviceService()

    public init() {}

    // MARK: - Tool Resolution

    private static let candidatePrefixes = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin"
    ]

    public var ideviceinstallerPath: String? {
        resolveTool(name: "ideviceinstaller")
    }

    public var afcclientPath: String? {
        resolveTool(name: "afcclient")
    }

    /// Whether the required tooling for direct USB app inspection is installed.
    public var isToolingAvailable: Bool {
        ideviceinstallerPath != nil && afcclientPath != nil
    }

    private func resolveTool(name: String) -> String? {
        let fm = FileManager.default
        for prefix in Self.candidatePrefixes {
            let path = "\(prefix)/\(name)"
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    // MARK: - App Listing

    /// Lists installed applications on the device via `ideviceinstaller list --xml`.
    /// - Parameters:
    ///   - udid: Target device identifier.
    ///   - includeSystemApps: If false (default), only user-installed apps are queried, which is significantly faster.
    public func fetchInstalledApps(udid: String, includeSystemApps: Bool = false) async throws -> [AppRecord] {
        guard let tool = ideviceinstallerPath else {
            throw LiveDeviceError.toolingNotFound("ideviceinstaller")
        }

        let typeFlag = includeSystemApps ? "--all" : "--user"
        let output = try await execute(
            executable: tool,
            arguments: ["-u", udid, "list", typeFlag, "--xml"],
            timeout: 30
        )

        guard let data = output.data(using: .utf8) else {
            return []
        }

        return try LiveDeviceParser.parseAppsPlist(data: data)
    }

    /// Tests the actual container or documents access level for a specific application.
    public func resolveAccessMode(udid: String, bundleID: String, hint: AppAccessMode) async -> AppAccessMode {
        guard let afc = afcclientPath else { return .restricted }

        // 1. If hinted as container, or unknown/not restricted, test container access first
        if hint == .container || hint == .unknown {
            if let res = try? await execute(executable: afc, arguments: ["-u", udid, "--container", bundleID, "--", "ls", "/"], timeout: 4),
               !res.contains("Error:") && !res.contains("ERROR:") {
                return .container
            }
        }

        // 2. Test documents access (/Documents or Documents)
        if let res = try? await execute(executable: afc, arguments: ["-u", udid, "--documents", bundleID, "--", "ls", "/Documents"], timeout: 4),
           !res.contains("Error:") && !res.contains("ERROR:") {
            return .documents
        }

        if let res = try? await execute(executable: afc, arguments: ["-u", udid, "--documents", bundleID, "--", "ls", "Documents"], timeout: 4),
           !res.contains("Error:") && !res.contains("ERROR:") {
            return .documents
        }

        return .restricted
    }

    /// Normalizes remote paths for AFC access modes.
    /// In `.documents` mode, files reside inside `/Documents`, whereas in `.container` mode, root is `/`.
    public func normalizeRemotePath(path: String, accessMode: AppAccessMode) -> String {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if accessMode == .documents {
            if clean.isEmpty || clean.lowercased() == "documents" {
                return "/Documents"
            }
            if clean.lowercased().hasPrefix("documents/") {
                return "/" + clean
            }
            return "/Documents/" + clean
        } else {
            return clean.isEmpty ? "/" : "/\(clean)"
        }
    }

    // MARK: - Directory Browsing

    /// Lists a specific directory within the app container or documents folder.
    public func listDirectory(
        udid: String,
        bundleID: String,
        accessMode: AppAccessMode,
        remotePath: String
    ) async throws -> [LiveFileItem] {
        guard let afc = afcclientPath else {
            throw LiveDeviceError.toolingNotFound("afcclient")
        }

        let flag = accessMode == .documents ? "--documents" : "--container"
        let pathArg = normalizeRemotePath(path: remotePath, accessMode: accessMode)
        let effectiveBase = remotePath

        let output = try await execute(
            executable: afc,
            arguments: ["-u", udid, flag, bundleID, "--", "ls", "-l", pathArg],
            timeout: 10
        )

        return LiveDeviceParser.parseAFCListOutput(output, basePath: effectiveBase)
    }

    /// Traverses directory tree up to `maxDepth` and returns `BackupFile` models for UI display.
    public func fetchAppFiles(
        udid: String,
        bundleID: String,
        accessMode: AppAccessMode,
        maxDepth: Int = 4
    ) async throws -> [BackupFile] {
        var collectedFiles: [BackupFile] = []
        let initialRoot = accessMode == .documents ? "Documents" : ""
        var queue: [(path: String, depth: Int)] = [(initialRoot, 0)]
        var visited = Set<String>()

        while !queue.isEmpty {
            let (currentDir, depth) = queue.removeFirst()
            if visited.contains(currentDir) { continue }
            visited.insert(currentDir)

            let items = (try? await listDirectory(udid: udid, bundleID: bundleID, accessMode: accessMode, remotePath: currentDir)) ?? []

            for item in items {
                if item.isDirectory {
                    if depth + 1 < maxDepth {
                        queue.append((path: item.remotePath, depth: depth + 1))
                    }
                } else {
                    collectedFiles.append(item.toBackupFile(bundleID: bundleID))
                }
            }
        }

        return collectedFiles
    }

    // MARK: - File Download & Inspection

    /// Downloads a remote file to a local temporary cache path, fetching companion WAL/SHM files for SQLite databases.
    public func downloadFile(
        udid: String,
        bundleID: String,
        accessMode: AppAccessMode,
        remotePath: String
    ) async throws -> URL {
        guard let afc = afcclientPath else {
            throw LiveDeviceError.toolingNotFound("afcclient")
        }

        let flag = accessMode == .documents ? "--documents" : "--container"
        let cleanRemote = normalizeRemotePath(path: remotePath, accessMode: accessMode)
        let relLocalPath = cleanRemote.hasPrefix("/") ? String(cleanRemote.dropFirst()) : cleanRemote

        // Prepare local cache directory
        let cacheBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhoneVaultLive", isDirectory: true)
            .appendingPathComponent(udid, isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)

        let localTarget = cacheBase.appendingPathComponent(relLocalPath)
        let parentDir = localTarget.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // Remove old cache copy if present
        try? FileManager.default.removeItem(at: localTarget)

        _ = try await execute(
            executable: afc,
            arguments: ["-u", udid, flag, bundleID, "--", "get", cleanRemote, localTarget.path],
            timeout: 30
        )

        guard FileManager.default.fileExists(atPath: localTarget.path) else {
            throw LiveDeviceError.fileNotFound(remotePath)
        }

        // If SQLite, opportunistically fetch WAL and SHM companions
        let ext = localTarget.pathExtension.lowercased()
        if ext == "sqlite" || ext == "db" || ext == "sqlite3" {
            for suffix in ["-wal", "-shm"] {
                let companionRemote = cleanRemote + suffix
                let companionLocal = localTarget.path + suffix
                _ = try? await execute(
                    executable: afc,
                    arguments: ["-u", udid, flag, bundleID, "--", "get", companionRemote, companionLocal],
                    timeout: 5
                )
            }
        }

        return localTarget
    }

    /// Exports a remote file or entire directory to the specified destination URL.
    public func exportRemote(
        udid: String,
        bundleID: String,
        accessMode: AppAccessMode,
        remotePath: String,
        destinationURL: URL
    ) async throws {
        guard let afc = afcclientPath else {
            throw LiveDeviceError.toolingNotFound("afcclient")
        }

        let flag = accessMode == .documents ? "--documents" : "--container"
        let cleanRemote = normalizeRemotePath(path: remotePath, accessMode: accessMode)

        _ = try await execute(
            executable: afc,
            arguments: ["-u", udid, flag, bundleID, "--", "get", "-rf", cleanRemote, destinationURL.path],
            timeout: 60
        )
    }

    // MARK: - Process Execution

    private func execute(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 30
    ) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            // Ensure Homebrew and system PATH are available to sub-processes
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            final class LockedBox<T>: @unchecked Sendable {
                private let lock = NSLock()
                private var _val: T
                init(_ val: T) { self._val = val }
                var value: T {
                    get { lock.withLock { _val } }
                    set { lock.withLock { _val = newValue } }
                }
            }

            let didTimeout = LockedBox<Bool>(false)
            let didResume = LockedBox<Bool>(false)
            let stdoutBox = LockedBox<Data>(Data())
            let stderrBox = LockedBox<Data>(Data())
            let ioGroup = DispatchGroup()

            // Concurrently drain stdout and stderr so pipe buffer capacity (64 KB) never blocks child process
            ioGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                stdoutBox.value = data
                ioGroup.leave()
            }

            ioGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                stderrBox.value = data
                ioGroup.leave()
            }

            do {
                try process.run()
            } catch {
                if !didResume.value {
                    didResume.value = true
                    continuation.resume(throwing: error)
                }
                return
            }

            // Timeout watchdog
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                if process.isRunning {
                    didTimeout.value = true
                    process.terminate()
                }
            }
            timer.resume()

            process.terminationHandler = { proc in
                timer.cancel()
                // Wait for background pipe readers to finish capturing output
                ioGroup.wait()

                let outData = stdoutBox.value
                let errData = stderrBox.value
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""

                guard !didResume.value else { return }
                didResume.value = true

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else if !outData.isEmpty, stdout.contains("</plist>"), (try? LiveDeviceParser.parseAppsPlist(data: outData)) != nil {
                    // Output contains a complete, valid XML plist despite non-zero exit code
                    continuation.resume(returning: stdout)
                } else if didTimeout.value {
                    continuation.resume(throwing: LiveDeviceError.commandFailed(
                        tool: (executable as NSString).lastPathComponent,
                        code: 15,
                        message: "Device communication timed out after \(Int(timeout))s. Ensure your iPhone is unlocked and trusted."
                    ))
                } else {
                    let errClean = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    let summary: String
                    if !errClean.isEmpty {
                        summary = String(errClean.prefix(300))
                    } else if stdout.contains("<plist") {
                        summary = "Process exited with code \(proc.terminationStatus) before completing XML payload."
                    } else {
                        summary = String(stdout.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    continuation.resume(throwing: LiveDeviceError.commandFailed(
                        tool: (executable as NSString).lastPathComponent,
                        code: proc.terminationStatus,
                        message: summary.isEmpty ? "Process exited with code \(proc.terminationStatus)" : summary
                    ))
                }
            }
        }
    }
}
