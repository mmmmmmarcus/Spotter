import SwiftUI

struct UptimeSettingsView: View {
    @ObservedObject var store: UptimeStore

    var body: some View {
        SettingsPane(title: "Uptime") {
            Section("Counting") {
                SettingsRow(
                    title: "Keyboard Counting",
                    subtitle: store.needsAccessibility
                        ? "Clicks are counted. Counting keys needs the Accessibility permission."
                        : nil
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

                SettingsRow(title: "Today's Counts") {
                    Button("Reset Today") { store.resetCounts() }
                        .controlSize(.small)
                }
            }

            // Kept deliberately: Uptime watches input system-wide, and this is the statement of what
            // it does and does not record.
            SettingsCallout(
                title: "Counts only",
                message:
                    "Spotter records that a key was pressed and that a click happened — never which "
                    + "key, what was typed, or where you clicked. There is nothing here to "
                    + "reconstruct your typing from. The totals stay on this Mac, never leave it, "
                    + "and clear at midnight.")
        }
    }
}
