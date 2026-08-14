import SwiftUI

struct DashboardWidgetsView: View {
    @ObservedObject var store: DashboardWidgetsStore
    @ObservedObject var weather: DashboardWeatherStore

    /// The weather card has no widget-kind flag of its own: consent plus a chosen city *is* its
    /// enable state, so there is no second switch to drift out of sync with the network gate.
    private var showsWeather: Bool { weather.isEnabled && weather.city != nil }

    @ViewBuilder
    var body: some View {
        if store.hasEnabledWidgets || showsWeather {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: Theme.Spacing.md) {
                    if store.isWidgetEnabled(.clock) {
                        clockCard(now: context.date)
                    }
                    if showsWeather {
                        weatherCard()
                    }
                    if store.isWidgetEnabled(.nextEvent) {
                        eventCard(now: context.date)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: Theme.Size.launcherDashboardHeight)
                // Lone square cards hug their width, so pin the strip to the list's leading edge.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { store.start() }
            .onDisappear { store.stop() }
        }
    }

    /// Square, like the clock: city, the temperature as the headline, then the condition.
    private func weatherCard() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(weather.snapshot?.cityName ?? weather.city?.name ?? "")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
            Text(temperatureText)
                .font(.largeTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            // No floor: the condition may wrap to two lines, and the gap is the first thing that should give.
            Spacer(minLength: 0)
            Image(systemName: condition?.symbolName ?? "cloud.fill")
                .symbolRenderingMode(.multicolor)
                .font(.title3)
            Text(condition?.description ?? "Updating…")
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.lg)
        .frame(
            width: Theme.Size.launcherDashboardHeight,
            alignment: .topLeading)
        .dashboardCardSurface()
    }

    private var condition: WeatherCondition? {
        weather.reading.map {
            DashboardWeatherEngine.condition(forWeatherCode: $0.weatherCode, isDay: $0.isDay)
        }
    }

    /// An em dash until the first reading lands, so the card never implies a temperature it doesn't have.
    private var temperatureText: String {
        guard let reading = weather.reading else { return "—" }
        return DashboardWeatherEngine.formattedTemperature(
            celsius: reading.temperatureCelsius, unit: weather.unit)
    }

    /// The clock is a square, title-free analog face; VoiceOver still reads the exact time and date.
    private func clockCard(now: Date) -> some View {
        AnalogClockFace(
            angles: DashboardWidgetsEngine.clockHandAngles(for: now, timeZone: store.clockTimeZone))
            .padding(Theme.Spacing.md)
            .frame(width: Theme.Size.launcherDashboardHeight)
            .dashboardCardSurface()
            .accessibilityLabel("\(formattedTime(now)), \(formattedDate(now))")
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

    private func formattedDate(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime
            .weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = store.clockTimeZone
        return date.formatted(style)
    }
}

/// A Clock-app-style face drawn in the palette's alpha ramp: ramp ticks, numerals and hands over the card fill, with the brand violet as the second hand — no opaque dial.
private struct AnalogClockFace: View {
    let angles: ClockHandAngles

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            for tick in 0..<60 {
                let isHour = tick.isMultiple(of: 5)
                context.stroke(
                    radial(
                        center: center, angle: .degrees(Double(tick) * 6),
                        from: radius * (isHour ? 0.87 : 0.93), to: radius * 0.99),
                    with: .color(isHour ? .primary : Theme.Colors.textTertiary),
                    style: StrokeStyle(lineWidth: isHour ? 2 : 1, lineCap: .round))
            }

            for hour in 1...12 {
                context.draw(
                    context.resolve(Text("\(hour)").font(.caption2.weight(.semibold))),
                    at: point(center: center, angle: .degrees(Double(hour) * 30), radius: radius * 0.70))
            }

            context.stroke(
                radial(center: center, angle: .degrees(angles.hour), from: -radius * 0.12, to: radius * 0.50),
                with: .color(.primary), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            context.stroke(
                radial(center: center, angle: .degrees(angles.minute), from: -radius * 0.12, to: radius * 0.74),
                with: .color(.primary), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            context.stroke(
                radial(center: center, angle: .degrees(angles.second), from: -radius * 0.20, to: radius * 0.80),
                with: .color(Theme.Colors.brand), style: StrokeStyle(lineWidth: 1.25, lineCap: .round))

            let hub = radius * 0.06
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)),
                with: .color(Theme.Colors.brand))
        }
    }

    /// A stroke segment along `angle` (degrees clockwise from 12), spanning `from`→`to` out of `center`; a negative `from` is the hand's counterweight tail.
    private func radial(center: CGPoint, angle: Angle, from: CGFloat, to: CGFloat) -> Path {
        var path = Path()
        path.move(to: point(center: center, angle: angle, radius: from))
        path.addLine(to: point(center: center, angle: angle, radius: to))
        return path
    }

    private func point(center: CGPoint, angle: Angle, radius: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + radius * sin(angle.radians),
            y: center.y - radius * cos(angle.radians))
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
        .dashboardCardSurface()
    }
}

extension View {
    /// The dashboard cards' shared surface — the same `cardFill`/`cardStroke` language as calculator cards.
    fileprivate func dashboardCardSurface() -> some View {
        background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
    }
}
