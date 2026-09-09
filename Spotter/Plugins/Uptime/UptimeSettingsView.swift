import SwiftUI

struct UptimeSettingsView: View {
    @ObservedObject var store: UptimeStore

    var body: some View {
        SettingsPane(
            title: "Uptime",
            subtitle: "How long today's session has run, and how many keys and clicks it took."
        ) {
            SettingsCard(header: "Counting") {
                SettingsRow(
                    title: "Keyboard Counting",
                    subtitle: store.needsAccessibility
                        ? "Clicks are counted. Counting keys needs the Accessibility permission."
                        : "Spotter counts that a key was pressed — never which one.",
                    systemImage: "keyboard", tint: .green
                ) {
                    if store.needsAccessibility {
                        Button("Allow…") { Permissions.ensureAccessibility() }
                            .controlSize(.small)
                    } else {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }

                SettingsDivider()
                SettingsRow(
                    title: "Today's Counts",
                    subtitle: "Tallies clear on their own at midnight.",
                    systemImage: "arrow.counterclockwise", tint: .secondary
                ) {
                    Button("Reset Today") { store.resetCounts() }
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Shortcut") {
                SettingsRow(
                    title: "Uptime",
                    subtitle: "Opens the reading in the launcher.",
                    systemImage: "timer", tint: .green
                ) {
                    ShortcutRecorder(action: .plugin(.openUptime))
                }
            }

            SettingsCallout(
                title: "Counts only",
                message:
                    "Spotter records that a key was pressed and that a click happened — never which "
                    + "key, what was typed, or where you clicked. There is nothing here to "
                    + "reconstruct your typing from. The totals stay on this Mac, never leave it, "
                    + "and clear at midnight.",
                systemImage: "hand.raised")
        }
    }
}
