import SwiftUI
import AppKit

struct RunningProcess: Identifiable {
    let id: Int32
    let name: String
    let cpu: Double
    let memoryMB: Double
}

struct ProcessMonitorView: View {
    @State private var processes: [RunningProcess] = []
    @State private var sortByMemory = true
    @State private var isLoading = false
    @State private var pendingForceQuit: RunningProcess?
    @State private var status = ""

    /// Killing these logs you out, freezes the screen, or destabilizes macOS.
    private static let criticalProcesses: Set<String> = [
        "loginwindow", "WindowServer", "kernel_task", "launchd", "Finder", "Dock",
        "SystemUIServer", "ControlCenter", "coreaudiod", "mds", "mds_stores", "cfprefsd"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Sort by", selection: $sortByMemory) {
                    Text("Top Memory (RAM)").tag(true)
                    Text("Top CPU").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .onChange(of: sortByMemory) { _ in refresh() }

                Spacer()

                if !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Button {
                    refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
            }

            List(processes) { proc in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(proc.name)
                            .font(.body.weight(.medium))
                        Text("PID \(proc.id)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.1f%% CPU", proc.cpu))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(proc.cpu > 50 ? .orange : .secondary)
                        .frame(width: 80, alignment: .trailing)
                    Text(String(format: "%.0f MB", proc.memoryMB))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(proc.memoryMB > 500 ? .red : .secondary)
                        .frame(width: 80, alignment: .trailing)

                    let critical = Self.criticalProcesses.contains(proc.name)
                    Button("Quit") {
                        terminate(proc, force: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(critical)

                    Button("Force", role: .destructive) {
                        pendingForceQuit = proc
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(critical)
                    .help(critical ? "macOS system process. Quitting it can log you out or freeze your Mac." : "Force quit (unsaved work will be lost)")
                }
            }
        }
        .padding()
        .onAppear { refresh() }
        .alert("Force Quit \(pendingForceQuit?.name ?? "")?", isPresented: Binding(
            get: { pendingForceQuit != nil },
            set: { if !$0 { pendingForceQuit = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingForceQuit = nil }
            Button("Force Quit", role: .destructive) {
                if let proc = pendingForceQuit { terminate(proc, force: true) }
                pendingForceQuit = nil
            }
        } message: {
            Text("Any unsaved work in this app will be lost.")
        }
    }

    private func refresh() {
        isLoading = true
        let byMem = sortByMemory
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/ps")
            p.arguments = ["-axo", "pid=,pcpu=,rss=,comm=", byMem ? "-m" : "-r"]
            let pipe = Pipe()
            p.standardOutput = pipe
            try? p.run()
            p.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let myPID = ProcessInfo.processInfo.processIdentifier

            var list: [RunningProcess] = []
            for line in output.components(separatedBy: .newlines) {
                let parts = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 3, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
                guard parts.count == 4,
                      let pid = Int32(parts[0]),
                      let cpu = Double(parts[1]),
                      let rssKB = Double(parts[2]),
                      pid > 1, pid != myPID else { continue }
                let fullPath = String(parts[3])
                let name = URL(fileURLWithPath: fullPath).lastPathComponent
                list.append(RunningProcess(id: pid, name: name, cpu: cpu, memoryMB: rssKB / 1024.0))
                if list.count >= 25 { break }
            }

            DispatchQueue.main.async {
                self.processes = list
                self.isLoading = false
            }
        }
    }

    private func terminate(_ proc: RunningProcess, force: Bool) {
        if kill(proc.id, force ? SIGKILL : SIGTERM) == 0 {
            status = force ? "Force quit \(proc.name)." : "Asked \(proc.name) to quit."
        } else if errno == EPERM {
            status = "\(proc.name) belongs to the system or another user and can't be quit from here."
        } else {
            status = "Couldn't quit \(proc.name) (it may have already exited)."
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            refresh()
        }
    }
}
