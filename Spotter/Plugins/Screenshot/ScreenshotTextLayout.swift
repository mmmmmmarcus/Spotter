import CoreGraphics
import Foundation

/// Assembles recognized text fragments back into reading order. Vision returns observations in no
/// useful order, so joining them as they arrive scrambles anything with more than one line. Pure, so
/// the harness can pin the ordering against shapes a real capture would produce.
enum ScreenshotTextLayout {
    /// One recognized fragment: its string and its box in Vision's normalized space, where the
    /// origin is bottom-left and both axes run 0...1.
    struct Fragment: Equatable {
        var string: String
        var box: CGRect

        init(string: String, box: CGRect) {
            self.string = string
            self.box = box
        }
    }

    /// Fragments whose vertical spans overlap by at least this much of the shorter one count as the
    /// same line. Generous enough for mixed font sizes, tight enough to keep stacked rows apart.
    static let lineOverlap: CGFloat = 0.3

    /// Top-to-bottom, then left-to-right within each line, joined by newlines.
    static func text(from fragments: [Fragment]) -> String {
        lines(from: fragments)
            .map { $0.map(\.string).joined(separator: " ") }
            .joined(separator: "\n")
    }

    /// The grouping itself, exposed so the harness can pin rows independently of the joining.
    static func lines(from fragments: [Fragment]) -> [[Fragment]] {
        let usable = fragments.filter { !$0.string.isEmpty }
        // Vision's y grows upward, so descending midY walks the capture from its top down.
        let ordered = usable.sorted { $0.box.midY > $1.box.midY }
        var lines: [[Fragment]] = []
        for fragment in ordered {
            if let index = lines.indices.last, shares(line: lines[index], with: fragment) {
                lines[index].append(fragment)
            } else {
                lines.append([fragment])
            }
        }
        return lines.map { $0.sorted { $0.box.minX < $1.box.minX } }
    }

    private static func shares(line: [Fragment], with fragment: Fragment) -> Bool {
        line.contains { overlap(of: $0.box, and: fragment.box) >= lineOverlap }
    }

    /// The shared fraction of the shorter fragment's height, so a tall heading beside small text
    /// does not swallow the row below it.
    static func overlap(of first: CGRect, and second: CGRect) -> CGFloat {
        let shared = min(first.maxY, second.maxY) - max(first.minY, second.minY)
        guard shared > 0 else { return 0 }
        let shortest = min(first.height, second.height)
        guard shortest > 0 else { return 0 }
        return shared / shortest
    }
}
