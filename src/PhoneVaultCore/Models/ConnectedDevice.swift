import Foundation

/// Represents an iOS device connected via USB or Wi-Fi.
public struct ConnectedDevice: Identifiable, Hashable, Sendable {

    /// Device UDID (e.g. "00008110-001E21D90E88201E").
    public let id: String

    /// Transient usbmuxd integer ID.
    public let deviceID: Int

    /// User-assigned device name (e.g. "Yuri's iPhone" or "🦄").
    public let name: String

    /// Hardware identifier (e.g. "iPhone14,7").
    public let productType: String

    /// Human-friendly model name (e.g. "iPhone 14 Plus").
    public let marketingName: String

    /// iOS version string (e.g. "17.4.1").
    public let productVersion: String

    /// Connection transport: "USB" or "WiFi".
    public let connectionType: String

    public init(
        id: String,
        deviceID: Int,
        name: String,
        productType: String,
        marketingName: String? = nil,
        productVersion: String,
        connectionType: String = "USB"
    ) {
        self.id = id
        self.deviceID = deviceID
        self.name = name
        self.productType = productType
        self.marketingName = marketingName ?? Self.friendlyModel(for: productType)
        self.productVersion = productVersion
        self.connectionType = connectionType
    }

    /// Translates raw Apple hardware strings (e.g. "iPhone14,7") into user-friendly names.
    public static func friendlyModel(for raw: String) -> String {
        let mapping: [String: String] = [
            // iPhone 16 series
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",

            // iPhone 15 series
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",

            // iPhone 14 series
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",

            // iPhone 13 series
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",

            // iPhone 12 series
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",

            // iPhone 11 series
            "iPhone12,1": "iPhone 11",
            "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max",

            // iPhone SE series
            "iPhone14,6": "iPhone SE (3rd gen)",
            "iPhone12,8": "iPhone SE (2nd gen)",

            // iPads (common)
            "iPad13,18": "iPad (10th gen)",
            "iPad13,19": "iPad (10th gen)",
            "iPad14,3": "iPad Pro 11-inch (4th gen)",
            "iPad14,4": "iPad Pro 11-inch (4th gen)",
            "iPad14,5": "iPad Pro 12.9-inch (6th gen)",
            "iPad14,6": "iPad Pro 12.9-inch (6th gen)",
            "iPad16,3": "iPad Pro 11-inch (M4)",
            "iPad16,4": "iPad Pro 11-inch (M4)",
            "iPad16,5": "iPad Pro 13-inch (M4)",
            "iPad16,6": "iPad Pro 13-inch (M4)"
        ]

        if let friendly = mapping[raw] {
            return friendly
        }
        if raw.hasPrefix("iPhone") {
            return "iPhone (\(raw))"
        }
        if raw.hasPrefix("iPad") {
            return "iPad (\(raw))"
        }
        return raw.isEmpty ? "iOS Device" : raw
    }
}
