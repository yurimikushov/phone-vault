import SwiftUI
import PhoneVaultCore

struct PlistPreviewView: View {

    let root: PlistNode

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PlistNodeRow(key: "root", node: root, depth: 0, isExpanded: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 400)
    }
}

// MARK: - Plist node row (recursive outline)

private struct PlistNodeRow: View {

    let key: String
    let node: PlistNode
    let depth: Int
    @State private var expanded: Bool

    init(key: String, node: PlistNode, depth: Int, isExpanded: Bool = false) {
        self.key = key
        self.node = node
        self.depth = depth
        self._expanded = State(initialValue: isExpanded || depth == 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Indentation
                Color.clear.frame(width: CGFloat(depth) * 14)

                if hasChildren {
                    Button {
                        expanded.toggle()
                    } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 14)
                }

                // Key
                Text(key)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.indigo)
                    .lineLimit(1)

                Text(" : ")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                // Value or type label
                Text(inlineLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture { if hasChildren { expanded.toggle() } }

            // Children
            if expanded, let children = childRows {
                ForEach(children, id: \.id) { child in
                    PlistNodeRow(key: child.key, node: child.node, depth: depth + 1)
                }
            }
        }
    }

    // MARK: - Helpers

    private var hasChildren: Bool {
        switch node {
        case .dictionary(let p): return !p.isEmpty
        case .array(let a): return !a.isEmpty
        default: return false
        }
    }

    private var childRows: [PlistRowItem]? {
        switch node {
        case .dictionary(let pairs):
            return pairs.map { PlistRowItem(key: $0.key, node: $0.value) }
        case .array(let items):
            return items.enumerated().map { PlistRowItem(key: "[\($0.offset)]", node: $0.element) }
        default:
            return nil
        }
    }

    private var inlineLabel: String {
        switch node {
        case .dictionary(let p): return "{\(p.count) keys}"
        case .array(let a): return "[\(a.count) items]"
        case .string(let s): return "\"\(s)\""
        case .integer(let i): return "\(i)"
        case .real(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        case .date(let d): return d.formatted()
        case .data(let d): return "<\(d.count) bytes>"
        case .unknown: return "<unknown>"
        }
    }

    private var valueColor: Color {
        switch node {
        case .dictionary, .array: return .secondary
        case .string:  return .green
        case .integer, .real: return .blue
        case .bool:    return .orange
        case .date:    return .purple
        default:       return .gray
        }
    }
}

// MARK: - Helper wrapper

private struct PlistRowItem: Identifiable {
    let id = UUID()
    let key: String
    let node: PlistNode
}
