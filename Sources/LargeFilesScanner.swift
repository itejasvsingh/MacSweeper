import Foundation

struct LargeFileItem: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let location: String
    let sizeBytes: Int64
    let modifiedDate: Date
    let tag: String
    var isSelected: Bool = false
}

final class LargeFilesScanner {
    static let fm = FileManager.default

    static func scan() -> [LargeFileItem] {
        let home = fm.homeDirectoryForCurrentUser
        let roots: [(String, URL)] = [
            ("Downloads", home.appendingPathComponent("Downloads")),
            ("Desktop", home.appendingPathComponent("Desktop")),
            ("Documents", home.appendingPathComponent("Documents"))
        ]

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey]
        let largeThreshold: Int64 = 100 * 1024 * 1024    // 100 MB
        let archiveThreshold: Int64 = 50 * 1024 * 1024   // 50 MB
        let installerThreshold: Int64 = 10 * 1024 * 1024 // 10 MB

        var results: [LargeFileItem] = []

        for (label, root) in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true else { continue }

                let size = Int64(values.fileSize ?? 0)
                let ext = url.pathExtension.lowercased()
                let modified = values.contentModificationDate ?? Date()

                var tag: String?
                if (ext == "dmg" || ext == "pkg") && size >= installerThreshold {
                    tag = "Installer"
                } else if (ext == "zip" || ext == "tar" || ext == "gz" || ext == "rar" || ext == "7z") && size >= archiveThreshold {
                    tag = "Archive"
                } else if size >= largeThreshold {
                    tag = "Large File"
                }

                if let tag = tag {
                    results.append(LargeFileItem(
                        name: url.lastPathComponent,
                        url: url,
                        location: "~/\(label)",
                        sizeBytes: size,
                        modifiedDate: modified,
                        tag: tag
                    ))
                }
            }
        }

        return Array(results.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(50))
    }
}
