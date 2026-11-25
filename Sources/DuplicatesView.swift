import SwiftUI
import CryptoKit
import AppKit

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let hash: String
    let size: Int64
    var files: [URL]
}

struct DuplicatesView: View {
    @State private var groups: [DuplicateGroup] = []
    @State private var isScanning = false
    @State private var status = "Scans Downloads, Desktop, and Documents for identical files over 1 MB."

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(status)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    scanDuplicates()
                } label: {
                    Label(isScanning ? "Scanning..." : "Find Duplicates", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning)
            }

            if isScanning {
                ProgressView("Comparing file sizes and SHA-256 hashes... (oldest copy in each group is kept as the original)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                Spacer()
                Text("No duplicate files found yet. Click 'Find Duplicates' to scan.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(groups) { group in
                        Section(header: Text("\(group.files.count) identical copies • \(ByteCountFormatter.string(fromByteCount: group.size, countStyle: .file)) each")) {
                            ForEach(Array(group.files.enumerated()), id: \.element) { idx, fileURL in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(fileURL.lastPathComponent)
                                            .font(.body.weight(idx == 0 ? .semibold : .regular))
                                        Text(fileURL.deletingLastPathComponent().path)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if idx == 0 {
                                        Text("Original")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.2))
                                            .foregroundColor(.green)
                                            .cornerRadius(4)
                                    } else {
                                        Button("Trash Copy", role: .destructive) {
                                            trashFile(fileURL, in: group.id)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func scanDuplicates() {
        isScanning = true
        status = "Scanning folders..."
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            let roots = ["Downloads", "Desktop", "Documents"].map { home.appendingPathComponent($0) }
            var bySize: [Int64: [URL]] = [:]

            for root in roots {
                guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let url as URL in enumerator {
                    guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                          vals.isRegularFile == true,
                          let sz = vals.fileSize, sz > 1_048_576 else { continue }
                    bySize[Int64(sz), default: []].append(url)
                }
            }

            var found: [DuplicateGroup] = []
            for (size, urls) in bySize where urls.count > 1 {
                var byHash: [String: [URL]] = [:]
                for url in urls {
                    if let hash = sha256(url: url) {
                        byHash[hash, default: []].append(url)
                    }
                }
                for (hash, dupes) in byHash where dupes.count > 1 {
                    // Treat the oldest copy as the original so the one you made first is kept.
                    let ordered = dupes.sorted { creationDate($0) < creationDate($1) }
                    found.append(DuplicateGroup(hash: hash, size: size, files: ordered))
                }
            }
            found.sort { $0.size > $1.size }

            DispatchQueue.main.async {
                self.groups = found
                self.isScanning = false
                self.status = found.isEmpty ? "No duplicates over 1 MB found." : "Found \(found.count) duplicate group(s)."
            }
        }
    }

    private func creationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantFuture
    }

    private func sha256(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 65536)
            if data.isEmpty { return false }
            hasher.update(data: data)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func trashFile(_ url: URL, in groupID: UUID) {
        do {
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            if let item = try FileManager.default.trashItemRecording(at: url) {
                HistoryManager.shared.add(title: "Trashed duplicate \(url.lastPathComponent)", bytes: size, items: [item])
            }
            status = "Moved \(url.lastPathComponent) to Trash."
        } catch {
            status = "Couldn't move \(url.lastPathComponent) to Trash: \(error.localizedDescription)"
            return
        }
        if let idx = groups.firstIndex(where: { $0.id == groupID }) {
            groups[idx].files.removeAll { $0 == url }
            if groups[idx].files.count <= 1 {
                groups.remove(at: idx)
            }
        }
    }
}
