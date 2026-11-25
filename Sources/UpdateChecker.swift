import Foundation
import AppKit

struct GitHubAsset: Decodable {
    let name: String
    let browser_download_url: String
}

struct GitHubRelease: Decodable {
    let tag_name: String
    let html_url: String
    let assets: [GitHubAsset]
}

enum UpdateCheckResult {
    case updateAvailable(version: String, downloadURL: URL, isZip: Bool)
    case upToDate(current: String)
    case error(String)
}

final class UpdateChecker {
    static let repo = "itejasvsingh/MacSweeper"

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.5.0"
    }

    static func checkForUpdates() async -> UpdateCheckResult {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return .error("Invalid GitHub repository URL.")
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacSweeper/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                return .error("No GitHub Releases found yet for \(repo).")
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .error("GitHub returned HTTP \(http.statusCode).")
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            let current = currentVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))

            if isVersion(latest, newerThan: current) {
                if let zipAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }),
                   let zipURL = URL(string: zipAsset.browser_download_url) {
                    return .updateAvailable(version: latest, downloadURL: zipURL, isZip: true)
                }
                if let fallback = URL(string: release.html_url) {
                    return .updateAvailable(version: latest, downloadURL: fallback, isZip: false)
                }
            }
            return .upToDate(current: current)
        } catch {
            return .error("Could not reach GitHub: \(error.localizedDescription)")
        }
    }

    static func installZipUpdate(from zipURL: URL) async throws {
        let fm = FileManager.default
        let tempDir = URL(fileURLWithPath: "/tmp/MacSweeperUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let (downloadedFile, _) = try await URLSession.shared.download(from: zipURL)
        let localZip = tempDir.appendingPathComponent("MacSweeper.zip")
        try fm.moveItem(at: downloadedFile, to: localZip)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-xk", localZip.path, tempDir.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            throw NSError(domain: "MacSweeper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract update zip."])
        }

        let newAppPath = tempDir.appendingPathComponent("MacSweeper.app").path
        guard fm.fileExists(atPath: newAppPath) else {
            throw NSError(domain: "MacSweeper", code: 2, userInfo: [NSLocalizedDescriptionKey: "MacSweeper.app not found inside update zip."])
        }

        let targetAppPath = Bundle.main.bundlePath.hasSuffix(".app") ? Bundle.main.bundlePath : "/Applications/MacSweeper.app"
        let pid = ProcessInfo.processInfo.processIdentifier

        // Detached shell script waits for current app to exit, swaps the bundle, clears quarantine, and relaunches
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf '\(targetAppPath)'
        mv '\(newAppPath)' '\(targetAppPath)'
        xattr -cr '\(targetAppPath)' 2>/dev/null || true
        rm -rf '\(tempDir.path)'
        open '\(targetAppPath)'
        """

        let updater = Process()
        updater.executableURL = URL(fileURLWithPath: "/bin/sh")
        updater.arguments = ["-c", script]
        try updater.run()

        await MainActor.run {
            NSApp.terminate(nil)
        }
    }

    private static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        let count = max(aParts.count, bParts.count)
        for i in 0..<count {
            let av = i < aParts.count ? aParts[i] : 0
            let bv = i < bParts.count ? bParts[i] : 0
            if av != bv { return av > bv }
        }
        return false
    }
}
