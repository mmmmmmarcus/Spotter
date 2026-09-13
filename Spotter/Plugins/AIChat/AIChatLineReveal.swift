import SwiftUI

// Text layout anchors keep wrapping, Markdown fonts and window width in the same coordinate space.
struct AIChatLineReveal: ViewModifier {
    let isStreaming: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lineTops: [CGFloat] = []
    @State private var revealedLines = 0

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                if isStreaming {
                    GeometryReader { geometry in
                        let tops = AIChatLineLayout.tops(
                            for: layouts.flatMap { anchored in
                                let origin = geometry[anchored.origin]
                                return anchored.layout.map {
                                    $0.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y)
                                }
                            })
                        Color.clear
                            .onChange(of: tops, initial: true) { _, value in
                                if lineTops != value { lineTops = value }
                            }
                    }
                    .allowsHitTesting(false)
                }
            }
            .mask(alignment: .topLeading) {
                if !isStreaming {
                    Rectangle()
                } else {
                    GeometryReader { geometry in
                        ForEach(lineTops.indices, id: \.self) { index in
                            let top = index == 0 ? 0 : lineTops[index]
                            let bottom = index + 1 < lineTops.count ? lineTops[index + 1] : geometry.size.height
                            Rectangle()
                                .frame(height: max(0, bottom - top))
                                .offset(y: top)
                                .opacity(index < revealedLines ? 1 : 0)
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: revealedLines)
                        }
                    }
                }
            }
            .task(id: RevealTarget(count: lineTops.count, streaming: isStreaming)) {
                guard isStreaming else { return }
                let target = max(0, lineTops.count - 1)
                if revealedLines > target { revealedLines = target }
                let pending = target - revealedLines
                guard pending > 0 else { return }
                let delay = reduceMotion ? 0 : min(0.06, 0.12 / Double(pending))
                while revealedLines < target {
                    guard !Task.isCancelled else { return }
                    revealedLines += 1
                    if revealedLines < target {
                        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                    }
                }
            }
    }

    private struct RevealTarget: Equatable {
        let count: Int
        let streaming: Bool
    }
}
