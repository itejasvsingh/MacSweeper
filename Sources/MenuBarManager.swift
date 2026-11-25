import AppKit
import Foundation

final class MenuBarManager: NSObject {
    static let shared = MenuBarManager()
    private var statusItem: NSStatusItem?

    func setup() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "MacSweeper")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.statusItem = item
    }

    private func freeDiskText() -> String {
        let url = URL(fileURLWithPath: "/")
        if let vals = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = vals.volumeAvailableCapacityForImportantUsage {
            return "Free Disk: \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file))"
        }
        return "Free Disk: --"
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension MenuBarManager: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let titleItem = NSMenuItem(title: "MacSweeper", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let diskItem = NSMenuItem(title: freeDiskText(), action: nil, keyEquivalent: "")
        diskItem.isEnabled = false
        menu.addItem(diskItem)

        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: "Open MacSweeper", action: #selector(openApp), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: "Quit MacSweeper", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
}
