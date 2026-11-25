import Foundation

final class FileScanner {
    static let fm = FileManager.default

    static func directorySize(at url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            let vals = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            return Int64(vals?.totalFileAllocatedSize ?? vals?.fileSize ?? 0)
        }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]),
                  vals.isRegularFile == true else { continue }
            total += Int64(vals.totalFileAllocatedSize ?? vals.fileSize ?? 0)
        }
        return total
    }

    static func diskSpace() -> (total: Int64, available: Int64) {
        let root = URL(fileURLWithPath: "/")
        let vals = try? root.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let total = Int64(vals?.volumeTotalCapacity ?? 0)
        let avail = vals?.volumeAvailableCapacityForImportantUsage ?? 0
        return (total, avail)
    }

    static func buildDefaultTargets() -> [CleanupTarget] {
        let home = fm.homeDirectoryForCurrentUser
        let lib = home.appendingPathComponent("Library")

        return [
            CleanupTarget(
                name: "Claude Desktop VM & Caches",
                category: .aiAndVMs,
                safety: .review,
                explanation: "Local Linux VM bundle and app caches. Re-downloads automatically if you use Claude sandbox features.",
                paths: [
                    lib.appendingPathComponent("Application Support/Claude/vm_bundles"),
                    lib.appendingPathComponent("Application Support/Claude/claude-code-vm"),
                    lib.appendingPathComponent("Application Support/Claude/Cache"),
                    lib.appendingPathComponent("Application Support/Claude/Code Cache"),
                    lib.appendingPathComponent("Application Support/Claude/GPUCache")
                ]
            ),
            CleanupTarget(
                name: "Ollama Local AI Models",
                category: .aiAndVMs,
                safety: .review,
                explanation: "Downloaded open-source LLMs. Safe to remove if you are done testing them; re-downloadable anytime.",
                paths: [home.appendingPathComponent(".ollama/models")]
            ),
            CleanupTarget(
                name: "UTM Virtual Machines",
                category: .aiAndVMs,
                safety: .caution,
                explanation: "Full guest OS virtual machine disk images. Only trash if you no longer need your VMs.",
                paths: [lib.appendingPathComponent("Containers/com.utmapp.UTM/Data/Documents")]
            ),
            CleanupTarget(
                name: "Xcode DerivedData",
                category: .developer,
                safety: .safe,
                explanation: "Temporary build artifacts and indexes. Xcode rebuilds them automatically when needed.",
                paths: [lib.appendingPathComponent("Developer/Xcode/DerivedData")]
            ),
            CleanupTarget(
                name: "iOS Simulator Devices",
                category: .developer,
                safety: .review,
                explanation: "Simulated iPhone/iPad storage. Safe to clear if you aren't actively testing iOS apps.",
                paths: [lib.appendingPathComponent("Developer/CoreSimulator/Devices")]
            ),
            CleanupTarget(
                name: "Package Manager Caches (npm, pip, HF)",
                category: .developer,
                safety: .safe,
                explanation: "Cached installers and model downloads. Zero impact on your already-installed projects.",
                paths: [
                    home.appendingPathComponent(".npm/_cacache"),
                    lib.appendingPathComponent("Caches/pip"),
                    home.appendingPathComponent(".cache")
                ]
            ),
            CleanupTarget(
                name: "Homebrew Download Cache",
                category: .developer,
                safety: .safe,
                explanation: "Old formula installers downloaded by Homebrew. Safe to trash anytime.",
                paths: [lib.appendingPathComponent("Caches/Homebrew")]
            ),
            CleanupTarget(
                name: "WhatsApp Local Media",
                category: .messaging,
                safety: .review,
                explanation: "Local copies of received videos, photos, and documents. Requires Full Disk Access to scan.",
                paths: [lib.appendingPathComponent("Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media")]
            ),
            CleanupTarget(
                name: "Telegram Local Cache",
                category: .messaging,
                safety: .safe,
                explanation: "Cached media and files. Your chats and media remain safely stored in Telegram's cloud.",
                paths: [lib.appendingPathComponent("Group Containers/6N38VWS5BX.ru.keepcoder.Telegram")]
            ),
            CleanupTarget(
                name: "User App Caches",
                category: .system,
                safety: .safe,
                explanation: "Temporary files created by apps to load faster. macOS and apps rebuild what they need.",
                paths: [lib.appendingPathComponent("Caches")]
            ),
            CleanupTarget(
                name: "User App Logs",
                category: .system,
                safety: .safe,
                explanation: "Diagnostic and crash logs from apps. Completely safe to clear.",
                paths: [lib.appendingPathComponent("Logs")]
            )
        ]
    }

    static func scanTargets() -> [CleanupTarget] {
        var results: [CleanupTarget] = []
        for var target in buildDefaultTargets() {
            var total: Int64 = 0
            var anyExists = false
            for path in target.paths {
                if fm.fileExists(atPath: path.path) {
                    anyExists = true
                    total += directorySize(at: path)
                }
            }
            target.sizeBytes = total
            target.exists = anyExists && total > 0
            if target.exists {
                results.append(target)
            }
        }
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    static func moveToTrash(urls: [URL]) -> (freed: Int64, errors: [String]) {
        var freed: Int64 = 0
        var errors: [String] = []

        for url in urls {
            guard fm.fileExists(atPath: url.path) else { continue }
            let size = directorySize(at: url)
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
                freed += size
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (freed, errors)
    }
}
