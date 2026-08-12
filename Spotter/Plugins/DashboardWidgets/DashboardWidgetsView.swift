import SwiftUI

struct DashboardWidgetsView: View {
    @ObservedObject var store: DashboardWidgetsStore

    @ViewBuilder
    var body: some View {
        if store.hasEnabledWidgets {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: Theme.Spacing.md) {
                    if store.isWidgetEnabled(.clock) {
                        timeCard(now: context.date)
                            .frame(
                                minWidth: Theme.Size.launcherDashboardTimeWidth,
                                maxWidth: compactWidgetMaximumWidth(
                                    Theme.Size.launcherDashboardTimeWidth))
                    }
                    if store.isWidgetEnabled(.nextEvent) {
                        eventCard(now: context.date)
                            .frame(maxWidth: .infinity)
                    }
                    if store.isWidgetEnabled(.claudeCode) {
                        usageCard(
                            title: "CLAUDE CODE", systemImage: "sparkles",
                            usage: store.claudeUsage, now: context.date)
                            .frame(
                                minWidth: Theme.Size.launcherDashboardUsageWidth,
                                maxWidth: compactWidgetMaximumWidth(
                                    Theme.Size.launcherDashboardUsageWidth))
                    }
                    if store.isWidgetEnabled(.codex) {
                        usageCard(
                            title: "CODEX", systemImage: "terminal",
                            usage: store.codexUsage, now: context.date)
                            .frame(
                                minWidth: Theme.Size.launcherDashboardUsageWidth,
                                maxWidth: compactWidgetMaximumWidth(
                                    Theme.Size.launcherDashboardUsageWidth))
                    }
                }
                .frame(height: Theme.Size.launcherDashboardHeight)
            }
            .onAppear { store.start() }
            .onDisappear { store.stop() }
        }
    }

    private func timeCard(now: Date) -> some View {
        DashboardWidgetCard(title: "TIME", systemImage: "clock") {
            Spacer(minLength: Theme.Spacing.xs)
            Text(formattedTime(now))
                .font(.title2.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(formattedDate(now))
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func eventCard(now: Date) -> some View {
        DashboardWidgetCard(title: "UP NEXT", systemImage: "calendar.badge.clock") {
            Spacer(minLength: Theme.Spacing.xs)
            switch store.calendarAccess {
            case .fullAccess:
                if let event = store.nextEvent {
                    Text(event.title)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    Text(eventTime(event, now: now))
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                    Text(event.calendarTitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                } else {
                    Text("No upcoming events")
                        .font(.body.weight(.medium))
                    Text("No events in the next year.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            case .notDetermined, .writeOnly:
                Text("Calendar access is off")
                    .font(.body.weight(.medium))
                if store.isRequestingCalendarAccess {
                    Text("Waiting for permission…")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    Button("Allow Calendar") { store.requestCalendarAccess() }
                        .buttonStyle(.link)
                        .controlSize(.small)
                }
            case .denied:
                Text("Calendar unavailable")
                    .font(.body.weight(.medium))
                Button("Open Settings") { Permissions.openCalendarSettings() }
                    .buttonStyle(.link)
                    .controlSize(.small)
            case .restricted:
                Text("Calendar restricted")
                    .font(.body.weight(.medium))
                Text("Managed by this Mac's policy.")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func usageCard(
        title: String, systemImage: String, usage: DashboardUsageSnapshot?, now: Date
    ) -> some View {
        DashboardWidgetCard(title: title, systemImage: systemImage) {
            Spacer(minLength: Theme.Spacing.xs)
            if let usage, let window = usage.currentWindows(at: now).first
            {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xxs) {
                    Text(window.usedPercent, format: .number.precision(.fractionLength(0)))
                        .font(.title2.weight(.semibold).monospacedDigit())
                    Text("%")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Text("\(window.name) used")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                if let other = usage.currentWindows(at: now).first(where: { $0 != window })
                {
                    Text("\(other.name) \(Int(other.usedPercent.rounded()))%")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                } else if let reset = window.resetsAt {
                    Text(reset, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            } else {
                Text("No current data")
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(usage == nil ? "Use the CLI first." : "Cached data expired.")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .help(usageHelp(usage))
    }

    private func eventTime(_ event: DashboardEvent, now: Date) -> String {
        if event.isAllDay { return "All day" }
        let day = Calendar.current.isDate(event.startDate, inSameDayAs: now)
            ? "Today" : event.startDate.formatted(.dateTime.weekday(.abbreviated))
        return "\(day) · \(event.startDate.formatted(.dateTime.hour().minute()))"
    }

    private func usageHelp(_ usage: DashboardUsageSnapshot?) -> String {
        guard let usage else {
            return "No local usage metadata found. Spotter never reads conversation content."
        }
        let source = switch usage.source {
        case .codexSession: "Codex session metadata"
        case .codexBarSnapshot: "CodexBar widget cache"
        case .codexBarHistory: "CodexBar history cache"
        }
        return "\(source), updated \(usage.updatedAt.formatted(date: .abbreviated, time: .shortened))."
    }

    private func compactWidgetMaximumWidth(_ fixedWidth: CGFloat) -> CGFloat {
        store.isWidgetEnabled(.nextEvent) ? fixedWidth : .infinity
    }

    private func formattedTime(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = store.clockTimeZone
        return date.formatted(style)
    }

    private func formattedDate(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime
            .weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = store.clockTimeZone
        return date.formatted(style)
    }
}

private struct DashboardWidgetCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.Colors.textSecondary)
            content
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
    }
}
