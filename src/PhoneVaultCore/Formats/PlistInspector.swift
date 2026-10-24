import Foundation

/// Converts a plist file or Data to a typed `PlistNode` tree for display.
public final class PlistInspector: Sendable {

    public init() {}

    public func read(url: URL) throws -> PlistNode {
        let data = try Data(contentsOf: url)
        return try decode(data: data)
    }

    public func decode(data: Data) throws -> PlistNode {
        let obj = try PropertyListSerialization.propertyList(from: data, format: nil)
        return convert(obj)
    }

    private func convert(_ obj: Any) -> PlistNode {
        switch obj {
        case let d as NSDictionary:
            let pairs = d.allKeys
                .compactMap { $0 as? String }
                .sorted()
                .map { key -> (key: String, value: PlistNode) in
                    (key: key, value: convert(d[key]!))
                }
            return .dictionary(pairs)
        case let a as NSArray:
            return .array(a.map { convert($0) })
        case let s as NSString:
            return .string(s as String)
        case let n as NSNumber:
            // NSNumber can be bool, int, or double — disambiguate using ObjC type encoding
            let encoding = String(cString: n.objCType)
            if encoding == "c" || encoding == "B" {
                return .bool(n.boolValue)
            }
            if n.doubleValue != Double(n.int64Value) {
                return .real(n.doubleValue)
            }
            return .integer(n.intValue)
        case let d as Date:
            return .date(d)
        case let data as Data:
            return .data(data)
        default:
            return .unknown
        }
    }
}

/// Formats a PlistNode as indented text for display.
public struct PlistFormatter {
    public init() {}

    public func format(_ node: PlistNode, indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch node {
        case .dictionary(let pairs):
            if pairs.isEmpty { return "{}" }
            let lines = pairs.map { "\(pad)  \($0.key): \(format($0.value, indent: indent + 1))" }
            return "{\n" + lines.joined(separator: "\n") + "\n\(pad)}"
        case .array(let items):
            if items.isEmpty { return "[]" }
            let lines = items.map { "\(pad)  \(format($0, indent: indent + 1))" }
            return "[\n" + lines.joined(separator: "\n") + "\n\(pad)]"
        case .string(let s): return "\"\(s)\""
        case .integer(let i): return "\(i)"
        case .real(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        case .date(let d): return ISO8601DateFormatter().string(from: d)
        case .data(let d): return "<Data \(d.count) bytes>"
        case .unknown: return "<unknown>"
        }
    }
}
