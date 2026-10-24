import Foundation

/// Parses device command output from `ideviceinstaller` and `afcclient`.
public enum LiveDeviceParser {

    private static let ansiRegex = try? NSRegularExpression(pattern: "\\x1B\\[[0-9;]*[a-zA-Z]")

    /// Strips ANSI terminal escape sequences (color codes, cursor controls) from command output.
    public static func stripAnsiCodes(_ text: String) -> String {
        guard let regex = ansiRegex else { return text }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    /// Parses the XML plist produced by `ideviceinstaller list --xml` into `[AppRecord]`.
    public static func parseAppsPlist(data: Data) throws -> [AppRecord] {
        guard !data.isEmpty else { return [] }

        let plistObj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let rawDicts: [[String: Any]]

        if let array = plistObj as? [[String: Any]] {
            rawDicts = array
        } else if let dict = plistObj as? [String: Any], let items = dict["DeviceList"] as? [[String: Any]] {
            rawDicts = items
        } else if let dict = plistObj as? [String: Any] {
            // Some versions return a dictionary keyed by BundleID
            rawDicts = dict.compactMap { key, val in
                if var sub = val as? [String: Any] {
                    if sub["CFBundleIdentifier"] == nil { sub["CFBundleIdentifier"] = key }
                    return sub
                }
                return ["CFBundleIdentifier": key]
            }
        } else {
            return []
        }

        var results: [AppRecord] = []

        for dict in rawDicts {
            guard let bundleID = (dict["CFBundleIdentifier"] as? String) ?? (dict["CFBundleExecutable"] as? String),
                  !bundleID.isEmpty else {
                continue
            }

            let name = (dict["CFBundleDisplayName"] as? String)
                ?? (dict["CFBundleName"] as? String)
                ?? (bundleID.split(separator: ".").last.map(String.init) ?? bundleID)

            let version = (dict["CFBundleShortVersionString"] as? String)
                ?? (dict["CFBundleVersion"] as? String)

            let fileSharingEnabled = (dict["UIFileSharingEnabled"] as? Bool == true)
                || ((dict["UIFileSharingEnabled"] as? Int) == 1)
                || (dict["LSSupportsOpeningDocumentsInPlace"] as? Bool == true)

            let signer = (dict["SignerIdentity"] as? String) ?? ""
            let isDeveloperSigned = signer.localizedCaseInsensitiveContains("Developer")
                || signer.localizedCaseInsensitiveContains("Development")
                || signer.localizedCaseInsensitiveContains("Xcode")

            let appType = (dict["ApplicationType"] as? String) ?? "User"
            let isSystem = appType.caseInsensitiveCompare("System") == .orderedSame

            let mode: AppAccessMode
            if isDeveloperSigned {
                mode = .container
            } else if fileSharingEnabled {
                mode = .documents
            } else if isSystem {
                mode = .restricted
            } else {
                mode = .unknown
            }

            let record = AppRecord(
                domain: bundleID,
                bundleID: bundleID,
                displayName: name,
                fileCount: 0,
                availableFileCount: 0,
                accessMode: mode,
                version: version,
                isSystemApp: isSystem
            )
            results.append(record)
        }

        // Sort user apps first, then alphabetically by display name
        return results.sorted { a, b in
            if a.isSystemApp != b.isSystemApp {
                return !a.isSystemApp
            }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    /// Parses directory listing output from `afcclient ls -l <path>` into `[LiveFileItem]`.
    public static func parseAFCListOutput(_ rawOutput: String, basePath: String) -> [LiveFileItem] {
        let clean = stripAnsiCodes(rawOutput)
        let lines = clean.components(separatedBy: .newlines)

        var items: [LiveFileItem] = []
        let normalizedBase = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "d MMM yyyy HH:mm:ss"

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Filter out afcclient header/error/prompt lines
            if trimmed.hasPrefix("Error:") || trimmed.hasPrefix("ERROR:") || trimmed.hasPrefix("afcclient") {
                continue
            }

            // afcclient ls -l formats:
            // Format A (POSIX 10+ tokens with nlink, user, group):
            // drwxr-xr-x    3 mobile mobile         96 21 Sep 2024 23:21:49 RTPhotos
            // -rw-r--r--    1 mobile mobile   15106048 24 Oct 2026 11:58:15 MEDB.db
            // Format B (8+ tokens with single user):
            // drwxr-xr-x mobile         160 24 Oct 2026 14:00:00 Documents
            // -rw-r--r-- mobile      122880 24 Oct 2026 14:02:15 AppData.sqlite
            let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

            guard let first = tokens.first,
                  (first.starts(with: "d") || first.starts(with: "-") || first.starts(with: "l")) else {
                if tokens.count == 1 {
                    let filename = tokens[0]
                    guard filename != ".", filename != ".." else { continue }
                    let remotePath = normalizedBase.isEmpty ? filename : "\(normalizedBase)/\(filename)"
                    items.append(LiveFileItem(
                        name: filename,
                        remotePath: remotePath,
                        isDirectory: false,
                        size: nil,
                        modificationDate: nil
                    ))
                }
                continue
            }

            let isDir = first.starts(with: "d")
            let size: Int64?
            let date: Date?
            let filename: String

            if tokens.count >= 10,
               Int64(tokens[1]) != nil,
               let parsedSize = Int64(tokens[4]) {
                // Format A (10+ tokens)
                size = parsedSize
                let dateString = "\(tokens[5]) \(tokens[6]) \(tokens[7]) \(tokens[8])"
                date = dateFormatter.date(from: dateString)
                filename = tokens.dropFirst(9).joined(separator: " ")
            } else if tokens.count >= 8,
                      let parsedSize = Int64(tokens[2]) {
                // Format B (8+ tokens)
                size = parsedSize
                let dateString = "\(tokens[3]) \(tokens[4]) \(tokens[5]) \(tokens[6])"
                date = dateFormatter.date(from: dateString)
                filename = tokens.dropFirst(7).joined(separator: " ")
            } else {
                continue
            }

            guard !filename.isEmpty, filename != ".", filename != ".." else { continue }

            let remotePath = normalizedBase.isEmpty ? filename : "\(normalizedBase)/\(filename)"
            items.append(LiveFileItem(
                name: filename,
                remotePath: remotePath,
                isDirectory: isDir,
                size: isDir ? nil : size,
                modificationDate: date
            ))
        }

        return items
    }
}
