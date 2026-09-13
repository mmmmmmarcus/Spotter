import Foundation
import CoreGraphics

// List markers and table cells can have different fonts but still belong to the same visual row.
enum AIChatLineLayout {
    static func tops(for rectangles: [CGRect]) -> [CGFloat] {
        let sorted = rectangles.filter { !$0.isEmpty }.sorted { $0.minY < $1.minY }
        var rows: [CGRect] = []
        for rectangle in sorted {
            if let previous = rows.last, rectangle.minY < previous.maxY - 0.5 {
                rows[rows.count - 1] = previous.union(rectangle)
            } else {
                rows.append(rectangle)
            }
        }
        return rows.map(\.minY)
    }
}
