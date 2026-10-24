import Foundation
import AppKit
import PhoneVaultCore

/// Virtual item shown in the file browser — either a folder or a concrete backup file.
enum BrowserItem: Identifiable, Sendable {
    case directory(name: String, path: String, fileCount: Int, availableCount: Int)
    case file(BackupFile)

    var id: String {
        switch self {
        case .directory(_, let path, _, _): return "dir://\(path)"
        case .file(let f): return f.id
        }
    }

    // MARK: - Sort keys

    var sortName: String {
        switch self {
        case .directory(let name, _, _, _): return name
        case .file(let f): return f.filename
        }
    }

    var sortPath: String {
        switch self {
        case .directory(_, let path, _, _): return path
        case .file(let f): return f.relativePath
        }
    }

    var sortSize: Int64 {
        switch self {
        case .directory: return -1          // dirs first when sorting by size asc
        case .file(let f): return f.fileSize ?? -1
        }
    }

    var sortDate: Date {
        switch self {
        case .directory: return .distantPast
        case .file(let f): return f.modificationDate ?? .distantPast
        }
    }

    var isDirectory: Bool {
        if case .directory = self { return true }
        return false
    }

    // MARK: - Virtual file-system builder

    /// Compute items visible at `directoryPath` from the given flat file list.
    /// If `search` is non-empty, returns a flat search result instead of a folder view.
    static func items(
        from files: [BackupFile],
        at directoryPath: String,
        matching search: String
    ) -> [BrowserItem] {

        if !search.isEmpty {
            return files
                .filter {
                    $0.filename.localizedCaseInsensitiveContains(search) ||
                    $0.relativePath.localizedCaseInsensitiveContains(search)
                }
                .map { .file($0) }
        }

        let prefix = directoryPath.isEmpty ? "" : directoryPath + "/"
        var subdirs: [String: (total: Int, available: Int)] = [:]
        var fileItems: [BackupFile] = []

        for file in files {
            let path = file.relativePath
            guard path.hasPrefix(prefix) || prefix.isEmpty else { continue }
            let rest: String
            if prefix.isEmpty {
                rest = path
            } else {
                guard path.count > prefix.count else { continue }
                rest = String(path.dropFirst(prefix.count))
            }

            if let slashIdx = rest.firstIndex(of: "/") {
                let subdirName = String(rest[..<slashIdx])
                guard !subdirName.isEmpty else { continue }
                var counts = subdirs[subdirName] ?? (0, 0)
                counts.total += 1
                if file.isAvailable { counts.available += 1 }
                subdirs[subdirName] = counts
            } else if !rest.isEmpty {
                if file.fileType == .directory {
                    var counts = subdirs[rest] ?? (0, 0)
                    counts.total += 1
                    if file.isAvailable { counts.available += 1 }
                    subdirs[rest] = counts
                } else {
                    fileItems.append(file)
                }
            }
        }

        let dirItems: [BrowserItem] = subdirs.sorted(by: { $0.key < $1.key }).map { name, counts in
            let fullPath = directoryPath.isEmpty ? name : "\(directoryPath)/\(name)"
            return .directory(name: name, path: fullPath, fileCount: counts.total, availableCount: counts.available)
        }

        return dirItems + fileItems.map { .file($0) }
    }
}
