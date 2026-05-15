import Foundation
@testable import LinkGuardV03Core
@testable import LinkGuardV03MacUI
import XCTest

final class MacSyncReceiverTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_710_000_000)

    func testMacSyncHealthRequestReturnsOK() throws {
        let request = Data("GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)

        let response = MacSyncHTTPResponder.response(for: request, receivedAt: fixedDate, batchHandler: nil)

        XCTAssertEqual(response.statusCode, 200)
        let body = try LinkGuardJSON.decode([String: String].self, from: response.body)
        XCTAssertEqual(body["status"], "ok")
        XCTAssertEqual(body["service"], "linkguard_sync_receiver")
    }

    func testMacSyncPostAppliesSOSBatchAndReturnsReceipt() throws {
        let envelope = try makeSOSEnvelope(createdAt: fixedDate.addingTimeInterval(1))
        let batch = SyncTransportBatch(
            device: DeviceIdentity(id: "IOS-TE-1", appID: .teamMember, platform: .iPhone, displayName: "TE 1"),
            generatedAt: fixedDate.addingTimeInterval(2),
            envelopes: [envelope]
        )
        let request = try postSyncRequest(body: LinkGuardJSON.encode(batch))
        var state = try MacSystemUIFactory.makeState(appID: .scc, deviceID: "MAC-SCC-1")
        let receivedAt = fixedDate.addingTimeInterval(3)

        let response = MacSyncHTTPResponder.response(for: request, receivedAt: receivedAt) { incomingBatch, batchReceivedAt in
            XCTAssertEqual(batchReceivedAt, receivedAt)
            return state.receive(incomingBatch, receivedAt: receivedAt)
        }

        XCTAssertEqual(response.statusCode, 200)
        let decodedResponse = try LinkGuardJSON.decode(SyncTransportResponse.self, from: response.body)
        XCTAssertEqual(decodedResponse.receipts, [
            SyncTransportReceipt(envelopeID: envelope.id, accepted: true, receivedAt: receivedAt)
        ])
        XCTAssertEqual(state.sosAlertItems.count, 1)
        XCTAssertEqual(state.sosAlertItems.first?.dangerType, .trapped)
        XCTAssertEqual(state.metrics.first { $0.id == "alerts" }?.value, "1")
    }

    func testMacSyncPostRejectsInvalidJSON() throws {
        let request = try postSyncRequest(body: Data("{bad json}".utf8))
        var handlerWasCalled = false

        let response = MacSyncHTTPResponder.response(for: request, receivedAt: fixedDate) { _, _ in
            handlerWasCalled = true
            return SyncTransportResponse(receipts: [])
        }

        XCTAssertFalse(handlerWasCalled)
        XCTAssertEqual(response.statusCode, 400)
        let body = try LinkGuardJSON.decode([String: String].self, from: response.body)
        XCTAssertNotNil(body["error"])
    }

    func testMacSyncRejectsUnsupportedRoutes() throws {
        let getSync = Data("GET /sync HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)
        let missingRoute = Data("POST /unknown HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n".utf8)

        XCTAssertEqual(MacSyncHTTPResponder.response(for: getSync, receivedAt: fixedDate, batchHandler: nil).statusCode, 405)
        XCTAssertEqual(MacSyncHTTPResponder.response(for: missingRoute, receivedAt: fixedDate, batchHandler: nil).statusCode, 404)
    }

    private func makeSOSEnvelope(createdAt: Date) throws -> SyncEnvelope {
        let report = SOSReport(
            id: "SOS-HTTP-1",
            incidentID: "INC-HTTP-1",
            reporterDeviceID: "IOS-TE-1",
            reporterAppID: .teamMember,
            location: GeoCoordinate(latitude: 25.0330, longitude: 121.5654, accuracyMeters: 8),
            dangerType: .trapped,
            note: "Need extraction",
            createdAt: createdAt
        )
        return try SyncEnvelope.make(
            id: "MSG-SOS-HTTP-1",
            messageType: .sosReportUpsert,
            sourceAppID: .teamMember,
            sourceDeviceID: "IOS-TE-1",
            priority: .critical,
            createdAt: createdAt,
            idempotencyKey: "sos-http-1",
            payload: report
        )
    }

    private func postSyncRequest(body: Data) throws -> Data {
        var request = Data("POST /sync HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        request.append(body)
        return request
    }
}