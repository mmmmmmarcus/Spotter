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
        }
    }
}
