import Foundation

/// Monitors connected iOS devices via the native macOS usbmuxd daemon (`/var/run/usbmuxd`).
///
/// Communicates directly using the Apple plist protocol over UNIX domain sockets.
/// Requires no external tools or libraries to discover connected devices.
public final class DeviceMonitor: Sendable {

    public static let shared = DeviceMonitor()

    private let socketPath: String

    public init(socketPath: String = "/var/run/usbmuxd") {
        self.socketPath = socketPath
    }

    // MARK: - Query connected devices

    /// Queries usbmuxd for all currently connected iOS devices.
    public func fetchConnectedDevices() async -> [ConnectedDevice] {
        await Task.detached(priority: .userInitiated) { [self] in
            return self.queryDevicesSync()
        }.value
    }

    private func queryDevicesSync() -> [ConnectedDevice] {
        guard FileManager.default.fileExists(atPath: socketPath) else {
            return []
        }

        guard let fd = connectSocket() else {
            return []
        }
        defer { close(fd) }

        // Send ListDevices request
        let listMsg: [String: Any] = [
            "MessageType": "ListDevices",
            "ClientVersionString": "PhoneVault",
            "ProgName": "PhoneVault"
        ]

        guard let payload = try? PropertyListSerialization.data(fromPropertyList: listMsg, format: .xml, options: 0),
              sendUSBMuxPacket(fd: fd, tag: 1, payload: payload),
              let respData = readUSBMuxPacket(fd: fd) else {
            return []
        }

        guard let respDict = (try? PropertyListSerialization.propertyList(from: respData, format: nil)) as? [String: Any],
              let deviceList = respDict["DeviceList"] as? [[String: Any]] else {
            return []
        }

        let candidates = Self.deduplicateDeviceEntries(deviceList)
        var results: [ConnectedDevice] = []

        for candidate in candidates {
            // Query lockdownd for richer metadata
            let lockdownInfo = queryLockdown(deviceID: candidate.devID)

            let name = lockdownInfo?.name ?? "iPhone"
            let productType = lockdownInfo?.productType ?? "iPhone"
            let version = lockdownInfo?.productVersion ?? "Unknown"

            let device = ConnectedDevice(
                id: candidate.serial,
                deviceID: candidate.devID,
                name: name,
                productType: productType,
                productVersion: version,
                connectionType: candidate.connType
            )
            results.append(device)
        }

        return results
    }

    public struct DeviceEntryCandidate: Equatable, Sendable {
        public let devID: Int
        public let serial: String
        public let connType: String

        public init(devID: Int, serial: String, connType: String) {
            self.devID = devID
            self.serial = serial
            self.connType = connType
        }
    }

    /// Deduplicates raw usbmuxd device entries by SerialNumber (UDID), strictly preferring "USB" over "Network".
    public static func deduplicateDeviceEntries(_ entries: [[String: Any]]) -> [DeviceEntryCandidate] {
        var preferredBySerial: [String: DeviceEntryCandidate] = [:]
        var serialOrder: [String] = []

        for entry in entries {
            guard let props = entry["Properties"] as? [String: Any] ?? (entry as [String: Any]?) else { continue }
            let devID = (props["DeviceID"] as? Int) ?? (entry["DeviceID"] as? Int) ?? 0
            let serial = (props["SerialNumber"] as? String) ?? (entry["SerialNumber"] as? String) ?? "Unknown"
            let connType = (props["ConnectionType"] as? String) ?? "USB"

            let candidate = DeviceEntryCandidate(devID: devID, serial: serial, connType: connType)
            let key = (serial.isEmpty || serial == "Unknown") ? "dev_\(devID)" : serial

            if let existing = preferredBySerial[key] {
                // Prefer USB over non-USB (e.g. Network/Wi-Fi)
                if existing.connType.caseInsensitiveCompare("USB") != .orderedSame &&
                   connType.caseInsensitiveCompare("USB") == .orderedSame {
                    preferredBySerial[key] = candidate
                }
            } else {
                preferredBySerial[key] = candidate
                serialOrder.append(key)
            }
        }

        return serialOrder.compactMap { preferredBySerial[$0] }
    }

    // MARK: - Lockdownd queries

    private struct LockdownInfo {
        let name: String
        let productType: String
        let productVersion: String
    }

