import Foundation

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
    case updateAvailable(version: String, downloadURL: URL)
    case upToDate(current: String)
    case error(String)
}

final class UpdateChecker {
    static let repo = "itejasvsingh/MacSweeper"

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.4"
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
                let dmgURLString = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })?.browser_download_url
                let targetString = dmgURLString ?? release.html_url
                if let downloadURL = URL(string: targetString) {
                    return .updateAvailable(version: latest, downloadURL: downloadURL)
                }
            }
            return .upToDate(current: current)
        } catch {
            return .error("Could not reach GitHub: \(error.localizedDescription)")
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
