import SwiftUI

struct WelcomeGuideView: View {
    @Binding var isPresented: Bool
    let onDismiss: () -> Void

    private let features: [(icon: String, color: Color, title: String, desc: String)] = [
        ("internaldrive", .blue, "System Data", "Clears safe caches, old logs, and Time Machine snapshots, and highlights large hidden ~/Library folders."),
        ("doc.text.magnifyingglass", .orange, "Large & Old Files", "Finds forgotten .dmg installers, big .zip archives, and files over 100 MB in Downloads, Desktop, and Documents."),
        ("trash", .red, "App Uninstaller", "Removes apps along with their hidden Library leftovers in one click, with a live search bar."),
        ("folder.badge.questionmark", .purple, "Orphaned Leftovers", "Detects large Library folders left behind by apps you previously deleted."),
        ("bolt.circle", .yellow, "Startup Items", "Shows background LaunchAgents and LaunchDaemons so you can remove bloatware slowing down login."),
        ("shippingbox", .teal, "Docker & Homebrew", "Automatically appears when Docker or Homebrew is installed to prune unused images and caches."),
        ("sparkles", .green, "SmartDelete", "Watches your Trash in the background and offers to clean up leftovers whenever you drag an app to the Trash.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to MacSweeper")
                        .font(.title2.bold())
                    Text("Everything you clean moves safely to your Mac Trash first.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(features, id: \.title) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.title3)
                                .foregroundColor(item.color)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.desc)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack {
                Text("Tip: Right-click any scan result to hide it from future scans.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Get Started") {
                    onDismiss()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520, height: 480)
    }
}
