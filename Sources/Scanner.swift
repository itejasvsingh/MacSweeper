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
                name: "Xcode Archives",
                category: .developer,
                safety: .review,
                explanation: "Builds you archived for App Store or TestFlight. Keep the ones you may need to symbolicate crash reports.",
                paths: [lib.appendingPathComponent("Developer/Xcode/Archives")]
            ),
            CleanupTarget(
                name: "iOS Device Support Files",
                category: .developer,
                safety: .safe,
                explanation: "Debug symbols copied from every iPhone/iPad you've connected. Xcode re-copies them the next time you plug a device in.",
                paths: [
                    lib.appendingPathComponent("Developer/Xcode/iOS DeviceSupport"),
                    lib.appendingPathComponent("Developer/Xcode/watchOS DeviceSupport")
                ]
            ),
            CleanupTarget(
                name: "JavaScript Package Caches (npm, Yarn, pnpm)",
                category: .developer,
                safety: .safe,
                explanation: "Downloaded package tarballs. Installed node_modules in your projects aren't touched; packages re-download when needed.",
                paths: [
                    home.appendingPathComponent(".npm/_cacache"),
                    lib.appendingPathComponent("Caches/Yarn"),
                    lib.appendingPathComponent("pnpm/store")
                ]
            ),
            CleanupTarget(
                name: "Python Caches (pip, Conda)",
                category: .developer,
                safety: .safe,
                explanation: "Downloaded wheels and Conda package archives. Existing virtual environments keep working.",
                paths: [
                    lib.appendingPathComponent("Caches/pip"),
                    home.appendingPathComponent("miniconda3/pkgs"),
                    home.appendingPathComponent("anaconda3/pkgs"),
                    home.appendingPathComponent("opt/anaconda3/pkgs")
                ]
            ),
            CleanupTarget(
                name: "Gradle, CocoaPods, Cargo & Go Caches",
                category: .developer,
                safety: .safe,
                explanation: "Dependency download caches for Android/Java, iOS, Rust, and Go. The next build re-downloads what it needs.",
                paths: [
                    home.appendingPathComponent(".gradle/caches"),
                    lib.appendingPathComponent("Caches/CocoaPods"),
                    home.appendingPathComponent(".cargo/registry/cache"),
                    home.appendingPathComponent("go/pkg/mod/cache")
                ]
            ),
            CleanupTarget(
                name: "Shared Tool Cache (~/.cache)",
                category: .developer,
                safety: .review,
                explanation: "Used by many command-line tools, including Hugging Face models, which can be large to re-download.",
                paths: [home.appendingPathComponent(".cache")]
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
                name: "Telegram Local Data",
                category: .messaging,
                safety: .caution,
                explanation: "Telegram's whole local container, including its database. Cloud chats re-download, but you'll be logged out and Secret Chats (stored only on this Mac) will be lost. Prefer Telegram → Settings → Data and Storage → Storage Usage → Clear Cache.",
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
        let all = buildDefaultTargets()
        let allPaths = all.flatMap { $0.paths }.map { $0.standardizedFileURL.path }
        var sizeCache: [String: Int64] = [:]
        func cachedSize(_ path: String) -> Int64 {
            if let s = sizeCache[path] { return s }
            let s = directorySize(at: URL(fileURLWithPath: path))
            sizeCache[path] = s
            return s
        }

        var results: [CleanupTarget] = []
        for var target in all {
            var total: Int64 = 0
            var anyExists = false
            for url in target.paths {
                let path = url.standardizedFileURL.path
                guard fm.fileExists(atPath: path) else { continue }
                anyExists = true
                // Don't count space twice: e.g. ~/Library/Caches contains Caches/Homebrew
                // and Caches/pip, which are already reported as their own targets.
                let nested = allPaths.filter { $0 != path && $0.hasPrefix(path + "/") && fm.fileExists(atPath: $0) }
                let nestedBytes = nested.reduce(Int64(0)) { $0 + cachedSize($1) }
                total += max(0, cachedSize(path) - nestedBytes)
            }
            target.sizeBytes = total
            target.exists = anyExists && total > 0
            if target.exists {
                results.append(target)
            }
        }
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    static func cleanTargetContents(urls: [URL]) -> (freed: Int64, errors: [String], moved: [TrashedItem]) {
        let fm = FileManager.default
        var freed: Int64 = 0
        var skipped = 0
        var moved: [TrashedItem] = []

        func sizeOf(_ url: URL) -> Int64 {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
            if !isDir.boolValue {
                return (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]))
                    .map { Int64($0.totalFileAllocatedSize ?? $0.fileSize ?? 0) } ?? 0
            }
            var total: Int64 = 0
            if let en = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey], options: [], errorHandler: { _, _ in true }) {
                for case let f as URL in en {
                    if let v = try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) {
                        total += Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
                    }
                }
            }
            return total
        }

        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
                for child in children {
                    let sz = sizeOf(child)
                    // Only ever move to Trash. If that fails, skip the item rather than
                    // deleting it permanently, so everything cleaned stays recoverable.
                    do {
                        if let item = try fm.trashItemRecording(at: child) { moved.append(item) }
                        freed += sz
                    } catch {
                        skipped += 1
                    }
                }
            } else {
                let sz = sizeOf(url)
                do {
                    if let item = try fm.trashItemRecording(at: url) { moved.append(item) }
                    freed += sz
                } catch {
                    skipped += 1
                }
            }
        }

        let errors = skipped > 0 ? ["Skipped \(skipped) item(s) that couldn't be moved to Trash (in use or protected by macOS)"] : []
        return (freed, errors, moved)
    }

    static func moveToTrash(urls: [URL]) -> (freed: Int64, errors: [String], moved: [TrashedItem]) {
        var freed: Int64 = 0
        var errors: [String] = []
        var moved: [TrashedItem] = []

        for url in urls {
            guard fm.fileExists(atPath: url.path) else { continue }
            let size = directorySize(at: url)
            do {
                if let item = try fm.trashItemRecording(at: url) { moved.append(item) }
                freed += size
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (freed, errors, moved)
    }
}
