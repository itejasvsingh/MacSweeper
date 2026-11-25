import SwiftUI

struct SettingsSheetView: View {
    @Binding var isPresented: Bool
    @Binding var showAdvancedTools: Bool
    @Binding var smartDeleteEnabled: Bool
    @Binding var weeklyReminderEnabled: Bool
    @Binding var launchAtLogin: Bool
    @Binding var appearanceMode: AppAppearance
    let onToggleSmartDelete: (Bool) -> Void
    let onToggleReminder: (Bool) -> Void
    let onToggleLogin: (Bool) -> Void
    let onSetAppearance: (AppAppearance) -> Void
    let onCheckUpdates: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("MacSweeper Settings")
                    .font(.title3.bold())
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }

            Divider()

            Toggle("Show Advanced Tools (RAM & CPU monitor, Space Lens)", isOn: $showAdvancedTools)
            Toggle("SmartDelete (Offer to clean app leftovers when trashing an app)", isOn: Binding(
                get: { smartDeleteEnabled },
                set: { val in
                    smartDeleteEnabled = val
                    onToggleSmartDelete(val)
                }
            ))
            Toggle("Weekly Clean Reminder (Sunday notification)", isOn: Binding(
                get: { weeklyReminderEnabled },
                set: { val in
                    weeklyReminderEnabled = val
                    onToggleReminder(val)
                }
            ))
            Toggle("Launch MacSweeper automatically at login", isOn: Binding(
                get: { launchAtLogin },
                set: { val in
                    launchAtLogin = val
                    onToggleLogin(val)
                }
            ))

            Picker("Appearance", selection: Binding(
                get: { appearanceMode },
                set: { val in
                    appearanceMode = val
                    onSetAppearance(val)
                }
            )) {
                ForEach(AppAppearance.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            HStack {
                Button("Check for Updates") {
                    isPresented = false
                    onCheckUpdates()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Uninstall MacSweeper", role: .destructive) {
                    isPresented = false
                    onUninstall()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
        .padding(20)
        .frame(width: 480, height: 300)
    }
}
