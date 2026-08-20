import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Editing state for one capture; the window is rebuilt per capture, so this owns exactly one image.
@MainActor
final class ScreenshotEditorModel: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case arrow, rectangle, ellipse, freehand, text

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .arrow: "arrow.up.right"
            case .rectangle: "rectangle"
            case .ellipse: "oval"
            case .freehand: "scribble"
            case .text: "textformat"
            }
        }
        var help: String {
            switch self {
            case .arrow: "Arrow"
            case .rectangle: "Rectangle"
            case .ellipse: "Ellipse"
            case .freehand: "Draw"
            case .text: "Text"
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
    }

    struct PendingText {
        var origin: CGPoint
        var string: String
        var fontSize: CGFloat
    }

    let capture: ScreenshotCapturePayload

    @Published var tool: Tool = .arrow
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

    func dragChanged(from start: CGPoint, to current: CGPoint, scale: CGFloat) {
        guard tool != .text else { return }
        let strokeWidth = width.stroke / scale
        let shape: ScreenshotAnnotation.Shape
        switch tool {
        case .arrow:
            shape = .arrow(start: start, end: current)
        case .rectangle:
            shape = .rectangle(ScreenshotAnnotationGeometry.normalizedRect(from: start, to: current))
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

    func dragEnded(from start: CGPoint, to end: CGPoint, scale: CGFloat) {
        if tool == .text {
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
    @EnvironmentObject private var core: AppCore
    @StateObject private var model: ScreenshotEditorModel
    @FocusState private var textEntryFocused: Bool
    @State private var dragStart: CGPoint?

    init(capture: ScreenshotCapturePayload) {
        _model = StateObject(wrappedValue: ScreenshotEditorModel(capture: capture))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvasArea
        }
        .background(Theme.Colors.cardFill.ignoresSafeArea())
    }

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(ScreenshotEditorModel.Tool.allCases) { tool in
                    toolButton(tool)
                }
            }
            barDivider
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(ScreenshotAnnotationColor.allCases, id: \.self) { color in
                    colorButton(color)
                }
            }
            barDivider
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(ScreenshotEditorModel.WidthPreset.allCases) { preset in
                    widthButton(preset)
                }
            }
            Spacer(minLength: Theme.Spacing.md)
            Button { model.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.plain)
            .disabled(!model.canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo")
            Button { model.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.plain)
            .disabled(!model.canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .help("Redo")
            barDivider
            Button("Save…") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(model.isExporting)
            Button("Copy") { copy() }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(model.isExporting)
        }
        .font(Theme.Typography.bar)
        // The leading inset clears the traffic lights under the seamless title bar.
        .padding(.leading, 80)
        .padding(.trailing, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .frame(height: 52)
    }

    private var barDivider: some View {
        Rectangle()
            .fill(Theme.Colors.border)
            .frame(width: 1, height: 20)
    }

    private func toolButton(_ tool: ScreenshotEditorModel.Tool) -> some View {
        Button {
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
                .frame(width: 22, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.keyCap)
                        .fill(model.width == preset ? Theme.Colors.selection : .clear))
        }
        .buttonStyle(.plain)
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
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStart == nil { dragStart = value.startLocation }
                    model.dragChanged(
                        from: imagePoint(value.startLocation, scale: scale),
                        to: imagePoint(value.location, scale: scale),
                        scale: scale)
                }
                .onEnded { value in
                    dragStart = nil
                    model.dragEnded(
                        from: imagePoint(value.startLocation, scale: scale),
                        to: imagePoint(value.location, scale: scale),
                        scale: scale)
                    if model.tool == .text { textEntryFocused = true }
                })
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

    private func fittedSize(in available: CGSize) -> CGSize {
        let image = model.imageSize
        guard image.width > 0, image.height > 0, available.width > 0, available.height > 0 else {
            return CGSize(width: 1, height: 1)
        }
        let scale = min(available.width / image.width, available.height / image.height, 1)
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
            core.closePluginWindow(id: "screenshot-editor")
        }
    }

    private func save() {
        model.commitPendingText()
        model.isExporting = true
        let capture = model.capture
        let annotations = model.annotations
        Task {
            let png = await Task.detached(priority: .userInitiated) {
                ScreenshotAnnotationRenderer.flatten(
                    image: capture.image, annotations: annotations
                ).flatMap {
                    ScreenshotImageProcessor.pngData(
                        from: $0, roundedCorners: capture.roundedCorners)
                }
            }.value
            model.isExporting = false
            guard let png else {
                core.hud.show(
                    title: "Save Failed", symbol: "exclamationmark.triangle", isNoOp: true)
                return
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = Self.defaultFilename()
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url)
                core.hud.show(title: "Screenshot Saved", symbol: "checkmark.circle")
            } catch {
                AppLog.error("screenshot", "Saving failed: \(error.localizedDescription)")
                core.hud.show(
                    title: "Save Failed", symbol: "exclamationmark.triangle", isNoOp: true)
            }
        }
    }

    private static func defaultFilename(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: now)).png"
    }
}
