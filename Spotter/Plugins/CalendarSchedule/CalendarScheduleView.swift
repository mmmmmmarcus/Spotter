import SwiftUI

struct CalendarScheduleView: View {
    @EnvironmentObject private var core: AppCore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: CalendarScheduleStore
    @ObservedObject var dashboard: DashboardWidgetsStore
    let context: PluginPaletteCanvasContext
    @State private var scrollPosition = ScrollPosition(y: 0)
    @State private var viewport = CGRect.zero
    @State private var hoveredEventID: String?
    @State private var positionedPeriod: TimelinePeriod?
    @State private var transitionPeriod: TimelinePeriod?
    @State private var transitionProgress: CGFloat = 1
    @State private var transitionDirection: CGFloat = 1

    private struct TimelinePeriod: Equatable {
        let mode: ScheduleViewMode
        let date: Date
    }

    private struct PositionRequest: Equatable {
        let period: TimelinePeriod
        let isLoading: Bool
        var reduceMotion = false
        var isPositioned = true
        var viewportHeight: CGFloat = 0
    }
    private var events: [DashboardEvent] { model.events }
    private var days: [Date] { model.days }
    private var hourHeight: CGFloat {
        ScheduleViewport.hourHeight(base: Theme.Size.scheduleHourHeight, zoom: model.zoom)
    }
    private var interactionAnimation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.2) }

    private var pagePeriod: TimelinePeriod {
        TimelinePeriod(mode: model.mode,
            date: model.calendar.dateInterval(of: model.mode.component, for: model.date)?.start ?? model.date)
    }

    private var pageProgress: CGFloat {
        if reduceMotion { return 1 }
        return transitionPeriod == nil || transitionPeriod == pagePeriod ? transitionProgress : 0
    }

    private var isPagePositioned: Bool {
        model.mode == .month || model.detailID != nil
            || positionedPeriod == TimelinePeriod(mode: model.mode, date: model.date)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            if model.mode == .month, model.detailID == nil {
                Text(model.date.formatted(.dateTime.month(.wide).year()))
                    .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Theme.Size.scheduleToolbarHeight)
            }
            if let id = model.detailID, let event = model.events.first(where: { rowID($0) == id }) {
                detail(event)
            } else if model.mode == .month {
                month
            } else {
                timeline
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.sm)
        .opacity(pageProgress)
        .offset(x: (1 - pageProgress) * transitionDirection * Theme.Spacing.md)
        .overlay(alignment: .bottomTrailing) {
            if model.isLoading { ProgressView().controlSize(.small).padding(Theme.Spacing.md) }
        }
        .overlayPreferenceValue(ScheduleEventBounds.self) { anchors in
            GeometryReader { geometry in
                if let id = model.peekID, let anchor = anchors[id],
                   let event = CalendarSchedulePlugin.event(store: model, itemID: id) {
                    peek(event, id: id, source: geometry[anchor], size: geometry.size)
                }
            }
        }
        .animation(interactionAnimation, value: model.peekID)
        .onChange(of: context.query) {
            model.peekID = nil
            model.isNavigatingEvents = false
            hoveredEventID = nil
        }
        .onChange(of: core.palette.menuOpen) {
            if core.palette.menuOpen { model.peekID = nil; hoveredEventID = nil }
        }
        .onChange(of: context.selectedID) { model.peekID = nil }
        .onChange(of: model.date) { hoveredEventID = nil }
        .onChange(of: model.mode) { hoveredEventID = nil }
        .onChange(of: model.detailID) { hoveredEventID = nil }
        .task(id: hoveredEventID) {
            guard let id = hoveredEventID else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard !Task.isCancelled, model.detailID == nil, !core.palette.menuOpen else { return }
            model.peekID = id
        }
        .onAppear { if !model.isLoading { model.refresh() } }
        .onChange(of: model.mode) { core.palette.focusToken = UUID() }
        .onChange(of: model.date) { core.palette.focusToken = UUID() }
        .onChange(of: dashboard.preferences) { model.refresh() }
        .onChange(of: dashboard.calendarAccess) { model.refresh() }
        .task(id: PositionRequest(period: pagePeriod, isLoading: model.isLoading,
                                 reduceMotion: reduceMotion, isPositioned: isPagePositioned)) {
            await animatePageSwitch()
        }
    }

    private func animatePageSwitch() async {
        let period = pagePeriod
        guard let previous = transitionPeriod else {
            transitionPeriod = period
            return
        }
        if reduceMotion || previous != period {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                transitionDirection = period.date < previous.date
                    || (period.date == previous.date && period.mode == .week) ? -1 : 1
                transitionPeriod = period
                transitionProgress = reduceMotion ? 1 : 0
            }
        }
        guard !model.isLoading, isPagePositioned, transitionProgress == 0 else { return }
        // Let the timeline establish its scroll position before revealing the new period.
        await Task.yield()
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: Theme.Animation.pageSwitch)) {
            transitionProgress = 1
        }
    }

    private func rowID(_ event: DashboardEvent) -> String { CalendarSchedulePlugin.rowID(for: event) }
    private func rowID(_ event: DashboardEvent, on day: Date) -> String {
        ScheduleEventPosition.id(eventID: rowID(event), day: day)
    }
    private func onDay(_ day: Date) -> [DashboardEvent] {
        events.filter {
            ScheduleLayout.overlaps(start: $0.startDate, end: $0.endDate, day: day, calendar: model.calendar)
        }
    }

    private func accent(_ event: DashboardEvent) -> Color {
        let index = event.calendarTitle.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % NoteTint.selectable.count }
        return Theme.Colors.noteTintAccent(NoteTint.selectable[index])
    }

    private func dayLabel(_ day: Date, weekday: Bool) -> some View {
        Text(day.formatted(weekday ? .dateTime.weekday(.abbreviated).day() : .dateTime.day()))
            .font(.system(size: 11, weight: model.calendar.isDateInToday(day) ? .bold : .medium))
            .foregroundStyle(model.calendar.isDateInToday(day) ? Theme.Colors.noteTintAccent(.red) : .primary)
    }

    private var month: some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: 0) {
                ForEach(Array(days.prefix(7)), id: \.self) { day in
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            GeometryReader { geometry in
                VStack(spacing: Theme.Spacing.xxs) {
                    ForEach(0..<6, id: \.self) { week in
                        HStack(spacing: Theme.Spacing.xxs) {
                            ForEach(Array(days.dropFirst(week * 7).prefix(7)), id: \.self) { day in
                                monthCell(day)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: max(0, (geometry.size.height - Theme.Spacing.xxs * 5) / 6))
                            }
                        }
                    }
                }
            }
        }
    }

    private func monthCell(_ day: Date) -> some View {
        let dayEvents = onDay(day)
        let matchingEvents = dayEvents.filter { model.matches($0, query: context.query) }
        let previewEvents = matchingEvents.isEmpty ? dayEvents : matchingEvents
        let selected = context.selectedID == CalendarSchedulePlugin.dayID(day)
        let inMonth = model.calendar.isDate(day, equalTo: model.date, toGranularity: .month)
        return Button { context.activate(CalendarSchedulePlugin.dayID(day)) } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xxs) {
                    dayLabel(day, weekday: false)
                    Spacer(minLength: 0)
                    if previewEvents.count > 1 {
                        Text("+\(previewEvents.count - 1)").font(.system(size: 9)).foregroundStyle(.secondary)
                            .opacity(matchingEvents.isEmpty ? Theme.Opacity.scheduleUnmatched : 1)
                    }
                }
                if let event = previewEvents.first {
                    Text(event.title).font(.system(size: 10)).lineLimit(1)
                        .foregroundStyle(accent(event))
                        .opacity(model.matches(event, query: context.query) ? 1 : Theme.Opacity.scheduleUnmatched)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.xs)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(selected ? Theme.Colors.selection : Theme.Colors.controlSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous))
            .opacity(inMonth ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(day.formatted(date: .complete, time: .omitted) + " · \(dayEvents.count) events — View Week")
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + ", \(dayEvents.count) events")
    }

    private var timeline: some View {
        let now = Date()
        return VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: 0) {
                Text(model.calendar.timeZone.abbreviation() ?? "")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .frame(width: Theme.Size.scheduleTimeGutter)
                ForEach(days, id: \.self) { day in
                    dayLabel(day, weekday: true)
                        .frame(maxWidth: .infinity)
                        .opacity(day < model.calendar.startOfDay(for: now) ? Theme.Opacity.schedulePast : 1)
                }
            }
            if events.contains(where: \.isAllDay) { allDayEvents(now: now) }
            ScrollView(.vertical) {
                GeometryReader { geometry in
                    timeGrid(width: geometry.size.width, now: now)
                }
                .frame(height: hourHeight * 24)
            }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, rect in
                viewport = rect
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .decelerating {
                    model.peekID = nil
                    hoveredEventID = nil
                }
            }
            .task(id: PositionRequest(
                period: TimelinePeriod(mode: model.mode, date: model.date), isLoading: model.isLoading,
                viewportHeight: viewport.height
            )) {
                let period = TimelinePeriod(mode: model.mode, date: model.date)
                guard !model.isLoading, positionedPeriod != period, viewport.height > 0 else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                let minute = ScheduleLayout.initialScrollMinute(
                    days: days, events: events.map { (start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay) },
                    now: now, calendar: model.calendar)
                scrollPosition.scrollTo(y: ScheduleViewport.clampedOffset(
                    minute / 60 * hourHeight - viewport.height / 2,
                    hourHeight: hourHeight, viewportHeight: viewport.height))
                positionedPeriod = period
            }
            .onDisappear { positionedPeriod = nil }
            .onChange(of: context.selectedID) { revealSelection() }
            .onChange(of: model.peekID) {
                if model.peekID == context.selectedID { revealSelection() }
            }
            .onChange(of: model.zoom) { previous, _ in
                let oldHeight = ScheduleViewport.hourHeight(base: Theme.Size.scheduleHourHeight, zoom: previous)
                let offset = ScheduleViewport.zoomedOffset(viewport.minY, from: oldHeight,
                    to: hourHeight, viewportHeight: viewport.height)
                withAnimation(interactionAnimation) { scrollPosition.scrollTo(y: offset) }
            }
            .animation(interactionAnimation, value: model.zoom)
            .overlayScroller()
            if model.matching(context.query).isEmpty, !model.isLoading {
                Text(context.query.isEmpty ? "No events in this period" : "No matching events")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func allDayEvents(now: Date) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("All day").font(.system(size: 9)).foregroundStyle(.secondary)
                .frame(width: Theme.Size.scheduleTimeGutter)
            ForEach(days, id: \.self) { day in
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: Theme.Spacing.xxs) {
                            ForEach(Array(onDay(day).filter(\.isAllDay).enumerated()), id: \.offset) { _, event in
                                eventButton(event, id: rowID(event, on: day))
                                    .opacity(day < model.calendar.startOfDay(for: now) ? Theme.Opacity.schedulePast : 1)
                                    .id(rowID(event, on: day))
                            }
                        }
                    }
                    .onChange(of: context.selectedID) {
                        if let id = context.selectedID { proxy.scrollTo(id) }
                    }
                }
                .frame(maxWidth: .infinity).frame(height: Theme.Size.scheduleAllDayHeight)
            }
        }
    }

    private func timeGrid(width: CGFloat, now: Date) -> some View {
        let gutter = Theme.Size.scheduleTimeGutter
        let gridWidth = max(0, width - gutter)
        let dayWidth = gridWidth / CGFloat(max(1, days.count))
        let containsToday = days.contains { model.calendar.isDate($0, inSameDayAs: now) }
        let minute = ScheduleLayout.elapsedMinutes(on: now, now: now, calendar: model.calendar)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hourLabel(hour)).font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: gutter, height: hourHeight, alignment: .topLeading)
                    .offset(y: CGFloat(hour) * hourHeight)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                timeColumn(day, width: dayWidth)
                    .frame(width: dayWidth, height: hourHeight * 24, alignment: .topLeading)
                    .mask(alignment: .top) {
                        VStack(spacing: 0) {
                            Rectangle().fill(.primary.opacity(Theme.Opacity.schedulePast))
                                .frame(height: CGFloat(ScheduleLayout.elapsedMinutes(
                                    on: day, now: now, calendar: model.calendar)) / 60 * hourHeight)
                            Rectangle().fill(.primary)
                        }
                    }
                    .offset(x: gutter + CGFloat(index) * dayWidth)
            }
            if containsToday {
                Rectangle().fill(Theme.Colors.noteTintAccent(.red))
                    .frame(width: gridWidth, height: 1)
                    .offset(x: gutter, y: CGFloat(minute) / 60 * hourHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private func timeColumn(_ day: Date, width: CGFloat) -> some View {
        let timed = onDay(day).filter { !$0.isAllDay }
        let blocks = ScheduleLayout.columns(timed.compactMap {
            ScheduleLayout.block(id: rowID($0, on: day), start: $0.startDate, end: $0.endDate,
                                 day: day, calendar: model.calendar)
        })
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Theme.Colors.separator).frame(width: 1, height: hourHeight * 24)
            ForEach(0..<24, id: \.self) { hour in
                Rectangle().fill(Theme.Colors.separator).frame(width: width, height: 1)
                    .offset(y: CGFloat(hour) * hourHeight)
            }
            ForEach(blocks) { block in
                if let event = timed.first(where: { rowID($0, on: day) == block.id }) {
                    let columnWidth = width / CGFloat(block.columnCount)
                    eventButton(event, id: block.id)
                        .frame(width: max(1, columnWidth - Theme.Spacing.xxs),
                               height: max(18, (block.endMinute - block.startMinute) / 60 * hourHeight - 2))
                        .clipped()
                        .offset(x: CGFloat(block.column) * columnWidth + 1,
                                y: block.startMinute / 60 * hourHeight)

                }
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        String(hour)
    }

    private func eventButton(_ event: DashboardEvent, id: String) -> some View {
        let matches = model.matches(event, query: context.query)
        return Button { context.activate(id) } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(event.title).font(.system(size: 10, weight: .medium)).lineLimit(2)
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xxs)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(accent(event).opacity(0.16))
            .overlay(alignment: .leading) { Rectangle().fill(accent(event)).frame(width: 2) }
            .overlay {
                if context.selectedID == id {
                    RoundedRectangle(cornerRadius: Theme.Radius.menu).strokeBorder(accent(event), lineWidth: 1.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(matches ? 1 : Theme.Opacity.scheduleUnmatched)
        .allowsHitTesting(matches)
        .accessibilityHidden(!matches)
        .anchorPreference(key: ScheduleEventBounds.self, value: .bounds) { [id: $0] }
        .onHover { inside in
            if inside { hoveredEventID = id }
            else if hoveredEventID == id { hoveredEventID = nil }
        }
        .accessibilityAction(named: "Preview Event") { model.peekID = id }
        .accessibilityLabel(event.title + ", " + CalendarScheduleEngine.timeLabel(
            start: event.startDate, end: event.endDate, isAllDay: event.isAllDay, calendar: model.calendar))
    }

    private func revealSelection() {
        guard !model.isLoading, viewport.height > 0,
              positionedPeriod == TimelinePeriod(mode: model.mode, date: model.date),
              let id = context.selectedID,
              let position = CalendarSchedulePlugin.positions(model: model, query: context.query).first(where: { $0.id == id }),
              !position.isAllDay,
              let event = CalendarSchedulePlugin.event(store: model, itemID: id),
              let block = ScheduleLayout.block(id: id, start: event.startDate, end: event.endDate,
                                               day: position.day, calendar: model.calendar) else { return }
        // Offset-drawn event views do not have usable ScrollViewReader layout rects.
        let offset = ScheduleViewport.revealing(startMinute: block.startMinute, endMinute: block.endMinute,
            hourHeight: hourHeight, offset: viewport.minY, viewportHeight: viewport.height)
        if abs(offset - viewport.minY) > 0.5 {
            withAnimation(interactionAnimation) { scrollPosition.scrollTo(y: offset) }
        }
    }

    private func peek(_ event: DashboardEvent, id: String, source: CGRect, size: CGSize) -> some View {
        let width = min(320, size.width)
        let height = min(280, size.height)
        let x = min(max(0, source.minX), max(0, size.width - width))
        let y = min(max(0, source.minY), max(0, size.height - height))
        let origin = UnitPoint(x: min(1, max(0, (source.midX - x) / width)),
                               y: min(1, max(0, (source.midY - y) / height)))
        return ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).onTapGesture { model.peekID = nil }
            CalendarEventPeekView(event: event, calendar: model.calendar, accent: accent(event)) {
                context.activate(id)
            }
            .frame(width: width, height: height)
            .onHover { inside in if !inside { model.peekID = nil } }
            .transition(.scale(scale: 0.94, anchor: origin).combined(with: .opacity))
            .offset(x: x, y: y)
        }
    }

    private func detail(_ event: DashboardEvent) -> some View {
        CalendarEventDetailView(event: event, calendar: model.calendar,
                                worldClock: core.worldClock, accent: accent(event),
                                joinMeeting: core.openCalendarMeetingLink)
    }

}

struct ScheduleHeaderControls: View {
    @ObservedObject var model: CalendarScheduleStore
    @ObservedObject var dashboard: DashboardWidgetsStore
    let today: () -> Void
    let select: (ScheduleViewMode) -> Void

    var body: some View {
        if dashboard.calendarAccess.canRead, model.detailID == nil {
            HStack(spacing: Theme.Spacing.sm) {
                Button(action: today) {
                    Text("Today")
                        .font(Theme.Typography.bar)
                        .padding(.horizontal, Theme.Spacing.xl)
                        .frame(height: Theme.Size.scheduleHeaderControlHeight)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .frosted(in: Capsule())
                .focusable(false)
                .help("Go to today")
                viewSegments
            }
        }
    }

    private var viewSegments: some View {
        HStack(spacing: 0) {
            ForEach(ScheduleViewMode.allCases, id: \.self) { mode in
                Button { select(mode) } label: {
                    Label(mode.title, systemImage: mode == .week ? "rectangle.split.3x1" : "calendar")
                        .labelStyle(.iconOnly)
                        .font(Theme.Typography.bar)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(model.mode == mode ? .primary : .secondary)
                        .frame(width: Theme.Size.scheduleHeaderControlHeight - Theme.Spacing.xxs * 2,
                               height: Theme.Size.scheduleHeaderControlHeight - Theme.Spacing.xxs * 2)
                        .background {
                            if model.mode == mode {
                                Capsule().fill(Theme.Colors.selection)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("\(mode.title) view")
                .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
            }
        }
        .padding(Theme.Spacing.xxs)
        .frosted(in: Capsule())
        .animation(nil, value: model.mode)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendar view")
    }
}

private struct ScheduleEventBounds: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
