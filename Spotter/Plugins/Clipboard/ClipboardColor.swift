import Foundation

struct ClipboardColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static func parse(_ text: String) -> ClipboardColor? {
        guard text.utf8.count <= 128 else { return nil }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("#") { return hex(String(token.dropFirst())) }
        let lower = token.lowercased()
        if lower.hasPrefix("rgb(") || lower.hasPrefix("rgba(") { return rgb(lower) }
        if lower.hasPrefix("hsl(") || lower.hasPrefix("hsla(") { return hsl(lower) }
        return nil
    }

    private static func hex(_ digits: String) -> ClipboardColor? {
        guard [3, 4, 6, 8].contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        let values: [Double]
        if digits.count <= 4 {
            values = digits.compactMap { $0.hexDigitValue }.map { Double($0 * 17) / 255 }
        } else {
            values = stride(from: 0, to: digits.count, by: 2).compactMap { offset in
                let start = digits.index(digits.startIndex, offsetBy: offset)
                let end = digits.index(start, offsetBy: 2)
                return UInt8(digits[start..<end], radix: 16).map { Double($0) / 255 }
            }
        }
        guard values.count == (digits.count <= 4 ? digits.count : digits.count / 2) else { return nil }
        return ClipboardColor(red: values[0], green: values[1], blue: values[2], alpha: values.count == 4 ? values[3] : 1)
    }

    private static func rgb(_ token: String) -> ClipboardColor? {
        guard let values = components(token), values.count == 3 || values.count == 4 else { return nil }
        func channel(_ value: String) -> Double? {
            if value.hasSuffix("%") { return Double(value.dropLast()).map { min(max($0 / 100, 0), 1) } }
            return Double(value).map { min(max($0 / 255, 0), 1) }
        }
        guard let red = channel(values[0]), let green = channel(values[1]), let blue = channel(values[2]) else { return nil }
        let alpha = values.count == 4 ? (Double(values[3]).map { min(max($0, 0), 1) } ?? -1) : 1
        guard alpha >= 0 else { return nil }
        return ClipboardColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func hsl(_ token: String) -> ClipboardColor? {
        guard let values = components(token), values.count == 3 || values.count == 4,
            let hueRaw = Double(values[0].replacingOccurrences(of: "deg", with: "")),
            values[1].hasSuffix("%"), values[2].hasSuffix("%"),
            let saturation = Double(values[1].dropLast()), let lightness = Double(values[2].dropLast())
        else { return nil }
        let h = ((hueRaw.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 60
        let s = min(max(saturation / 100, 0), 1)
        let l = min(max(lightness / 100, 0), 1)
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch h {
        case ..<1: (c, x, 0)
        case ..<2: (x, c, 0)
        case ..<3: (0, c, x)
        case ..<4: (0, x, c)
        case ..<5: (x, 0, c)
        default: (c, 0, x)
        }
        let m = l - c / 2
        let alpha = values.count == 4 ? (Double(values[3]).map { min(max($0, 0), 1) } ?? -1) : 1
        guard alpha >= 0 else { return nil }
        return ClipboardColor(red: r + m, green: g + m, blue: b + m, alpha: alpha)
    }

    private static func components(_ token: String) -> [String]? {
        guard let open = token.firstIndex(of: "("), token.hasSuffix(")") else { return nil }
        let body = token[token.index(after: open)..<token.index(before: token.endIndex)]
        let normalized = body.replacingOccurrences(of: "/", with: ",")
        let values = normalized.contains(",")
            ? normalized.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            : normalized.split(whereSeparator: \.isWhitespace).map(String.init)
        return values.isEmpty ? nil : values
    }
}
