import CoreLocation
import Foundation
import LinkGuardV03Core

final class FieldLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isRequestingFix = false
    @Published private(set) var lastFix: GPSFix?
    @Published private(set) var lastErrorMessage: String?

    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    var canRequestFix: Bool {
        switch authorizationStatus {
        case .notDetermined, .authorizedAlways, .authorizedWhenInUse:
            return isRequestingFix == false
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    var statusTitle: String {
        if isRequestingFix { return "Updating GPS" }
        if lastErrorMessage != nil { return "GPS Blocked" }
        if lastFix != nil { return "GPS Fix Recorded" }
        switch authorizationStatus {
        case .denied, .restricted:
            return "GPS Permission Needed"
        default:
            return "GPS Needed"
        }
    }

    var statusDetail: String {
        if let lastErrorMessage { return lastErrorMessage }
        if let lastFix {
            let coordinate = lastFix.coordinate
            let latitude = coordinate.latitude.formatted(.number.precision(.fractionLength(5)))
            let longitude = coordinate.longitude.formatted(.number.precision(.fractionLength(5)))
            let accuracy = coordinate.accuracyMeters.map { " +/- \(Int($0))m" } ?? ""
            return "\(latitude), \(longitude)\(accuracy)"
        }
        switch authorizationStatus {
        case .notDetermined:
            return "Foreground location not requested."
        case .authorizedAlways, .authorizedWhenInUse:
            return "Foreground location is available."
        case .denied, .restricted:
            return "Location permission disabled."
        @unknown default:
            return "Location authorization is unavailable."
        }
    }

    func requestCurrentFix() {
        lastErrorMessage = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            isRequestingFix = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isRequestingFix = true
            manager.requestLocation()
        case .denied, .restricted:
            isRequestingFix = false
            lastErrorMessage = "Location permission denied."
        @unknown default:
            isRequestingFix = false
            lastErrorMessage = "Location authorization unavailable."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse where isRequestingFix:
            manager.requestLocation()
        case .denied, .restricted:
            isRequestingFix = false
            lastErrorMessage = "Location permission denied."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            isRequestingFix = false
            lastErrorMessage = "No location fix returned."
            return
        }

        let accuracy = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
        lastFix = GPSFix(
            coordinate: GeoCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracyMeters: accuracy
            ),
            source: .deviceGPS,
            capturedAt: location.timestamp
        )
        isRequestingFix = false
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isRequestingFix = false
        lastErrorMessage = error.localizedDescription
    }
}