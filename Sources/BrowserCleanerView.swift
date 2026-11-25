import SwiftUI

struct BrowserCacheItem: Identifiable {
    let id = UUID()
    let name: String
    let path: URL
    var bytes: Int64
    var isSelected: Bool = true
}

struct BrowserCleanerView: View {
    @State private var items: [BrowserCacheItem] = []
    @State private var status = "Safely cleans browser caches without touching passwords, bookmarks, or logins."
    @State private var isScanning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(status)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Rescan") { scan() }
                    .buttonStyle(.bordered)
                Button("Clean Selected") { cleanSelected() }
                    .buttonStyle(.borderedProminent)
                    .disabled(items.filter { $0.isSelected && $0.bytes > 0 }.isEmpty)
            }

            if isScanning {
                ProgressView("Scanning browser caches...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                Spacer()
                Text("No browser caches found.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List($items) { $item in
                    HStack {
                        Toggle("", isOn: $item.isSelected)
                            .labelsHidden()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.body.weight(.medium))
                            Text(item.path.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        }
        .padding()
        .onAppear { scan() }
    }

    private func scan() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let targets: [(String, String)] = [
                ("Google Chrome Cache", "Library/Caches/Google/Chrome"),
                ("Safari Cache", "Library/Caches/com.apple.Safari"),
                ("Arc Browser Cache", "Library/Caches/company.thebrowser.Browser"),
                ("Brave Browser Cache", "Library/Caches/BraveSoftware/Brave-Browser"),
                ("Firefox Cache", "Library/Caches/Firefox"),
                ("Microsoft Edge Cache", "Library/Caches/Microsoft Edge")
            ]

            var found: [BrowserCacheItem] = []
            for (name, rel) in targets {
                let url = home.appendingPathComponent(rel)
                if FileManager.default.fileExists(atPath: url.path) {
                    let bytes = folderSize(url)
                    if bytes > 0 {
                        found.append(BrowserCacheItem(name: name, path: url, bytes: bytes))
                    }
                }
            }

            DispatchQueue.main.async {
                self.items = found
                self.isScanning = false
            }
        }
    }

    private func cleanSelected() {
        let selected = items.filter { $0.isSelected }.map { $0.path }
        status = "Moving browser caches to Trash..."
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var freed: Int64 = 0
            var skipped = 0
            for dir in selected {
                let children = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                for child in children {
                    let size = folderSize(child)
                    do {
                        try fm.trashItem(at: child, resultingItemURL: nil)
                        freed += size
                    } catch {
                        skipped += 1
                    }
                }
            }
            DispatchQueue.main.async {
                let freedText = ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)
                status = skipped == 0
                    ? "Moved \(freedText) of browser cache to Trash."
                    : "Moved \(freedText) of browser cache to Trash. Skipped \(skipped) item(s) in use — quit the browser and try again."
                scan()
            }
        }
    }

    private func folderSize(_ url: URL) -> Int64 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        p.arguments = ["-sk", url.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (Int64(out.split(separator: "\t").first ?? "") ?? 0) * 1024
    }
}
