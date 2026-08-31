import AppKit
import SwiftUI

struct DashboardWidgetsView: View {
    @ObservedObject var store: DashboardWidgetsStore
    @ObservedObject var weather: DashboardWeatherStore
    @ObservedObject var music: DashboardMusicStore
    @ObservedObject var battery: DashboardDeviceBatteryStore
    @ObservedObject var fileInfo: DashboardFileInfoStore
    @EnvironmentObject private var core: AppCore
    /// The music card shows its controls only under the pointer; the cover is the card at rest.
    @State private var isHoveringMusic = false

    /// Every card shows; the only card that withholds itself is the one that would otherwise be an
    /// empty square claiming a reading it doesn't have — a Mac with nothing connected that reports a
    /// battery level is the normal case. File Info is deliberately *not* conditioned on there being a
    /// selection: it has a resting state, so it holds its place instead of shuffling the strip every
    /// time the Finder loses focus.
    private func isVisible(_ kind: DashboardWidgetKind) -> Bool {
        guard kind == .deviceBattery else { return true }
        return !battery.devices.isEmpty
    }

    /// Live-reorder state: hold a card briefly and it lifts and follows the pointer while the other
    /// cards slide out of its way, home-screen style. `liveOrder` is the working order for the
    /// gesture's duration; the store is written once, on release.
    @State private var dragKind: DashboardWidgetKind?
    @State private var dragStartSlot = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var liveOrder: [DashboardWidgetKind] = []

    /// One card plus one gap — the stride between slot origins.
    private static let slotSpan = Theme.Size.launcherDashboardHeight + Theme.Spacing.md

