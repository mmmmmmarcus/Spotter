import AppKit

@main
@MainActor
struct ScreenshotInteractionTests {
    static var failures = 0

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { print("PASS  \(message)") }
        else { failures += 1; print("FAIL  \(message)") }
    }

    static func main() {
        _ = NSApplication.shared
        let previousApp = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let previousKey = NSApp.keyWindow
        let cursor = NSCursor.current
        defer { cursor.set() }
        let frame = CGRect(x: -10_000, y: -10_000, width: 100, height: 100)
        let view = ScreenshotSelectionView(screenFrame: frame, visibleFrame: frame, roundedCorners: true)
        let panel = ScreenshotSelectionPanel(screenFrame: frame, contentView: view)
        defer { panel.deactivate() }
        check(panel.styleMask.contains(.nonactivatingPanel), "overlay does not activate Spotter")
        check(!panel.canBecomeKey && !panel.canBecomeMain, "overlay cannot steal menu keyboard focus")
        check(panel.becomesKeyOnlyIfNeeded && !view.needsPanelToBecomeKey, "selection clicks never request key focus")
        check(!view.acceptsFirstResponder, "selection view does not claim keyboard input")
        panel.activate()
        check(!panel.isKeyWindow && NSApp.keyWindow === previousKey, "presenting overlay preserves the previous key window")
        check(NSWorkspace.shared.frontmostApplication?.processIdentifier == previousApp, "presentation preserves the frontmost app")
        check(ScreenshotSelectionKey.allCases.map(\.rawValue) == [53, 49, 48], "transient capture keys cover Escape Space and Tab")
        check(Set(ScreenshotSelectionKey.allCases.map(\.id)).count == 3, "each transient key has its own release identity")

        var screens = 0
        var selections = 0
        var cancellations = 0
        view.onScreenCapture = { screens += 1 }
        view.onSelection = { _ in selections += 1 }
        view.onCancel = { cancellations += 1 }
        panel.captureScreenIfIdle()
        check(screens == 1, "Tab captures in idle screenshot mode without a key window")
        panel.apply(mode: .ocr)
        panel.captureScreenIfIdle()
        panel.apply(mode: .colorPicker)
        panel.captureScreenIfIdle()
        check(screens == 1, "Tab cannot capture a screen in OCR or color mode")
        panel.apply(mode: .screenshot)
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 10, y: 10)))
        check(!panel.isKeyWindow && NSApp.keyWindow === previousKey, "starting a region drag does not steal keyboard focus")
        panel.captureScreenIfIdle()
        check(screens == 1, "Tab stays inert during a region drag")
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 30, y: 30)))
        check(selections == 1 && cancellations == 0, "region selection works without keyboard focus")
        panel.captureScreenIfIdle()
        check(screens == 2, "Tab becomes available after the drag ends")
        panel.deactivate()
        check(!panel.isVisible && NSApp.keyWindow === previousKey, "dismissal leaves keyboard focus unchanged")
        print(failures == 0 ? "All screenshot interaction checks passed" : "\(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
