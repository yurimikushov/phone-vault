import Foundation
import SQLite3

/// Read-only SQLite inspector. Opens databases in read-only mode and never modifies them.
public final class SQLiteInspector: Sendable {

    public init() {}

    /// Open the database at `url` and return schema information for all tables and views.
    /// Throws if the file cannot be opened or is not a valid SQLite database.
    public func schema(at url: URL) throws -> [SQLiteTableInfo] {
        let db = try openReadOnly(url: url)
        defer { sqlite3_close(db) }
        return try listTables(db: db, dbURL: url)
    }

    /// Fetch a page of rows from a table.
    ///
    /// - Parameters:
    ///   - url: Path to the SQLite database.
    ///   - tableName: Table or view name (validated against the schema before use).
    ///   - page: Zero-based page index.
    ///   - pageSize: Number of rows per page (capped at 500).
    public func fetchPage(
        at url: URL,
        tableName: String,
        page: Int,
        pageSize: Int = 200
    ) throws -> PreviewResult {
        let db = try openReadOnly(url: url)
        defer { sqlite3_close(db) }

        let safePageSize = min(max(pageSize, 1), 500)
        let offset = page * safePageSize

        // Validate the table name by checking it exists in sqlite_master.
        // This prevents SQL injection from malicious table names stored in the DB.
        let tables = try listTables(db: db, dbURL: url)
        guard tables.contains(where: { $0.name == tableName }) else {
            return .error("Table '\(tableName)' not found in the database.")
        }

        // Use parameterised LIMIT/OFFSET. The table name is validated above, not user-supplied.
        let quotedName = "\"" + tableName.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        let sql = "SELECT * FROM \(quotedName) LIMIT \(safePageSize + 1) OFFSET \(offset)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            return .error("Query failed: \(msg)")
        }
        defer { sqlite3_finalize(stmt) }

        let colCount = Int(sqlite3_column_count(stmt))
        var columns: [String] = []
        for i in 0 ..< colCount {
            let name = sqlite3_column_name(stmt, Int32(i)).map { String(cString: $0) } ?? "col\(i)"
            columns.append(name)
        }

        var rows: [[SQLiteValue]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [SQLiteValue] = []
            for i in 0 ..< colCount {
                row.append(decodeColumn(stmt: stmt, col: Int32(i)))
            }
            rows.append(row)
        }

        let hasMore = rows.count > safePageSize
        if hasMore { rows.removeLast() }

        return .sqliteTablePage(
            table: tableName,
            columns: columns,
            rows: rows,
            page: page,
            hasMore: hasMore
        )
    }

    // MARK: - Helpers

    private func openReadOnly(url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(url.path, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            throw BackupReaderError.manifestQueryFailed("Cannot open \(url.lastPathComponent): \(msg)")
        }
        return db
    }

    private func listTables(db: OpaquePointer, dbURL: URL) throws -> [SQLiteTableInfo] {
        let sql = """
            SELECT name, type, sql
            FROM sqlite_master
            WHERE type IN ('table','view')
            ORDER BY name
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw BackupReaderError.manifestQueryFailed(msg)
        }
        defer { sqlite3_finalize(stmt) }

        var tables: [SQLiteTableInfo] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let nameCStr = sqlite3_column_text(stmt, 0),
                let typeCStr = sqlite3_column_text(stmt, 1)
            else { continue }
            let name    = String(cString: nameCStr)
            let type    = String(cString: typeCStr)
            let schema  = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let isView  = type == "view"
            let rowCount = isView ? nil : countRows(db: db, tableName: name)
            tables.append(SQLiteTableInfo(name: name, isView: isView, rowCount: rowCount, schema: schema))
        }
        return tables
    }

    private func countRows(db: OpaquePointer, tableName: String) -> Int? {
        let quoted = "\"" + tableName.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        let sql = "SELECT COUNT(*) FROM \(quoted)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func decodeColumn(stmt: OpaquePointer, col: Int32) -> SQLiteValue {
        switch sqlite3_column_type(stmt, col) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(stmt, col))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(stmt, col))
        case SQLITE_TEXT:
            return .text(String(cString: sqlite3_column_text(stmt, col)))
        case SQLITE_BLOB:
            let ptr = sqlite3_column_blob(stmt, col)
            let len = Int(sqlite3_column_bytes(stmt, col))
            if let ptr {
                return .blob(Data(bytes: ptr, count: len))
            }
            return .blob(Data())
        case SQLITE_NULL:
            return .null
        default:
            return .null
        }
    }
}
