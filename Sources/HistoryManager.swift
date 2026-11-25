import Foundation

/// One file or folder MacSweeper moved to the Trash, and where it went.
struct TrashedItem: Codable, Hashable {
    let original: String
    let trashed: String
}

/// One cleaning action (e.g. "Cleaned System Data"), so it can be undone later.
struct CleanupRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let bytes: Int64
    var items: [TrashedItem]
}

extension Notification.Name {
    static let cleanupHistoryChanged = Notification.Name("MacSweeperCleanupHistoryChanged")
}

/// Keeps a log of everything MacSweeper moves to the Trash and can put it back.
/// Thread-safe: every read and write goes through a private serial queue.
final class HistoryManager {
    static let shared = HistoryManager()

    private let queue = DispatchQueue(label: "com.local.macsweeper.history")
    private let maxRecords = 100
    private var cache: [CleanupRecord]?

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MacSweeper/history.json")
    }

    // MARK: - Reading

    func records() -> [CleanupRecord] {
        queue.sync { loadLocked() }
    }

    /// Items in a record that can still be put back: still in the Trash, and nothing
    /// has been created at the original location since.
    static func restorableItems(in record: CleanupRecord) -> [TrashedItem] {
        let fm = FileManager.default
        return record.items.filter { fm.fileExists(atPath: $0.trashed) && !fm.fileExists(atPath: $0.original) }
    }

    // MARK: - Writing

    func add(title: String, bytes: Int64, items: [TrashedItem]) {
        guard !items.isEmpty else { return }
        queue.sync {
            var all = loadLocked()
            all.insert(CleanupRecord(id: UUID(), date: Date(), title: title, bytes: bytes, items: items), at: 0)
            if all.count > maxRecords { all = Array(all.prefix(maxRecords)) }
            saveLocked(all)
        }
        notifyChanged()
    }

    func clear() {
        queue.sync { saveLocked([]) }
        notifyChanged()
    }

    /// Moves a record's items back to where they came from.
    func restore(_ recordID: UUID) -> (restored: Int, failed: [String]) {
        let result: (Int, [String]) = queue.sync {
            var all = loadLocked()
            guard let idx = all.firstIndex(where: { $0.id == recordID }) else { return (0, []) }

            let fm = FileManager.default
            var restored = 0
            var failed: [String] = []
            var remaining: [TrashedItem] = []

            for item in all[idx].items {
                let src = URL(fileURLWithPath: item.trashed)
                let dst = URL(fileURLWithPath: item.original)
                guard fm.fileExists(atPath: src.path) else { continue } // Trash was emptied
                if fm.fileExists(atPath: dst.path) {
                    failed.append("\(dst.lastPathComponent): something already exists at the original location")
                    remaining.append(item)
                    continue
                }
                do {
                    try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: src, to: dst)
                    restored += 1
                } catch {
                    failed.append("\(dst.lastPathComponent): \(error.localizedDescription)")
                    remaining.append(item)
                }
            }

            if remaining.isEmpty {
                all.remove(at: idx)
            } else {
                all[idx].items = remaining
            }
            saveLocked(all)
            return (restored, failed)
        }
        notifyChanged()
        return result
    }

    // MARK: - Private (call only on `queue`)

    private func loadLocked() -> [CleanupRecord] {
        if let cache = cache { return cache }
        guard let data = try? Data(contentsOf: fileURL) else {
            cache = []
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = (try? decoder.decode([CleanupRecord].self, from: data)) ?? []
        cache = loaded
        return loaded
    }

    private func saveLocked(_ records: [CleanupRecord]) {
        cache = records
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .cleanupHistoryChanged, object: nil)
        }
    }
}

extension FileManager {
    /// Moves an item to the Trash and returns where it ended up, for the history log.
    func trashItemRecording(at url: URL) throws -> TrashedItem? {
        var resulting: NSURL?
        try trashItem(at: url, resultingItemURL: &resulting)
        guard let dest = resulting as URL? else { return nil }
        return TrashedItem(original: url.path, trashed: dest.path)
    }
}
