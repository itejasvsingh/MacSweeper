import Foundation

struct BrewPackage: Identifiable {
    let id = UUID()
    let name: String
    let isCask: Bool
}

final class HomebrewManager {
    static var brewPath: String? {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isInstalled: Bool {
        brewPath != nil
    }

    private static func runBrew(args: [String]) -> (exitCode: Int32, output: String) {
        guard let bin = brewPath else { return (127, "Homebrew not installed.") }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus, text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (1, error.localizedDescription)
        }
    }

    static func listPackages() -> [BrewPackage] {
        guard isInstalled else { return [] }
        var packages: [BrewPackage] = []

        let formulae = runBrew(args: ["list", "--formula", "-1"])
        if formulae.exitCode == 0 {
            for line in formulae.output.split(separator: "\n") {
                let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { packages.append(BrewPackage(name: name, isCask: false)) }
            }
        }

        let casks = runBrew(args: ["list", "--cask", "-1"])
        if casks.exitCode == 0 {
            for line in casks.output.split(separator: "\n") {
                let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { packages.append(BrewPackage(name: name, isCask: true)) }
            }
        }

        return packages.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    static func cleanup() -> String {
        let res = runBrew(args: ["cleanup", "-s"])
        return res.output.isEmpty ? "Homebrew cleanup complete." : res.output
    }

    static func uninstall(_ pkg: BrewPackage) -> String {
        let args = pkg.isCask ? ["uninstall", "--cask", pkg.name] : ["uninstall", pkg.name]
        let res = runBrew(args: args)
        return res.exitCode == 0 ? "Uninstalled \(pkg.name)." : "Failed to uninstall \(pkg.name): \(res.output)"
    }
}
