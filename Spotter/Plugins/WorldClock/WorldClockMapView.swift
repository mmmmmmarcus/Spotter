import SwiftUI

struct WorldClockMapView: View {
    @ObservedObject var store: WorldClockStore
    let query: String
    let selectedID: String?

    var body: some View {
        WorldClockMapContent(store: store, instant: store.mapInstant(for: query), selectedID: selectedID)
            .overlay {
                WorldClockMapInteraction(query: query,
                    begin: { store.beginMapDrag(query: query) },
                    update: { store.dragMap(to: $0, query: query) },
                    end: { store.endMapDrag() })
                    .accessibilityHidden(true)
            }
            .aspectRatio(Theme.Size.worldClockMapAspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row))
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.sm)
            .help("Drag to move the daylight boundary; scroll to adjust time")
    }
}

// A supplied instant keeps event maps independent of World Clock's live clock and scrub offset.
struct WorldClockMapContent: View {
    @ObservedObject var store: WorldClockStore
    let instant: Date
    var selectedID: String? = nil

    var body: some View {
        let night = WorldClockMapGeometry.nightPolygon(at: instant)
        let markers = store.cities.compactMap { city -> Marker? in
            guard let coordinate = store.coordinate(for: city),
                  let result = WorldClockEngine.result(for: city, now: instant, localTimeZone: .autoupdatingCurrent)
            else { return nil }
            return Marker(city: city, coordinate: coordinate, time: result.time,
                          selected: selectedID == city.id || selectedID == WorldClockEngine.conversionRowPrefix + city.id)
        }
        GeometryReader { geometry in
          ZStack {
            Theme.Colors.worldClockOcean
            Image("WorldClockLand")
                .resizable()
                .foregroundStyle(Theme.Colors.worldClockLand)
                .frame(width: geometry.size.width, height: geometry.size.width / 2)
                .position(x: geometry.size.width / 2,
                          y: WorldClockMapGeometry.croppedY(latitude: 0, width: geometry.size.width, height: geometry.size.height))
            Canvas { context, size in
                var grid = Path()
                for meridian in 1..<12 {
                    let x = size.width * Double(meridian) / 12
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(grid, with: .color(Theme.Colors.separator), lineWidth: 0.5)
                var shadow = Path()
                for (index, coordinate) in night.enumerated() {
                    let point = projected(coordinate, size: size)
                    if index == 0 { shadow.move(to: point) } else { shadow.addLine(to: point) }
                }
                shadow.closeSubpath()
                context.fill(shadow, with: .color(Theme.Colors.worldClockNight))
                context.stroke(shadow, with: .color(Theme.Colors.border), lineWidth: 0.75)
                drawMarkers(markers, context: context, size: size)
            }
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("World map with day and night regions")
        .accessibilityValue(markers.map { "\($0.city.name), \($0.time)" }.joined(separator: "; "))
    }

    private struct Marker {
        let city: WorldClockCity
        let coordinate: WorldClockCoordinate
        let time: String
        let selected: Bool
    }

    private func projected(_ coordinate: WorldClockCoordinate, size: CGSize) -> CGPoint {
        CGPoint(x: coordinate.x * size.width,
                y: WorldClockMapGeometry.croppedY(latitude: coordinate.latitude, width: size.width, height: size.height))
    }

    private func drawMarkers(_ markers: [Marker], context: GraphicsContext, size: CGSize) {
        let diameter = Theme.Size.worldClockMapMarker
        for marker in markers {
            let point = projected(marker.coordinate, size: size)
            if marker.selected {
                context.stroke(Path(ellipseIn: CGRect(x: point.x - diameter, y: point.y - diameter,
                                                       width: diameter * 2, height: diameter * 2)),
                               with: .color(.orange.opacity(0.55)), lineWidth: 1)
            }
            context.fill(Path(ellipseIn: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
                                                 width: diameter, height: diameter)), with: .color(.orange))
        }
        // Prioritize the focused city, then omit overlapping labels while retaining every location dot.
        var occupied: [CGRect] = markers.map { marker in
            let point = projected(marker.coordinate, size: size)
            return CGRect(x: point.x - diameter, y: point.y - diameter, width: diameter * 2, height: diameter * 2)
        }
        let visible = markers.filter { (0...size.height).contains(projected($0.coordinate, size: size).y) }
        let ordered = visible.filter(\.selected) + visible.filter { !$0.selected }
        let gap = Theme.Spacing.md
        for marker in ordered {
            let point = projected(marker.coordinate, size: size)
            let label = context.resolve(Text(marker.city.name + "\n" + marker.time)
                .font(.system(size: Theme.Size.worldClockMapLabel, weight: marker.selected ? .semibold : .medium).monospacedDigit())
                .foregroundStyle(.primary))
            let measured = label.measure(in: size)
            let positions = [
                CGPoint(x: point.x + gap, y: point.y - measured.height / 2),
                CGPoint(x: point.x - gap - measured.width, y: point.y - measured.height / 2),
                CGPoint(x: point.x - measured.width / 2, y: point.y + gap),
                CGPoint(x: point.x - measured.width / 2, y: point.y - gap - measured.height)
            ]
            let bounds = CGRect(origin: .zero, size: size).insetBy(dx: gap, dy: gap)
            for origin in positions {
                let rect = CGRect(origin: origin, size: measured)
                guard bounds.contains(rect), !occupied.contains(where: { $0.intersects(rect) }) else { continue }
                context.draw(label, at: origin, anchor: .topLeading)
                occupied.append(rect.insetBy(dx: -Theme.Spacing.xs, dy: -Theme.Spacing.xxs))
                break
            }
        }
    }
}
