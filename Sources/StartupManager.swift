import Foundation

struct StartupItem: Identifiable {
    let id = UUID()
    let name: String
    let label: String
    let url: URL
    let scope: String
    let isSystem: Bool
}

final class StartupManager {
    static let fm = FileManager.default

    static func scan() -> [StartupItem] {
        let home = fm.homeDirectoryForCurrentUser
        let locations: [(URL, String, Bool)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), "User Agent", false),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), "System Agent", true),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), "System Daemon", true)
        ]

        var items: [StartupItem] = []

        for (dir, scope, isSystem) in locations {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == "plist" {
                let name = file.deletingPathExtension().lastPathComponent
                if name.hasPrefix("com.apple.") { continue }

                var label = name
                if let data = try? Data(contentsOf: file),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let plistLabel = plist["Label"] as? String {
                    label = plistLabel
                }

                items.append(StartupItem(
                    name: name,
                    label: label,
                    url: file,
                    scope: scope,
                    isSystem: isSystem
                ))
            }
        }

        return items.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// launchd domain the job is loaded in: daemons live in "system",
    /// agents (user or /Library/LaunchAgents) live in the user's GUI session.
    private static func domain(for item: StartupItem) -> String {
        item.scope == "System Daemon" ? "system" : "gui/\(getuid())"
    }

    /// Stops the job now, so removing it takes effect without a restart.
    /// Ignores failures: the job may simply not be loaded.
    private static func bootout(_ item: StartupItem) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", domain(for: item), item.url.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    static func removeItem(_ item: StartupItem) -> String {
        if item.isSystem {
            var pre: [String] = []
            if item.scope == "System Daemon" {
                // Needs root, so it runs inside the same admin prompt as the move.
                pre.append("/bin/launchctl bootout system \(AppUninstaller.shellEscape(item.url.path))")
            } else {
                bootout(item)
            }
            let res = AppUninstaller.removeSystemWideItems(urls: [item.url], preCommands: pre)
            if let err = res.error { return err }
            return "Stopped \(item.name) and moved it to Trash."
        } else {
            bootout(item)
            let res = FileScanner.moveToTrash(urls: [item.url])
            if !res.errors.isEmpty { return res.errors.joined(separator: "; ") }
            return "Stopped \(item.name) and moved it to Trash."
        }
    }
}
