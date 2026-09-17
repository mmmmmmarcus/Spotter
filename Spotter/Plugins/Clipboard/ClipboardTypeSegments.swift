import AppKit
import SwiftUI

struct ClipboardTypeSegments: NSViewRepresentable {
    let filter: ClipboardFilter
    let select: (ClipboardFilter) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(select: select) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = ClipboardSegmentedControl()
        control.segmentCount = ClipboardFilter.allCases.count
        control.trackingMode = .selectOne
        control.segmentStyle = .rounded
        control.controlSize = .small
        control.setAccessibilityLabel("Clipboard type")
        for (index, filter) in ClipboardFilter.allCases.enumerated() {
            control.setImage(NSImage(systemSymbolName: filter.systemImage,
                                     accessibilityDescription: filter.title), forSegment: index)
            control.setToolTip(filter.title, forSegment: index)
            control.setWidth(Theme.Size.clipboardFilterSegmentWidth, forSegment: index)
        }
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        control.selectedSegment = ClipboardFilter.allCases.firstIndex(of: filter) ?? 0
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.select = select
        control.selectedSegment = ClipboardFilter.allCases.firstIndex(of: filter) ?? 0
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl,
                      context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    @MainActor
    final class Coordinator: NSObject {
        var select: (ClipboardFilter) -> Void
        init(select: @escaping (ClipboardFilter) -> Void) { self.select = select }

        @objc func changed(_ control: NSSegmentedControl) {
            guard ClipboardFilter.allCases.indices.contains(control.selectedSegment) else { return }
            select(ClipboardFilter.allCases[control.selectedSegment])
        }
    }
}

private final class ClipboardSegmentedControl: NSSegmentedControl {
    // Choosing a type must not take the insertion point away from the palette search field.
    override var acceptsFirstResponder: Bool { false }
}
