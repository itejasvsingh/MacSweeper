import SwiftUI
import AppKit

struct FolderSizeItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let bytes: Int64
    let isDirectory: Bool
}

struct SpaceLensView: View {
    @State private var currentURL = FileManager.default.homeDirectoryForCurrentUser
    @State private var items: [FolderSizeItem] = []
    @State private var isScanning = false

    private var maxBytes: Int64 {
        max(items.first?.bytes ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if currentURL != FileManager.default.homeDirectoryForCurrentUser {
                    Button {
                        currentURL = currentURL.deletingLastPathComponent()
                        scan(url: currentURL)
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                }
                Text(currentURL.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    scan(url: currentURL)
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning)
            }

            if isScanning {
                ProgressView("Calculating folder sizes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                            .foregroundColor(item.isDirectory ? .blue : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.name)
                                    .font(.body.weight(.medium))
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.accentColor.opacity(0.7))
                                    .frame(width: max(4, geo.size.width * CGFloat(Double(item.bytes) / Double(maxBytes))), height: 6)
                            }
                            .frame(height: 6)
                        }
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal in Finder")

                        if item.isDirectory {
                            Button {
                                currentURL = item.url
                                scan(url: item.url)
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .onAppear { scan(url: currentURL) }
    }

    private func scan(url: URL) {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let contents = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? []
            var results: [FolderSizeItem] = []

            for child in contents {
                let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let size = duSize(for: child)
                if size > 0 {
                    results.append(FolderSizeItem(url: child, name: child.lastPathComponent, bytes: size, isDirectory: isDir))
                }
            }
            results.sort { $0.bytes > $1.bytes }

            DispatchQueue.main.async {
                self.items = results
                self.isScanning = false
            }
        }
    }

    private func duSize(for url: URL) -> Int64 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        p.arguments = ["-sk", url.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if let kb = Int64(out.split(separator: "\t").first ?? "") {
            return kb * 1024
        }
        return 0
    }
}
