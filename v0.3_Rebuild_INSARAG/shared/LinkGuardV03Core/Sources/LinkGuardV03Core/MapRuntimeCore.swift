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

public struct MapTileCoordinate: Codable, Hashable, Sendable, Comparable {
    public var zoom: Int
    public var x: Int
    public var y: Int

    public init(zoom: Int, x: Int, y: Int) {
        self.zoom = zoom
        self.x = x
        self.y = y
    }

    public static func < (lhs: MapTileCoordinate, rhs: MapTileCoordinate) -> Bool {
        if lhs.zoom != rhs.zoom { return lhs.zoom < rhs.zoom }
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        return lhs.y < rhs.y
    }
}

public struct MapTileURLTemplate: Codable, Hashable, Sendable {
    public var template: String

    public init(template: String) {
        self.template = template
    }

    public func url(for coordinate: MapTileCoordinate) -> URL? {
        let urlString = template
            .replacingOccurrences(of: "{z}", with: String(coordinate.zoom))
            .replacingOccurrences(of: "{x}", with: String(coordinate.x))
            .replacingOccurrences(of: "{y}", with: String(coordinate.y))
        return URL(string: urlString)
    }
}

public struct OfflineMapTileDownloadRequest: Codable, Hashable, Sendable {
    public var coordinate: MapTileCoordinate
    public var url: URL

    public init(coordinate: MapTileCoordinate, url: URL) {
        self.coordinate = coordinate
        self.url = url
    }
}

public struct OfflineMapTileManifest: Codable, Hashable, Sendable {
    public var packID: LinkGuardID
    public var tileCoordinates: [MapTileCoordinate]

    public init(packID: LinkGuardID, tileCoordinates: [MapTileCoordinate]) {
        self.packID = packID
        self.tileCoordinates = tileCoordinates.sorted()
    }

    public var totalTileCount: Int {
        tileCoordinates.count
    }

    public func downloadRequests(using template: MapTileURLTemplate) -> [OfflineMapTileDownloadRequest] {
        tileCoordinates.compactMap { coordinate in
            guard let url = template.url(for: coordinate) else { return nil }
            return OfflineMapTileDownloadRequest(coordinate: coordinate, url: url)
        }
    }
}

public enum OfflineMapTilePlanningError: Error, Equatable, Sendable {
    case invalidZoomRange(minimumZoom: Int, maximumZoom: Int)
    case tileLimitExceeded(count: Int, limit: Int)
}

public struct OfflineMapTileDownloadProgress: Codable, Hashable, Sendable {
    public var packID: LinkGuardID
    public var totalTileCount: Int
    public private(set) var downloadedTileCount: Int
    public private(set) var failedTileCount: Int
    public private(set) var updatedAt: Date

    public init(packID: LinkGuardID, totalTileCount: Int, downloadedTileCount: Int = 0, failedTileCount: Int = 0, updatedAt: Date) {
        self.packID = packID
        self.totalTileCount = totalTileCount
        self.downloadedTileCount = downloadedTileCount
        self.failedTileCount = failedTileCount
        self.updatedAt = updatedAt
    }

    public var fractionComplete: Double {
        guard totalTileCount > 0 else { return 1 }
        return Double(downloadedTileCount) / Double(totalTileCount)
    }

    public mutating func recordDownloaded(at date: Date) {
        downloadedTileCount = min(totalTileCount, downloadedTileCount + 1)
        updatedAt = date
    }

    public mutating func recordFailed(at date: Date) {
        failedTileCount += 1
        updatedAt = date
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

    public func tileManifest(for packID: LinkGuardID, maxTileCount: Int = 5_000) throws -> OfflineMapTileManifest? {
        guard let pack = offlinePacks[packID] else { return nil }
        return try pack.tileManifest(maxTileCount: maxTileCount)
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

public extension OfflineMapPack {
    func tileManifest(maxTileCount: Int = 5_000) throws -> OfflineMapTileManifest {
        guard minimumZoom <= maximumZoom else {
            throw OfflineMapTilePlanningError.invalidZoomRange(minimumZoom: minimumZoom, maximumZoom: maximumZoom)
        }

        var coordinates = Set<MapTileCoordinate>()
        for zoom in minimumZoom...maximumZoom {
            let minimumTile = Self.tileCoordinate(latitude: bounds.maximumLatitude, longitude: bounds.minimumLongitude, zoom: zoom)
            let maximumTile = Self.tileCoordinate(latitude: bounds.minimumLatitude, longitude: bounds.maximumLongitude, zoom: zoom)
            for x in minimumTile.x...maximumTile.x {
                for y in minimumTile.y...maximumTile.y {
                    coordinates.insert(MapTileCoordinate(zoom: zoom, x: x, y: y))
                    if coordinates.count > maxTileCount {
                        throw OfflineMapTilePlanningError.tileLimitExceeded(count: coordinates.count, limit: maxTileCount)
                    }
                }
            }
        }
        return OfflineMapTileManifest(packID: id, tileCoordinates: Array(coordinates))
    }

    private static func tileCoordinate(latitude: Double, longitude: Double, zoom: Int) -> MapTileCoordinate {
        let clampedLatitude = min(max(latitude, -85.05112878), 85.05112878)
        let clampedLongitude = min(max(longitude, -180), 179.999999)
        let scale = pow(2.0, Double(zoom))
        let latitudeRadians = clampedLatitude * .pi / 180
        let x = Int(floor((clampedLongitude + 180) / 360 * scale))
        let y = Int(floor((1 - log(tan(latitudeRadians) + 1 / cos(latitudeRadians)) / .pi) / 2 * scale))
        let maxIndex = max(0, Int(scale) - 1)
        return MapTileCoordinate(zoom: zoom, x: min(max(x, 0), maxIndex), y: min(max(y, 0), maxIndex))
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