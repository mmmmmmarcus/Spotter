import AppKit

// Only intercepts pointer events during selection, before an outside click can dismiss transient UI.
@MainActor
final class ScreenshotPointerCapture {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var onPointer: ((CGEventType, CGPoint) -> Void)?
    var onUnavailable: (() -> Void)?

    func start() -> Bool {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel, .mouseMoved]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let forward = MainActor.assumeIsolated {
                    let owner = Unmanaged<ScreenshotPointerCapture>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        owner.onUnavailable?()
                        return true
                    }
                    let point = CGPoint(x: event.location.x,
                        y: (NSScreen.screens.first?.frame.maxY ?? 0) - event.location.y)
                    owner.onPointer?(type, point)
                    return type == .mouseMoved
                }
                return forward ? Unmanaged.passUnretained(event) : nil
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }
}
