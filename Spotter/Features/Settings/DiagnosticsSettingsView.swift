import AppKit
import SwiftUI

/// The in-app view of `AppLog`: recent events newest-first, with the log file one click away.
struct DiagnosticsSettingsView: View {
    @ObservedObject private var log = AppLog.shared

    var body: some View {
        SettingsPane(title: "Diagnostics") {
            Section("Log File") {
                SettingsRow(title: "spotter.log") {
                    HStack(spacing: Theme.Spacing.md) {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([log.fileURL])
                        }
                        .controlSize(.small)
                        Button("Copy Recent") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(log.transcript, forType: .string)
                        }
                        .controlSize(.small)
                        .disabled(log.entries.isEmpty)
                        Button("Clear") { log.clear() }
                            .controlSize(.small)
                            .disabled(log.entries.isEmpty)
                    }
                }
            }

            Section("Recent Events") {
                if log.entries.isEmpty {
                    SettingsRow(title: "Nothing logged yet") { EmptyView() }
                } else {
                    // Newest first — the entry being investigated is almost always the last one.
                    ForEach(Array(log.entries.reversed().prefix(100))) { entry in
                        DiagnosticsRow(entry: entry)
                    }
                }
            }
        }
    }
}

private struct DiagnosticsRow: View {
    let entry: AppLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                // The severity glyph is gone with every other leading icon, so the message itself carries the error tint.
                Text(entry.message)
                    .font(.callout)
                    .foregroundStyle(
                        entry.level == .error ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary)
                    )
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Spacing.sm) {
                    Text(entry.subsystem)
                        .font(Theme.Typography.keyCap)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
                                .fill(Theme.Colors.controlSurface)
                        )
                    Text(entry.date.formatted(date: .omitted, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