    @ViewBuilder
    var body: some View {
        let visible = store.orderedWidgets.filter(isVisible)
        if !visible.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                strip(visible: visible, now: context.date)
            }
            .onAppear {
                store.start()
                battery.start()
                music.start()
            }
            .onDisappear {
                store.stop()
                battery.stop()
                music.stop()
            }
        }
    }

    /// Slot layout instead of an HStack: every card owns a computed offset, so reordering is just
    /// slots changing hands under a spring while the lifted card keeps tracking the pointer.
    private func strip(visible: [DashboardWidgetKind], now: Date) -> some View {
        let order = dragKind == nil ? visible : liveOrder
        return ZStack(alignment: .topLeading) {
            ForEach(order, id: \.self) { kind in
                let slot = order.firstIndex(of: kind) ?? 0
                card(kind, now: now)
                    .scaleEffect(kind == dragKind ? 1.06 : 1)
                    .shadow(
                        color: .black.opacity(kind == dragKind ? 0.25 : 0), radius: 10, y: 4)
                    .offset(
                        x: kind == dragKind
                            ? Self.slotSpan * CGFloat(dragStartSlot) + dragTranslation
                            : Self.slotSpan * CGFloat(slot))
                    .zIndex(kind == dragKind ? 1 : 0)
                    .gesture(reorderGesture(for: kind, visible: visible))
            }
        }
        .animation(.spring(duration: 0.3), value: order)
        .animation(.spring(duration: 0.3), value: dragKind)
        .frame(height: Theme.Size.launcherDashboardHeight, alignment: .topLeading)
        // Every card is a square that hugs its width, so pin the strip to the list's leading edge.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Hold-then-drag, so a quick click still taps the card and a quick swipe still scrolls the list.
    private func reorderGesture(
        for kind: DashboardWidgetKind, visible: [DashboardWidgetKind]
    ) -> some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture())
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragKind == nil {
                    dragKind = kind
                    liveOrder = visible
                    dragStartSlot = visible.firstIndex(of: kind) ?? 0
                    dragTranslation = 0
                }
                guard dragKind == kind else { return }
                dragTranslation = drag?.translation.width ?? 0
                let target = targetSlot(count: liveOrder.count)
                if let current = liveOrder.firstIndex(of: kind), current != target {
                    liveOrder.remove(at: current)
                    liveOrder.insert(kind, at: target)
                }
            }
            .onEnded { _ in commitReorder(kind) }
    }

    private func targetSlot(count: Int) -> Int {
        let position = Self.slotSpan * CGFloat(dragStartSlot) + dragTranslation
        return min(max(Int((position / Self.slotSpan).rounded()), 0), count - 1)
    }

    /// Write the finished order once: the dragged card's final slot, translated from the visible
    /// list into the full order (a hidden card must keep its place without pinning its neighbors).
    private func commitReorder(_ kind: DashboardWidgetKind) {
        defer {
            withAnimation(.spring(duration: 0.3)) {
                dragKind = nil
                dragTranslation = 0
                liveOrder = []
            }
        }
        guard dragKind == kind, let slot = liveOrder.firstIndex(of: kind) else { return }
        let remaining = store.orderedWidgets.filter { $0 != kind }
        let destination: Int
        if let next = liveOrder.dropFirst(slot + 1).first,
            let nextIndex = remaining.firstIndex(of: next)
        {
            destination = nextIndex
        } else if slot > 0, let previousIndex = remaining.firstIndex(of: liveOrder[slot - 1]) {
            destination = previousIndex + 1
        } else {
            destination = 0
        }
        store.moveWidget(kind, to: destination)
    }

    @ViewBuilder
    private func card(_ kind: DashboardWidgetKind, now: Date) -> some View {
        switch kind {
        case .clock: clockCard(now: now)
        case .music: musicCard(now: now)
        case .deviceBattery: batteryCard()
        case .nextEvent: eventCard(now: now)
        case .fileInfo: DashboardFileInfoCard(snapshot: fileInfo.snapshot)
        }
    }

    private func cardTitle(_ text: String) -> some View { DashboardCardTitle(text) }

    /// The headline every card shares, one step below the title in the same rhythm. It is sized so
    /// a full reading fits the square's 96-point interior; the scale floor is the guard for the
    /// outliers rather than the normal case.
    private func cardHeadline(_ text: String) -> some View {
        Text(text)
            .font(.largeTitle)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
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

    /// Weather draws on the clock only once there is something real to draw: consent alone would put
    /// three empty corners on the face while the first reading is still in flight.
    private var showsWeather: Bool { weather.isEnabled && weather.reading != nil }

    /// The date's three parts, each in the clock's own time zone — a face abroad must not date
    /// itself from home. Uppercased so the curved corner labels read as bezel engraving.
    private func monthText(_ date: Date) -> String {
        corner(date, style: Date.FormatStyle.dateTime.month(.abbreviated))
    }

    private func dayText(_ date: Date) -> String {
        corner(date, style: Date.FormatStyle.dateTime.day())
    }

    private func weekdayText(_ date: Date) -> String {
        corner(date, style: Date.FormatStyle.dateTime.weekday(.abbreviated))
    }

    private func corner(_ date: Date, style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = store.clockTimeZone
        return date.formatted(style).uppercased()
    }

    private func clockAccessibilityLabel(_ now: Date) -> String {
        var parts = [formattedTime(now), formattedDate(now)]
        if showsWeather {
            parts.append(temperatureText)
            if let condition { parts.append(condition.description) }
        }
        return parts.joined(separator: ", ")
    }

    /// The artwork *is* the card — it fills the square edge to edge with the text and transport
    /// laid over a scrim, the way a player's now-playing tile reads. Without artwork the same layout
    /// runs over the ordinary card surface, so the strip keeps its rhythm either way.
    private func musicCard(now: Date) -> some View {
        let snapshot = music.snapshot
        return ZStack {
            musicArtwork
            // Without a cover there is nothing to show at rest: a coverless track is named and
            // nothing else, and with no track at all the card's own mark stands alone — the
            // resting words live in Settings and the accessibility label.
            if music.artwork == nil, !isHoveringMusic {
                if let title = snapshot.track?.title {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.md)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            if isHoveringMusic {
                // The scrim arrives with the controls: at rest the cover is the card, and nothing
                // dims it.
                Rectangle()
                    .fill(.black.opacity(0.45))
                    .transition(.opacity)
                musicTransport(isPlaying: snapshot.isPlaying)
                    .transition(.opacity)
            }
        }
        .frame(
            width: Theme.Size.launcherDashboardHeight,
            height: Theme.Size.launcherDashboardHeight)
        .dashboardCardSurface()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: Theme.Animation.quick)) {
                isHoveringMusic = hovering
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(musicAccessibilityLabel(snapshot))
    }

    /// The cover, edge to edge and undimmed — it *is* the card until the pointer arrives.
    @ViewBuilder private var musicArtwork: some View {
        if let artwork = music.artwork {
            Image(nsImage: artwork)
                .resizable()
                .scaledToFill()
                .frame(
                    width: Theme.Size.launcherDashboardHeight,
                    height: Theme.Size.launcherDashboardHeight)
                .clipped()
        }
    }

    /// Three controls, centred, shown only while the pointer is on the card. Always white: they sit
    /// on a scrim over artwork that could be any colour, never on the card surface.
    private func musicTransport(isPlaying: Bool) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            musicButton("backward.fill", label: "Previous Track") { music.previousTrack() }
            musicButton(isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? "Pause" : "Play") {
                music.playPause()
            }
            musicButton("forward.fill", label: "Next Track") { music.nextTrack() }
        }
    }

    private func musicButton(
        _ systemImage: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                // A full-cell hit target: a glyph alone leaves most of the control unclickable.
                .frame(width: Self.musicButtonSize, height: Self.musicButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .help(label)
        .accessibilityLabel(label)
    }


    private static let musicButtonSize: CGFloat = 22

    private func musicAccessibilityLabel(_ snapshot: DashboardMusicSnapshot) -> String {
        guard let track = snapshot.track else {
            return DashboardMusicEngine.restingLine(isRunning: snapshot.isRunning)
        }
        let state = snapshot.isPlaying ? "Playing" : "Paused"
        return "\(state): \(track.title), \(DashboardMusicEngine.subtitle(for: track))"
    }

    private static let batteryGaugeSpacing = Theme.Spacing.md
    /// Ring thickness and glyph size as fractions of the gauge, so a lone full-square gauge and four
    /// quarter-square ones read as the same object at different scales.
    private static let batteryGaugeStrokeRatio: CGFloat = 0.1
    private static let batteryGaugeIconRatio: CGFloat = 0.34

    /// Title-free and filled edge to edge, like the clock: the grid of rings *is* the card, and a
    /// heading would cost a row of gauge. Exact levels live in Settings and the accessibility label —
    /// at this size a ring answers "does anything need charging" better than four small numbers.
    ///
    /// The grid is always four slots ranged from the top-left corner, empty rings included: a device
    /// then keeps its place as others connect and disconnect, instead of the whole card re-centring
    /// and every ring changing size under the same reading.
    private func batteryCard() -> some View {
        let slots = DashboardDeviceBatteryEngine.gaugeSlots(
            for: battery.devices, limit: DashboardDeviceBatteryEngine.gaugeSlotLimit)
        let interior = Theme.Size.launcherDashboardHeight - 2 * Theme.Spacing.lg
        let diameter = DashboardDeviceBatteryEngine.gaugeDiameter(
            slotCount: slots.count, interior: interior, spacing: Self.batteryGaugeSpacing)
        let columns = DashboardDeviceBatteryEngine.gaugeColumns(slotCount: slots.count)
        return VStack(alignment: .leading, spacing: Self.batteryGaugeSpacing) {
            // Keyed by position: a row is a group of gauges, not an identity of its own.
            ForEach(
                Array(
                    DashboardDeviceBatteryEngine.gaugeRows(for: slots, columns: columns)
                        .enumerated()), id: \.offset
            ) { _, row in
                HStack(spacing: Self.batteryGaugeSpacing) {
                    ForEach(row) { slot in
                        batteryGauge(slot, diameter: diameter)
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        // Square like every other card, and ranged top-left inside it rather than centred.
        .frame(
            width: Theme.Size.launcherDashboardHeight,
            height: Theme.Size.launcherDashboardHeight, alignment: .topLeading)
        .dashboardCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(DashboardDeviceBatteryEngine.accessibilityLabel(for: battery.devices))
    }

    /// One ring: a faint full track with the level swept clockwise from twelve over it, the device's
    /// SF Symbol in the middle. Red under the low threshold, which is the whole point of the glance.
    /// A charging device breaks the ring at twelve for a bolt to sit in.
    private func batteryGauge(_ slot: DeviceBatterySlot, diameter: CGFloat) -> some View {
        let stroke = diameter * Self.batteryGaugeStrokeRatio
        let isCharging = slot.isCharging
        return ZStack {
            ZStack {
                Circle()
                    .stroke(Theme.Colors.controlSurface, lineWidth: stroke)
                if case .device(let device) = slot {
                    Circle()
                        .trim(
                            from: 0, to: DashboardDeviceBatteryEngine.gaugeFraction(device.percent)
                        )
                        .stroke(
                            DashboardDeviceBatteryEngine.isLow(device.percent) ? Color.red : .green,
                            style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                        // `trim` starts at three o'clock; a level reads from the top.
                        .rotationEffect(.degrees(-90))
                }
            }
            // Punched rather than drawn over: the bolt sits on the arc it reports, and a translucent
            // card fill behind it would let the green through instead of clearing a notch for it.
            .compositingGroup()
            .overlay(alignment: .top) {
                if isCharging {
                    Circle()
                        .frame(width: stroke * 2.6, height: stroke * 2.6)
                        .offset(y: -stroke * 1.3)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()

            if isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: stroke * 1.9))
                    .frame(width: stroke * 2.6, height: stroke * 2.6)
                    .offset(y: -diameter / 2)
            }

            switch slot {
            case .device(let device):
                Image(systemName: device.kind.systemImage)
                    .font(.system(size: diameter * Self.batteryGaugeIconRatio))
            case .overflow(let count):
                Text("+\(count)")
                    .font(.system(size: diameter * Self.batteryGaugeIconRatio, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            // A slot with nothing in it is the track alone — a glyph would name a device that isn't
            // there, and the empty ring's job is only to hold the grid's shape.
            case .empty:
                EmptyView()
            }
        }
        .frame(width: diameter, height: diameter)
    }

    /// A spelled-out tally. The longest realistic line ("123,456 mouse clicks") overruns the square's
    /// 96 points, so it shrinks rather than truncating the word that says what was counted.
    private func countLine(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }

    /// How far the dial is held off the card's edge, leaving the lane the complications ride in.
    /// Every other card keeps a uniform `md` margin; this one spends its whole square, because the
    /// complications *are* its bezel and the dial is what the margin would otherwise shrink.
    private static let clockFaceInset: CGFloat = 6

    /// A watch face: the analog dial with its complications set along the bezel — the date split
    /// across three corners (month top-right, day bottom-left, weekday bottom-right) and, when
    /// weather is on and a reading has landed, the temperature top-left with the condition glyph
    /// inside the dial above the six. A corner with nothing known stays empty rather than drawing a
    /// placeholder, so the clock alone is still a clock.
    private func clockCard(now: Date) -> some View {
        ZStack {
            AnalogClockFace(
                timeZone: store.clockTimeZone,
                conditionSymbol: showsWeather ? condition?.symbolName : nil)
                .padding(Self.clockFaceInset)
            ClockComplicationRing(
                topLeft: showsWeather ? temperatureText : nil,
                topRight: monthText(now),
                bottomLeft: dayText(now),
                bottomRight: weekdayText(now),
                color: Theme.Colors.textSecondary)
        }
        .frame(
            width: Theme.Size.launcherDashboardHeight,
            height: Theme.Size.launcherDashboardHeight)
        .dashboardCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(clockAccessibilityLabel(now))
    }

    /// Only what is next, and the event itself is the headline — a "Up Next" title would spend the
    /// card's best line saying what the card obviously is. The date left here for the clock's corner
    /// too. The title is ranged from the top-left and the time pinned to the bottom-left, so a
    /// one-line title and a three-line one put the time in the same place. Without calendar access
    /// the access state takes the headline's slot, rather than the card going missing.
    private func eventCard(now: Date) -> some View {
        let event = store.calendarAccess == .fullAccess ? store.nextEvent : nil
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            eventHeadline(now: now)
            Spacer(minLength: 0)
            if let event {
                Text(eventTime(event, now: now))
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(
            width: Theme.Size.launcherDashboardHeight,
            height: Theme.Size.launcherDashboardHeight, alignment: .topLeading)
        .dashboardCardSurface()
        // The card is a door to the real thing: clicking it opens Calendar. The access-state buttons consume their own clicks first.
        .contentShape(Rectangle())
        .onTapGesture { openCalendarApp() }
    }

    private func openCalendarApp() {
        core.hidePalette(restoreFocus: false)
        guard
            let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.iCal")
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @ViewBuilder
    private func eventHeadline(now: Date) -> some View {
        switch store.calendarAccess {
        case .fullAccess:
            if let event = store.nextEvent {
                // Three lines at this size fits a long title without shrinking it to unreadable —
                // the scale floor is the guard for the outliers rather than the normal case.
                Text(event.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                footerNote("No events ahead")
            }
        case .notDetermined, .writeOnly:
            if store.isRequestingCalendarAccess {
                footerNote("Waiting…")
            } else {
                footerButton("Allow Calendar") { store.requestCalendarAccess() }
            }
        case .denied:
            footerButton("Open Settings") { Permissions.openCalendarSettings() }
        case .restricted:
            footerNote("Calendar restricted")
        }
    }

    private func footerNote(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Theme.Colors.textSecondary)
            .lineLimit(2)
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.link)
            .controlSize(.small)
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    /// The card already shows today's date, so a same-day event needs only its time.
    private func eventTime(_ event: DashboardEvent, now: Date) -> String {
        if event.isAllDay { return "All day" }
        let time = event.startDate.formatted(.dateTime.hour().minute())
        guard !Calendar.current.isDate(event.startDate, inSameDayAs: now) else { return time }
        return "\(event.startDate.formatted(.dateTime.weekday(.abbreviated))) · \(time)"
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

/// The one title style every card shares, so the strip reads as one row rather than five designs.
/// Uppercased here rather than at each call site — a file's kind arrives as the Finder words it.
private struct DashboardCardTitle: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.localizedUppercase)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.Colors.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// Square like every other card: the kind in the title slot, the item's own Finder icon as the
/// middle, then what it is called and how big it is. With nothing selected it rests on a generic
/// glyph rather than leaving the strip — a card that came and went couldn't be relied on to be there.
private struct DashboardFileInfoCard: View {
    let snapshot: DashboardFileInfoSnapshot

    private static let iconSize: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            DashboardCardTitle(snapshot.kindLine)
            Spacer(minLength: 0)
            icon
                .frame(width: Self.iconSize, height: Self.iconSize)
            Spacer(minLength: 0)
            // Truncated in the middle: the extension is half of what the card is reporting.
            Text(snapshot.nameLine)
                .font(.caption2.weight(.medium))
                .foregroundStyle(snapshot.isEmpty ? Theme.Colors.textSecondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if !snapshot.sizeLine.isEmpty {
                Text(snapshot.sizeLine)
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(
            width: Theme.Size.launcherDashboardHeight,
            height: Theme.Size.launcherDashboardHeight)
        .dashboardCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(snapshot.accessibilityLabel)
    }

    @ViewBuilder
    private var icon: some View {
        if let path = snapshot.iconPath {
            DashboardFileIcon(path: path)
        } else {
            Image(systemName: "doc")
                .font(.system(size: Self.iconSize * 0.8, weight: .light))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}

/// The selected item's own Finder icon, warm from `IconCache` when the launcher has drawn it before.
private struct DashboardFileIcon: View {
    let path: String
    @State private var image: NSImage?

    init(path: String) {
        self.path = path
        _image = State(initialValue: IconCache.cached(forFile: path))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                    .fill(Theme.Colors.controlSurface)
            }
        }
        // Reloaded on every path change rather than only when empty: the selection moves from file to
        // file, and a `nil`-guard would pin the first icon to every later one.
        .task(id: path) {
            if let cached = IconCache.cached(forFile: path) {
                image = cached
                return
            }
            image = await IconCache.loadAsync(forFile: path)
        }
    }
}

/// The clock's corner complications, set along the bezel the way a watch face carries them: each
/// label is laid out character by character around one circle, so it curves with the dial instead of
/// sitting square in a corner. The two bottom labels run the other way round and are turned over, or
/// they would read upside down.
private struct ClockComplicationRing: View {
    var topLeft: String?
    var topRight: String?
    var bottomLeft: String?
    var bottomRight: String?
    let color: Color

    /// Degrees clockwise from 12 o'clock, matching the face's own angle convention.
    private static let topLeftAngle = 315.0
    private static let topRightAngle = 45.0
    private static let bottomLeftAngle = 225.0
    private static let bottomRightAngle = 135.0
    /// Small enough that the longest label ("100°F") still spans well under its quadrant here.
    private static let font = Font.system(size: 9, weight: .medium)
    /// Negative on purpose: the labels ride the corners, where the square reaches furthest past its
    /// inscribed circle, so the arc is drawn wider than the card and the type still lands inside the
    /// rounding. Past about -12 the ends of the longest label start clipping the straight edges.
    private static let ringInset: CGFloat = -4

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2 - Self.ringInset
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                draw(topLeft, at: Self.topLeftAngle, flipped: false,
                    context: &context, center: center, radius: radius)
                draw(topRight, at: Self.topRightAngle, flipped: false,
                    context: &context, center: center, radius: radius)
                draw(bottomLeft, at: Self.bottomLeftAngle, flipped: true,
                    context: &context, center: center, radius: radius)
                draw(bottomRight, at: Self.bottomRightAngle, flipped: true,
                    context: &context, center: center, radius: radius)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// Sets one string on the arc, centred on `centerAngle`. Each glyph is placed at the angle its
    /// own width has reached and turned to stand on the tangent there; resolving per character is
    /// what costs the string its kerning, which is the usual trade for type on a curve.
    private func draw(
        _ text: String?, at centerAngle: Double, flipped: Bool,
        context: inout GraphicsContext, center: CGPoint, radius: CGFloat
    ) {
        guard let text, !text.isEmpty, radius > 0 else { return }
        let glyphs = text.map { character -> (text: GraphicsContext.ResolvedText, width: CGFloat) in
            let resolved = context.resolve(
                Text(String(character)).font(Self.font).foregroundStyle(color))
            return (resolved, resolved.measure(in: CGSize(width: 200, height: 200)).width)
        }
        // Arc length over radius is the angle it subtends, so the whole string spans `span` degrees.
        let span = degrees(glyphs.reduce(0) { $0 + $1.width }, radius: radius)
        var travelled: CGFloat = 0
        for glyph in glyphs {
            let reached = degrees(travelled + glyph.width / 2, radius: radius)
            // Flipped labels run anticlockwise, which is what keeps them reading left to right along
            // the bottom of the circle.
            let angle = flipped
                ? centerAngle + span / 2 - reached
                : centerAngle - span / 2 + reached
            let radians = angle * .pi / 180
            context.drawLayer { layer in
                layer.translateBy(
                    x: center.x + radius * sin(radians), y: center.y - radius * cos(radians))
                layer.rotate(by: .degrees(flipped ? angle + 180 : angle))
                layer.draw(glyph.text, at: .zero, anchor: .center)
            }
            travelled += glyph.width
        }
    }

    private func degrees(_ arcLength: CGFloat, radius: CGFloat) -> Double {
        Double(arcLength / radius) * 180 / .pi
    }
}

/// A Clock-app-style face drawn in the palette's alpha ramp: ramp ticks, numerals and hands over the card fill, with an orange second hand — no opaque dial.
private struct AnalogClockFace: View {
    let timeZone: TimeZone
    var conditionSymbol: String?

    /// Where the weather glyph sits, as a fraction of the dial's radius straight down from the hub —
    /// clear of the hands' hub and short of the six, the slot a watch face keeps for it.
    private static let complicationRadius: CGFloat = 0.44
    private static let complicationSize: CGFloat = 11

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2
            ZStack {
                // Its own timeline, at the display's refresh rate: the strip's one-second tick would
                // step the second hand instead of sweeping it, and raising that cadence would redraw
                // every other card too.
                TimelineView(.animation) { context in
                    face(
                        angles: DashboardWidgetsEngine.clockHandAngles(
                            for: context.date, timeZone: timeZone))
                }
                if let conditionSymbol {
                    Image(systemName: conditionSymbol)
                        // Monochrome, like every other glyph on the strip — multicolor was the one
                        // card that pulled Apple's own palette in instead of the app's.
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: Self.complicationSize))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .offset(y: radius * Self.complicationRadius)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func face(angles: ClockHandAngles) -> some View {
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

            // Only the quarters are numbered; the tick ring already says where the rest are, and a
            // full set of twelve crowds the glyph slot above the six.
            for hour in stride(from: 3, through: 12, by: 3) {
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
                with: .color(.orange), style: StrokeStyle(lineWidth: 1.25, lineCap: .round))

            // Same orange as the hand it caps — the two read as one element, so they can't diverge.
            let hub = radius * 0.06
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)),
                with: .color(.orange))
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
