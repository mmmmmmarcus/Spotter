import SwiftUI

struct UptimeSettingsView: View {
    @ObservedObject var store: UptimeStore
    @State private var askingConsent = false

    var body: some View {
        SettingsPane(
            title: "Uptime",
            subtitle: "How long today's session has run, and how many keys and clicks it took."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Uptime",
                    subtitle: "Count today's keys and clicks, and show them in the launcher.",
                    systemImage: "timer",
                    tint: .green
                ) {
                    // The switch is the consent act, so turning it on asks before anything counts.
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { store.isEnabled },
                            set: { wantsOn in
                                if wantsOn {
                                    askingConsent = true
                                } else {
                                    store.setEnabled(false)
                                }
                            })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            if store.isEnabled { countsCard }

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
                    + "key, what was typed, or where you clicked. The totals stay on this Mac, clear "
                    + "at midnight, and are deleted when you turn this off.",
                systemImage: "hand.raised")
        }
        .sheet(isPresented: $askingConsent) {
            UptimeConsentSheet(
                onCancel: { askingConsent = false },
                onAccept: {
                    askingConsent = false
                    store.setEnabled(true)
                })
        }
    }

    private var countsCard: some View {
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
    }
}

/// Nothing here reaches the network, but a system-wide input counter is asked for as plainly as one
/// that does — the user should turn this on knowing exactly what is and isn't recorded.
private struct UptimeConsentSheet: View {
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "timer")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.green)
                Text("Turn on Uptime?")
                    .font(.headline)
            }

            Text(
                "Spotter counts how many keys you press and how many times you click, everywhere on "
                    + "this Mac, and shows the totals next to how long the screen has been on today. "
                    + "It records only that a key was pressed — never which key, what you typed, or "
                    + "where you clicked. The totals stay on this Mac, clear at midnight, and are "
                    + "deleted when you turn this off. Counting keys needs the Accessibility "
                    + "permission; clicks are counted without it."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
                Spacer()
                Button("Not Now", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Enable", action: onAccept)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 420)
    }
}
