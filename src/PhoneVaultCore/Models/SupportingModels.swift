import Foundation

/// Metadata returned when inspecting a file.
public struct FileMetadata: Sendable {
    public let fileSize: Int64
    public let modificationDate: Date?
    public let creationDate: Date?
    public let fileKind: FileKind
    /// MIME type guessed from extension + magic bytes.
    public let mimeType: String?

    public init(
        fileSize: Int64,
        modificationDate: Date?,
        creationDate: Date?,
        fileKind: FileKind,
        mimeType: String?
    ) {
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.fileKind = fileKind
        self.mimeType = mimeType
    }
}

/// A request to export one or more files.
public struct ExportRequest: Sendable {
    public enum Selection: Sendable {
        case single(BackupFile)
        case multiple([BackupFile])
        case folder(domain: String, folderPath: String, files: [BackupFile])
        case app(AppRecord, files: [BackupFile])
    }
    public let selection: Selection
    /// Root destination directory chosen by the user.
    public let destinationURL: URL
    /// Whether to preserve the relative path hierarchy under the destination.
    public let preserveRelativePaths: Bool

    public init(selection: Selection, destinationURL: URL, preserveRelativePaths: Bool = true) {
        self.selection = selection
        self.destinationURL = destinationURL
        self.preserveRelativePaths = preserveRelativePaths
    }
}

/// Summary of a completed export operation.
public struct ExportResult: Sendable {
    public struct Item: Sendable {
        public let file: BackupFile
        public let destinationURL: URL?
        public let error: (any Error)?
        public var succeeded: Bool { error == nil && destinationURL != nil }

        public init(file: BackupFile, destinationURL: URL?, error: (any Error)? = nil) {
            self.file = file
            self.destinationURL = destinationURL
            self.error = error
        }
    }
    public let items: [Item]
    public var succeeded: [Item] { items.filter(\.succeeded) }
    public var failed: [Item] { items.filter { !$0.succeeded } }

    public init(items: [Item]) {
        self.items = items
    }
}

/// Result of a format-specific preview operation.
public enum PreviewResult: Sendable {
    case sqliteSchema(tables: [SQLiteTableInfo])
    case sqliteTablePage(table: String, columns: [String], rows: [[SQLiteValue]], page: Int, hasMore: Bool)
    case plist(root: PlistNode)
    case json(formatted: String)
    case text(content: String, truncated: Bool)
    case image(url: URL)
    case unsupported(mimeType: String?)
    case error(String)
}

/// Info about a single SQLite table.
public struct SQLiteTableInfo: Sendable, Identifiable {
    public let id: String  // table name
    public var name: String { id }
    public let isView: Bool
    public let rowCount: Int?
    public let schema: String

    public init(name: String, isView: Bool, rowCount: Int?, schema: String) {
        self.id = name
        self.isView = isView
        self.rowCount = rowCount
        self.schema = schema
    }
}

/// A value decoded from a SQLite column.
public enum SQLiteValue: Sendable, CustomStringConvertible {
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
    case null

    public var description: String {
        switch self {
        case .integer(let v): return String(v)
        case .real(let v): return String(v)
        case .text(let t): return t
        case .blob(let d): return "<BLOB \(d.count) bytes>"
        case .null: return "NULL"
        }
    }
}

/// Recursive plist node for tree display.
public indirect enum PlistNode: Sendable {
    case dictionary([(key: String, value: PlistNode)])
    case array([PlistNode])
    case string(String)
    case integer(Int)
    case real(Double)
    case bool(Bool)
    case date(Date)
    case data(Data)
    case unknown
}
