import Foundation

struct DockerStatus {
    let installed: Bool
    let running: Bool
    let output: String
}

final class DockerCleaner {
    static func dockerBinaryPath() -> String? {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func runDocker(args: [String]) -> (exitCode: Int32, output: String) {
        guard let bin = dockerBinaryPath() else {
            return (127, "Docker CLI not found.")
        }
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

    static func checkStatus() -> DockerStatus {
        guard dockerBinaryPath() != nil else {
            return DockerStatus(installed: false, running: false, output: "Docker Desktop is not installed.")
        }
        let res = runDocker(args: ["system", "df"])
        if res.exitCode == 0 {
            return DockerStatus(installed: true, running: true, output: res.output)
        } else {
            return DockerStatus(installed: true, running: false, output: "Docker Desktop is currently closed. Open Docker Desktop to inspect or prune images.")
        }
    }

    static func pruneAll() -> String {
        let res = runDocker(args: ["system", "prune", "-a", "-f"])
        return res.output.isEmpty ? "Docker prune completed." : res.output
    }
}
