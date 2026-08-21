import CoreLocation
import Foundation
import OSLog

/// A single coordinate, on request, in the foreground.
protocol OneTimeLocationProviding: Sendable {
    func authorizationStatus() -> CLAuthorizationStatus
    /// Asks for permission if it has not been asked, then returns one fix.
    ///
    /// Returns nil when the user declines or the fix does not arrive. **Never throws the caller
    /// off its path**: declining location must not stop anybody recording an off-rent
    /// confirmation on a jobsite with no signal.
    func requestOneTimeLocation() async -> LocationSnapshotRecord?
}

/// `requestLocation()`, once, foreground only.
///
/// There is no `startUpdatingLocation` in this file and there never will be. The app asks for
/// `WhenInUse`, takes a single fix when the user taps "Add current location", and stops. No
/// significant-change monitoring, no region monitoring, no background mode, no route history —
/// the Info.plist has no `NSLocationAlwaysAndWhenInUseUsageDescription` and the app declares no
/// location background mode, so the capability to do otherwise is not present.
final class CoreLocationOneShotProvider: NSObject, OneTimeLocationProviding, CLLocationManagerDelegate, @unchecked Sendable {

    private static let logger = Logger(subsystem: "com.idlery.offrent", category: "location")

    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<LocationSnapshotRecord?, Never>?
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
        // A jobsite pin does not need street-level precision, and asking for less means a faster
        // fix and a smaller privacy footprint.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func authorizationStatus() -> CLAuthorizationStatus { manager.authorizationStatus }

    func requestOneTimeLocation() async -> LocationSnapshotRecord? {
        var status = manager.authorizationStatus

        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                lock.lock()
                authorizationContinuation = continuation
                lock.unlock()
                manager.requestWhenInUseAuthorization()
            }
        }

        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            Self.logger.info("Location declined; continuing without a coordinate")
            return nil
        }

        return await withCheckedContinuation { continuation in
            lock.lock()
            // A second request while one is outstanding resolves the first with nil rather than
            // leaking a continuation.
            if let existing = self.continuation {
                self.continuation = nil
                existing.resume(returning: nil)
            }
            self.continuation = continuation
            lock.unlock()
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        lock.lock()
        let pending = authorizationContinuation
        authorizationContinuation = nil
        lock.unlock()
        pending?.resume(returning: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return finish(with: nil) }
        finish(
            with: LocationSnapshotRecord(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracyMetres: location.horizontalAccuracy,
                capturedAt: location.timestamp
            )
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Self.logger.info("Location fix failed: \(String(describing: error), privacy: .public)")
        finish(with: nil)
    }

    private func finish(with snapshot: LocationSnapshotRecord?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: snapshot)
    }
}

struct StubLocationProvider: OneTimeLocationProviding {
    var status: CLAuthorizationStatus = .authorizedWhenInUse
    var snapshot: LocationSnapshotRecord?

    func authorizationStatus() -> CLAuthorizationStatus { status }
    func requestOneTimeLocation() async -> LocationSnapshotRecord? { snapshot }

    static let denied = StubLocationProvider(status: .denied, snapshot: nil)
    static let jobsite = StubLocationProvider(
        snapshot: LocationSnapshotRecord(
            latitude: 33.0198, longitude: -96.6989,
            horizontalAccuracyMetres: 65, capturedAt: Date(timeIntervalSince1970: 1_778_000_000)
        )
    )
}
