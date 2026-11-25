import SwiftUI
import AppKit

enum SidebarTab: String, CaseIterable, Identifiable {
    case systemData = "System Data"
    case docker = "Docker"
    case uninstaller = "App Uninstaller"
    case orphans = "Orphaned Leftovers"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .systemData: return "internaldrive"
        case .docker: return "shippingbox"
        case .uninstaller: return "trash"
        case .orphans: return "folder.badge.questionmark"
        }
    }
}

@MainActor
final class SweeperViewModel: ObservableObject {
    @Published var targets: [CleanupTarget] = []
    @Published var apps: [InstalledApp] = []
    @Published var orphans: [OrphanFolder] = []
    @Published var dockerStatus = DockerStatus(installed: true, running: false, output: "Click 'Refresh Docker' to inspect Docker storage.")
    @Published var dockerLog = ""
    @Published var isScanning = false
    @Published var isPruningDocker = false
    @Published var isCheckingUpdates = false
    @Published var statusMessage = "Click Scan Mac to inspect System Data, apps, and leftovers."
    @Published var availableDisk: Int64 = 0
    @Published var totalDisk: Int64 = 0
    @Published var selectedAppId: UUID?
    @Published var launchAtLogin: Bool = LoginItemManager.isEnabled

    @Published var showUpdateAlert = false
    @Published var updateAlertTitle = ""
    @Published var updateAlertMessage = ""
    @Published var updateDownloadURL: URL?
    @Published var updateIsZip = false
    @Published var isInstallingUpdate = false

    init() {
        refreshDiskSpace()
        checkForUpdates(silentIfUpToDate: true)
    }

    func checkForUpdates(silentIfUpToDate: Bool = false) {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        if !silentIfUpToDate {
            statusMessage = "Checking GitHub Releases for updates..."
        }

        Task {
            let result = await UpdateChecker.checkForUpdates()
            self.isCheckingUpdates = false
            switch result {
            case .updateAvailable(let version, let url, let isZip):
                self.updateAlertTitle = "Update Available (v\(version))"
                self.updateAlertMessage = isZip
                    ? "A newer version of MacSweeper is ready. Click Install & Relaunch to update automatically."
                    : "A newer version of MacSweeper is available on GitHub."
                self.updateDownloadURL = url
                self.updateIsZip = isZip
                self.statusMessage = "Update available: v\(version)"
                self.showUpdateAlert = true
            case .upToDate(let current):
                if !silentIfUpToDate {
                    self.updateAlertTitle = "You're Up to Date"
                    self.updateAlertMessage = "MacSweeper v\(current) is the latest version."
                    self.updateDownloadURL = nil
                    self.updateIsZip = false
                    self.statusMessage = "MacSweeper v\(current) is up to date."
                    self.showUpdateAlert = true
                }
            case .error(let msg):
                if !silentIfUpToDate {
                    self.updateAlertTitle = "Update Check Failed"
                    self.updateAlertMessage = msg
                    self.updateDownloadURL = nil
                    self.updateIsZip = false
                    self.statusMessage = msg
                    self.showUpdateAlert = true
                }
            }
        }
    }

