import Foundation

@main
@MainActor
struct DashboardWidgetsTests {
    private static var failures = 0

    static func main() {
        check(
            DashboardWidgetsEngine.widgetOrder(from: nil) == DashboardWidgetKind.allCases,
            "no saved arrangement should fall back to the catalog order")
        check(
            DashboardWidgetsEngine.widgetOrder(from: ["file-info", "clock"]).prefix(2)
                == [.fileInfo, .clock],
            "a saved arrangement should lead with what it named")
        check(
            Set(DashboardWidgetsEngine.widgetOrder(from: ["file-info"]))
                == Set(DashboardWidgetKind.allCases),
            "a partial arrangement should still cover every widget")
        check(
            DashboardWidgetsEngine.widgetOrder(from: ["clock", "clock", "nonsense"]).count
                == DashboardWidgetKind.allCases.count,
            "duplicates and unknown identifiers should not change the widget count")
        check(
            DashboardWidgetsEngine.widgetOrder(from: ["clock", "clock"]).filter { $0 == .clock }
                .count == 1,
            "a duplicate should be kept only once")

        let sep = DashboardMusicEngine.fieldSeparator
        let playing = DashboardMusicEngine.snapshot(
            fromScriptOutput: ["playing", "A1B2", "Weightless", "Marconi Union", "Ambient", "486.5"]
                .joined(separator: sep))
        check(playing.state == .playing && playing.isPlaying, "a playing line reads as playing")
        check(playing.track?.title == "Weightless", "the track's name survives the separator")
        check(playing.track?.duration == 486.5, "the duration parses as seconds")
        check(
            DashboardMusicEngine.subtitle(for: playing.track!) == "Marconi Union",
            "the second line is the artist")
        let paused = DashboardMusicEngine.snapshot(
            fromScriptOutput: ["paused", "A1B2", "Weightless", "", "Ambient", "486.5"]
                .joined(separator: sep))
        check(!paused.isPlaying && paused.track != nil, "a paused track is still a track")
        check(
            DashboardMusicEngine.subtitle(for: paused.track!) == "Ambient",
            "a track with no artist falls back to its album")
        check(
            DashboardMusicEngine.snapshot(fromScriptOutput: "stopped").track == nil,
            "a stopped player has no track")
        check(
            DashboardMusicEngine.snapshot(fromScriptOutput: "").track == nil,
            "an empty answer is not a track")
        check(
            DashboardMusicEngine.snapshot(fromScriptOutput: "playing\(sep)id").track == nil,
            "a truncated answer is not a track")
        check(
            DashboardMusicEngine.snapshot(
                fromScriptOutput: ["playing", "A1B2", "   ", "Artist", "Album", "10"]
                    .joined(separator: sep)).track == nil,
            "a nameless track is nothing to draw")

        check(
            DashboardMusicEngine.restingLine(isRunning: false) == "Music is not open"
                && DashboardMusicEngine.restingLine(isRunning: true) == "Nothing playing",
            "a closed player and an idle one say different things")

        let order: [DashboardWidgetKind] = [.clock, .music, .deviceBattery, .nextEvent, .fileInfo]
        check(
            DashboardWidgetsEngine.reorder(order, moving: .fileInfo, to: 0).first == .fileInfo,
            "moving to the front should put the widget first")
        check(
            DashboardWidgetsEngine.reorder(order, moving: .clock, to: 4).last == .clock,
            "moving to the end should put the widget last")
        check(
            DashboardWidgetsEngine.reorder(order, moving: .clock, to: 1)
                == [.music, .clock, .deviceBattery, .nextEvent, .fileInfo],
            "a downward move should land where the dragged row was dropped")
        check(
            DashboardWidgetsEngine.reorder(order, moving: .clock, to: 0) == order,
            "moving onto its own position should change nothing")
        check(
            DashboardWidgetsEngine.reorder(order, moving: .clock, to: 9) == order,
            "an out-of-range destination should change nothing")
        check(
            Set(DashboardWidgetsEngine.reorder(order, moving: .nextEvent, to: 2)) == Set(order),
            "reordering should never add or drop a widget")

        // One place, and it is this Mac's own: the forecast names the zone the clock then keeps.
        let located = WeatherPlace(
            latitude: 52.52, longitude: 13.405, timeZoneIdentifier: "Europe/Berlin")
        check(
            DashboardWeatherEngine.clockTimeZoneIdentifier(for: located) == "Europe/Berlin",
            "a located place should hand the clock the zone the forecast named")
        check(
            DashboardWeatherEngine.clockTimeZoneIdentifier(
                for: WeatherPlace(
                    latitude: 0, longitude: 0, timeZoneIdentifier: "Mars/Olympus")) == nil,
            "an unresolvable zone should never overwrite the clock's setting")
        check(
            DashboardWeatherEngine.clockTimeZoneIdentifier(
                for: WeatherPlace(latitude: 52.52, longitude: 13.405)) == nil,
            "a fix with no forecast yet names no zone, so the clock keeps the one it had")

        // Resolving a place: what macOS allows, and whether a fix has landed.
        check(
            DashboardWeatherEngine.locationState(
                authorization: .authorized, place: located, hasFailedFix: false)
                == .located(located),
            "an allowed Mac with a fix is located")
        check(
            DashboardWeatherEngine.locationState(
                authorization: .notDetermined, place: nil, hasFailedFix: false) == .waiting,
            "an unanswered permission is still waiting, not a failure")
        check(
            DashboardWeatherEngine.locationState(
                authorization: .authorized, place: nil, hasFailedFix: false) == .waiting,
            "an allowed Mac whose first fix is in flight is waiting")
        check(
            DashboardWeatherEngine.locationState(
                authorization: .authorized, place: nil, hasFailedFix: true) == .unavailable,
            "allowed but unable to get a fix is unavailable, not waiting forever")
        check(
            DashboardWeatherEngine.locationState(
                authorization: .denied, place: located, hasFailedFix: false) == .denied,
            "a refused grant is a refusal even with a place cached from before it")
        check(
            DashboardWeatherEngine.locationState(
                authorization: .restricted, place: located, hasFailedFix: false) == .restricted,
            "a policy-restricted Mac reports the restriction rather than a stale place")
        check(
            DashboardWeatherEngine.isLocated(
                DashboardWeatherEngine.locationState(
                    authorization: .authorized, place: located, hasFailedFix: false)),
            "only a located Mac may draw a reading")
        for state in [WeatherLocationState.waiting, .denied, .restricted, .unavailable] {
            check(
                !DashboardWeatherEngine.isLocated(state)
                    && DashboardWeatherEngine.place(from: state) == nil,
                "no place means no request and nothing drawn: \(state)")
        }

        // Every failure says so, because removing manual entry removed the only recourse.
        check(
            DashboardWeatherEngine.cardIssue(
                for: .located(located)) == nil
                && DashboardWeatherEngine.cardIssue(for: .waiting) == nil,
            "a working or still-locating card says nothing rather than crying wolf")
        for state in [WeatherLocationState.denied, .restricted, .unavailable] {
            let issue = DashboardWeatherEngine.cardIssue(for: state)
            check(
                issue?.hasPrefix("Location unavailable") == true,
                "every failure names itself on the card: \(state)")
            check(
                issue == DashboardWeatherEngine.locationStatusMessage(for: state),
                "the card and the Settings row state the same failure: \(state)")
        }
        check(
            DashboardWeatherEngine.locationStatusMessage(for: .denied)
                .contains("System Settings ▸ Privacy & Security ▸ Location Services"),
            "a refusal names the one place it can be undone")
        check(
            DashboardWeatherEngine.opensLocationSettings(for: .denied)
                && DashboardWeatherEngine.opensLocationSettings(for: .unavailable),
            "a failure the user can act on offers the way to act on it")
        check(
            !DashboardWeatherEngine.opensLocationSettings(for: .restricted),
            "a restricted Mac has nothing to open, so it is offered no button")
        check(
            !DashboardWeatherEngine.opensLocationSettings(for: .located(located))
                && !DashboardWeatherEngine.opensLocationSettings(for: .waiting),
            "a working card offers no fix-it for a problem it doesn't have")
        check(
            DashboardWeatherEngine.locationStatusMessage(for: .located(located))
                == "Current location · 52.5°N, 13.4°E",
            "a located Mac states the fix at the precision it actually asked for")
        check(
            DashboardWeatherEngine.formattedCoordinates(
                WeatherPlace(latitude: -33.87, longitude: -151.21)) == "33.9°S, 151.2°W",
            "hemispheres read as letters rather than a minus sign")

        // The one location line: where the weather is read, and what the clock runs on.
        check(
            DashboardWeatherEngine.locationSummary(
                state: .located(located), clockTimeZoneIdentifier: "Europe/Berlin",
                systemTimeZoneIdentifier: "Europe/Paris")
                == "Current location · 52.5°N, 13.4°E · clock on Europe/Berlin",
            "one located place should read as one line")
        check(
            DashboardWeatherEngine.locationSummary(
                state: .denied, clockTimeZoneIdentifier: nil,
                systemTimeZoneIdentifier: "Europe/Paris")
                .hasSuffix("· clock on System Default (Europe/Paris)"),
            "a Mac with no weather still says what its clock is running on")
        check(
            DashboardWidgetsEngine.clockSummary(
                clockTimeZoneIdentifier: "America/New_York",
                systemTimeZoneIdentifier: "Europe/Paris") == "America/New York",
            "a saved zone reads as words rather than an identifier")
        check(
            DashboardWidgetsEngine.clockSummary(
                clockTimeZoneIdentifier: nil, systemTimeZoneIdentifier: "Europe/Paris")
                == "System Default (Europe/Paris)",
            "a clock with no saved zone names the system's rather than nothing")

        // A reading belongs to the place it was taken at, and to nowhere else.
        let berlinReading = reading(latitude: 52.52, longitude: 13.405)
        check(
            DashboardWeatherEngine.isSnapshot(
                berlinReading, current: WeatherPlace(latitude: 52.53, longitude: 13.41)),
            "a coarse fix's own jitter must not throw a good reading away")
        check(
            !DashboardWeatherEngine.isSnapshot(
                berlinReading, current: WeatherPlace(latitude: 48.856, longitude: 2.352)),
            "a reading from another city must never caption where the Mac now is")
        check(
            near(
                DashboardWeatherEngine.distanceKilometers(
                    from: WeatherPlace(latitude: 52.52, longitude: 13.405),
                    to: WeatherPlace(latitude: 52.52, longitude: 13.405)), 0),
            "a place is no distance from itself")
        check(
            abs(
                DashboardWeatherEngine.distanceKilometers(
                    from: WeatherPlace(latitude: 52.52, longitude: 13.405),
                    to: WeatherPlace(latitude: 48.856, longitude: 2.352)) - 878) < 15,
            "Berlin to Paris should measure about 878 km")
        check(
            berlinReading.place.timeZoneIdentifier == "Europe/Berlin",
            "a cached reading carries the zone forward, so a relaunch keeps the located clock")

        // Only the coordinates the forecast is for leave the Mac.
        let url = DashboardWeatherEngine.forecastURL(latitude: 52.52, longitude: 13.405)?
            .absoluteString ?? ""
        check(url.contains("latitude=52.52") && url.contains("longitude=13.405"), "the request carries the fix")
        check(
            url.contains("timezone=auto"),
            "the forecast asks for the located place's own day, which is also the clock's zone")

        // Weather is asked exactly once, and "asked" is not "granted".
        check(
            DashboardWeatherEngine.consentState(hasBeenAsked: false, isGranted: false)
                == .unanswered,
            "a fresh install has not answered the weather question")
        check(
            DashboardWeatherEngine.consentState(hasBeenAsked: true, isGranted: false) == .declined,
            "a decline is an answer, and leaves weather off")
        check(
            DashboardWeatherEngine.consentState(hasBeenAsked: true, isGranted: true) == .granted,
            "an accepted dialog grants weather")
        check(
            DashboardWeatherEngine.consentState(hasBeenAsked: false, isGranted: true) == .granted,
            "a grant restored from a trusted file counts as answered without a dialog")
        check(
            DashboardWeatherEngine.shouldPresentConsent(hasBeenAsked: false, isGranted: false),
            "the dialog is raised for someone who has never answered")
        check(
            !DashboardWeatherEngine.shouldPresentConsent(hasBeenAsked: true, isGranted: false),
            "someone who declined is never asked again")
        check(
            !DashboardWeatherEngine.shouldPresentConsent(hasBeenAsked: true, isGranted: true),
            "someone who accepted is never asked again")
        check(
            !DashboardWeatherEngine.shouldPresentConsent(hasBeenAsked: false, isGranted: true),
            "a synced grant is not re-asked on the receiving Mac")

        // The clock runs whether or not the weather question has been answered: its saved zone, or
        // the system's, and never a blank face.
        check(
            DashboardWidgetsEngine.resolvedTimeZone(
                identifier: "Europe/Berlin", fallback: TimeZone(identifier: "Europe/Paris")!)
                == TimeZone(identifier: "Europe/Berlin")!,
            "a saved zone drives the clock with no city and no consent")
        check(
            DashboardWidgetsEngine.resolvedTimeZone(
                identifier: nil, fallback: TimeZone(identifier: "Europe/Paris")!)
                == TimeZone(identifier: "Europe/Paris")!,
            "an unset zone falls back rather than leaving the clock without one")
        check(
            DashboardWidgetsEngine.resolvedTimeZone(
                identifier: "Nowhere/Nowhere", fallback: TimeZone(identifier: "Europe/Paris")!)
                == TimeZone(identifier: "Europe/Paris")!,
            "an unresolvable saved zone falls back rather than stranding the clock")

        // 1_000_000_020 is a whole minute past the reference epoch; 1_000_000_000 is 40s short of it.
        let midMinute = Date(timeIntervalSinceReferenceDate: 1_000_000_000)
        check(
            DashboardWidgetsEngine.nextMinute(after: midMinute)
                == Date(timeIntervalSinceReferenceDate: 1_000_000_020),
            "the strip's tick lands on the next whole minute, not a minute later")
        check(
            DashboardWidgetsEngine.nextMinute(after: midMinute) > midMinute,
            "a tick is always in the future, so the schedule can never stall on one entry")
        check(
            DashboardWidgetsEngine.nextMinute(
                after: Date(timeIntervalSinceReferenceDate: 1_000_000_000.75))
                == Date(timeIntervalSinceReferenceDate: 1_000_000_020),
            "a fractional second is dropped rather than carried into the next tick")
        check(
            DashboardWidgetsEngine.nextMinute(after: midMinute)
                == DashboardWidgetsEngine.nextMinute(
                    after: Date(timeIntervalSinceReferenceDate: 1_000_000_019)),
            "two moments inside one minute tick at the same instant")
        check(
            DashboardWidgetsEngine.nextMinute(
                after: Date(timeIntervalSinceReferenceDate: 1_000_000_020))
                == Date(timeIntervalSinceReferenceDate: 1_000_000_080),
            "a moment already on the minute advances a whole minute rather than repeating itself")
        check(
            DashboardWidgetsEngine.nextMinute(
                after: Date(timeIntervalSinceReferenceDate: -30))
                == Date(timeIntervalSinceReferenceDate: 0),
            "a date before the reference epoch still rounds forward, never back")
        // File Info: what the square says about a Finder selection.
        check(DashboardFileInfoSnapshot().isEmpty, "no selection should read as empty")
        // The empty card draws its mark alone, so these lines are spoken rather than drawn — the
        // accessibility label is the one place they still name the source and the empty selection.
        check(
            DashboardFileInfoSnapshot().kindLine == "Finder",
            "an empty snapshot should name where it reads from")
        check(
            DashboardFileInfoSnapshot().nameLine == "No selection",
            "an empty snapshot should say so rather than go blank")
        check(
            DashboardFileInfoSnapshot().sizeLine.isEmpty,
            "an empty snapshot should have no size to state")
        check(
            DashboardFileInfoSnapshot().iconPath == nil,
            "an empty snapshot should have no file icon, so the card rests on a generic glyph")

        let png = fileItem("Shot.png", kind: "PNG image", bytes: 1_500_000)
        let shot = DashboardFileInfoSnapshot(items: [png])
        check(shot.kindLine == "PNG image", "one file should lead with its kind")
        check(shot.nameLine == "Shot.png", "one file should be named by its filename")
        check(shot.sizeLine.contains("MB"), "one file should state its size")
        check(shot.iconPath == "/tmp/Shot.png", "the icon should come from the item")

        let folder = DashboardFileInfoSnapshot(items: [folderItem("Docs", children: 12)])
        check(folder.sizeLine == "12 items", "a folder should be counted rather than weighed")
        check(
            DashboardFileInfoSnapshot(items: [folderItem("Docs", children: 1)]).sizeLine == "1 item",
            "a single child should be singular")
        check(
            DashboardFileInfoSnapshot(items: [folderItem("Locked", children: nil)]).sizeLine.isEmpty,
            "an unreadable folder should drop the size line rather than guess")

        let app = DashboardFileInfoSnapshot(items: [
            fileItem("Spotter", kind: "Application", bytes: 12_000_000, path: "/Applications/Spotter.app")
        ])
        check(app.kindLine == "Application", "a package should state its kind")
        check(app.sizeLine.contains("MB"), "a package should be weighed like a file")

        let many = DashboardFileInfoSnapshot(items: [
            fileItem("a.png", kind: "PNG image", bytes: 1_000_000),
            fileItem("b.png", kind: "PNG image", bytes: 2_000_000),
        ])
        check(many.kindLine == "Selection", "several items have no one kind to lead with")
        check(many.nameLine == "2 items", "several items should be named by their count")
        check(
            many.sizeLine == DashboardFileInfoSummary.size(bytes: 3_000_000),
            "several items should sum to one size")
        check(many.iconPath == "/tmp/a.png", "several items should borrow the first icon")

        let mixed = DashboardFileInfoSnapshot(items: [
            fileItem("a.png", kind: "PNG image", bytes: 1_000_000),
            folderItem("Docs", children: 3), folderItem("More", children: 4),
        ])
        check(
            mixed.sizeLine == DashboardFileInfoSummary.size(bytes: 1_000_000) + " · 2 folders",
            "a mixed total should name the folders it could not cover")
        check(
            DashboardFileInfoSnapshot(items: [
                fileItem("a.png", kind: "PNG image", bytes: 1), folderItem("Docs", children: 3),
            ]).sizeLine.hasSuffix("· 1 folder"),
            "one uncovered folder should be singular")
        check(
            DashboardFileInfoSnapshot(items: [
                folderItem("A", children: 1), folderItem("B", children: 2),
            ]).sizeLine == "2 folders",
            "an all-folder selection should state only the folder count")
        check(
            !mixed.accessibilityLabel.isEmpty && mixed.accessibilityLabel.contains(","),
            "the three lines should be spoken as one sentence")

        // Device battery: two scans merge into one card.
        check(
            DashboardDeviceBatteryEngine.kind(forMinorType: "Keyboard", productName: "")
                == .keyboard,
            "bluetoothd's minor type should decide the category outright")
        check(
            DashboardDeviceBatteryEngine.kind(forMinorType: "Headset", productName: "")
                == .headphones,
            "a headset is drawn as headphones")
        check(
            DashboardDeviceBatteryEngine.kind(forMinorType: "", productName: "Keyboard Craft")
                == .keyboard,
            "a missing minor type should fall back to the product name")
        check(
            DashboardDeviceBatteryEngine.kind(forProductName: "Bunny's AirPods") == .headphones,
            "AirPods read as headphones by name")
        check(
            DashboardDeviceBatteryEngine.normalizedAddress("C0:44:42:D9:F9:83")
                == "c0-44-42-d9-f9-83",
            "bluetoothd's address spelling should normalize to IOKit's")

        let profilerJSON = """
            {"SPBluetoothDataType":[{"device_connected":[
            {"Keyboard Craft":{"device_address":"F5:B7:55:5E:72:17",
            "device_batteryLevelMain":"100%","device_minorType":"Keyboard"}},
            {"Quiet Mouse":{"device_address":"C0:44:42:D9:F9:83","device_minorType":"Mouse"}},
            {"AirPods Pro":{"device_address":"14:88:E6:AC:7F:37","device_batteryLevelLeft":"80%",
            "device_batteryLevelRight":"75%","device_batteryLevelCase":"5%",
            "device_minorType":"Headphones"}}],
            "device_not_connected":[{"Old Keyboard":{"device_address":"AA:BB:CC:DD:EE:FF",
            "device_batteryLevelMain":"50%"}}]}]}
            """.data(using: .utf8)!
        let bluetooth = DashboardDeviceBatteryEngine.bluetoothDevices(
            fromProfilerJSON: profilerJSON)
        check(
            bluetooth.count == 2,
            "only connected devices that report a level should be read")
        check(
            bluetooth.contains {
                $0.kind == .keyboard && $0.percent == 100 && $0.id == "f5-b7-55-5e-72-17"
            },
            "a keyboard's main level and normalized address should come through")
        check(
            bluetooth.contains { $0.kind == .headphones && $0.percent == 75 },
            "earbuds should read as their lowest bud, with the case ignored")
        check(
            bluetooth.allSatisfy { !$0.isCharging },
            "bluetoothd reports no charging state, so no bolt")
        check(
            DashboardDeviceBatteryEngine.bluetoothDevices(fromProfilerJSON: Data()).isEmpty,
            "unparseable profiler output should read as no devices")

        let hidMouse = DeviceBattery(
            id: "c0-44-42-d9-f9-83", productName: "Magic Mouse", kind: .mouse, percent: 85,
            isCharging: true)
        let merged = DashboardDeviceBatteryEngine.merged(hid: [hidMouse], bluetooth: bluetooth)
        check(
            merged.count == 3,
            "the Bluetooth scan should add only devices the HID scan didn't find")
        check(
            merged.contains { $0.id == "c0-44-42-d9-f9-83" && $0.isCharging },
            "a device both scans found should keep the HID reading and its charging flag")
        check(
            merged.first?.kind == .headphones,
            "the merged list should stay ordered lowest-first")

        check(DashboardFileInfoSummary.size(bytes: 512).contains("512"), "bytes should stay bytes")
        check(DashboardFileInfoSummary.size(bytes: 1_000).contains("KB"), "kilobytes are file-style")
        check(
            DashboardFileInfoSummary.size(bytes: 5_000_000_000).contains("GB"),
            "gigabytes are file-style")
        check(
            DashboardFileInfoSummary.size(bytes: -5) == DashboardFileInfoSummary.size(bytes: 0),
            "a negative size can only be a bad read, so it floors at zero")

        print(failures == 0 ? "Dashboard widgets tests passed" : "\(failures) test(s) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    private static func fileItem(
        _ name: String, kind: String, bytes: Int64, path: String? = nil
    ) -> DashboardFileInfoItem {
        DashboardFileInfoItem(
            path: path ?? "/tmp/\(name)", name: name, kind: kind, byteCount: bytes,
            childCount: nil)
    }

    private static func folderItem(_ name: String, children: Int?) -> DashboardFileInfoItem {
        DashboardFileInfoItem(
            path: "/tmp/\(name)", name: name, kind: "Folder", byteCount: nil,
            childCount: children)
    }

    private static func reading(latitude: Double, longitude: Double) -> WeatherSnapshot {
        WeatherSnapshot(
            latitude: latitude, longitude: longitude, temperatureCelsius: 14, weatherCode: 3,
            isDay: true, fetchedAt: Date(timeIntervalSinceReferenceDate: 1_000_000_000),
            lowCelsius: 9, highCelsius: 18, timeZoneIdentifier: "Europe/Berlin")
    }

    private static func near(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 0.0001
    }

    private static func battery(
        _ productName: String, _ percent: Int, id: String = "id", charging: Bool = false
    ) -> DeviceBattery {
        DeviceBattery(
            id: id, productName: productName,
            kind: DashboardDeviceBatteryEngine.kind(forProductName: productName), percent: percent,
            isCharging: charging)
    }

    private static func date(_ stamp: String, _ calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: stamp)!
    }
}
