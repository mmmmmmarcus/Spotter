import SwiftUI

struct ExtensionFormKeys: ViewModifier {
    let field: ExtensionFormField
    let onActivate: () -> Void
    let onSubmit: () -> Void
    @Environment(ExtensionPaletteState.self) private var palette

    func body(content: Content) -> some View {
        content.onKeyPress(keys: ExtensionFormKey.enterKeys.union([.space]), phases: [.down, .repeat]) {
            press in
            switch ExtensionFormKey.resolve(
                field: field, key: press.key, modifiers: press.modifiers,
                repeating: press.phase == .repeat, menuOpen: palette.menuOpen,
                composing: palette.isComposing)
            {
            case .activate: onActivate()
            case .submit: onSubmit()
            case .consume: break
            case .ignored: return .ignored
            }
            return .handled
        }
    }
}
