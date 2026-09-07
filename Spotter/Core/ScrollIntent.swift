import SwiftUI

/// A palette scroll request: reset and follow need different, estimation-safe scroll ops on a lazy container, so the caller states which it wants instead of the view guessing from one shared token.
struct ScrollIntent: Equatable {
    enum Kind {
        /// Reset: restore the content origin. Estimation-proof — the origin anchor sits at offset 0, so no row height has to be guessed.
        case top
        /// Keyboard nav: minimal scroll-to-visible, which leaves an already-visible row exactly where it is.
        case follow
    }

    var kind: Kind
    /// Distinguishes back-to-back intents of the same kind so `onChange` still fires.
    var nonce = UUID()
}

extension View {
    /// Marks the top of a scroll view's content as the `scrollToOrigin` target. Apply to the scrolled content *after* its padding: the anchor rides in a zero-height overlay, so it pins the true origin (offset 0) without taking part in layout — scrolling to the first row instead would leave the content's top padding hidden under the header.
    func scrollOriginAnchor() -> some View {
        overlay(alignment: .top) {
            Color.clear.frame(height: 0).id(ScrollOrigin.id)
        }
    }
}

private enum ScrollOrigin {
    nonisolated static let id = "scroll-origin-anchor"
}

extension ScrollViewProxy {
    /// Restores the exact resting offset, insets included — requires `scrollOriginAnchor()` on the content.
    func scrollToOrigin() {
        scrollTo(ScrollOrigin.id, anchor: .top)
    }

    /// Minimal scroll-to-visible: brings `id` just inside the viewport and never repositions it once visible, so the list stays put while the selection walks across it.
    func reveal(_ id: String) {
        scrollTo(id, anchor: nil)
    }
}

extension View {
    /// Drives one palette list's scroll from the shared `ScrollIntent`. Attach to the `ScrollView`, inside its `ScrollViewReader`.
    ///
    /// The intent is applied **on mount as well as on change**: a mode switch writes the arriving intent in the same update that mounts the arriving list, so the list is born already holding it and `onChange` — which never fires for a view's initial value — would let that reset through unapplied. It is applied once more when the scroll view's top content inset lands, because a scroll view that mounted before its `safeAreaInset` header rests one inset below the origin; keying that on the inset itself makes the correction deterministic where a post-mount timer only raced it.
    ///
    /// `followIsFirstRow` snaps a `.follow` to the origin instead of revealing the row, so the first row's section header shows too — a nil anchor won't, since the row is already visible.
    func paletteScroll(
        _ intent: ScrollIntent, proxy: ScrollViewProxy, followIsFirstRow: Bool,
        followRowID: String?
    ) -> some View {
        modifier(
            PaletteScrollIntent(
                intent: intent, proxy: proxy, followIsFirstRow: followIsFirstRow,
                followRowID: followRowID))
    }
}

/// The one place a `ScrollIntent` reaches a scroll view; see `View.paletteScroll`.
private struct PaletteScrollIntent: ViewModifier {
    let intent: ScrollIntent
    let proxy: ScrollViewProxy
    let followIsFirstRow: Bool
    let followRowID: String?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: apply)
            .onChange(of: intent) { apply() }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.top } action: { _, _ in
                // Only ever re-asserts a pending reset, and an inset never moves in response to the user's own scrolling, so this cannot fight a list the user has scrolled.
                if case .top = intent.kind { proxy.scrollToOrigin() }
            }
    }

    private func apply() {
        switch intent.kind {
        case .top:
            proxy.scrollToOrigin()
        case .follow:
            if followIsFirstRow {
                proxy.scrollToOrigin()
            } else if let followRowID {
                proxy.reveal(followRowID)
            }
        }
    }
}
