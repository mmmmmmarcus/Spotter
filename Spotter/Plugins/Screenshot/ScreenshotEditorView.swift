import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Editing state for one capture; the window is rebuilt per capture, so this owns exactly one image.
@MainActor
final class ScreenshotEditorModel: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case rectangle, ellipse, freehand, text

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .rectangle: "rectangle"
            case .ellipse: "oval"
            case .freehand: "pencil.line"
            case .text: "textformat"
            }
        }
        var help: String {
            switch self {
            case .rectangle: "Rectangle — right-drag for an arrow (R)"
            case .ellipse: "Oval (O)"
            case .freehand: "Pencil (P)"
            case .text: "Text (T)"
            }
        }
        var shortcut: KeyEquivalent {
            switch self {
            case .rectangle: "r"
            case .ellipse: "o"
            case .freehand: "p"
            case .text: "t"
            }
        }
    }

    /// Stroke and type presets in view points; both scale into image pixels at creation time.
    enum WidthPreset: CaseIterable, Identifiable {
        case thin, regular, bold

        var id: Self { self }
        var stroke: CGFloat {
            switch self {
            case .thin: 2
            case .regular: 4
            case .bold: 8
            }
        }
        var fontSize: CGFloat {
            switch self {
            case .thin: 16
            case .regular: 24
            case .bold: 36
            }
        }
        var dotDiameter: CGFloat {
            switch self {
            case .thin: 4
            case .regular: 6
            case .bold: 9
            }
        }
        var help: String {
            switch self {
            case .thin: "Thin"
            case .regular: "Regular"
            case .bold: "Bold"
            }
        }
    }

    struct PendingText {
        var origin: CGPoint
        var string: String
        var fontSize: CGFloat
    }

    let capture: ScreenshotCapturePayload

    @Published var tool: Tool = .rectangle
    @Published var color: ScreenshotAnnotationColor = .red
    @Published var width: WidthPreset = .regular
    @Published private(set) var annotations: [ScreenshotAnnotation] = []
    @Published private(set) var redoStack: [ScreenshotAnnotation] = []
    @Published private(set) var draft: ScreenshotAnnotation?
    @Published var pendingText: PendingText?
    @Published var isExporting = false

    init(capture: ScreenshotCapturePayload) {
        self.capture = capture
    }

    var imageSize: CGSize {
        CGSize(width: capture.image.width, height: capture.image.height)
    }

    var canUndo: Bool { !annotations.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// The committed marks plus the in-flight drag, which is what the canvas paints every frame.
    var visibleAnnotations: [ScreenshotAnnotation] {
        draft.map { annotations + [$0] } ?? annotations
    }

    /// `secondary` is the right mouse button: only the rectangle tool reads it, drawing an arrow.
    func dragChanged(from start: CGPoint, to current: CGPoint, scale: CGFloat, secondary: Bool) {
        guard tool != .text, tool == .rectangle || !secondary else { return }
        let strokeWidth = width.stroke / scale
        let shape: ScreenshotAnnotation.Shape
        switch tool {
        case .rectangle:
            shape = secondary
                ? .arrow(start: start, end: current)
                : .rectangle(ScreenshotAnnotationGeometry.normalizedRect(from: start, to: current))
        case .ellipse:
            shape = .ellipse(ScreenshotAnnotationGeometry.normalizedRect(from: start, to: current))
        case .freehand:
            if case .freehand(let points) = draft?.shape {
                shape = .freehand(points + [current])
            } else {
                shape = .freehand([start, current])
            }
        case .text:
            return
        }
        draft = ScreenshotAnnotation(shape: shape, color: color, width: strokeWidth)
    }

    func dragEnded(from start: CGPoint, to end: CGPoint, scale: CGFloat, secondary: Bool) {
        if tool == .text {
            guard !secondary else { return }
            commitPendingText()
            pendingText = PendingText(origin: end, string: "", fontSize: width.fontSize / scale)
            return
        }
        defer { draft = nil }
        // A twitch of a couple of pixels is a misclick, not a mark.
        guard let draft, hypot(end.x - start.x, end.y - start.y) * scale >= 3 else { return }
        annotations.append(draft)
        redoStack = []
    }

    func commitPendingText() {
        guard let pending = pendingText else { return }
        pendingText = nil
        let trimmed = pending.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        annotations.append(
            ScreenshotAnnotation(
                shape: .text(
                    origin: pending.origin, string: trimmed, fontSize: pending.fontSize),
                color: color,
                width: 1))
        redoStack = []
    }

    func undo() {
        pendingText = nil
        guard let last = annotations.popLast() else { return }
        redoStack.append(last)
    }

    func redo() {
        guard let restored = redoStack.popLast() else { return }
        annotations.append(restored)
    }
}

