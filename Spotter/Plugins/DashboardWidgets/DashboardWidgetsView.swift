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
                                width: Theme.Size.launcherDashboardClockSize,
                                height: Theme.Size.launcherDashboardClockSize)
                    }
                    if store.isWidgetEnabled(.nextEvent) {
                        eventCard(now: context.date)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: Theme.Size.launcherDashboardHeight)
            }
            .onAppear { store.start() }
            .onDisappear { store.stop() }
        }
    }

    private func timeCard(now: Date) -> some View {
        DashboardClockCard(
            angles: DashboardWidgetsEngine.clockAngles(
                at: now, calendar: .autoupdatingCurrent, timeZone: store.clockTimeZone),
            accessibilityValue: formattedTime(now))
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

    private func eventTime(_ event: DashboardEvent, now: Date) -> String {
        if event.isAllDay { return "All day" }
        let day = Calendar.current.isDate(event.startDate, inSameDayAs: now)
            ? "Today" : event.startDate.formatted(.dateTime.weekday(.abbreviated))
        return "\(day) · \(event.startDate.formatted(.dateTime.hour().minute()))"
    }

    private func formattedTime(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = store.clockTimeZone
        return date.formatted(style)
    }
}

private struct DashboardClockCard: View {
    let angles: DashboardClockAngles
    let accessibilityValue: String

    var body: some View {
        AnalogClockFace(angles: angles)
            .frame(
                width: Theme.Size.launcherDashboardClockFace,
                height: Theme.Size.launcherDashboardClockFace)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dashboardWidgetSurface()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Time")
            .accessibilityValue(accessibilityValue)
    }
}

private struct AnalogClockFace: View {
    let angles: DashboardClockAngles

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = side / 2

            let face = Path(ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: side, height: side))
            context.fill(face, with: .color(Theme.Colors.surfaceGlow))
            context.stroke(face, with: .color(Theme.Colors.cardStroke), lineWidth: 1)

            for index in 0..<12 {
                let isQuarter = index.isMultiple(of: 3)
                var tick = Path()
                tick.move(to: point(
                    from: center,
                    radius: radius * (isQuarter ? 0.72 : 0.78),
                    degrees: Double(index) * 30))
                tick.addLine(to: point(
                    from: center, radius: radius * 0.88,
                    degrees: Double(index) * 30))
                context.stroke(
                    tick,
                    with: .color(isQuarter ? Theme.Colors.textSecondary : Theme.Colors.textTertiary),
                    style: StrokeStyle(
                        lineWidth: side * (isQuarter ? 0.045 : 0.028),
                        lineCap: .round))
            }

            drawHand(
                in: &context, center: center, radius: radius * 0.48,
                degrees: angles.hour, lineWidth: side * 0.050, color: .primary)
            drawHand(
                in: &context, center: center, radius: radius * 0.68,
                degrees: angles.minute, lineWidth: side * 0.036, color: .primary)
            drawHand(
                in: &context, center: center, radius: radius * 0.78,
                tail: radius * 0.16, degrees: angles.second,
                lineWidth: side * 0.014, color: .orange)

            let hubSize = side * 0.075
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - hubSize / 2, y: center.y - hubSize / 2,
                    width: hubSize, height: hubSize)),
                with: .color(.orange))
            let pinSize = side * 0.028
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - pinSize / 2, y: center.y - pinSize / 2,
                    width: pinSize, height: pinSize)),
                with: .color(Theme.Colors.cardFill))
        }
    }

    private func drawHand(
        in context: inout GraphicsContext, center: CGPoint, radius: CGFloat,
        tail: CGFloat = 0, degrees: Double, lineWidth: CGFloat, color: Color
    ) {
        var path = Path()
        path.move(to: point(from: center, radius: -tail, degrees: degrees))
        path.addLine(to: point(from: center, radius: radius, degrees: degrees))
        context.stroke(
            path, with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }

    private func point(from center: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let radians = (degrees - 90) * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius)
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
        .dashboardWidgetSurface()
    }
}

private extension View {
    func dashboardWidgetSurface() -> some View {
        self
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
