import SwiftUI
import PhoneVaultCore

// MARK: - SQLite schema view (table list)

struct SQLitePreviewView: View {

    let tables: [SQLiteTableInfo]
    let file: BackupFile
    @Environment(BackupViewModel.self) private var vm

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tables.isEmpty {
                Label("No tables found.", systemImage: "tray")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(tables) { table in
                    tableRow(table)
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    private func tableRow(_ table: SQLiteTableInfo) -> some View {
        Button {
            guard let url = file.physicalURL else { return }
            vm.loadSQLiteTablePage(url: url, table: table.name, page: 0)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: table.isView ? "eyes" : "tablecells")
                    .foregroundStyle(table.isView ? .teal : .indigo)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(table.name)
                        .font(.callout)
                        .foregroundStyle(.primary)
                    if let count = table.rowCount {
                        Text("\(count) rows")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - SQLite table page view (paginated rows)

struct SQLiteTablePageView: View {

    let tableName: String
    let columns: [String]
    let rows: [[SQLiteValue]]
    let page: Int
    let hasMore: Bool
    let file: BackupFile

    @Environment(BackupViewModel.self) private var vm

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Table header
            tableHeaderBar

            // Scrollable data grid
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                            HStack(spacing: 0) {
                                ForEach(Array(columns.enumerated()), id: \.offset) { colIdx, _ in
                                    cellView(value: colIdx < row.count ? row[colIdx] : .null)
                                }
                            }
                            .background(rowIdx.isMultiple(of: 2) ? Color.clear : Color(nsColor: .alternatingContentBackgroundColors[1]))
                        }
                    } header: {
                        columnHeaderRow
                    }
                }
            }
            .frame(maxHeight: 320)

            // Pagination bar
            paginationBar
        }
    }

    private var tableHeaderBar: some View {
        HStack {
            Button {
                guard let url = file.physicalURL else { return }
                let inspector = SQLiteInspector()
                Task {
                    let tables = try? inspector.schema(at: url)
                    await MainActor.run {
                        if let tables {
                            vm.previewResult = .sqliteSchema(tables: tables)
                        }
                    }
                }
            } label: {
                Label("Tables", systemImage: "chevron.left")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()
            Text(tableName)
                .font(.caption.bold())
            Spacer()
            Text("Page \(page + 1)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var columnHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.self) { col in
                Text(col)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 130, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.bar)
            }
        }
    }

    private func cellView(value: SQLiteValue) -> some View {
        Text(value.description)
            .font(.system(size: 11, design: .monospaced))
            .lineLimit(1)
            .frame(width: 130, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
    }

    private var paginationBar: some View {
        HStack {
            Button {
                guard let url = file.physicalURL, page > 0 else { return }
                vm.loadSQLiteTablePage(url: url, table: tableName, page: page - 1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .disabled(page == 0)

            Spacer()
            Text("\(rows.count) rows shown")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()

            Button {
                guard let url = file.physicalURL, hasMore else { return }
                vm.loadSQLiteTablePage(url: url, table: tableName, page: page + 1)
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(!hasMore)
        }
        .padding(8)
        .background(.bar)
    }
}
