import XCTest
@testable import LinkGuardV03Core
@testable import LinkGuardV03FieldUI

@MainActor
final class FieldAppMapMarkupIntegrationTests: XCTestCase {
    func testQueueMapMarkupFeaturePreservesPolygonCoordinates() throws {
        var controller = FieldAppController(
            appID: .sccIPad,
            platform: .iPad,
            deviceID: LinkGuardID("DEVICE-SCC-IPAD"),
            displayName: "SCC iPad"
        )

        let coordinates = [
            MapCoordinate(latitude: 25.0330, longitude: 121.5650),
            MapCoordinate(latitude: 25.0333, longitude: 121.5654),
            MapCoordinate(latitude: 25.0328, longitude: 121.5658)
        ]
        let markup = MapMarkupFeature(
            id: LinkGuardID("MAP-MARKUP-1"),
            incidentID: controller.context.incidentID,
            sectionID: .sectionA,
            geometry: .polygon(.hazardousZone, coordinates),
            searchState: .highRisk,
            title: "Hazard polygon",
            createdBy: controller.runtime.device.id
        )

        let envelope = try controller.queueMapMarkupFeature(markup, featureType: .hazardPolygon, now: Date(timeIntervalSince1970: 1_800_000_120))
        let payload = try envelope.decodePayload(MapFeature.self)

        XCTAssertEqual(payload.id, markup.id)
        XCTAssertEqual(payload.featureType, .hazardPolygon)
        XCTAssertEqual(payload.geometry.type, .polygon)
        XCTAssertEqual(payload.geometry.points.count, coordinates.count)
        XCTAssertEqual(payload.geometry.points[0].latitude, coordinates[0].latitude)
        XCTAssertEqual(payload.geometry.points[1].longitude, coordinates[1].longitude)
        XCTAssertEqual(payload.severity, .critical)
    }
}