/// The Capso-style post-capture workspace: the capture at fit scale with mark-up tools above it.
struct ScreenshotEditorView: View {
    /// Matches the id `AppCore.showScreenshotEditor` opens under, so Cancel closes this window.
    static let windowID = "screenshot-editor"
    /// Shared with the window sizing so the canvas gets the space the bar does not.
    static let toolbarHeight: CGFloat = 68

    @EnvironmentObject private var core: AppCore
    @Environment(\.displayScale) private var displayScale
    @StateObject private var model: ScreenshotEditorModel
    @FocusState private var textEntryFocused: Bool

    init(capture: ScreenshotCapturePayload) {
        _model = StateObject(wrappedValue: ScreenshotEditorModel(capture: capture))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            canvasArea
        }
        .ignoresSafeArea(edges: .top)
        // Behind-window blending, as Notes uses: a SwiftUI `Material` only blurs what is inside the app, so the desktop would stay opaque behind the window.
        .background(VisualEffectView(material: .hudWindow, blending: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous))
    }

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // The window hides its traffic lights, so this is the only way to close it.
            cancelButton
            Spacer(minLength: Theme.Spacing.md)
            // Undo and redo read as one control: a container merges closely-spaced glass shapes.
            GlassEffectContainer(spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xxs) {
                    Button { model.undo() } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!model.canUndo)
                    .keyboardShortcut("z", modifiers: .command)
                    .help("Undo")
                    Button { model.redo() } label: {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                    }
                    .disabled(!model.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .help("Redo")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            Button { save() } label: {
                Label("Save…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(model.isExporting)
            .help("Save…")
            Button { copy() } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.isExporting)
            .help("Copy")
        }
        // Icon-only everywhere but Cancel, so each label doubles as the tooltip and the VoiceOver name.
        .labelStyle(.iconOnly)
        .controlSize(.extraLarge)
        // Scales the SF Symbols with the buttons; Cancel's text is unaffected.
        .imageScale(.large)
        .font(Theme.Typography.bar)
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .frame(height: Self.toolbarHeight)
        // The window opts out of background dragging so a stroke on the canvas can never move it, which makes this strip the one deliberate handle. Controls above take their own clicks first, so only the gaps between them drag.
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    /// A bare letter is a key equivalent, which fires even while a field edits — so the shortcut is only attached while no text annotation is being typed.
    @ViewBuilder
    private func toolButton(_ tool: ScreenshotEditorModel.Tool) -> some View {
        let button = Button {
            model.commitPendingText()
            model.tool = tool
        } label: {
            Image(systemName: tool.symbol)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.keyCap)
                        .fill(model.tool == tool ? Theme.Colors.selection : .clear))
        }
        .buttonStyle(.plain)
        .help(tool.help)
        if model.pendingText == nil {
            button.keyboardShortcut(tool.shortcut, modifiers: [])
        } else {
            button
        }
    }

    private func colorButton(_ color: ScreenshotAnnotationColor) -> some View {
        let rgba = color.rgba
        return Button {
            model.color = color
        } label: {
            Circle()
                .fill(Color(red: rgba.red, green: rgba.green, blue: rgba.blue))
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Theme.Colors.border, lineWidth: 1))
                .overlay(
                    Circle()
                        .stroke(Theme.Colors.textSecondary, lineWidth: model.color == color ? 2 : 0)
                        .padding(-3))
                .padding(3)
        }
        .buttonStyle(.plain)
    }

    private func widthButton(_ preset: ScreenshotEditorModel.WidthPreset) -> some View {
        Button {
            model.width = preset
        } label: {
            Circle()
                .fill(Theme.Colors.textSecondary)
                .frame(width: preset.dotDiameter, height: preset.dotDiameter)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.keyCap)
                        .fill(model.width == preset ? Theme.Colors.selection : .clear))
                // Without this only the dot itself was clickable: a `.clear` fill takes no hits, so an unselected preset had a 4-point target.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(preset.help)
    }

    private var canvasArea: some View {
        GeometryReader { geometry in
            let fitted = fittedSize(in: geometry.size)
            let scale = fitted.width / model.imageSize.width
            ZStack(alignment: .topLeading) {
                canvas(scale: scale)
                    .frame(width: fitted.width, height: fitted.height)
                if let pending = model.pendingText {
                    textEntryField(pending, scale: scale)
                }
            }
            .frame(width: fitted.width, height: fitted.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.thumbnail)
                    .stroke(Theme.Colors.border, lineWidth: 1))
            .frame(
                maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(Theme.Spacing.xl)
        .overlay(alignment: .bottomLeading) {
            floatingPalette { toolPaletteContent }
        }
        .overlay(alignment: .bottomTrailing) {
            floatingPalette { colorPaletteContent }
        }
    }

    /// Escape is attached only when no text annotation is being typed — otherwise it would close the
    /// window out from under a half-written mark instead of discarding it.
    @ViewBuilder
    private var cancelButton: some View {
        let button = Button("Cancel") { core.closePluginWindow(id: Self.windowID) }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .help("Close without copying")
        if model.pendingText == nil {
            button.keyboardShortcut(.cancelAction)
        } else {
            button
        }
    }

    /// The floating corner cards; a shared wrapper keeps both sides the same surface.
    private func floatingPalette<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: Theme.Spacing.xs) { content() }
            .fixedSize()
            .padding(Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colors.cardFill))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Colors.cardStroke))
            .padding(Theme.Spacing.xl)
    }

    private var toolPaletteContent: some View {
        ForEach(ScreenshotEditorModel.Tool.allCases) { tool in
            toolButton(tool)
        }
    }

    /// Colors first, then the stroke weights that apply to them — one card, two groups, no rule
    /// between them. The groups are nested stacks rather than one stack with a spacer: a spacer view
    /// takes the whole width the overlay proposes, which stretched the card across the canvas.
    private var colorPaletteContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.xs) {
                ForEach(ScreenshotAnnotationColor.allCases, id: \.self) { color in
                    colorButton(color)
                }
            }
            VStack(spacing: Theme.Spacing.xs) {
                ForEach(ScreenshotEditorModel.WidthPreset.allCases) { preset in
                    widthButton(preset)
                }
            }
        }
    }

    private func canvas(scale: CGFloat) -> some View {
        Canvas { context, size in
            context.draw(
                Image(decorative: model.capture.image, scale: 1),
                in: CGRect(origin: .zero, size: size))
            let annotations = model.visibleAnnotations
            guard !annotations.isEmpty else { return }
            context.withCGContext { cg in
                cg.scaleBy(x: scale, y: scale)
                ScreenshotAnnotationRenderer.draw(annotations, in: cg)
            }
        }
        .overlay(
            CanvasMouseView(
                onChanged: { start, current, secondary in
                    model.dragChanged(
                        from: imagePoint(start, scale: scale),
                        to: imagePoint(current, scale: scale),
                        scale: scale,
                        secondary: secondary)
                },
                onEnded: { start, end, secondary in
                    model.dragEnded(
                        from: imagePoint(start, scale: scale),
                        to: imagePoint(end, scale: scale),
                        scale: scale,
                        secondary: secondary)
                    if model.tool == .text, !secondary { textEntryFocused = true }
                }))
    }

    private func textEntryField(
        _ pending: ScreenshotEditorModel.PendingText, scale: CGFloat
    ) -> some View {
        let rgba = model.color.rgba
        return TextField(
            "Text",
            text: Binding(
                get: { model.pendingText?.string ?? "" },
                set: { model.pendingText?.string = $0 }))
            .textFieldStyle(.plain)
            .font(.system(size: pending.fontSize * scale, weight: .bold))
            .foregroundStyle(Color(red: rgba.red, green: rgba.green, blue: rgba.blue))
            .frame(width: 280)
            .focused($textEntryFocused)
            .onSubmit { model.commitPendingText() }
            .onExitCommand { model.pendingText = nil }
            .offset(x: pending.origin.x * scale, y: pending.origin.y * scale)
    }

    /// Points per image pixel. Capped at `1 / displayScale`, which is one image pixel per device
    /// pixel: past that the canvas would be enlarging the capture, and a Retina screen would show a
    /// small shot at 2× — soft enough to read as a bad capture rather than a zoomed preview.
    private func fittedSize(in available: CGSize) -> CGSize {
        let image = model.imageSize
        guard image.width > 0, image.height > 0, available.width > 0, available.height > 0 else {
            return CGSize(width: 1, height: 1)
        }
        let oneToOne = 1 / max(displayScale, 1)
        let scale = min(available.width / image.width, available.height / image.height, oneToOne)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    private func imagePoint(_ viewPoint: CGPoint, scale: CGFloat) -> CGPoint {
        let image = model.imageSize
        return CGPoint(
            x: min(max(viewPoint.x / scale, 0), image.width),
            y: min(max(viewPoint.y / scale, 0), image.height))
    }

    private func copy() {
        model.commitPendingText()
        model.isExporting = true
        let capture = model.capture
        let annotations = model.annotations
        Task {
            let flattened = await Task.detached(priority: .userInitiated) {
                ScreenshotAnnotationRenderer.flatten(
                    image: capture.image, annotations: annotations)
            }.value
            guard let flattened,
                await core.screenshot.copyEdited(flattened, roundedCorners: capture.roundedCorners)
            else {
                model.isExporting = false
                core.hud.show(
                    title: "Copy Failed", symbol: "exclamationmark.triangle", isNoOp: true)
                return
            }
            model.isExporting = false
            core.hud.show(title: "Screenshot Copied", symbol: "checkmark.circle")
            core.closePluginWindow(id: Self.windowID)
        }
    }

    private func save() {
        model.commitPendingText()
        model.isExporting = true
        let capture = model.capture
        let annotations = model.annotations
        let format = core.screenshot.fileFormat
        Task {
            let encoded = await Task.detached(priority: .userInitiated) {
                ScreenshotAnnotationRenderer.flatten(
                    image: capture.image, annotations: annotations
                ).flatMap {
                    ScreenshotImageProcessor.fileData(
                        from: $0, format: format, roundedCorners: capture.roundedCorners)
                }
            }.value
            model.isExporting = false
            guard let encoded else {
                core.hud.show(
                    title: "Save Failed", symbol: "exclamationmark.triangle", isNoOp: true)
                return
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [format.contentType]
            panel.nameFieldStringValue = "\(capture.fileName).\(format.fileExtension)"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try encoded.write(to: url)
                core.hud.show(title: "Screenshot Saved", symbol: "checkmark.circle")
            } catch {
                AppLog.error("screenshot", "Saving failed: \(error.localizedDescription)")
                core.hud.show(
                    title: "Save Failed", symbol: "exclamationmark.triangle", isNoOp: true)
            }
        }
    }

}

