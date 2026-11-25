import Foundation

struct SmartDeletePrompt: Identifiable {
    let id = UUID()
    let appName: String
    let relatedFiles: [RelatedFile]

    var totalSize: Int64 {
        relatedFiles.reduce(0) { $0 + $1.size }
    }
}

final class TrashWatcher {
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var knownTrashedApps: Set<String> = []
    private let trashURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    private let onAppTrashed: (SmartDeletePrompt) -> Void

    init(onAppTrashed: @escaping (SmartDeletePrompt) -> Void) {
        self.onAppTrashed = onAppTrashed
        self.knownTrashedApps = currentTrashedAppNames()
    }

    func start() {
        stop()
        knownTrashedApps = currentTrashedAppNames()

        let fd = open(trashURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .utility)
        )
        src.setEventHandler { [weak self] in
            self?.checkForNewlyTrashedApps()
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
        stop()
    }

    private func currentTrashedAppNames() -> Set<String> {
        guard let items = try? FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil) else {
            return []
        }
        return Set(items.filter { $0.pathExtension == "app" }.map { $0.lastPathComponent })
    }

    private func checkForNewlyTrashedApps() {
        guard let items = try? FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil) else {
            return
        }
        let currentApps = items.filter { $0.pathExtension == "app" }
        let currentNames = Set(currentApps.map { $0.lastPathComponent })
        let newNames = currentNames.subtracting(knownTrashedApps)
        knownTrashedApps = currentNames

        for appURL in currentApps where newNames.contains(appURL.lastPathComponent) {
            let appName = appURL.deletingPathExtension().lastPathComponent
            let bundleId = Bundle(url: appURL)?.bundleIdentifier ?? ""
            if bundleId.hasPrefix("com.apple.") { continue }

            let leftovers = AppUninstaller.findRelatedFiles(appName: appName, bundleId: bundleId)
            if !leftovers.isEmpty {
                let prompt = SmartDeletePrompt(appName: appName, relatedFiles: leftovers)
                onAppTrashed(prompt)
            }
        }
    }
}
