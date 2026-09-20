import EventKit
import Foundation

// Read native objects only on the event reader's queue and return plain display values.
enum CalendarEventMetadata {
    static func read(_ event: EKEvent) -> [DashboardEventDetail] {
        var fields: [DashboardEventDetail] = []
        if let organizer = event.organizer {
            fields.append(.init(name: "Organizer", value: participant(organizer, includesResponse: false)))
        }
        if let attendees = event.attendees, !attendees.isEmpty {
            fields.append(.init(name: "Participants", value: attendees.map { participant($0, includesResponse: true) }.joined(separator: "\n")))
        }
        if let rules = event.recurrenceRules, !rules.isEmpty {
            fields.append(.init(name: "Repeats", value: rules.map { recurrence($0, zone: event.timeZone ?? .current) }.joined(separator: "\n")))
        }
        if let alarms = event.alarms, !alarms.isEmpty {
            fields.append(.init(name: "Alerts", value: alarms.map { alarm in
                if let location = alarm.structuredLocation {
                    return (alarm.proximity == .leave ? "Leaving " : "Arriving at ") + (location.title ?? "location")
                }
                if let date = alarm.absoluteDate {
                    var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
                    style.timeZone = event.timeZone ?? .current
                    return date.formatted(style)
                }
                if alarm.relativeOffset == 0 { return "At time of event" }
                let minutes = Int(abs(alarm.relativeOffset) / 60)
                let duration = minutes % 1440 == 0 ? "\(minutes / 1440) d" : minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes) min"
                return duration + (alarm.relativeOffset < 0 ? " before" : " after")
            }.joined(separator: "\n")))
        }
        let availability: String? = switch event.availability {
        case .busy: "Busy"
        case .free: "Free"
        case .tentative: "Tentative"
        case .unavailable: "Unavailable"
        default: nil
        }
        if let availability { fields.append(.init(name: "Availability", value: availability)) }
        let status: String? = switch event.status {
        case .confirmed: "Confirmed"
        case .tentative: "Tentative"
        case .canceled: "Canceled"
        default: nil
        }
        if let status { fields.append(.init(name: "Status", value: status)) }
        return fields
    }

    private static func participant(_ person: EKParticipant, includesResponse: Bool) -> String {
        let rawAddress = person.url.scheme == "mailto" ? String(person.url.absoluteString.dropFirst(7)) : person.url.absoluteString
        let address = rawAddress.removingPercentEncoding ?? rawAddress
        var parts = [person.name?.isEmpty == false ? person.name! : address]
        if person.url.scheme == "mailto", address != parts[0] { parts.append(address) }
        if person.isCurrentUser { parts.append("You") }
        if includesResponse {
            let response: String? = switch person.participantStatus {
            case .pending: "Pending"
            case .accepted: "Accepted"
            case .declined: "Declined"
            case .tentative: "Tentative"
            case .delegated: "Delegated"
            case .completed: "Completed"
            case .inProcess: "In progress"
            default: nil
            }
            if person.participantRole == .optional { parts.append("Optional") }
            if person.participantRole == .chair { parts.append("Chair") }
            if let response { parts.append(response) }
        }
        return parts.joined(separator: " · ")
    }

    private static func recurrence(_ rule: EKRecurrenceRule, zone: TimeZone) -> String {
        let unit: String = switch rule.frequency {
        case .daily: "day"
        case .weekly: "week"
        case .monthly: "month"
        case .yearly: "year"
        @unknown default: "period"
        }
        var parts = [rule.interval == 1 ? "Every \(unit)" : "Every \(rule.interval) \(unit)s"]
        let calendar = Calendar.current
        if let days = rule.daysOfTheWeek, !days.isEmpty {
            parts.append(days.map { day in
                let index = day.dayOfTheWeek.rawValue - 1
                let name = calendar.weekdaySymbols.indices.contains(index) ? calendar.weekdaySymbols[index] : ""
                return day.weekNumber == 0 ? name : "\(day.weekNumber) · \(name)"
            }.joined(separator: ", "))
        }
        for (label, values) in [("Month days", rule.daysOfTheMonth), ("Months", rule.monthsOfTheYear),
                                ("Year days", rule.daysOfTheYear), ("Year weeks", rule.weeksOfTheYear), ("Positions", rule.setPositions)] {
            if let values, !values.isEmpty { parts.append(label + ": " + values.map(\.stringValue).joined(separator: ", ")) }
        }
        if let end = rule.recurrenceEnd {
            if let date = end.endDate {
                var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
                style.timeZone = zone
                parts.append("Until " + date.formatted(style))
            } else if end.occurrenceCount > 0 { parts.append("\(end.occurrenceCount) occurrences") }
        }
        return parts.joined(separator: " · ")
    }
}
