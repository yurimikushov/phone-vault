import SwiftUI
import PhoneVaultCore

struct DeviceInspectorView: View {

    @Environment(BackupViewModel.self) private var vm

    var body: some View {
        Group {
            if let device = vm.selectedDevice {
                deviceInspector(device)
            } else {
                EmptyStateView(
                    icon: "iphone.slash",
                    title: "No Device Selected",
                    message: "Select a connected device to inspect its properties."
                )
            }
        }
        .frame(minWidth: 280)
        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 440)
    }

    private func deviceInspector(_ device: ConnectedDevice) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                        .overlay(Image(systemName: "iphone").font(.title3).foregroundStyle(.white))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text(device.marketingName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()

                Divider()

                // Properties
                SectionHeader(title: "Hardware & Connection")
                MetadataRow(label: "Model", value: device.marketingName)
                MetadataRow(label: "Identifier", value: device.productType)
                MetadataRow(label: "iOS Version", value: device.productVersion.isEmpty ? "Unknown" : device.productVersion)
                MetadataRow(label: "Transport", value: device.connectionType)
                MetadataRow(label: "usbmuxd ID", value: "\(device.deviceID)")
                MetadataRow(label: "UDID", value: device.id)

                Divider()

                SectionHeader(title: "Status")
                HStack(spacing: 8) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("Device Connected via USB")
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