/// SwiftUI's DragGesture only speaks the primary button, so the canvas listens through AppKit:
/// the rectangle tool's right-drag arrow needs both buttons on one surface.
private struct CanvasMouseView: NSViewRepresentable {
    var onChanged: (CGPoint, CGPoint, Bool) -> Void
    var onEnded: (CGPoint, CGPoint, Bool) -> Void

    func makeNSView(context: Context) -> MouseView {
        let view = MouseView()
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateNSView(_ view: MouseView, context: Context) {
        view.onChanged = onChanged
        view.onEnded = onEnded
    }

    final class MouseView: NSView {
        var onChanged: ((CGPoint, CGPoint, Bool) -> Void)?
        var onEnded: ((CGPoint, CGPoint, Bool) -> Void)?
        private var dragStart: CGPoint?
        private var secondary = false

        // Top-left origin, matching the SwiftUI canvas the view overlays.
        override var isFlipped: Bool { true }

        override func mouseDown(with event: NSEvent) { begin(event, secondary: false) }
        override func rightMouseDown(with event: NSEvent) { begin(event, secondary: true) }
        override func mouseDragged(with event: NSEvent) { moved(event) }
        override func rightMouseDragged(with event: NSEvent) { moved(event) }
        override func mouseUp(with event: NSEvent) { ended(event) }
        override func rightMouseUp(with event: NSEvent) { ended(event) }

        private func begin(_ event: NSEvent, secondary: Bool) {
            dragStart = convert(event.locationInWindow, from: nil)
            self.secondary = secondary
        }

        private func moved(_ event: NSEvent) {
            guard let dragStart else { return }
            onChanged?(dragStart, convert(event.locationInWindow, from: nil), secondary)
        }

        private func ended(_ event: NSEvent) {
            guard let dragStart else { return }
            self.dragStart = nil
            onEnded?(dragStart, convert(event.locationInWindow, from: nil), secondary)
        }
    }
}