    func installPendingUpdate() {
        guard let url = updateDownloadURL else { return }
        if !updateIsZip {
            NSWorkspace.shared.open(url)
            return
        }
        isInstallingUpdate = true
        statusMessage = "Downloading and installing update..."
        Task {
            do {
                try await UpdateChecker.installZipUpdate(from: url)
            } catch {
                self.isInstallingUpdate = false
                self.statusMessage = "Update failed: \(error.localizedDescription)"
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LoginItemManager.setEnabled(enabled)
        launchAtLogin = LoginItemManager.isEnabled
        statusMessage = launchAtLogin ? "MacSweeper will now launch automatically at login." : "Launch at Login disabled."
    }

    var usedDisk: Int64 {
        max(0, totalDisk - availableDisk)
    }

    var totalReclaimableBytes: Int64 {
        targets.reduce(0) { $0 + $1.sizeBytes }
    }

    func refreshDiskSpace() {
        let space = FileScanner.diskSpace()
        totalDisk = space.total
        availableDisk = space.available
    }

    func runFullScan() {
        isScanning = true
        statusMessage = "Scanning Library folders, Docker, and Applications..."

        Task.detached(priority: .userInitiated) {
            let scannedTargets = FileScanner.scanTargets()
            let scannedApps = AppUninstaller.scanInstalledApps()
            let scannedOrphans = AppUninstaller.scanOrphans(installedApps: scannedApps)
            let docker = DockerCleaner.checkStatus()
            let space = FileScanner.diskSpace()

            await MainActor.run {
                self.targets = scannedTargets
                self.apps = scannedApps
                self.orphans = scannedOrphans
                self.dockerStatus = docker
                self.totalDisk = space.total
                self.availableDisk = space.available
                self.isScanning = false
                let totalFound = scannedTargets.reduce(0) { $0 + $1.sizeBytes }
                self.statusMessage = "Scan complete. Found \(formatBytes(totalFound)) across \(scannedTargets.count) System Data targets and \(scannedApps.count) apps."
            }
        }
    }

    func refreshDocker() {
        Task.detached(priority: .userInitiated) {
            let status = DockerCleaner.checkStatus()
            let space = FileScanner.diskSpace()
            await MainActor.run {
                self.dockerStatus = status
                self.availableDisk = space.available
            }
        }
    }

    func pruneDocker() {
        isPruningDocker = true
        statusMessage = "Pruning unused Docker images and build cache..."
        Task.detached(priority: .userInitiated) {
            let log = DockerCleaner.pruneAll()
            let status = DockerCleaner.checkStatus()
            let space = FileScanner.diskSpace()
            await MainActor.run {
                self.dockerLog = log
                self.dockerStatus = status
                self.availableDisk = space.available
                self.isPruningDocker = false
                self.statusMessage = "Docker prune finished."
            }
        }
    }

    func toggleTarget(_ id: UUID) {
        if let idx = targets.firstIndex(where: { $0.id == id }) {
            targets[idx].isSelected.toggle()
        }
    }

    func toggleOrphan(_ id: UUID) {
        if let idx = orphans.firstIndex(where: { $0.id == id }) {
            orphans[idx].isSelected.toggle()
        }
    }

    func toggleRelatedFile(appId: UUID, fileId: UUID) {
        guard let appIdx = apps.firstIndex(where: { $0.id == appId }),
              let fileIdx = apps[appIdx].relatedFiles.firstIndex(where: { $0.id == fileId }) else { return }
        apps[appIdx].relatedFiles[fileIdx].isSelected.toggle()
    }

    var selectedTargetBytes: Int64 {
        targets.filter { $0.isSelected }.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedOrphanBytes: Int64 {
        orphans.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }

    func cleanSelectedTargets() {
        let urls = targets.filter { $0.isSelected }.flatMap { $0.paths }
        guard !urls.isEmpty else { return }

        let result = FileScanner.moveToTrash(urls: urls)
        if result.errors.isEmpty {
            statusMessage = "Moved \(formatBytes(result.freed)) to Trash. Empty Trash to reclaim disk space."
        } else {
            statusMessage = "Moved \(formatBytes(result.freed)) to Trash with warnings: \(result.errors.joined(separator: "; "))"
        }
        runFullScan()
    }

    func cleanSelectedOrphans() {
        let urls = orphans.filter { $0.isSelected }.map { $0.url }
        guard !urls.isEmpty else { return }

        let result = FileScanner.moveToTrash(urls: urls)
        statusMessage = "Moved \(formatBytes(result.freed)) of orphaned leftovers to Trash."
        runFullScan()
    }

    func uninstallApp(_ app: InstalledApp) {
        if app.isRunning {
            for running in NSWorkspace.shared.runningApplications where running.bundleIdentifier == app.bundleId {
                running.terminate()
            }
        }

        let selectedFiles = app.relatedFiles.filter { $0.isSelected }
        var userURLs = [app.appURL]
        userURLs.append(contentsOf: selectedFiles.filter { !$0.isSystemWide }.map { $0.url })
        let systemURLs = selectedFiles.filter { $0.isSystemWide }.map { $0.url }

        let userResult = FileScanner.moveToTrash(urls: userURLs)
        var totalFreed = userResult.freed
        var allErrors = userResult.errors

        if !systemURLs.isEmpty {
            let sysResult = AppUninstaller.removeSystemWideItems(urls: systemURLs)
            totalFreed += sysResult.freed
            if let err = sysResult.error {
                allErrors.append(err)
            }
        }

        if allErrors.isEmpty {
            statusMessage = "Uninstalled \(app.name) — moved \(formatBytes(totalFreed)) to Trash."
        } else {
            statusMessage = "Uninstalled \(app.name) (\(formatBytes(totalFreed))) with notes: \(allErrors.joined(separator: "; "))"
        }
        selectedAppId = nil
        runFullScan()
    }
}

struct DiskUsageBar: View {
    let total: Int64
    let used: Int64
    let reclaimable: Int64
    let available: Int64

    var body: some View {
        let safeTotal = max(1, Double(total))
        let reclaim = min(Double(reclaimable), Double(used))
        let activeUsed = max(0, Double(used) - reclaim)
        let activeRatio = activeUsed / safeTotal
        let reclaimRatio = reclaim / safeTotal

        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: max(0, geo.size.width * activeRatio))
                    if reclaimRatio > 0 {
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: max(4, geo.size.width * reclaimRatio))
                    }
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)

            HStack(spacing: 14) {
                legendDot(color: .blue, text: "Used: \(formatBytes(used))")
                if reclaimable > 0 {
                    legendDot(color: .orange, text: "Reclaimable: \(formatBytes(reclaimable))")
                }
                legendDot(color: .secondary.opacity(0.4), text: "Available: \(formatBytes(available)) of \(formatBytes(total))")
                Spacer()
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }
}

struct ContentView: View {
    @ObservedObject var vm: SweeperViewModel
    @State private var selectedTab: SidebarTab = .systemData
    @State private var showCleanConfirm = false
    @State private var showDockerConfirm = false
    @State private var appToUninstall: InstalledApp?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(SidebarTab.allCases, selection: $selectedTab) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
                .listStyle(.sidebar)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        vm.checkForUpdates()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text(vm.isCheckingUpdates ? "Checking..." : "Check for Updates")
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(vm.isCheckingUpdates)