    private func queryLockdown(deviceID: Int) -> LockdownInfo? {
        guard deviceID > 0 else { return nil }
        guard let fd = connectSocket() else { return nil }
        defer { close(fd) }

        // usbmuxd port 62078 in network byte order
        let portNBO = Int(((62078 & 0xff) << 8) | ((62078 >> 8) & 0xff))
        let connMsg: [String: Any] = [
            "MessageType": "Connect",
            "ClientVersionString": "PhoneVault",
            "ProgName": "PhoneVault",
            "DeviceID": deviceID,
            "PortNumber": portNBO
        ]

        guard let payload = try? PropertyListSerialization.data(fromPropertyList: connMsg, format: .xml, options: 0),
              sendUSBMuxPacket(fd: fd, tag: 2, payload: payload),
              let respData = readUSBMuxPacket(fd: fd) else {
            return nil
        }

        guard let respDict = (try? PropertyListSerialization.propertyList(from: respData, format: nil)) as? [String: Any],
              let number = respDict["Number"] as? Int, number == 0 else {
            return nil
        }

        // Lockdownd connection established! Send GetValue request.
        let valMsg: [String: Any] = [
            "Request": "GetValue",
            "Label": "PhoneVault"
        ]
        guard let valData = try? PropertyListSerialization.data(fromPropertyList: valMsg, format: .xml, options: 0) else {
            return nil
        }

        var lenBig = CFSwapInt32HostToBig(UInt32(valData.count))
        guard writeAll(fd: fd, buffer: &lenBig, length: 4) else { return nil }
        guard valData.withUnsafeBytes({ ptr in
            guard let base = ptr.baseAddress else { return false }
            return writeAll(fd: fd, buffer: base, length: valData.count)
        }) else { return nil }

        // Read 4-byte big-endian response length
        var respLenBig: UInt32 = 0
        guard readAll(fd: fd, buffer: &respLenBig, length: 4) else { return nil }
        let respLen = Int(CFSwapInt32BigToHost(respLenBig))
        guard respLen > 0 && respLen < 2_000_000 else { return nil }

        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: respLen)
        defer { buf.deallocate() }
        guard readAll(fd: fd, buffer: buf, length: respLen) else { return nil }

        let responseData = Data(bytes: buf, count: respLen)
        guard let responseDict = (try? PropertyListSerialization.propertyList(from: responseData, format: nil)) as? [String: Any],
              let value = responseDict["Value"] as? [String: Any] else {
            return nil
        }

        let name = (value["DeviceName"] as? String) ?? "iPhone"
        let pType = (value["ProductType"] as? String) ?? "iPhone"
        let pVer = (value["ProductVersion"] as? String) ?? ""

        return LockdownInfo(name: name, productType: pType, productVersion: pVer)
    }

    // MARK: - Low-level socket helpers

    private func connectSocket() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        // 3-second timeout for read & write to avoid hanging
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { cstr in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
                _ = strncpy(ptr, cstr, 104)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, addrLen)
            }
        }

        guard connected == 0 else {
            close(fd)
            return nil
        }

        return fd
    }

    private func sendUSBMuxPacket(fd: Int32, tag: UInt32, payload: Data) -> Bool {
        let totalLen = UInt32(16 + payload.count)
        var header: [UInt32] = [totalLen, 1, 8, tag] // length, version=1, request=8, tag
        guard writeAll(fd: fd, buffer: &header, length: 16) else { return false }
        return payload.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return false }
            return writeAll(fd: fd, buffer: base, length: payload.count)
        }
    }

    private func readUSBMuxPacket(fd: Int32) -> Data? {
        var header = [UInt32](repeating: 0, count: 4)
        guard readAll(fd: fd, buffer: &header, length: 16) else { return nil }
        let totalLen = Int(header[0])
        guard totalLen >= 16 && totalLen < 2_000_000 else { return nil }
        let payloadLen = totalLen - 16
        if payloadLen == 0 { return Data() }

        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: payloadLen)
        defer { buf.deallocate() }
        guard readAll(fd: fd, buffer: buf, length: payloadLen) else { return nil }
        return Data(bytes: buf, count: payloadLen)
    }

    private func writeAll(fd: Int32, buffer: UnsafeRawPointer, length: Int) -> Bool {
        var written = 0
        while written < length {
            let n = write(fd, buffer.advanced(by: written), length - written)
            if n <= 0 { return false }
            written += n
        }
        return true
    }

    private func readAll(fd: Int32, buffer: UnsafeMutableRawPointer, length: Int) -> Bool {
        var offset = 0
        while offset < length {
            let n = read(fd, buffer.advanced(by: offset), length - offset)
            if n <= 0 { return false }
            offset += n
        }
        return true
    }
}
