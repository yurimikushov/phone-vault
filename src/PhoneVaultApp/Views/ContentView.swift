import SwiftUI
import PhoneVaultCore

struct ContentView: View {

    @Environment(BackupViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        NavigationSplitView {
            SidebarView()
        } content: {
            if let device = vm.selectedDevice, vm.activeLiveApp == nil {
                DeviceDetailView(device: device)
            } else {
                FileBrowserView()
            }
        } detail: {
            if vm.selectedDevice != nil && vm.activeLiveApp == nil {
                DeviceInspectorView()
            } else {
                InspectorView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if vm.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    if vm.isLiveSession {
                        Button {
                            vm.refreshLiveApp()
                        } label: {
                            Label("Refresh Live Files", systemImage: "arrow.clockwise")
                        }
                        .help("Refresh live files and databases from device")
                    }

                    Button {
                        vm.presentOpenPanel()
                    } label: {
                        Label("Open Backup", systemImage: "folder.badge.plus")
                    }
                    .help("Open an iTunes / Finder backup folder")

                    if vm.backupInfo != nil || vm.isLiveSession {
                        Divider()
                        Button {
                            vm.exportSelected()
                        } label: {
                            Label("Export Selected", systemImage: "square.and.arrow.up")
                        }
                        .disabled(vm.selectedItemIDs.isEmpty || vm.isExporting)
                        .help("Export selected files to a folder")
                    }
                }
            }
        }
        .alert("Export Complete", isPresented: $vm.showExportSummary, presenting: vm.exportResult) { _ in
            Button("OK") { vm.exportResult = nil }
        } message: { result in
            let ok = result.succeeded.count
            let fail = result.failed.count
            if fail == 0 {
                Text("Successfully exported \(ok) \(ok == 1 ? "file" : "files").")
            } else {
                Text("Exported \(ok) files. \(fail) failed.")
            }
        }
        .alert("Error", isPresented: Binding(get: { vm.loadError != nil }, set: { if !$0 { vm.loadError = nil } })) {
            Button("OK") { vm.loadError = nil }
        } message: {
            Text(vm.loadError ?? "")
        }
    }
}
