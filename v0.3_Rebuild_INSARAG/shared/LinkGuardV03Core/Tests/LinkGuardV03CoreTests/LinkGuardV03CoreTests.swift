import XCTest
@testable import LinkGuardV03Core

final class LinkGuardV03CoreTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_799_712_000)

    func testEMTProfileKeepsMedicalDataIndependent() {
        let emtProfile = RoleProfileCatalog.profile(for: .emt)
        let sccProfile = RoleProfileCatalog.profile(for: .scc)

        XCTAssertEqual(emtProfile.medicalAccess, .fullClinical)
        XCTAssertTrue(emtProfile.allows(.manageMedicalPatient))
        XCTAssertTrue(emtProfile.allows(.viewMedicalDetails))
        XCTAssertFalse(sccProfile.allows(.viewMedicalDetails))
        XCTAssertFalse(sccProfile.allows(.manageMedicalPatient))
    }

    func testAppBlueprintsMatchRoleProfiles() {
        for appID in LinkGuardAppID.allCases {
            let blueprint = AppBlueprintCatalog.blueprint(for: appID)
            let profile = RoleProfileCatalog.profile(for: appID)
            XCTAssertTrue(blueprint.validate(against: profile), "Blueprint does not match \(appID.rawValue)")
        }
    }

    func testOfflineQueuePrioritizesCriticalMessagesAndDeduplicates() throws {
        var queue = OfflineQueue()
        let lowPriorityTask = FieldTask(
            id: "TASK-1",
            incidentID: "INC-1",
            type: .recon,
            status: .assigned,
            priority: .low,
            summary: "Recon",
            createdAt: fixedDate
        )
        let criticalAlert = IncidentAlert(
            id: "ALERT-1",
            incidentID: "INC-1",
            type: .evacuation,
            priority: .critical,
            title: "Evacuate",
            body: "Leave now",
            issuedBy: "UCC-1",
            issuedAt: fixedDate
        )
        let taskEnvelope = try SyncEnvelope.make(
            messageType: .taskUpsert,
            sourceAppID: .teamLeader,
            sourceDeviceID: "DEVICE-TL",
            priority: .low,
            createdAt: fixedDate,
            idempotencyKey: "task-1",
            payload: lowPriorityTask
        )
        let alertEnvelope = try SyncEnvelope.make(
            messageType: .alertUpsert,
            sourceAppID: .scc,
            sourceDeviceID: "DEVICE-SCC",
            priority: .critical,
            createdAt: fixedDate,
            idempotencyKey: "alert-1",
            payload: criticalAlert
        )

        queue.enqueue(taskEnvelope, queuedAt: fixedDate)
        queue.enqueue(alertEnvelope, queuedAt: fixedDate.addingTimeInterval(10))
        queue.enqueue(alertEnvelope, queuedAt: fixedDate.addingTimeInterval(20))

        XCTAssertEqual(queue.entries.count, 2)
        XCTAssertEqual(queue.nextPending?.envelope.messageType, .alertUpsert)
    }

    func testOperationStoreAppliesEnvelopeOnlyOnce() throws {
        var snapshot = OperationSnapshot()
        let activeIncident = Incident(
            id: "INC-1",
            displayName: "Incident",
            status: .active,
            createdAt: fixedDate,
            createdBy: "UCC-1"
        )
        let closedIncident = Incident(
            id: "INC-1",
            displayName: "Incident",
            status: .closed,
            createdAt: fixedDate,
            createdBy: "UCC-1"
        )
        let firstEnvelope = try SyncEnvelope.make(
            messageType: .incidentUpsert,
            sourceAppID: .ucc,
            sourceDeviceID: "DEVICE-UCC",
            priority: .high,
            createdAt: fixedDate,
            idempotencyKey: "incident-1",
            payload: activeIncident
        )
        let duplicateEnvelope = try SyncEnvelope.make(
            messageType: .incidentUpsert,
            sourceAppID: .ucc,
            sourceDeviceID: "DEVICE-UCC",
            priority: .high,
            createdAt: fixedDate,
            idempotencyKey: "incident-1",
            payload: closedIncident
        )

        try snapshot.apply(firstEnvelope)
        try snapshot.apply(duplicateEnvelope)

        XCTAssertEqual(snapshot.incidents["INC-1"]?.status, .active)
    }

    func testSyncEnvelopeRoundTripDecodesPayload() throws {
        let patient = PatientRecord(
            id: "PATIENT-1",
            incidentID: "INC-1",
            displayCode: "P001",
            triageCategory: .red,
            injurySummary: "Leg bleed",
            latestVitals: VitalSigns(heartRate: 120, respiratoryRate: 28, gcs: 14, recordedAt: fixedDate),
            updatedAt: fixedDate
        )
        let envelope = try SyncEnvelope.make(
            messageType: .patientUpsert,
            sourceAppID: .emt,
            sourceDeviceID: "DEVICE-EMT",
            sourceRole: .emt,
            priority: .critical,
            createdAt: fixedDate,
            idempotencyKey: "patient-1",
            payload: patient
        )
        let encodedEnvelope = try LinkGuardJSON.encode(envelope)
        let decodedEnvelope = try LinkGuardJSON.decode(SyncEnvelope.self, from: encodedEnvelope)
        let decodedPatient = try decodedEnvelope.decodePayload(PatientRecord.self)

        XCTAssertEqual(decodedEnvelope.messageType, .patientUpsert)
        XCTAssertEqual(decodedPatient.triageCategory, .red)
        XCTAssertEqual(decodedPatient.latestVitals?.heartRate, 120)
    }
}
