import Foundation
import CoreLocation
import SwiftUI
import RelayCore

@MainActor final class RequestLocationModel: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var busy = false
    @Published var problem = ""
    private let manager = CLLocationManager()
    private var result: ((RequestLocation) -> Void)?
    private var requesting = false
    private var timeout: Task<Void, Never>?
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest }
    func capture(_ done: @escaping (RequestLocation) -> Void) {
        guard !busy else { return }; busy = true; problem = ""; result = done
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: locate()
        default: fail("Location access is off. You can enter a landmark or enable access in Settings.")
        }
    }
    private func locate() {
        guard !requesting else { return }; requesting = true
        manager.requestLocation()
        timeout?.cancel(); timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.busy else { return }
            self.fail("Could not get a recent location. Try outdoors or enter a landmark.")
        }
    }
    private func fail(_ text: String) { problem = text; busy = false; requesting = false; result = nil; timeout?.cancel(); manager.stopUpdatingLocation() }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard busy else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: locate()
        case .denied, .restricted: fail("Location permission was declined. Enter a landmark instead.")
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard busy else { return }
        guard let value = locations.last, value.horizontalAccuracy >= 0,
              abs(value.timestamp.timeIntervalSinceNow) < 120 else { fail("Location is old or unavailable. Refresh or enter a landmark."); return }
        do {
            let snapshot = try RequestLocation(latitude: value.coordinate.latitude, longitude: value.coordinate.longitude,
                accuracy: value.horizontalAccuracy, capturedAt: value.timestamp,
                precision: manager.accuracyAuthorization == .reducedAccuracy ? "approximate" : "precise")
            let done = result; result = nil; busy = false; requesting = false; timeout?.cancel(); manager.stopUpdatingLocation(); done?(snapshot)
        } catch { fail(error.localizedDescription) }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { guard busy else { return }; fail("Location unavailable. Try again or enter a landmark.") }
}
