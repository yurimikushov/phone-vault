import SwiftUI

@main
struct PhoneVaultApp: App {

    @State private var vm = BackupViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(vm)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .newItem) {
                Button("Open Backup…") {
                    vm.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Open Demo Sample Backup") {
                    Task { await vm.loadSampleBackup() }
                }

                Button("Reload Backup") {
                    Task { await vm.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(vm.backupURL == nil || vm.isLoading)

                Divider()

                Button("Export Selected…") {
                    vm.exportSelected()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(vm.selectedItemIDs.isEmpty || vm.isExporting)

                Button("Export Current Folder…") {
                    vm.exportCurrentFolder()
                }
                .disabled(vm.currentPath.isEmpty || vm.isExporting)

                Button("Export App Data…") {
                    vm.exportCurrentApp()
                }
                .disabled(vm.selectedAppID == nil || vm.isExporting)
            }
        }
    }
}
