import Foundation
import AppKit

enum UpdateCheckResult {
    case updateAvailable(version: String, downloadURL: URL, isZip: Bool)
    case upToDate(current: String)
    case error(String)
}

final class UpdateChecker {
    private static let repo = "itejasvsingh/MacSweeper"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static func checkForUpdates() async -> UpdateCheckResult {
        guard let latestURL = URL(string: "https://github.com/\(repo)/releases/latest") else {
            return .error("Invalid update URL.")
        }

        var request = URLRequest(url: latestURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        request.setValue("MacSweeper/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .error("Invalid response from GitHub.")
            }
            guard (200...399).contains(http.statusCode), let finalURL = http.url else {
                return .error("GitHub returned HTTP \(http.statusCode).")
            }

            let tag = finalURL.lastPathComponent
            guard !tag.isEmpty, tag != "releases", tag != "latest" else {
                return .upToDate(current: currentVersion)
            }

            let latestVersion = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag

            if latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                let zipURL = URL(string: "https://github.com/\(repo)/releases/download/\(tag)/MacSweeper.zip")!
                return .updateAvailable(version: latestVersion, downloadURL: zipURL, isZip: true)
            } else {
                return .upToDate(current: currentVersion)
            }
        } catch {
            return .error("Network error: \(error.localizedDescription)")
        }
    }

    static func installZipUpdate(from url: URL) async throws {
        let (tempZip, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "UpdateChecker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to download update zip."])
        }

        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("MacSweeperUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", tempZip.path, workDir.path]
        try unzip.run()
        unzip.waitUntilExit()

        let newApp = workDir.appendingPathComponent("MacSweeper.app")
        guard fm.fileExists(atPath: newApp.path) else {
            throw NSError(domain: "UpdateChecker", code: 2, userInfo: [NSLocalizedDescriptionKey: "MacSweeper.app not found inside update zip."])
        }

        let targetApp = Bundle.main.bundleURL.path.hasSuffix(".app")
            ? Bundle.main.bundleURL.path
            : "/Applications/MacSweeper.app"

        let escapedNew = newApp.path.replacingOccurrences(of: "'", with: "'\\''")
        let escapedTarget = targetApp.replacingOccurrences(of: "'", with: "'\\''")
        let escapedWork = workDir.path.replacingOccurrences(of: "'", with: "'\\''")

        let script = """
        sleep 1
        rm -rf '\(escapedTarget)'
        mv '\(escapedNew)' '\(escapedTarget)'
        xattr -cr '\(escapedTarget)' 2>/dev/null || true
        open '\(escapedTarget)'
        rm -rf '\(escapedWork)'
        """

        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        launcher.arguments = ["-c", script]
        try launcher.run()

        await MainActor.run {
            NSApp.terminate(nil)
        }
    }
}
