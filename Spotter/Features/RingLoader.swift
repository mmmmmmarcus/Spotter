import SwiftUI

/// The shared loading indicator: a ring stroked from the top over a faint track. Determinate when a
/// fraction is known, otherwise a partial arc turning forever for a phase with nothing to measure.
struct RingLoader: View {
    /// Nil is indeterminate — the ring spins instead of filling.
    var progress: Double?
    var size: CGFloat

    private var lineWidth: CGFloat { max(1.5, size * 0.11) }
    private var stroke: StrokeStyle { StrokeStyle(lineWidth: lineWidth, lineCap: .round) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.controlSurface, lineWidth: lineWidth)
            arc
        }
        // Insets the stroke so the ring's outer edge lands on `size` rather than half a line past it.
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var arc: some View {
        if let progress {
            Circle()
                // A rounded cap needs a sliver of trim to draw at all, so zero still reads as a dot.
                .trim(from: 0, to: min(max(progress, 0.001), 1))
                .stroke(Theme.Colors.textSecondary, style: stroke)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: progress)
        } else {
            // Clock-driven rotation survives determinate/indeterminate swaps and reopening the palette.
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Theme.Colors.textSecondary, style: stroke)
                    .rotationEffect(.degrees(turn * 360 - 90))
            }
        }
    }
}
