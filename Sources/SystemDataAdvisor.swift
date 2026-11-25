import Foundation

struct LargeSystemFolder: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let location: String
    let sizeBytes: Int64
    let advice: String
}

final class SystemDataAdvisor {
    static let fm = FileManager.default

    static func scanTopSystemHogs() -> [LargeSystemFolder] {
        let lib = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let dirs: [(String, URL, String)] = [
            ("Application Support", lib.appendingPathComponent("Application Support"), "App data & local databases. Safe to delete only if you no longer use this app."),
            ("Caches", lib.appendingPathComponent("Caches"), "Temporary cache files. Safe to clear; the app will rebuild what it needs."),
            ("Containers", lib.appendingPathComponent("Containers"), "Sandboxed app storage. Remove if the app is already uninstalled."),
            ("Group Containers", lib.appendingPathComponent("Group Containers"), "Shared app data (e.g., Office, WhatsApp). Review carefully before deleting.")
        ]

        let minSize: Int64 = 200 * 1024 * 1024 // 200 MB
        var results: [LargeSystemFolder] = []

        for (label, dir, defaultAdvice) in dirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for item in items {
                let name = item.lastPathComponent
                if name.hasPrefix("com.apple.") || name == "Apple" { continue }
                let size = FileScanner.directorySize(at: item)
                if size >= minSize {
                    results.append(LargeSystemFolder(
                        name: name,
                        url: item,
                        location: "~/Library/\(label)",
                        sizeBytes: size,
                        advice: defaultAdvice
                    ))
                }
            }
        }

        return Array(results.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(12))
    }

    static func countLocalSnapshots() -> Int {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", "/"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return text
                .split(separator: "\n")
                .filter { $0.contains("com.apple.TimeMachine") }
                .count
        } catch {
            return 0
        }
    }

    static func thinLocalSnapshots() -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["thinlocalsnapshots", "/", "10000000000", "4"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? "Requested macOS to thin local Time Machine snapshots." : text
        } catch {
            return "Could not thin snapshots: \(error.localizedDescription)"
        }
    }
}
