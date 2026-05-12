import XCTest
@testable import LinkGuardV03Core

final class LinkGuardV03CoreTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_799_712_000)

    private func runtime(appID: LinkGuardAppID, id: LinkGuardID? = nil) -> LinkGuardAppRuntime {
        let platform: AppPlatform
        switch appID {
        case .ucc, .scc:
            platform = .mac
        case .sccIPad, .teamLeaderIPad, .emtIPad:
            platform = .iPad
        case .volunteer, .teamMember, .teamLeader, .emt:
            platform = .iPhone
        }
        return LinkGuardAppRuntime(
            device: DeviceIdentity(
                id: id ?? LinkGuardID("DEVICE-\(appID.rawValue)"),
                appID: appID,
                platform: platform,
                displayName: appID.rawValue
            )
        )
    }

    private func allAppRuntimes() -> [LinkGuardAppRuntime] {
        LinkGuardAppID.allCases.map { runtime(appID: $0) }
    }

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

    func testAllAppsInitializeWithRuntimeAndBlueprint() {
        let runtimes = allAppRuntimes()

        XCTAssertEqual(runtimes.count, LinkGuardAppID.allCases.count)
        for runtime in runtimes {
            XCTAssertEqual(runtime.profile.appID, runtime.device.appID)
            XCTAssertEqual(runtime.blueprint.appID, runtime.device.appID)
            XCTAssertTrue(runtime.blueprint.validate(against: runtime.profile))
        }
    }

    func testTeamMemberCannotIssueCommandButTeamLeaderCan() throws {
        let teamMember = runtime(appID: .teamMember)
        let teamLeader = runtime(appID: .teamLeader)
        let command = OperationalCommand(
            id: "CMD-1",
            incidentID: "INC-1",
            type: .worksiteAssignment,
            status: .issued,
            priority: .high,
            title: "Enter worksite",
            body: "Start search",
            issuedBy: teamLeader.device.id,
            issuedAt: fixedDate,
            targetRole: .teamMember
        )

        XCTAssertThrowsError(
            try teamMember.makeEnvelope(
                messageType: .commandUpsert,
                payload: command,
                createdAt: fixedDate,
                idempotencyKey: "cmd-denied"
            )
        )

        XCTAssertNoThrow(
            try teamLeader.makeEnvelope(
                messageType: .commandUpsert,
                payload: command,
                createdAt: fixedDate,
                idempotencyKey: "cmd-allowed"
            )
        )
    }

    func testAlertBroadcastReachesEveryRegisteredApp() throws {
        let ucc = runtime(appID: .ucc)
        let hub = InMemoryTransportHub(runtimes: allAppRuntimes())
        let alert = IncidentAlert(
            id: "ALERT-BROADCAST",
            incidentID: "INC-1",
            type: .evacuation,
            priority: .critical,
            title: "Evacuate",
            body: "All teams evacuate",
            issuedBy: ucc.device.id,
            issuedAt: fixedDate
        )

        let receipts = try hub.send(
            messageType: .alertUpsert,
            payload: alert,
            from: ucc.device.id,
            createdAt: fixedDate,
            idempotencyKey: "alert-broadcast"
        )

        XCTAssertEqual(receipts.count, LinkGuardAppID.allCases.count)
        for appID in LinkGuardAppID.allCases {
            let deviceID = LinkGuardID("DEVICE-\(appID.rawValue)")
            XCTAssertEqual(hub.runtime(for: deviceID)?.snapshot.alerts["ALERT-BROADCAST"]?.type, .evacuation)
        }
    }

    func testClinicalPatientPayloadStaysInsideEMTApps() throws {
        let emt = runtime(appID: .emt)
        let hub = InMemoryTransportHub(runtimes: allAppRuntimes())
        let patient = PatientRecord(
            id: "PATIENT-CLINICAL",
            incidentID: "INC-1",
            displayCode: "P-RED-01",
            triageCategory: .red,
            injurySummary: "Crush injury",
            latestVitals: VitalSigns(heartRate: 132, respiratoryRate: 30, spo2: 88, gcs: 13, recordedAt: fixedDate),
            updatedAt: fixedDate
        )

        let receipts = try hub.send(
            messageType: .patientUpsert,
            payload: patient,
            from: emt.device.id,
            createdAt: fixedDate,
            idempotencyKey: "patient-clinical"
        )

        XCTAssertEqual(Set(receipts.map(\.recipientAppID)), [.emt, .emtIPad])
        XCTAssertNotNil(hub.runtime(for: "DEVICE-LinkGuard-EMT")?.snapshot.patients["PATIENT-CLINICAL"])
        XCTAssertNotNil(hub.runtime(for: "DEVICE-LinkGuard-EMT-iPad")?.snapshot.patients["PATIENT-CLINICAL"])
        XCTAssertNil(hub.runtime(for: "DEVICE-LinkGuard-SCC")?.snapshot.patients["PATIENT-CLINICAL"])
        XCTAssertNil(hub.runtime(for: "DEVICE-LinkGuard-UCC")?.snapshot.patients["PATIENT-CLINICAL"])
    }

    func testTeamLeaderTaskFlowsThroughFieldOperationsChain() throws {
        let teamLeader = runtime(appID: .teamLeader)
        let hub = InMemoryTransportHub(runtimes: allAppRuntimes())
        let task = FieldTask(
            id: "TASK-FIELD",
            incidentID: "INC-1",
            worksiteID: "WORKSITE-1",
            assignedTeamID: "TEAM-1",
            type: .search,
            status: .assigned,
            priority: .medium,
            summary: "Search west side",
            createdAt: fixedDate
        )

        let receipts = try hub.send(
            messageType: .taskUpsert,
            payload: task,
            from: teamLeader.device.id,
            createdAt: fixedDate,
            idempotencyKey: "task-field"
        )
        let recipientApps = Set(receipts.map(\.recipientAppID))

        XCTAssertTrue(recipientApps.isSuperset(of: [.ucc, .scc, .sccIPad, .teamLeader, .teamLeaderIPad, .teamMember, .volunteer]))
        XCTAssertFalse(recipientApps.contains(.emt))
        XCTAssertFalse(recipientApps.contains(.emtIPad))
        XCTAssertEqual(hub.runtime(for: "DEVICE-LinkGuard-TE")?.snapshot.tasks["TASK-FIELD"]?.status, .assigned)
    }

    func testEvacuationRequestUsesMedicalOperationalRoute() throws {
        let emt = runtime(appID: .emt)
        let hub = InMemoryTransportHub(runtimes: allAppRuntimes())
        let request = EvacuationRequest(
            id: "EVAC-1",
            patientID: "PATIENT-1",
            priority: .critical,
            status: .pending,
            requestedAt: fixedDate
        )

        let receipts = try hub.send(
            messageType: .evacuationRequestUpsert,
            payload: request,
            from: emt.device.id,
            createdAt: fixedDate,
            idempotencyKey: "evac-1"
        )
        let recipientApps = Set(receipts.map(\.recipientAppID))

        XCTAssertEqual(recipientApps, [.ucc, .scc, .sccIPad, .emt, .emtIPad])
        XCTAssertNotNil(hub.runtime(for: "DEVICE-LinkGuard-SCC")?.snapshot.evacuationRequests["EVAC-1"])
        XCTAssertNil(hub.runtime(for: "DEVICE-LinkGuard-TE")?.snapshot.evacuationRequests["EVAC-1"])
    }
}
