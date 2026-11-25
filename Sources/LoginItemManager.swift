import Foundation

final class LoginItemManager {
    static let label = "com.local.macsweeper"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Wherever this copy of the app actually lives (/Applications or ~/Applications).
    static var appPath: String {
        let path = Bundle.main.bundleURL.path
        return path.hasSuffix(".app") ? path : "/Applications/MacSweeper.app"
    }

    static func setEnabled(_ enabled: Bool) {
        let fm = FileManager.default
        if enabled {
            let dir = plistURL.deletingLastPathComponent()
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", "-a", appPath],
                "RunAtLoad": true
            ]
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: plistURL)
            }
        } else {
            try? fm.removeItem(at: plistURL)
        }
    }
}
