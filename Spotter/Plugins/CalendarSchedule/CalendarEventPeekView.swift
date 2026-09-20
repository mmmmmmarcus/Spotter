import SwiftUI

struct CalendarEventPeekView: View {
    let event: DashboardEvent
    let calendar: Calendar
    let accent: Color
    let open: () -> Void
    @State private var importedFields: [ScheduleNoteField] = []

    private var time: ScheduleEventTime? {
        CalendarScheduleEngine.detailTimes(start: event.startDate, end: event.endDate,
            isAllDay: event.isAllDay, eventTimeZoneIdentifier: event.timeZoneIdentifier,
            cities: [], calendar: calendar, locale: .current).first
    }

    private var people: [DashboardEventDetail] {
        let native = event.details.filter { ["Organizer", "Participants"].contains($0.name) }
        return native + importedFields.filter { field in
            ["Organizer", "Participants"].contains(field.name) && !native.contains { $0.name == field.name }
        }.map { DashboardEventDetail(name: $0.name, value: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top) {
                Text(event.title).font(.headline).lineLimit(3)
                Spacer(minLength: Theme.Spacing.xs)
                Button(action: open) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption)
                }
                .buttonStyle(.plain).help("View Event Details")
                .accessibilityLabel("View Event Details")
            }
            Text(event.calendarTitle).font(.caption).foregroundStyle(accent).lineLimit(1)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    if let time {
                        Label {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(time.time).monospacedDigit()
                                Text(time.date).foregroundStyle(.secondary)
                                if !event.isAllDay { Text(time.name).foregroundStyle(.secondary) }
                            }
                        } icon: { Image(systemName: "clock") }
                    }
                    if let location = event.location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                    }
                    ForEach(people, id: \.name) { field in
                        Label {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(field.name).foregroundStyle(.secondary)
                                Text(field.value)
                            }
                        } icon: { Image(systemName: field.name == "Organizer" ? "person" : "person.2") }
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlayScroller()
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(accent.opacity(0.16))
        .background(.regularMaterial)
        .overlay(alignment: .leading) { Rectangle().fill(accent).frame(width: 2) }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.menu).strokeBorder(accent.opacity(0.6), lineWidth: 1) }
        .shadow(radius: 12, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Event preview")
        .task(id: event.notes) {
            let notes = event.notes ?? ""
            let fields = await Task.detached(priority: .userInitiated) { ScheduleNotes.parse(notes).fields }.value
            guard !Task.isCancelled else { return }
            importedFields = fields
        }
    }
}
