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

    static func removeItem(_ item: StartupItem) -> String {
        if item.isSystem {
            let res = AppUninstaller.removeSystemWideItems(urls: [item.url])
            if let err = res.error { return err }
            return "Moved \(item.name) to Trash."
        } else {
            let res = FileScanner.moveToTrash(urls: [item.url])
            if !res.errors.isEmpty { return res.errors.joined(separator: "; ") }
            return "Moved \(item.name) to Trash."
        }
    }
}
