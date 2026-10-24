import Foundation

/// Reads text and log files up to a configurable byte limit.
public final class TextInspector: Sendable {

    /// Maximum bytes to read before truncating (default 512 KB).
    public let limit: Int

    public init(limit: Int = 512 * 1024) {
        self.limit = limit
    }

    public func read(url: URL) throws -> PreviewResult {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attrs[.size] as? Int) ?? 0
        let truncated = fileSize > limit

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = (try handle.read(upToCount: limit)) ?? Data()

        // Attempt UTF-8, then fall back to latin-1 for log/binary text files
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? "<Unable to decode text>"

        return .text(content: text, truncated: truncated)
    }
}
