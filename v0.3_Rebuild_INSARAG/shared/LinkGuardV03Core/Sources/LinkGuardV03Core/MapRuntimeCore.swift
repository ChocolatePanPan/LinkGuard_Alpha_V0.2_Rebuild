import Foundation

public enum GPSFixSource: String, Codable, CaseIterable, Sendable {
    case deviceGPS
    case manual
    case relay
}

public struct GPSFix: Codable, Hashable, Sendable {
    public var coordinate: GeoCoordinate
    public var source: GPSFixSource
    public var capturedAt: Date
    public var headingDegrees: Double?
    public var speedMetersPerSecond: Double?

    public init(
        coordinate: GeoCoordinate,
        source: GPSFixSource,
        capturedAt: Date,
        headingDegrees: Double? = nil,
        speedMetersPerSecond: Double? = nil
    ) {
        self.coordinate = coordinate
        self.source = source
        self.capturedAt = capturedAt
        self.headingDegrees = headingDegrees
        self.speedMetersPerSecond = speedMetersPerSecond
    }
}

public struct MapBoundingBox: Codable, Hashable, Sendable {
    public var minimumLatitude: Double
    public var minimumLongitude: Double
    public var maximumLatitude: Double
    public var maximumLongitude: Double

    public init(minimumLatitude: Double, minimumLongitude: Double, maximumLatitude: Double, maximumLongitude: Double) {
        self.minimumLatitude = min(minimumLatitude, maximumLatitude)
        self.minimumLongitude = min(minimumLongitude, maximumLongitude)
        self.maximumLatitude = max(minimumLatitude, maximumLatitude)
        self.maximumLongitude = max(minimumLongitude, maximumLongitude)
    }

    public func contains(_ coordinate: GeoCoordinate) -> Bool {
        coordinate.latitude >= minimumLatitude &&
            coordinate.latitude <= maximumLatitude &&
            coordinate.longitude >= minimumLongitude &&
            coordinate.longitude <= maximumLongitude
    }
}

public enum OfflineMapPackStatus: String, Codable, CaseIterable, Sendable {
    case requested
    case downloading
    case available
    case expired
    case failed
}

public struct OfflineMapPack: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var name: String
    public var bounds: MapBoundingBox
    public var minimumZoom: Int
    public var maximumZoom: Int
    public var status: OfflineMapPackStatus
    public var byteSize: Int64
    public var downloadedAt: Date?

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        name: String,
        bounds: MapBoundingBox,
        minimumZoom: Int,
        maximumZoom: Int,
        status: OfflineMapPackStatus,
        byteSize: Int64 = 0,
        downloadedAt: Date? = nil
    ) {
        self.id = id
        self.incidentID = incidentID
        self.name = name
        self.bounds = bounds
        self.minimumZoom = minimumZoom
        self.maximumZoom = maximumZoom
        self.status = status
        self.byteSize = byteSize
        self.downloadedAt = downloadedAt
    }
}

public struct MapLayerState: Codable, Sendable {
    public private(set) var features: [LinkGuardID: MapFeature]
    public private(set) var gpsFixesByDeviceID: [LinkGuardID: GPSFix]
    public private(set) var offlinePacks: [LinkGuardID: OfflineMapPack]

    public init(
        features: [LinkGuardID: MapFeature] = [:],
        gpsFixesByDeviceID: [LinkGuardID: GPSFix] = [:],
        offlinePacks: [LinkGuardID: OfflineMapPack] = [:]
    ) {
        self.features = features
        self.gpsFixesByDeviceID = gpsFixesByDeviceID
        self.offlinePacks = offlinePacks
    }

    public mutating func upsertFeature(_ feature: MapFeature) {
        features[feature.id] = feature
    }

    public mutating func updateGPS(deviceID: LinkGuardID, fix: GPSFix) {
        gpsFixesByDeviceID[deviceID] = fix
    }

    public mutating func upsertOfflinePack(_ pack: OfflineMapPack) {
        offlinePacks[pack.id] = pack
    }

    public func features(for incidentID: LinkGuardID) -> [MapFeature] {
        features.values
            .filter { $0.incidentID == incidentID }
            .sorted { $0.updatedAt < $1.updatedAt }
    }

    public func availableOfflinePack(containing coordinate: GeoCoordinate) -> OfflineMapPack? {
        offlinePacks.values
            .filter { $0.status == .available && $0.bounds.contains(coordinate) }
            .sorted { $0.maximumZoom > $1.maximumZoom }
            .first
    }
}

public extension MapGeometry {
    var isValidForDisplay: Bool {
        switch type {
        case .point:
            return points.count == 1
        case .polyline:
            return points.count >= 2
        case .polygon:
            return points.count >= 3
        }
    }

    var containsGPSCoordinates: Bool {
        points.allSatisfy { $0.latitude != nil && $0.longitude != nil }
    }

    static func point(_ coordinate: GeoCoordinate) -> MapGeometry {
        MapGeometry(type: .point, points: [MapPoint(gps: coordinate)])
    }

    static func polyline(_ coordinates: [GeoCoordinate]) -> MapGeometry {
        MapGeometry(type: .polyline, points: coordinates.map(MapPoint.init(gps:)))
    }

    static func polygon(_ coordinates: [GeoCoordinate]) -> MapGeometry {
        MapGeometry(type: .polygon, points: coordinates.map(MapPoint.init(gps:)))
    }
}

public extension MapPoint {
    init(gps coordinate: GeoCoordinate) {
        self.init(x: coordinate.longitude, y: coordinate.latitude, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}