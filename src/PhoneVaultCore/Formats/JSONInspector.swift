import Foundation

/// Reads and formats a JSON file for display.
public final class JSONInspector: Sendable {

    public init() {}

    /// Load and pretty-print JSON from a file URL.
    public func read(url: URL) throws -> PreviewResult {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try format(data: data)
    }

    public func format(data: Data) throws -> PreviewResult {
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let prettyData = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        let text = String(decoding: prettyData, as: UTF8.self)
        return .json(formatted: text)
    }
}
