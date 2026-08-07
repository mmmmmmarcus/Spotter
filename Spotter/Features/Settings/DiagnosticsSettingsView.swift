import AppKit
import SwiftUI

/// The in-app view of `AppLog`: recent events newest-first, with the log file one click away.
struct DiagnosticsSettingsView: View {
    @ObservedObject private var log = AppLog.shared

    var body: some View {
        SettingsPane(
            title: "Diagnostics",
            subtitle: "What went wrong and when — errors from every feature land here."
        ) {
            SettingsCard(header: "Log File") {
                SettingsRow(
                    title: "spotter.log",
                    subtitle: "Full history, capped at 512 KB with one rotation. Attach it to a bug report.",
                    systemImage: "doc.text",
                    tint: .orange
                ) {
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

            SettingsCard(header: "Recent Events") {
                if log.entries.isEmpty {
                    SettingsRow(
                        title: "Nothing logged yet",
                        subtitle: "Errors and notable events from this session will appear here.",
                        systemImage: "checkmark.circle",
                        tint: .secondary
                    ) { EmptyView() }
                } else {
                    // Newest first — the entry being investigated is almost always the last one.
                    ForEach(Array(log.entries.reversed().prefix(100).enumerated()), id: \.element.id)
                    { index, entry in
                        if index > 0 { SettingsDivider() }
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
            Image(systemName: entry.level == .error ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(entry.level == .error ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .frame(width: Theme.Size.settingsRowIcon)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(entry.message)
                    .font(.callout)
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
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }
}
