import Foundation
import AppKit
import CryptoKit

enum UpdateCheckResult {
    case updateAvailable(version: String, downloadURL: URL, isZip: Bool)
    case upToDate(current: String)
    case error(String)
}

final class UpdateChecker {
    private static let repo = "itejasvsingh/MacSweeper"

    /// Base64 of the raw 32-byte Ed25519 public key used to sign release zips.
    /// Generate a key pair with `swift scripts/generate-update-key.swift`, paste the
    /// public key here, and store the private key as the `UPDATE_SIGNING_KEY` repo secret.
    /// While this is empty, automatic install is disabled and users are sent to the
    /// release page to download manually instead.
    static let updatePublicKeyBase64 = ""

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private static var signingPublicKey: Curve25519.Signing.PublicKey? {
        guard let raw = Data(base64Encoded: updatePublicKeyBase64), raw.count == 32 else { return nil }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
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
                // Only offer one-click install when we can cryptographically verify the download.
                if signingPublicKey != nil,
                   let zipURL = URL(string: "https://github.com/\(repo)/releases/download/\(tag)/MacSweeper.zip") {
                    return .updateAvailable(version: latestVersion, downloadURL: zipURL, isZip: true)
                }
                return .updateAvailable(version: latestVersion, downloadURL: finalURL, isZip: false)
            } else {
                return .upToDate(current: currentVersion)
            }
        } catch {
            return .error("Network error: \(error.localizedDescription)")
        }
    }

    private static func fail(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "UpdateChecker", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func run(_ executable: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func installZipUpdate(from url: URL) async throws {
        guard let publicKey = signingPublicKey else {
            throw fail(10, "Automatic updates are not configured. Please download the update from GitHub.")
        }

        // 1. Download the zip and its detached Ed25519 signature.
        let (tempZip, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw fail(1, "Failed to download update zip.")
        }
        let sigURL = url.appendingPathExtension("sig")
        let (sigData, sigResponse) = try await URLSession.shared.data(from: sigURL)
        guard let sigHTTP = sigResponse as? HTTPURLResponse, (200...299).contains(sigHTTP.statusCode),
              let sigText = String(data: sigData, encoding: .utf8),
              let signature = Data(base64Encoded: sigText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw fail(3, "Update signature is missing. The update was not installed.")
        }

        // 2. Verify the signature before touching anything on disk.
        let zipData = try Data(contentsOf: tempZip)
        guard publicKey.isValidSignature(signature, for: zipData) else {
            throw fail(4, "Update signature is invalid. The download may have been tampered with, so it was not installed.")
        }

        // 3. Extract and sanity-check the new bundle.
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("MacSweeperUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        guard try run("/usr/bin/ditto", ["-x", "-k", tempZip.path, workDir.path]) == 0 else {
            throw fail(5, "Could not extract the update.")
        }

        let newApp = workDir.appendingPathComponent("MacSweeper.app")
        guard fm.fileExists(atPath: newApp.path) else {
            throw fail(2, "MacSweeper.app not found inside update zip.")
        }
        guard Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw fail(6, "The update's bundle identifier does not match this app.")
        }
        guard try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]) == 0 else {
            throw fail(7, "The update's code signature failed verification.")
        }

        // 4. Swap bundles with a backup, restoring the old app if the move fails.
        let targetApp = Bundle.main.bundleURL.path.hasSuffix(".app")
            ? Bundle.main.bundleURL.path
            : "/Applications/MacSweeper.app"
        let backup = workDir.appendingPathComponent("MacSweeper-previous.app").path

        let target = shellQuote(targetApp)
        let script = """
        pid=\(ProcessInfo.processInfo.processIdentifier)
        i=0
        while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 30 ]; do sleep 0.5; i=$((i+1)); done
        if [ -e \(target) ]; then
          mv \(target) \(shellQuote(backup)) || exit 1
        fi
        if mv \(shellQuote(newApp.path)) \(target); then
          open \(target)
          rm -rf \(shellQuote(workDir.path))
        else
          [ -e \(shellQuote(backup)) ] && mv \(shellQuote(backup)) \(target)
          open \(target)
        fi
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
