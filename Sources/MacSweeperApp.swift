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
        }
        .windowStyle(.titleBar)

        MenuBarExtra("MacSweeper", systemImage: "sparkles") {
            Text("Available: \(formatBytes(vm.availableDisk))")
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
