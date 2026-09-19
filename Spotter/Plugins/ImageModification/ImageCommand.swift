import Foundation

enum ImageCommand: Equatable, Sendable {
    case convert(ImageFormat)
    case resize(width: Int, height: Int)
    case scale(Double)
    case optimize(Double)

    var operation: ImageOperation {
        switch self {
        case .convert: .convert
        case .resize: .resize
        case .scale: .scale
        case .optimize: .optimize
        }
    }

    var argument: String {
        switch self {
        case .convert(let format): format.rawValue
        case .resize(let width, let height): "\(width)x\(height)"
        case .scale(let factor): Self.number(factor)
        case .optimize(let quality): Self.number(quality * 100) + "%"
        }
    }

    var id: String { operation.rawValue + " " + argument }

    var title: String {
        switch self {
        case .convert(let format): "Convert to \(format.title)"
        case .resize(let width, let height): "Resize to Fit \(width) × \(height)"
        case .scale(let factor): "Scale to \(Self.number(factor))×"
        case .optimize(let quality): "Optimize at \(Self.number(quality * 100))% Quality"
        }
    }

    func apply(to request: inout ImageModificationRequest) {
        request.operation = operation
        switch self {
        case .convert(let format): request.format = format
        case .resize(let width, let height):
            request.width = width
            request.height = height
            request.preserveAspect = true
        case .scale(let factor): request.scale = factor
        case .optimize(let quality): request.quality = quality
        }
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value && abs(value) < Double(Int.max) ? String(Int(value)) : String(value)
    }
}

enum ImageCommandParser {
    static let operations: [ImageOperation] = [.convert, .resize, .scale, .optimize]

    static func parse(_ query: String) -> ImageCommand? {
        guard query.count <= 256 else { return nil }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for operation in operations {
            guard text.hasPrefix(operation.rawValue) else { continue }
            var argument = String(text.dropFirst(operation.rawValue.count))
                .trimmingCharacters(in: .whitespaces)
            for prefix in ["image ", "to ", "by ", "at "] where argument.hasPrefix(prefix) {
                argument = String(argument.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
            return parseArgument(argument, operation: operation)
        }
        return nil
    }

    static func format(_ argument: String) -> ImageFormat? {
        switch argument.lowercased() {
        case "jpg", "jpe": .jpeg
        case "tif": .tiff
        default: ImageFormat(rawValue: argument.lowercased())
        }
    }

    static func parseArgument(_ raw: String, operation: ImageOperation) -> ImageCommand? {
        guard raw.count <= 256 else { return nil }
        let argument = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch operation {
        case .convert:
            return format(argument).map(ImageCommand.convert)
        case .resize:
            let parts = argument.replacingOccurrences(of: "×", with: "x")
                .split(separator: "x", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard (1...2).contains(parts.count),
                  let width = Int(parts[0]), let height = Int(parts.last!),
                  (1...32768).contains(width), (1...32768).contains(height)
            else { return nil }
            return .resize(width: width, height: height)
        case .scale:
            let percent = argument.hasSuffix("%")
            let hasSuffix = percent || argument.hasSuffix("x") || argument.hasSuffix("×")
            let text = hasSuffix ? String(argument.dropLast()) : argument
            guard let number = decimal(text), number > 0 else { return nil }
            let factor = percent ? number / 100 : number
            guard factor.isFinite, factor > 0 else { return nil }
            return .scale(factor)
        case .optimize:
            let percent = argument.hasSuffix("%")
            let text = percent ? String(argument.dropLast()) : argument
            guard let number = decimal(text) else { return nil }
            let quality = percent || number > 1 ? number / 100 : number
            guard (0.05...1).contains(quality) else { return nil }
            return .optimize(quality)
        default: return nil
        }
    }

    static func presets(for operation: ImageOperation) -> [ImageCommand] {
        switch operation {
        case .convert: ImageFormat.allCases.map(ImageCommand.convert)
        case .resize: [(640, 480), (1280, 720), (1920, 1080), (3840, 2160)].map {
            .resize(width: $0.0, height: $0.1)
        }
        case .scale: [0.5, 1, 2, 3].map(ImageCommand.scale)
        case .optimize: [0.6, 0.82, 0.95].map(ImageCommand.optimize)
        default: []
        }
    }

    private static func decimal(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard text.range(of: "^(?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$", options: .regularExpression) != nil,
              let value = Double(text), value.isFinite else { return nil }
        return value
    }
}
