import SwiftUI
import AppKit

enum SidebarTab: String, CaseIterable, Identifiable {
    case systemData = "System Data"
    case largeFiles = "Large & Old Files"
    case docker = "Docker"
    case homebrew = "Homebrew"
    case startup = "Startup Items"
    case uninstaller = "App Uninstaller"
    case orphans = "Orphaned Leftovers"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .systemData: return "internaldrive"
        case .largeFiles: return "doc.text.magnifyingglass"
        case .docker: return "shippingbox"
        case .homebrew: return "mug"
        case .startup: return "bolt.circle"
        case .uninstaller: return "trash"
        case .orphans: return "folder.badge.questionmark"
        }
    }
}

@MainActor
final class SweeperViewModel: ObservableObject {
    @Published var targets: [CleanupTarget] = []
    @Published var largeFiles: [LargeFileItem] = []
    @Published var startupItems: [StartupItem] = []
    @Published var brewPackages: [BrewPackage] = []
    @Published var brewLog: String = ""
    @Published var isRunningBrew: Bool = false
    @Published var apps: [InstalledApp] = []
    @Published var orphans: [OrphanFolder] = []
    @Published var topSystemHogs: [LargeSystemFolder] = []
    @Published var localSnapshotCount: Int = 0
    @Published var isDockerInstalled: Bool = DockerCleaner.isInstalled
    @Published var isBrewInstalled: Bool = HomebrewManager.isInstalled
    @Published var hasFullDiskAccess: Bool = SystemDataAdvisor.hasFullDiskAccess()
    @Published var trashSizeBytes: Int64 = 0
    @Published var appSearchText: String = ""
    @Published var ignoredKeys: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "ignoredKeys") ?? [])
    @Published var dockerStatus = DockerStatus(installed: DockerCleaner.isInstalled, running: false, output: "Click 'Refresh Docker' to inspect Docker storage.")
    @Published var dockerLog = ""
    @Published var isScanning = false
    @Published var isPruningDocker = false
    @Published var isThinningSnapshots = false
    @Published var isCheckingUpdates = false
    @Published var statusMessage = "Click Scan Mac to inspect System Data, large files, startup items, and apps."
    @Published var availableDisk: Int64 = 0
    @Published var totalDisk: Int64 = 0
    @Published var selectedAppId: UUID?
    @Published var launchAtLogin: Bool = LoginItemManager.isEnabled
    @Published var smartDeleteEnabled: Bool = UserDefaults.standard.object(forKey: "smartDeleteEnabled") as? Bool ?? true
    @Published var smartDeletePrompt: SmartDeletePrompt?

    @Published var showUpdateAlert = false
    @Published var updateAlertTitle = ""
    @Published var updateAlertMessage = ""
    @Published var updateDownloadURL: URL?
    @Published var updateIsZip = false
    @Published var isInstallingUpdate = false

    private var trashWatcher: TrashWatcher?

    var visibleTabs: [SidebarTab] {
        SidebarTab.allCases.filter { tab in
            if tab == .docker { return isDockerInstalled }
            if tab == .homebrew { return isBrewInstalled }
            return true
        }
    }

    var visibleTargets: [CleanupTarget] {
        targets.filter { !ignoredKeys.contains("target:\($0.name)") }
    }

    var visibleLargeFiles: [LargeFileItem] {
        largeFiles.filter { !ignoredKeys.contains("file:\($0.url.path)") }
    }

    var visibleOrphans: [OrphanFolder] {
        orphans.filter { !ignoredKeys.contains("orphan:\($0.url.path)") }
    }

    var filteredApps: [InstalledApp] {
        let query = appSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return apps }
        return apps.filter {
            $0.name.lowercased().contains(query) || $0.bundleId.lowercased().contains(query)
        }
    }

    var allSafeSelected: Bool {
        let safeTargets = visibleTargets.filter { $0.safety == .safe }
        return !safeTargets.isEmpty && safeTargets.allSatisfy { $0.isSelected }
    }

    init() {
        refreshDiskSpace()
        refreshPermissionsAndTrash()
        checkForUpdates(silentIfUpToDate: true)
        setupTrashWatcher()
    }

    func ignoreItem(key: String, label: String) {
        ignoredKeys.insert(key)
        UserDefaults.standard.set(Array(ignoredKeys), forKey: "ignoredKeys")
        statusMessage = "Hidden '\(label)' from future scans."
    }

    func resetIgnoredItems() {
        ignoredKeys.removeAll()
        UserDefaults.standard.removeObject(forKey: "ignoredKeys")
        statusMessage = "Cleared all ignored items."
    }

    private func setupTrashWatcher() {
        trashWatcher = TrashWatcher { [weak self] prompt in
            Task { @MainActor in
                guard let self = self, self.smartDeleteEnabled else { return }
                self.smartDeletePrompt = prompt
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        if smartDeleteEnabled {
            trashWatcher?.start()
        }
    }

    func setSmartDeleteEnabled(_ enabled: Bool) {
        smartDeleteEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "smartDeleteEnabled")
        if enabled {
            trashWatcher?.start()
            statusMessage = "SmartDelete enabled — watching Trash for uninstalled apps."
        } else {
            trashWatcher?.stop()
            statusMessage = "SmartDelete paused."
        }
    }

    func cleanSmartDeleteLeftovers(_ prompt: SmartDeletePrompt) {
        let userURLs = prompt.relatedFiles.filter { !$0.isSystemWide }.map { $0.url }
        let systemURLs = prompt.relatedFiles.filter { $0.isSystemWide }.map { $0.url }

        let userResult = FileScanner.moveToTrash(urls: userURLs)
        var totalFreed = userResult.freed
        if !systemURLs.isEmpty {
            let sysResult = AppUninstaller.removeSystemWideItems(urls: systemURLs)
            totalFreed += sysResult.freed
        }
        statusMessage = "SmartDelete cleaned \(formatBytes(totalFreed)) of leftovers for \(prompt.appName)."
        refreshPermissionsAndTrash()
    }

    func refreshPermissionsAndTrash() {
        hasFullDiskAccess = SystemDataAdvisor.hasFullDiskAccess()
        Task.detached(priority: .utility) {
            let trash = SystemDataAdvisor.trashSize()
            await MainActor.run {
                self.trashSizeBytes = trash
            }
        }
    }

    func cleanAllSafeTargets() {
    let safeURLs = visibleTargets
        .filter { $0.safety == .safe && !ignoredKeys.contains("target:\($0.name)") }
        .flatMap { $0.paths }
    guard !safeURLs.isEmpty else {
        statusMessage = "No safe junk items found to clean."
        return
    }

    statusMessage = "Cleaning all safe items..."
    Task.detached(priority: .userInitiated) {
        let result = FileScanner.cleanTargetContents(urls: safeURLs)
        let freedText = ByteCountFormatter.string(fromByteCount: result.freed, countStyle: .file)
        await MainActor.run {
            self.statusMessage = result.errors.isEmpty
                ? "Cleaned \(freedText) of safe junk. Click Empty Trash to reclaim disk space."
                : "Cleaned \(freedText) of safe junk (\(result.errors.joined(separator: "; ")))."
            self.runFullScan()
        }
    }
}

func toggleSelectAllSafe() {
        let shouldSelect = !allSafeSelected
        for idx in targets.indices where targets[idx].safety == .safe && !ignoredKeys.contains("target:\(targets[idx].name)") {
            targets[idx].isSelected = shouldSelect
        }
    }

    func emptyTrash() {
        statusMessage = "Emptying Trash..."
        Task.detached(priority: .userInitiated) {
            let result = SystemDataAdvisor.emptyTrash()
            let trash = SystemDataAdvisor.trashSize()
            let space = FileScanner.diskSpace()
            await MainActor.run {
                self.trashSizeBytes = trash
                self.availableDisk = space.available
                self.totalDisk = space.total
                if result.errors.isEmpty {
                    self.statusMessage = "Emptied Trash — reclaimed \(formatBytes(result.freed))."
                } else {
                    self.statusMessage = "Emptied Trash (\(formatBytes(result.freed))) with warnings: \(result.errors.joined(separator: "; "))"
                }
            }
        }
    }

    func runBrewCleanup() {
        isRunningBrew = true
        statusMessage = "Running brew cleanup -s..."
        Task.detached(priority: .userInitiated) {
            let log = HomebrewManager.cleanup()
            let space = FileScanner.diskSpace()
            await MainActor.run {
                self.brewLog = log
                self.availableDisk = space.available
                self.isRunningBrew = false
                self.statusMessage = "Homebrew cleanup finished."
            }
        }
    }

    func uninstallBrewPackage(_ pkg: BrewPackage) {
        isRunningBrew = true
        statusMessage = "Uninstalling \(pkg.name) via Homebrew..."
        Task.detached(priority: .userInitiated) {
            let log = HomebrewManager.uninstall(pkg)
            let updated = HomebrewManager.listPackages()
            let space = FileScanner.diskSpace()
            await MainActor.run {
                self.brewLog = log
                self.brewPackages = updated
                self.availableDisk = space.available
                self.isRunningBrew = false
                self.statusMessage = log
            }
        }
    }

    func removeStartupItem(_ item: StartupItem) {
        let msg = StartupManager.removeItem(item)
        statusMessage = msg
        startupItems = StartupManager.scan()
        refreshPermissionsAndTrash()
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

    func selfUninstall() {
        LoginItemManager.setEnabled(false)
        trashWatcher?.stop()

        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
            UserDefaults.standard.synchronize()
        }

        let appURL = Bundle.main.bundleURL
        let appPath = appURL.path
        let prefPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.local.macsweeper.plist").path

        let script: String
        if appPath.hasSuffix(".app") {
            let escapedApp = appPath.replacingOccurrences(of: "'", with: "'\\''")
            let escapedPref = prefPath.replacingOccurrences(of: "'", with: "'\\''")
            script = "sleep 1; rm -f '\(escapedPref)'; osascript -e 'tell application \"Finder\" to delete POSIX file \"\(escapedApp)\"' >/dev/null 2>&1 || mv '\(escapedApp)' \"$HOME/.Trash/MacSweeper-$(date +%s).app\""
        } else {
            let escapedPref = prefPath.replacingOccurrences(of: "'", with: "'\\''")
            script = "sleep 1; rm -f '\(escapedPref)'"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()

        NSApp.terminate(nil)
    }

    var usedDisk: Int64 {
        max(0, totalDisk - availableDisk)
    }

    var totalReclaimableBytes: Int64 {
        visibleTargets.reduce(0) { $0 + $1.sizeBytes }
    }

    func refreshDiskSpace() {
        let space = FileScanner.diskSpace()
        totalDisk = space.total
        availableDisk = space.available
    }

    func runFullScan() {
        isScanning = true
        statusMessage = "Scanning System Data, large files, startup items, Homebrew, and Applications..."

        Task.detached(priority: .userInitiated) {
            let scannedTargets = FileScanner.scanTargets()
            let scannedLarge = LargeFilesScanner.scan()
            let scannedStartup = StartupManager.scan()
            let brewInstalled = HomebrewManager.isInstalled
            let scannedBrew = brewInstalled ? HomebrewManager.listPackages() : []
            let scannedApps = AppUninstaller.scanInstalledApps()
            let scannedOrphans = AppUninstaller.scanOrphans(installedApps: scannedApps)
            let hogs = SystemDataAdvisor.scanTopSystemHogs()
            let snapshots = SystemDataAdvisor.countLocalSnapshots()
            let fda = SystemDataAdvisor.hasFullDiskAccess()
            let trash = SystemDataAdvisor.trashSize()
            let dockerInstalled = DockerCleaner.isInstalled
            let docker = dockerInstalled
                ? DockerCleaner.checkStatus()
                : DockerStatus(installed: false, running: false, output: "Docker Desktop is not installed.")
            let space = FileScanner.diskSpace()

            await MainActor.run {
                self.targets = scannedTargets
                self.largeFiles = scannedLarge
                self.startupItems = scannedStartup
                self.isBrewInstalled = brewInstalled
                self.brewPackages = scannedBrew
                self.apps = scannedApps
                self.orphans = scannedOrphans
                self.topSystemHogs = hogs
                self.localSnapshotCount = snapshots
                self.hasFullDiskAccess = fda
                self.trashSizeBytes = trash
                self.isDockerInstalled = dockerInstalled
                self.dockerStatus = docker
                self.totalDisk = space.total
                self.availableDisk = space.available
                self.isScanning = false
                let totalFound = self.visibleTargets.reduce(0) { $0 + $1.sizeBytes }
                self.statusMessage = "Scan complete. Found \(formatBytes(totalFound)) in System Data, \(self.visibleLargeFiles.count) large files, and \(scannedApps.count) apps."
            }
        }
    }

    func thinSnapshots() {
        isThinningSnapshots = true
        statusMessage = "Thinning local Time Machine snapshots..."
        Task.detached(priority: .userInitiated) {
            let msg = SystemDataAdvisor.thinLocalSnapshots()
            let snapshots = SystemDataAdvisor.countLocalSnapshots()
            let space = FileScanner.diskSpace()
            await MainActor.run {
                self.localSnapshotCount = snapshots
                self.availableDisk = space.available
                self.isThinningSnapshots = false
                self.statusMessage = msg
            }
        }
    }

    func refreshDocker() {
        Task.detached(priority: .userInitiated) {
            let installed = DockerCleaner.isInstalled
            let status = DockerCleaner.checkStatus()
            let space = FileScanner.diskSpace()
            await MainActor.run {
                self.isDockerInstalled = installed
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

    func toggleLargeFile(_ id: UUID) {
        if let idx = largeFiles.firstIndex(where: { $0.id == id }) {
            largeFiles[idx].isSelected.toggle()
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
        visibleTargets.filter { $0.isSelected }.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedLargeFileBytes: Int64 {
        visibleLargeFiles.filter { $0.isSelected }.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedOrphanBytes: Int64 {
        visibleOrphans.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }

    func cleanSelectedTargets() {
        let urls = visibleTargets.filter { $0.isSelected }.flatMap { $0.paths }
        guard !urls.isEmpty else { return }

        statusMessage = "Cleaning selected items..."
        Task.detached(priority: .userInitiated) {
            let result = FileScanner.cleanTargetContents(urls: urls)
            let freedText = ByteCountFormatter.string(fromByteCount: result.freed, countStyle: .file)
            await MainActor.run {
                if result.errors.isEmpty {
                    self.statusMessage = "Cleaned \(freedText). Click Empty Trash to reclaim disk space."
                } else {
                    self.statusMessage = "Cleaned \(freedText) (\(result.errors.joined(separator: "; ")))."
                }
                self.runFullScan()
            }
        }
    }

    func cleanSelectedLargeFiles() {
        let urls = visibleLargeFiles.filter { $0.isSelected }.map { $0.url }
        guard !urls.isEmpty else { return }

        let result = FileScanner.moveToTrash(urls: urls)
        statusMessage = "Moved \(formatBytes(result.freed)) of large files to Trash."
        runFullScan()
    }

    func cleanSelectedOrphans() {
        let urls = visibleOrphans.filter { $0.isSelected }.map { $0.url }
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
    @State private var showEmptyTrashConfirm = false
    @State private var appToUninstall: InstalledApp?
    @State private var startupToRemove: StartupItem?
    @AppStorage("hasSeenWelcomeGuide") private var hasSeenWelcomeGuide = false
    @State private var showWelcomeGuide = false
    @AppStorage("showAdvancedTools") private var showAdvancedTools = false
    @State private var showSettingsSheet = false
    @AppStorage("seenTabHelpKeys") private var seenTabHelpKeys = ""
    @State private var activeTabHelp: TabHelpInfo?
    @State private var showSelfUninstallConfirm = false

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(vm.visibleTabs, selection: $selectedTab) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
                .listStyle(.sidebar)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        showSettingsSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "gearshape")
                            Text("Settings")
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        showWelcomeGuide = true
                    } label: {
                        HStack {
                            Image(systemName: "questionmark.circle")
                            Text("Feature Guide")
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

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

                    if !vm.ignoredKeys.isEmpty {
                        Button("Reset Ignored (\(vm.ignoredKeys.count))") {
                            vm.resetIgnoredItems()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }

                    Toggle("SmartDelete", isOn: Binding(
                        get: { vm.smartDeleteEnabled },
                        set: { vm.setSmartDeleteEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.caption)

                    Toggle("Weekly Reminder", isOn: Binding(
                        get: { ReminderManager.isEnabled },
                        set: { ReminderManager.setEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.caption)

                    Toggle("Launch at Login", isOn: Binding(
                        get: { vm.launchAtLogin },
                        set: { vm.setLaunchAtLogin($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.caption)

                    Divider()
                        .padding(.vertical, 2)

                    Button(role: .destructive) {
                        showSelfUninstallConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Uninstall MacSweeper")
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
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
                case .largeFiles:
                    largeFilesView
                case .docker:
                    dockerView
                case .homebrew:
                    homebrewView
                case .startup:
                    startupView
                case .uninstaller:
                    uninstallerView
                case .orphans:
                    orphansView
                }
                Divider()
                footerBar
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            vm.refreshPermissionsAndTrash()
        }
        .onChange(of: vm.isDockerInstalled) { installed in
            if !installed && selectedTab == .docker { selectedTab = .systemData }
        }
        .onChange(of: vm.isBrewInstalled) { installed in
            if !installed && selectedTab == .homebrew { selectedTab = .systemData }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            MenuBarManager.shared.setup()
            if !hasSeenWelcomeGuide {
                showWelcomeGuide = true
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsSheetView(
                isPresented: $showSettingsSheet,
                showAdvancedTools: $showAdvancedTools,
                smartDeleteEnabled: .constant(true),
                weeklyReminderEnabled: .constant(ReminderManager.isEnabled),
                launchAtLogin: .constant(vm.launchAtLogin),
                onToggleSmartDelete: { _ in },
                onToggleReminder: { ReminderManager.setEnabled($0) },
                onToggleLogin: { vm.setLaunchAtLogin($0) },
                onCheckUpdates: { vm.checkForUpdates() },
                onUninstall: { showSelfUninstallConfirm = true }
            )
        }
        .sheet(isPresented: $showWelcomeGuide) {
            WelcomeGuideView(isPresented: $showWelcomeGuide) {
                hasSeenWelcomeGuide = true
            }
        }
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
        .alert(item: $vm.smartDeletePrompt) { prompt in
            Alert(
                title: Text("SmartDelete: \(prompt.appName) Trashed"),
                message: Text("Found \(prompt.relatedFiles.count) leftover files (\(formatBytes(prompt.totalSize))) in Library. Move them to Trash too?"),
                primaryButton: .destructive(Text("Clean Leftovers")) {
                    vm.cleanSmartDeleteLeftovers(prompt)
                },
                secondaryButton: .cancel(Text("Ignore"))
            )
        }
        .alert(item: $startupToRemove) { item in
            Alert(
                title: Text("Remove Startup Item?"),
                message: Text("Move \(item.name).plist (\(item.scope)) to Trash? It will no longer launch automatically at login.\(item.isSystem ? " macOS will ask for your password." : "")"),
                primaryButton: .destructive(Text("Move to Trash")) {
                    vm.removeStartupItem(item)
                },
                secondaryButton: .cancel()
            )
        }
        .alert("Move Selected Items to Trash?", isPresented: $showCleanConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                if selectedTab == .systemData {
                    vm.cleanSelectedTargets()
                } else if selectedTab == .largeFiles {
                    vm.cleanSelectedLargeFiles()
                } else if selectedTab == .orphans {
                    vm.cleanSelectedOrphans()
                }
            }
        } message: {
            Text("Files will be moved to your macOS Trash so you can recover them if needed.")
        }
        .onChange(of: selectedTab) { newTab in
            let key = newTab.rawValue
            let seen = Set(seenTabHelpKeys.split(separator: "|").map(String.init))
            if !seen.contains(key) {
                seenTabHelpKeys = (seen.union([key])).joined(separator: "|")
                activeTabHelp = TabHelpInfo.info(for: key)
            }
        }
        .alert(activeTabHelp?.title ?? "", isPresented: Binding(
            get: { activeTabHelp != nil },
            set: { if !$0 { activeTabHelp = nil } }
        )) {
            Button("Got It", role: .cancel) {}
        } message: {
            Text(activeTabHelp?.message ?? "")
        }
        .alert("Uninstall MacSweeper?", isPresented: $showSelfUninstallConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall & Quit", role: .destructive) {
                vm.selfUninstall()
            }
        } message: {
            Text("This disables Launch at Login, clears MacSweeper's preferences, quits the app, and moves MacSweeper.app to your Trash.")
        }
        .alert("Empty Trash Permanently?", isPresented: $showEmptyTrashConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Empty Trash", role: .destructive) {
                vm.emptyTrash()
            }
        } message: {
            Text("This permanently deletes \(formatBytes(vm.trashSizeBytes)) from your Trash and frees up disk space immediately.")
        }
        .alert("Prune Unused Docker Data?", isPresented: $showDockerConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Prune Now", role: .destructive) {
                vm.pruneDocker()
            }
        } message: {
            Text("This removes stopped containers, unused networks, dangling (untagged) images, and build cache. Tagged images, active containers, and volumes stay untouched.")
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
                HStack(spacing: 6) {
                        Text(selectedTab.rawValue)
                    .font(.title2.bold())
                        Button {
                            activeTabHelp = TabHelpInfo.info(for: selectedTab.rawValue)
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("What is this tab?")
                    }
                Spacer()
                if selectedTab == .systemData && !vm.visibleTargets.isEmpty {
                    Button(vm.allSafeSelected ? "Deselect Safe" : "Select All Safe") {
                        vm.toggleSelectAllSafe()
                    }
                    .buttonStyle(.bordered)
                }
                if !vm.hasFullDiskAccess {
                    Button("Full Disk Access") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }

                    Button {
                        vm.cleanAllSafeTargets()
                    } label: {
                        Label("Clean All Safe", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

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
            if vm.visibleTargets.isEmpty && vm.topSystemHogs.isEmpty {
                Text("No scan results yet. Click 'Scan Mac' to inspect your System Data and get reduction tips.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 24)
            } else {
                Section("Quick Cleanup Targets (Right-click to ignore)") {
                    ForEach(vm.visibleTargets) { target in
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
                        .contextMenu {
                            Button("Ignore in Future Scans") {
                                vm.ignoreItem(key: "target:\(target.name)", label: target.name)
                            }
                        }
                    }
                }

                Section("How to Decrease System Data") {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Time Machine Local Snapshots: \(vm.localSnapshotCount)")
                                .font(.headline)
                            Text(vm.localSnapshotCount > 0
                                 ? "Local APFS snapshots count toward System Data. Thinning them safely frees hidden space."
                                 : "No local Time Machine snapshots detected.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if vm.localSnapshotCount > 0 {
                            Button(vm.isThinningSnapshots ? "Thinning..." : "Thin Snapshots") {
                                vm.thinSnapshots()
                            }
                            .buttonStyle(.bordered)
                            .disabled(vm.isThinningSnapshots)
                        }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Other Ways to Shrink System Data")
                            .font(.headline)
                        Text("• Empty your macOS Trash after cleaning — moved files still occupy space until Trash is emptied.\n• Restart your Mac occasionally to clear macOS swap and temporary system caches.\n• Review the largest hidden ~/Library folders below and delete leftovers from apps you no longer use.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if !vm.topSystemHogs.isEmpty {
                    Section("Largest Hidden ~/Library Folders (>200 MB)") {
                        ForEach(vm.topSystemHogs) { hog in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(hog.name).font(.headline)
                                        Text(hog.location)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(hog.advice)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(formatBytes(hog.sizeBytes))
                                        .font(.system(.body, design: .monospaced).bold())
                                    Button("Reveal") {
                                        NSWorkspace.shared.activateFileViewerSelecting([hog.url])
                                    }
                                    .buttonStyle(.link)
                                    .font(.caption)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
    }

    private var largeFilesView: some View {
        List {
            if vm.visibleLargeFiles.isEmpty {
                Text("No large files or installers found yet. Click 'Scan Mac' to scan Downloads, Desktop, and Documents.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 24)
            } else {
                ForEach(vm.visibleLargeFiles) { item in
                    HStack(alignment: .center, spacing: 12) {
                        Toggle("", isOn: Binding(
                            get: { item.isSelected },
                            set: { _ in vm.toggleLargeFile(item.id) }
                        ))
                        .labelsHidden()

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.name).font(.headline)
                                Text(item.tag)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(item.tag == "Installer" ? Color.orange.opacity(0.2) : Color.blue.opacity(0.18))
                                    .foregroundColor(item.tag == "Installer" ? .orange : .blue)
                                    .cornerRadius(4)
                            }
                            Text("\(item.location) • Modified \(Self.dateFormatter.string(from: item.modifiedDate))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(formatBytes(item.sizeBytes))
                            .font(.system(.body, design: .monospaced).bold())
                        Button("Reveal") {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    .padding(.vertical, 3)
                    .contextMenu {
                        Button("Ignore in Future Scans") {
                            vm.ignoreItem(key: "file:\(item.url.path)", label: item.name)
                        }
                    }
                }
            }
        }
    }

    private var homebrewView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(vm.brewPackages.count) Installed Packages")
                    .font(.headline)
                Spacer()
                Button(vm.isRunningBrew ? "Running..." : "Run brew cleanup") {
                    vm.runBrewCleanup()
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isRunningBrew)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            if !vm.brewLog.isEmpty {
                GroupBox("Homebrew Output") {
                    ScrollView {
                        Text(vm.brewLog)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                    .frame(height: 80)
                }
                .padding(.horizontal)
            }

            List(vm.brewPackages) { pkg in
                HStack {
                    Text(pkg.name).font(.headline)
                    Text(pkg.isCask ? "Cask" : "Formula")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(pkg.isCask ? Color.purple.opacity(0.18) : Color.blue.opacity(0.18))
                        .foregroundColor(pkg.isCask ? .purple : .blue)
                        .cornerRadius(4)
                    Spacer()
                    Button("Uninstall") {
                        vm.uninstallBrewPackage(pkg)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(vm.isRunningBrew)
                }
            }
        }
    }

    private var startupView: some View {
        List {
            if vm.startupItems.isEmpty {
                Text("No third-party background LaunchAgents or LaunchDaemons found. Click 'Scan Mac' to check.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 24)
            } else {
                ForEach(vm.startupItems) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.name).font(.headline)
                                Text(item.scope)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(item.isSystem ? Color.orange.opacity(0.2) : Color.blue.opacity(0.18))
                                    .foregroundColor(item.isSystem ? .orange : .blue)
                                    .cornerRadius(4)
                            }
                            Text(item.url.path)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Reveal") {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        }
                        .buttonStyle(.link)
                        .font(.caption)

                        Button("Remove") {
                            startupToRemove = item
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 3)
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
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search apps...", text: $vm.appSearchText)
                        .textFieldStyle(.plain)
                    if !vm.appSearchText.isEmpty {
                        Button {
                            vm.appSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding(8)

                List(vm.filteredApps, selection: $vm.selectedAppId) { app in
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
            if vm.visibleOrphans.isEmpty {
                Text("No large orphaned Containers (>10 MB) found. Click 'Scan Mac' to check.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 24)
            } else {
                ForEach(vm.visibleOrphans) { orphan in
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
                    .contextMenu {
                        Button("Ignore in Future Scans") {
                            vm.ignoreItem(key: "orphan:\(orphan.url.path)", label: orphan.name)
                        }
                    }
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
            if vm.trashSizeBytes > 0 {
                Button("Empty Trash (\(formatBytes(vm.trashSizeBytes)))") {
                    showEmptyTrashConfirm = true
                }
                .buttonStyle(.bordered)
            }
            if selectedTab == .systemData && vm.selectedTargetBytes > 0 {
                Button("Move Selected to Trash (\(formatBytes(vm.selectedTargetBytes)))") {
                    showCleanConfirm = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else if selectedTab == .largeFiles && vm.selectedLargeFileBytes > 0 {
                Button("Move Files to Trash (\(formatBytes(vm.selectedLargeFileBytes)))") {
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
