import Foundation

/// The part of a scroll event's phase the swipe decision reads, free of AppKit.
enum NoteSwipePhase: Equatable, Sendable {
    case began
    case changed
    case ended
    case cancelled
    /// Inertia the system keeps sending after the fingers lift.
    case momentum
    /// No gesture is underway, such as fingers resting on the surface before any travel.
    case idle
}

/// Turns one sideways scroll gesture over the editor into at most one Note change.
struct NoteSwipeTracker: Equatable, Sendable {
    /// Net sideways travel, in points, one gesture needs before it changes the Note; retune here.
    static let fireDistance = 40.0
    /// Travel on either axis, in points, after which the gesture's axis is settled for its whole life.
    static let axisLockDistance = 4.0
    /// How many times the sideways travel must outweigh the vertical for a gesture to lock horizontal.
    static let horizontalDominance = 2.0

    struct Outcome: Equatable, Sendable {
        /// True when the scroll view must not see the event as an ordinary scroll.
        let consumesEvent: Bool
        let navigation: NoteNavigationDirection?

        static let forwarded = Outcome(consumesEvent: false, navigation: nil)
    }

    private enum Axis: Equatable, Sendable {
        case undecided
        case vertical
        case horizontal
    }

    /// False until a gesture begins here, so one that started over another view is never adopted.
    private var isTracking = false
    private var axis = Axis.undecided
    /// The finger's travel since the gesture began; positive is rightwards.
    private var fingerTravelX = 0.0
    private var travelY = 0.0
    private var hasFired = false
    private var swallowsMomentum = false

    /// Takes the event's scrolling deltas in points and its natural-scrolling flag.
    mutating func handle(
        phase: NoteSwipePhase, deltaX: Double, deltaY: Double, isDirectionInverted: Bool
    ) -> Outcome {
        switch phase {
        case .idle:
            return .forwarded
        case .momentum:
            return Outcome(consumesEvent: swallowsMomentum, navigation: nil)
        case .began:
            self = NoteSwipeTracker()
            isTracking = true
            let outcome = advance(deltaX: deltaX, deltaY: deltaY, isDirectionInverted: isDirectionInverted)
            // The scroll view sees every gesture open and close, so its own bookkeeping stays paired.
            return Outcome(consumesEvent: false, navigation: outcome.navigation)
        case .changed:
            guard isTracking else { return .forwarded }
            return advance(deltaX: deltaX, deltaY: deltaY, isDirectionInverted: isDirectionInverted)
        case .ended, .cancelled:
            let wasHorizontal = axis == .horizontal
            self = NoteSwipeTracker()
            swallowsMomentum = wasHorizontal
            return .forwarded
        }
    }

    private mutating func advance(deltaX: Double, deltaY: Double, isDirectionInverted: Bool) -> Outcome {
        // Deltas say where the content moves; natural scrolling moves it with the finger, classic against it.
        fingerTravelX += isDirectionInverted ? deltaX : -deltaX
        travelY += deltaY
        if axis == .undecided, max(abs(fingerTravelX), abs(travelY)) >= Self.axisLockDistance {
            let isSideways = abs(fingerTravelX) >= abs(travelY) * Self.horizontalDominance
            axis = isSideways ? .horizontal : .vertical
        }
        guard axis == .horizontal else { return .forwarded }
        guard !hasFired, abs(fingerTravelX) >= Self.fireDistance else {
            return Outcome(consumesEvent: true, navigation: nil)
        }
        hasFired = true
        // The page follows the finger: pushed left it gives way to the next Note, pulled right to the previous.
        return Outcome(consumesEvent: true, navigation: fingerTravelX < 0 ? .next : .previous)
    }
}
