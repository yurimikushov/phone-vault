import Foundation

/// Handles safe file export operations.
///
/// - Never modifies source backup files.
/// - Validates all output paths stay within the user-chosen destination.
/// - Preserves relative path hierarchy by default.
/// - Reports per-file results instead of failing the whole batch.
public final class ExportService: Sendable {

    public init() {}

    /// Export files according to the given request. Returns an `ExportResult` summarising each file.
    public func export(_ request: ExportRequest) async throws -> ExportResult {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: request.destinationURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw ExportError.destinationNotADirectory(request.destinationURL)
        }

        let files: [BackupFile]
        switch request.selection {
        case .single(let f):   files = [f]
        case .multiple(let fs): files = fs
        case .folder(_, _, let fs): files = fs
        case .app(_, let fs): files = fs
        }

        var items: [ExportResult.Item] = []
        for file in files {
            let item = await exportOne(file: file, request: request, fm: fm)
            items.append(item)
        }
        return ExportResult(items: items)
    }

    // MARK: - Single file export

    private func exportOne(file: BackupFile, request: ExportRequest, fm: FileManager) async -> ExportResult.Item {
        guard let sourceURL = file.physicalURL, file.isAvailable else {
            return ExportResult.Item(file: file, destinationURL: nil, error: ExportError.sourceUnavailable(file))
        }

        do {
            let destURL = try destinationURL(
                for: file,
                request: request,
                fm: fm
            )

            // Create intermediate directories
            let destDir = destURL.deletingLastPathComponent()
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

            // Avoid overwriting: append a disambiguator
            let finalURL = availableURL(at: destURL, fm: fm)

            try fm.copyItem(at: sourceURL, to: finalURL)
            return ExportResult.Item(file: file, destinationURL: finalURL, error: nil)
        } catch {
            return ExportResult.Item(file: file, destinationURL: nil, error: error)
        }
    }

    // MARK: - Path computation

    private func destinationURL(for file: BackupFile, request: ExportRequest, fm: FileManager) throws -> URL {
        let baseURL = request.destinationURL.standardizedFileURL

        let relPath: String
        if request.preserveRelativePaths {
            relPath = file.relativePath
        } else {
            relPath = file.filename
        }

        // Prevent path traversal: reject any component that is ".."
        let components = relPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        for component in components {
            if component == ".." {
                throw ExportError.pathTraversalAttempt(relPath)
            }
        }

        var destURL = baseURL
        for component in components {
            destURL = destURL.appendingPathComponent(component)
        }

        // Double-check the resolved path is still under baseURL
        let destResolved  = destURL.standardizedFileURL.path
        let baseResolved  = baseURL.path
        guard destResolved.hasPrefix(baseResolved) else {
            throw ExportError.pathTraversalAttempt(relPath)
        }
        return destURL
    }

    /// If `url` already exists, append ` (N)` before the extension until a free path is found.
    private func availableURL(at url: URL, fm: FileManager) -> URL {
        guard fm.fileExists(atPath: url.path) else { return url }
        let ext  = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let dir  = url.deletingLastPathComponent()
        var count = 2
        while true {
            let candidate: URL
            if ext.isEmpty {
                candidate = dir.appendingPathComponent("\(base) (\(count))")
            } else {
                candidate = dir.appendingPathComponent("\(base) (\(count)).\(ext)")
            }
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            count += 1
        }
    }
}
