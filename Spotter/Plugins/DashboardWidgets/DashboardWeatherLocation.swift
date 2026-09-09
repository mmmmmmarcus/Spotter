import CoreLocation
import Foundation

/// The only place Spotter reads this Mac's location: one coarse fix, on demand, for the weather the
/// clock face wears. Nothing here runs until the weather question has been answered with a yes — the
/// store creates this provider at that moment and never before, so a decline raises no system prompt
/// either.
///
/// The accuracy asked for is `kCLLocationAccuracyReduced` (roughly a few kilometres, the
/// same coarse fix Apple hands an app that was denied precise location): a forecast is a property of
/// a city, so street-level precision would be data Spotter has no use for. `Info.plist` carries
/// `NSLocationDefaultAccuracyReduced` so macOS never even offers to grant the precise kind.
///
/// `CLLocationManagerDelegate` is a callback API, so its methods stay `nonisolated` and only plain
/// values — two `Double`s and an enum — cross back onto the main actor. `CLLocation` itself never
/// does.
@MainActor
final class WeatherLocationProvider: NSObject {
    var onAuthorization: ((WeatherLocationAuthorization) -> Void)?
    var onFix: ((Double, Double) -> Void)?
    var onFailure: (() -> Void)?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        manager.delegate = self
    }

    var authorization: WeatherLocationAuthorization {
        Self.authorization(from: manager.authorizationStatus)
    }

    /// Raises macOS's own prompt, and only for someone who has never answered it — every other
    /// status is already an answer, and asking again would be a dialog macOS suppresses anyway.
    func requestAuthorizationIfNeeded() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// One fix, not a subscription: `requestLocation` delivers a single reading and stops, so
    /// nothing is monitoring where this Mac goes between refreshes.
    func requestFix() {
        guard authorization == .authorized else { return }
        manager.requestLocation()
    }

    fileprivate nonisolated static func authorization(from status: CLAuthorizationStatus)
        -> WeatherLocationAuthorization
    {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        @unknown default: return .denied
        }
    }
}

extension WeatherLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authorization = Self.authorization(from: manager.authorizationStatus)
        Task { @MainActor [weak self] in self?.onAuthorization?(authorization) }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        // Decoded to plain values here: a `CLLocation` is not `Sendable` and must not cross.
        guard let coordinate = locations.last?.coordinate,
            CLLocationCoordinate2DIsValid(coordinate)
        else { return }
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        Task { @MainActor [weak self] in self?.onFix?(latitude, longitude) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.onFailure?() }
    }
}
