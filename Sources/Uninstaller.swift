import Foundation
import AppKit
import CoreServices

final class AppUninstaller {
    static let fm = FileManager.default
    static let protectedVendors: Set<String> = [
        "google", "microsoft", "adobe", "apple", "mozilla", "jetbrains", "oracle", "meta", "zoom"
    ]

    static func scanInstalledApps() -> [InstalledApp] {
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        let runningIds = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        var apps: [InstalledApp] = []

        for dir in appDirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in items where url.pathExtension == "app" {
                let bundle = Bundle(url: url)
                let bundleId = bundle?.bundleIdentifier ?? ""
                if bundleId.hasPrefix("com.apple.") { continue }

                let name = url.deletingPathExtension().lastPathComponent
                let appSize = FileScanner.directorySize(at: url)
                let related = findRelatedFiles(appName: name, bundleId: bundleId)
                let isRunning = !bundleId.isEmpty && runningIds.contains(bundleId)

                apps.append(InstalledApp(
                    name: name,
                    bundleId: bundleId,
                    appURL: url,
                    appSize: appSize,
                    relatedFiles: related,
                    isRunning: isRunning,
                    lastUsed: lastUsedDate(for: url)
                ))
            }
        }
        return apps.sorted { $0.totalSize > $1.totalSize }
    }

    /// Spotlight's "Last opened" date for an app bundle.
    static func lastUsedDate(for url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    static func findRelatedFiles(appName: String, bundleId: String) -> [RelatedFile] {
        let userLib = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let sysLib = URL(fileURLWithPath: "/Library")

        let searchLocations: [(String, URL, Bool)] = [
            ("~/Library/Application Support", userLib.appendingPathComponent("Application Support"), false),
            ("~/Library/Containers", userLib.appendingPathComponent("Containers"), false),
            ("~/Library/Group Containers", userLib.appendingPathComponent("Group Containers"), false),
            ("~/Library/Caches", userLib.appendingPathComponent("Caches"), false),
            ("~/Library/Preferences", userLib.appendingPathComponent("Preferences"), false),
            ("~/Library/Saved State", userLib.appendingPathComponent("Saved Application State"), false),
            ("~/Library/LaunchAgents", userLib.appendingPathComponent("LaunchAgents"), false),
            ("/Library/Application Support", sysLib.appendingPathComponent("Application Support"), true),
            ("/Library/Caches", sysLib.appendingPathComponent("Caches"), true),
            ("/Library/Preferences", sysLib.appendingPathComponent("Preferences"), true),
            ("/Library/LaunchAgents", sysLib.appendingPathComponent("LaunchAgents"), true),
            ("/Library/LaunchDaemons", sysLib.appendingPathComponent("LaunchDaemons"), true),
            ("/Library/PrivilegedHelperTools", sysLib.appendingPathComponent("PrivilegedHelperTools"), true)
        ]

        let lowerBundle = bundleId.lowercased()
        let lowerName = appName.lowercased()
        let allowNameMatch = lowerName.count >= 4 && !protectedVendors.contains(lowerName)
        var found: [RelatedFile] = []

        for (label, dir, isSystem) in searchLocations {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for item in items {
                let itemName = item.lastPathComponent.lowercased()
                if itemName.hasPrefix("com.apple.") { continue }

                let matchesBundle = !lowerBundle.isEmpty && itemName.contains(lowerBundle)
                let matchesName = allowNameMatch && (itemName == lowerName || itemName == "\(lowerName).plist")

                if matchesBundle || matchesName {
                    let size = FileScanner.directorySize(at: item)
                    found.append(RelatedFile(url: item, location: label, size: size, isSelected: true, isSystemWide: isSystem))
                }
            }
        }
        return found.sorted { $0.size > $1.size }
    }

    /// `preCommands` run first (as root) and their failures are ignored — used to
    /// unload launchd jobs before their plists are moved.
    static func removeSystemWideItems(urls: [URL], preCommands: [String] = []) -> (freed: Int64, error: String?) {
        guard !urls.isEmpty else { return (0, nil) }

        let trashDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path
        var totalSize: Int64 = 0
        var shellCommands: [String] = []
        let prefix = preCommands.map { "\($0) >/dev/null 2>&1; " }.joined()

        for url in urls {
            guard fm.fileExists(atPath: url.path) else { continue }
            totalSize += FileScanner.directorySize(at: url)
            let src = shellEscape(url.path)
            let dest = shellEscape("\(trashDir)/\(url.lastPathComponent)")
            shellCommands.append("mv -f \(src) \(dest)")
        }

        guard !shellCommands.isEmpty else { return (0, nil) }

        let combined = prefix + shellCommands.joined(separator: " && ")
        let escapedForAS = combined
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = "do shell script \"\(escapedForAS)\" with administrator privileges"
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return (totalSize, nil)
            } else {
                let errData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Admin authorization cancelled."
                return (0, errText)
            }
        } catch {
            return (0, error.localizedDescription)
        }
    }

    static func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func scanOrphans(installedApps: [InstalledApp]) -> [OrphanFolder] {
        let installedBundles = Set(installedApps.map { $0.bundleId.lowercased() }.filter { !$0.isEmpty })
        let installedNames = Set(installedApps.map { $0.name.lowercased() })
        let containersDir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers")
        let trashDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path

        guard let items = try? fm.contentsOfDirectory(at: containersDir, includingPropertiesForKeys: nil) else {
            return []
        }

        var orphans: [OrphanFolder] = []
        let minSize: Int64 = 10 * 1024 * 1024 // 10 MB threshold

        for item in items {
            let folderName = item.lastPathComponent
            let lower = folderName.lowercased()
            if lower.hasPrefix("com.apple.") || lower.hasPrefix("group.com.apple.") { continue }

            // ~/Library/Containers uses symlinks; resolve the real path and skip
            // anything that has already been moved to the Trash (the symlink is
            // gone or its target now lives inside ~/.Trash).
            let resolved = item.resolvingSymlinksInPath()
            if !fm.fileExists(atPath: item.path) { continue }
            if resolved.path.hasPrefix(trashDir) { continue }

            let isInstalled = installedBundles.contains(where: { lower.contains($0) || $0.contains(lower) })
                || installedNames.contains(where: { $0.count >= 4 && lower.contains($0) })

            if !isInstalled {
                let size = FileScanner.directorySize(at: item)
                if size >= minSize {
                    orphans.append(OrphanFolder(name: folderName, url: item, location: "Containers", size: size))
                }
            }
        }
        return orphans.sorted { $0.size > $1.size }
    }
}
