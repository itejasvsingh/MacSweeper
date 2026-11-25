import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct MacSweeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var vm = SweeperViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("MacSweeper", id: "main") {
            ContentView(vm: vm)
                .preferredColorScheme(vm.appearanceMode.colorScheme)
        }
        .windowStyle(.titleBar)

        MenuBarExtra("MacSweeper", systemImage: "sparkles") {
            Text("Available: \(formatBytes(vm.availableDisk))")
            if vm.hasScanned {
                Text("Safe to free: \(formatBytes(vm.safeReclaimableBytes))")
            }
            Divider()
            Button("Open MacSweeper") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Scan Mac Now") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                vm.runFullScan()
            }
            Button("Check for Updates") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                vm.checkForUpdates()
            }
            if vm.trashSizeBytes > 0 {
                Button("Empty Trash (\(formatBytes(vm.trashSizeBytes)))…") {
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.messageText = "Empty Trash Permanently?"
                    alert.informativeText = "This permanently deletes \(formatBytes(vm.trashSizeBytes)) from your Trash. Cleanups in MacSweeper's history can no longer be undone afterwards."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Empty Trash")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        vm.emptyTrash()
                    }
                }
            }
            Divider()
            Toggle("Launch at Login", isOn: Binding(
                get: { vm.launchAtLogin },
                set: { vm.setLaunchAtLogin($0) }
            ))
            Divider()
            Button("Quit MacSweeper") {
                NSApp.terminate(nil)
            }
        }
    }
}
