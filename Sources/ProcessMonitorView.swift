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

                    Button("Quit") {
                        terminate(pid: proc.id, force: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Force", role: .destructive) {
                        terminate(pid: proc.id, force: true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .onAppear { refresh() }
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

    private func terminate(pid: Int32, force: Bool) {
        kill(pid, force ? SIGKILL : SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            refresh()
        }
    }
}
