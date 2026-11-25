import SwiftUI

/// Home screen: disk usage at a glance, one-click Smart Clean, and shortcuts into each tool.
struct OverviewView: View {
    @ObservedObject var vm: SweeperViewModel
    let onSmartClean: () -> Void
    let onEmptyTrash: () -> Void
    let onOpenTab: (SidebarTab) -> Void

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroCard

                if vm.hasScanned {
                    Text("Where your space is")
                        .font(.headline)
                    LazyVGrid(columns: columns, spacing: 14) {
                        StatCard(
                            icon: "internaldrive", tint: .blue,
                            title: "System Data",
                            value: formatBytes(vm.safeReclaimableBytes + vm.reviewReclaimableBytes),
                            detail: "\(formatBytes(vm.safeReclaimableBytes)) safe · \(formatBytes(vm.reviewReclaimableBytes)) to review",
                            action: { onOpenTab(.systemData) }
                        )
                        StatCard(
                            icon: "doc.text.magnifyingglass", tint: .orange,
                            title: "Large & Old Files",
                            value: formatBytes(vm.largeFilesBytes),
                            detail: "\(vm.visibleLargeFiles.count) files in Downloads, Desktop & Documents",
                            action: { onOpenTab(.largeFiles) }
                        )
                        StatCard(
                            icon: "app.badge", tint: .purple,
                            title: "Unused Apps",
                            value: formatBytes(vm.unusedAppsBytes),
                            detail: vm.unusedApps.isEmpty
                                ? "Every app was opened in the last 6 months"
                                : "\(vm.unusedApps.count) apps not opened in 6+ months",
                            action: {
                                vm.appSort = .unused
                                onOpenTab(.uninstaller)
                            }
                        )
                        StatCard(
                            icon: "folder.badge.questionmark", tint: .teal,
                            title: "Orphaned Leftovers",
                            value: formatBytes(vm.orphanBytes),
                            detail: "\(vm.visibleOrphans.count) folders from apps you deleted",
                            action: { onOpenTab(.orphans) }
                        )
                        StatCard(
                            icon: "trash", tint: .red,
                            title: "Trash",
                            value: formatBytes(vm.trashSizeBytes),
                            detail: vm.trashSizeBytes > 0
                                ? "Still using disk space until emptied"
                                : "Trash is empty",
                            actionTitle: vm.trashSizeBytes > 0 ? "Empty Trash…" : nil,
                            action: onEmptyTrash
                        )
                        StatCard(
                            icon: "bolt.circle", tint: .yellow,
                            title: "Startup Items",
                            value: "\(vm.startupItems.count)",
                            detail: "Background helpers that launch at login",
                            action: { onOpenTab(.startup) }
                        )
                    }
                }

                if !vm.history.isEmpty {
                    recentActivity
                }
            }
            .padding(20)
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        HStack(spacing: 28) {
            DiskRing(used: vm.usedDisk, total: vm.totalDisk)
                .frame(width: 140, height: 140)

            VStack(alignment: .leading, spacing: 10) {
                if vm.isScanning {
                    Text("Scanning your Mac…")
                        .font(.title2.bold())
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 280)
                    Text("Checking caches, large files, apps, and leftovers.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else if !vm.hasScanned {
                    Text("See what you can free up")
                        .font(.title2.bold())
                    Text("Scan finds caches, forgotten downloads, unused apps, and leftovers. Nothing is removed until you confirm, and everything goes to the Trash first.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        vm.runFullScan()
                    } label: {
                        Label("Scan Mac", systemImage: "magnifyingglass")
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text("You can safely free")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text(formatBytes(vm.safeReclaimableBytes))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(vm.safeReclaimableBytes > 0 ? Color.accentColor : Color.secondary)
                    if vm.reviewReclaimableBytes > 0 {
                        Text("Plus \(formatBytes(vm.reviewReclaimableBytes)) worth reviewing in System Data.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 10) {
                        Button {
                            onSmartClean()
                        } label: {
                            Label("Smart Clean", systemImage: "sparkles")
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(vm.safeReclaimableBytes == 0)

                        Button("Scan Again") { vm.runFullScan() }
                            .controlSize(.large)
                    }
                    if let date = vm.lastScanDate {
                        Text("Last scanned \(date, style: .relative) ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.secondary.opacity(0.15))
        )
    }

    // MARK: Recent activity

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent cleanups")
                    .font(.headline)
                Spacer()
                Button("See All") { onOpenTab(.history) }
                    .buttonStyle(.link)
            }
            VStack(spacing: 0) {
                ForEach(vm.history.prefix(3)) { row in
                    HistoryRowView(row: row, compact: true) { vm.restore(row) }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    if row.id != vm.history.prefix(3).last?.id {
                        Divider()
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }
}

// MARK: - Components

/// Circular disk-usage gauge with free space in the middle.
struct DiskRing: View {
    let used: Int64
    let total: Int64

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(used) / Double(total)))
    }

    private var tint: Color {
        fraction > 0.9 ? Color.red : (fraction > 0.75 ? Color.orange : Color.accentColor)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: fraction)
            VStack(spacing: 2) {
                Text(formatBytes(max(0, total - used)))
                    .font(.system(.headline, design: .rounded))
                Text("free")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(Int((fraction * 100).rounded()))% used")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// Clickable summary card used on the Overview grid.
struct StatCard: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let detail: String
    var actionTitle: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(tint)
                        .frame(width: 32, height: 32)
                        .background(tint.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    Image(systemName: actionTitle == nil ? "chevron.right" : "trash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(.title2, design: .rounded).bold())
                    .foregroundColor(.primary)
                Text(actionTitle ?? detail)
                    .font(.caption)
                    .foregroundColor(actionTitle == nil ? Color.secondary : tint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isHovering ? tint.opacity(0.6) : Color.secondary.opacity(0.15))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(detail)
    }
}
