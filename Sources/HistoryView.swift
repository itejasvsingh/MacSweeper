import SwiftUI
import AppKit

/// A history record plus how many of its items can still be put back.
struct HistoryRow: Identifiable {
    let record: CleanupRecord
    let restorableCount: Int
    var id: UUID { record.id }

    var canRestore: Bool { restorableCount > 0 }
}

/// Lists every cleanup MacSweeper did, with one-click Undo while items are still in the Trash.
struct HistoryView: View {
    @ObservedObject var vm: SweeperViewModel
    @State private var showClearConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Undo any cleanup while its files are still in the Trash. Once the Trash is emptied, they're gone for good.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Clear History") { showClearConfirm = true }
                    .buttonStyle(.bordered)
                    .disabled(vm.history.isEmpty)
            }

            if vm.history.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No cleanups yet")
                        .font(.headline)
                    Text("Anything MacSweeper moves to the Trash will show up here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(vm.history) { row in
                    HistoryRowView(row: row, compact: false) { vm.restore(row) }
                        .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .onAppear { vm.reloadHistory() }
        .alert("Clear Cleaning History?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { vm.clearHistory() }
        } message: {
            Text("You won't be able to undo past cleanups from MacSweeper. The files stay in your Trash, and you can still drag them out manually.")
        }
    }
}

struct HistoryRowView: View {
    let row: HistoryRow
    let compact: Bool
    let onRestore: () -> Void

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.canRestore ? "arrow.uturn.backward.circle.fill" : "checkmark.circle")
                .font(.title3)
                .foregroundColor(row.canRestore ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.record.title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(formatBytes(row.record.bytes))
                .font(.system(.caption, design: .monospaced).bold())

            if row.canRestore {
                Button("Undo", action: onRestore)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Move \(row.restorableCount) item(s) back from the Trash")
            } else {
                Text("Trash emptied")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !compact, let first = row.record.items.first(where: { FileManager.default.fileExists(atPath: $0.trashed) }) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: first.trashed)])
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Show in Trash")
            }
        }
    }

    private var subtitle: String {
        let when = Self.formatter.string(from: row.record.date)
        let count = row.record.items.count
        if row.canRestore && row.restorableCount < count {
            return "\(when) · \(row.restorableCount) of \(count) items restorable"
        }
        return "\(when) · \(count) item\(count == 1 ? "" : "s")"
    }
}
