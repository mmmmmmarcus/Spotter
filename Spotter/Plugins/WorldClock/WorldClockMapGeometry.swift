import Foundation

struct WorldClockCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    var x: Double { (longitude + 180) / 360 }
    var y: Double { (90 - latitude) / 180 }
}

enum WorldClockMapGeometry {
    static let cropCenterLatitude = 30.0
    static let minutesPerPoint = 2.0

    static func croppedY(latitude: Double, width: Double, height: Double) -> Double {
        guard width > 0 else { return height / 2 }
        let center = min(cropCenterLatitude, max(0, 90 - height * 180 / width))
        return height / 2 + (center - latitude) * width / 360
    }

    static func dragMinutes(translation: Double) -> Int {
        guard translation.isFinite else { return 0 }
        return Int(max(-525_600, min(525_600, -(translation * minutesPerPoint).rounded())))
    }

    static func coordinates(fromZoneTab text: String) -> [String: WorldClockCoordinate] {
        var result: [String: WorldClockCoordinate] = [:]
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let columns = line.split(separator: "\t")
            guard columns.count >= 3, let coordinate = parseCoordinate(String(columns[1])) else { continue }
            result[String(columns[2])] = coordinate
        }
        return result
    }

    static func parseCoordinate(_ text: String) -> WorldClockCoordinate? {
        guard let split = text.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }),
              let latitude = angle(String(text[..<split]), degrees: 2, limit: 90),
              let longitude = angle(String(text[split...]), degrees: 3, limit: 180) else { return nil }
        return WorldClockCoordinate(latitude: latitude, longitude: longitude)
    }

    static func coordinate(for city: WorldClockCity, zones: [String: WorldClockCoordinate]) -> WorldClockCoordinate? {
        // These catalog cities share another city's IANA zone, so its reference coordinate would be misleading.
        switch city.id {
        case "America/Los_Angeles#San Francisco": return .init(latitude: 37.7749, longitude: -122.4194)
        case "Asia/Shanghai#Beijing": return .init(latitude: 39.9042, longitude: 116.4074)
        case "Asia/Kolkata#Mumbai": return .init(latitude: 19.0760, longitude: 72.8777)
        case "Asia/Kolkata#Delhi": return .init(latitude: 28.6139, longitude: 77.2090)
        default: return zones[city.timeZoneIdentifier]
        }
    }

    static func sun(at date: Date) -> WorldClockCoordinate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.ordinality(of: .day, in: .year, for: date)!
        let days = calendar.range(of: .day, in: .year, for: date)!.count
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let minutes = Double(parts.hour! * 60 + parts.minute!) + Double(parts.second!) / 60
        let gamma = 2 * Double.pi / Double(days) * (Double(day - 1) + (minutes / 60 - 12) / 24)
        // NOAA's fractional-year approximation supplies solar declination and the equation of time.
        let equation = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let declination = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let longitude = 180 - (minutes + equation) / 4
        return .init(latitude: declination * 180 / .pi,
                     longitude: (longitude + 540).truncatingRemainder(dividingBy: 360) - 180)
    }

    static func isDaylight(at point: WorldClockCoordinate, sun: WorldClockCoordinate) -> Bool {
        let latitude = point.latitude * .pi / 180
        let declination = sun.latitude * .pi / 180
        let hourAngle = (point.longitude - sun.longitude) * .pi / 180
        return sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hourAngle) >= 0
    }

    static func nightPolygon(at date: Date) -> [WorldClockCoordinate] {
        let sun = sun(at: date)
        let declination = sun.latitude * .pi / 180
        let tangent = abs(declination) < 1e-10 ? (declination < 0 ? -1e-10 : 1e-10) : tan(declination)
        let boundary = (-360...360).map { step in
            let longitude = Double(step) / 2
            let latitude = atan(-cos((longitude - sun.longitude) * .pi / 180) / tangent) * 180 / .pi
            return WorldClockCoordinate(latitude: latitude, longitude: longitude)
        }
        let pole = declination >= 0 ? -90.0 : 90.0
        return boundary + [.init(latitude: pole, longitude: 180), .init(latitude: pole, longitude: -180)]
    }

    private static func angle(_ text: String, degrees: Int, limit: Double) -> Double? {
        guard text.first == "+" || text.first == "-" else { return nil }
        let digits = Array(text.dropFirst())
        guard digits.count == degrees + 2 || digits.count == degrees + 4,
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let whole = Double(String(digits.prefix(degrees))),
              let minutes = Double(String(digits[degrees..<(degrees + 2)])) else { return nil }
        let seconds = digits.count == degrees + 4 ? Double(String(digits.suffix(2)))! : 0
        let value = whole + minutes / 60 + seconds / 3600
        guard minutes < 60, seconds < 60, value <= limit else { return nil }
        return text.first == "-" ? -value : value
    }
}

struct WorldClockScrollAccumulator {
    private var remainder = 0.0

    mutating func consume(x: Double, y: Double) -> Int {
        guard x.isFinite, y.isFinite else { return 0 }
        let delta = abs(x) >= abs(y) ? x : y
        remainder += max(-525_600, min(525_600, delta * WorldClockMapGeometry.minutesPerPoint))
        let minutes = Int(remainder.rounded(.towardZero))
        remainder -= Double(minutes)
        return minutes
    }
}