                    Toggle("Launch at Login", isOn: Binding(
                        get: { vm.launchAtLogin },
                        set: { vm.setLaunchAtLogin($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.caption)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .navigationSplitViewColumnWidth(min: 195, ideal: 215)
        } detail: {
            VStack(spacing: 0) {
                headerBar
                Divider()
                switch selectedTab {
                case .systemData:
                    systemDataView
                case .docker:
                    dockerView
                case .uninstaller:
                    uninstallerView
                case .orphans:
                    orphansView
                }
                Divider()
                footerBar
            }
        }
        .frame(minWidth: 880, minHeight: 580)
        .alert(vm.updateAlertTitle, isPresented: $vm.showUpdateAlert) {
            if vm.updateDownloadURL != nil {
                Button(vm.updateIsZip ? "Install & Relaunch" : "Download Update") {
                    vm.installPendingUpdate()
                }
                Button("Later", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(vm.updateAlertMessage)
        }
        .alert("Move Selected Items to Trash?", isPresented: $showCleanConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                if selectedTab == .systemData {
                    vm.cleanSelectedTargets()
                } else if selectedTab == .orphans {
                    vm.cleanSelectedOrphans()
                }
            }
        } message: {
            Text("Files will be moved to your macOS Trash so you can recover them if needed.")
        }
        .alert("Prune Unused Docker Data?", isPresented: $showDockerConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Prune Now", role: .destructive) {
                vm.pruneDocker()
            }
        } message: {
            Text("This removes all stopped containers, unused images, and build caches. Active containers and named volumes stay untouched.")
        }
        .alert(item: $appToUninstall) { app in
            let selectedCount = app.relatedFiles.filter { $0.isSelected }.count
            let needsAdmin = app.relatedFiles.contains { $0.isSelected && $0.isSystemWide }
            let adminNote = needsAdmin ? " macOS will ask for your password to move system-wide /Library files." : ""
            return Alert(
                title: Text("Uninstall \(app.name)?"),
                message: Text("This moves \(app.name).app and \(selectedCount) selected leftover items (\(formatBytes(app.selectedTotalSize))) to the Trash.\(adminNote)"),
                primaryButton: .destructive(Text("Move to Trash")) {
                    vm.uninstallApp(app)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var headerBar: some View {
        VStack(spacing: 12) {
            HStack {
                Text(selectedTab.rawValue)
                    .font(.title2.bold())
                Spacer()
                Button("Full Disk Access") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    vm.runFullScan()
                } label: {
                    if vm.isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Scan Mac", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isScanning)
            }

            DiskUsageBar(
                total: vm.totalDisk,
                used: vm.usedDisk,
                reclaimable: vm.totalReclaimableBytes,
                available: vm.availableDisk
            )
        }
        .padding()
    }

    private var systemDataView: some View {
        List {
            if vm.targets.isEmpty {
                Text("No scan results yet. Click 'Scan Mac' to inspect your System Data.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 24)
            } else {
                ForEach(vm.targets) { target in
                    HStack(alignment: .top, spacing: 12) {
                        Toggle("", isOn: Binding(
                            get: { target.isSelected },
                            set: { _ in vm.toggleTarget(target.id) }
                        ))
                        .labelsHidden()

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(target.name).font(.headline)
                                Text(target.safety.rawValue)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(target.safety.color.opacity(0.18))
                                    .foregroundColor(target.safety.color)
                                    .cornerRadius(4)
                                Text(target.category.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text(target.explanation)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(formatBytes(target.sizeBytes))
                                .font(.system(.body, design: .monospaced).bold())
                            Button("Reveal") {
                                if let first = target.paths.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                                    NSWorkspace.shared.activateFileViewerSelecting([first])
                                }
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var dockerView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Circle()
                    .fill(vm.dockerStatus.running ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(vm.dockerStatus.running ? "Docker Engine Running" : "Docker Engine Offline")
                    .font(.headline)
                Spacer()
                if !vm.dockerStatus.running && vm.dockerStatus.installed {
                    Button("Open Docker Desktop") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app"))
                    }
                    .buttonStyle(.bordered)
                }
                Button("Refresh Docker") {
                    vm.refreshDocker()
                }
                .buttonStyle(.bordered)

                Button("Prune Unused Data") {
                    showDockerConfirm = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!vm.dockerStatus.running || vm.isPruningDocker)
            }

            GroupBox("Docker Disk Usage (docker system df)") {
                ScrollView {
                    Text(vm.dockerStatus.output)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 140)
            }

            if !vm.dockerLog.isEmpty {
                GroupBox("Last Prune Output") {
                    ScrollView {
                        Text(vm.dockerLog)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 120)
                }
            }
            Spacer()
        }
        .padding()
    }

    private var uninstallerView: some View {
        HSplitView {
            List(vm.apps, selection: $vm.selectedAppId) { app in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.appURL.path))
                        .resizable()
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading) {
                        Text(app.name).font(.headline)
                        Text("\(app.relatedFiles.count) leftover items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(formatBytes(app.totalSize))
                        .font(.system(.caption, design: .monospaced).bold())
                }
                .tag(app.id)
            }
            .frame(minWidth: 280)

            if let app = vm.apps.first(where: { $0.id == vm.selectedAppId }) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.appURL.path))
                            .resizable()
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading) {
                            Text(app.name).font(.title2.bold())
                            Text(app.bundleId.isEmpty ? "No Bundle ID" : app.bundleId)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Uninstall (\(formatBytes(app.selectedTotalSize)))") {
                            appToUninstall = app
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }

                    if app.isRunning {
                        Text("This app is currently running and will be quit before uninstalling.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    Divider()
                    Text("Included Files (\(app.relatedFiles.count + 1))").font(.headline)

                    List {
                        HStack {
                            Label(app.appURL.lastPathComponent, systemImage: "app.badge")
                            Spacer()
                            Text(formatBytes(app.appSize)).font(.system(.caption, design: .monospaced))
                        }
                        ForEach(app.relatedFiles) { file in
                            HStack(spacing: 8) {
                                Toggle("", isOn: Binding(
                                    get: { file.isSelected },
                                    set: { _ in vm.toggleRelatedFile(appId: app.id, fileId: file.id) }
                                ))
                                .labelsHidden()

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(file.url.lastPathComponent).font(.subheadline)
                                        if file.isSystemWide {
                                            Text("Admin")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.orange.opacity(0.2))
                                                .foregroundColor(.orange)
                                                .cornerRadius(4)
                                        }
                                    }
                                    Text(file.location).font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(formatBytes(file.size)).font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }
                .padding()
            } else {
                Text("Select an app on the left to inspect its hidden Library files and uninstall cleanly.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var orphansView: some View {
        List {
            if vm.orphans.isEmpty {
                Text("No large orphaned Containers (>10 MB) found. Click 'Scan Mac' to check.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 24)
            } else {
                ForEach(vm.orphans) { orphan in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { orphan.isSelected },
                            set: { _ in vm.toggleOrphan(orphan.id) }
                        ))
                        .labelsHidden()

                        VStack(alignment: .leading) {
                            Text(orphan.name).font(.headline)
                            Text("Inside ~/Library/\(orphan.location) — no matching app found in /Applications")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(formatBytes(orphan.size))
                            .font(.system(.body, design: .monospaced).bold())
                        Button("Reveal") {
                            NSWorkspace.shared.activateFileViewerSelecting([orphan.url])
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var footerBar: some View {
        HStack {
            Text(vm.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            if selectedTab == .systemData && vm.selectedTargetBytes > 0 {
                Button("Move Selected to Trash (\(formatBytes(vm.selectedTargetBytes)))") {
                    showCleanConfirm = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else if selectedTab == .orphans && vm.selectedOrphanBytes > 0 {
                Button("Move Leftovers to Trash (\(formatBytes(vm.selectedOrphanBytes)))") {
                    showCleanConfirm = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}
