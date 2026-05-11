import Foundation

public enum CoordinateMode: String, Codable, CaseIterable, Sendable {
    case gps
    case localImage
    case calibratedMixed
}

public enum GeometryType: String, Codable, CaseIterable, Sendable {
    case point
    case polyline
    case polygon
}

public enum MapFeatureType: String, Codable, CaseIterable, Sendable {
    case victimPoint
    case assemblyPoint
    case safetyZone
    case restrictedZone
    case roadBlockLine
    case hazardPolygon
    case collapsedAreaPolygon
    case triageArea
    case casualtyCollectionPoint
    case medicalStation
    case evacuationRoute
    case worksiteBoundary
}

public struct MapPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var latitude: Double?
    public var longitude: Double?

    public init(x: Double, y: Double, latitude: Double? = nil, longitude: Double? = nil) {
        self.x = x
        self.y = y
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct MapGeometry: Codable, Hashable, Sendable {
    public var type: GeometryType
    public var points: [MapPoint]

    public init(type: GeometryType, points: [MapPoint]) {
        self.type = type
        self.points = points
    }
}

public struct MapFeature: Codable, Hashable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var featureType: MapFeatureType
    public var coordinateMode: CoordinateMode
    public var geometry: MapGeometry
    public var severity: PriorityLevel
    public var title: String
    public var createdBy: LinkGuardID
    public var updatedAt: Date
    public var attachmentIDs: [LinkGuardID]

    public init(
        id: LinkGuardID,
        incidentID: LinkGuardID,
        featureType: MapFeatureType,
        coordinateMode: CoordinateMode,
        geometry: MapGeometry,
        severity: PriorityLevel,
        title: String,
        createdBy: LinkGuardID,
        updatedAt: Date,
        attachmentIDs: [LinkGuardID] = []
    ) {
        self.id = id
        self.incidentID = incidentID
        self.featureType = featureType
        self.coordinateMode = coordinateMode
        self.geometry = geometry
        self.severity = severity
        self.title = title
        self.createdBy = createdBy
        self.updatedAt = updatedAt
        self.attachmentIDs = attachmentIDs
    }
}
