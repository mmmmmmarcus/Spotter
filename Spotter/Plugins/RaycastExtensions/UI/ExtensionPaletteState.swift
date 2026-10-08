import SwiftUI

@MainActor
@Observable
final class ExtensionPaletteState {
    var menuQuery = ""
    var menuOpen = false
    var isComposing: Bool { (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true }
    var hoverHighlightArmed = true
    var controlListDismissToken = UUID()
    private let palette: PaletteViewModel
    var selection: Int {
        get { palette.selection }
        set { palette.selection = newValue }
    }
    var isEditingField = false
    init(palette: PaletteViewModel) { self.palette = palette }
    func dismissControlList() { controlListDismissToken = UUID(); menuOpen = false }
    func noteEditingField(_ editing: Bool) { isEditingField = editing }
    func notePointerMoved(to point: CGPoint) { hoverHighlightArmed = true }
    func disarmHoverHighlight(pointerAt point: CGPoint) { hoverHighlightArmed = false }
    func noteControlListOpen(_ open: Bool) { menuOpen = open }
}

struct RaycastImportCandidate: Identifiable {
    let installed: InstalledExtension
    let isInstalled: Bool
    var id: String { installed.id }
}

extension View {
    func scrollFollowsSelection(_ intent: ScrollIntent, row: String?, atOrigin: Bool, proxy: ScrollViewProxy) -> some View {
        onChange(of: intent) { _, value in
            if value.kind == .top || atOrigin { proxy.scrollToOrigin() }
            else if let row { proxy.reveal(row) }
        }
    }
}
