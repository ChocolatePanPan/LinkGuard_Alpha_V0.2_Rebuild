import XCTest
@testable import LinkGuardV03Core
@testable import LinkGuardV03FieldUI
@testable import LinkGuardV03MacUI

final class LinkGuardV03CoreTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_799_712_000)

    private struct AcceptingTransport: SyncTransportClient {
        func deliver(_ envelopes: [SyncEnvelope], from device: DeviceIdentity, at date: Date) async throws -> SyncTransportResponse {
            SyncTransportResponse(
                receipts: envelopes.map { envelope in
                    SyncTransportReceipt(envelopeID: envelope.id, accepted: true, receivedAt: date)
                }
            )
        }
    }

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

    private func temporaryCacheURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LinkGuardV03CoreTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("local-cache.json")
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

    func testFeatureAccessMatrixMatchesOperationalRoleTable() {
        var checkedFeatures = Set<LinkGuardFeature>()

        func assertAccess(
            _ feature: LinkGuardFeature,
            _ ucc: FeatureAccessLevel,
            _ scc: FeatureAccessLevel,
            _ teamLeader: FeatureAccessLevel,
            _ teamMember: FeatureAccessLevel,
            _ emt: FeatureAccessLevel,
            _ volunteer: FeatureAccessLevel
        ) {
            checkedFeatures.insert(feature)
            let expected: [LinkGuardAppID: FeatureAccessLevel] = [
                .ucc: ucc,
                .scc: scc,
                .teamLeader: teamLeader,
                .teamMember: teamMember,
                .emt: emt,
                .volunteer: volunteer
            ]
            for (appID, level) in expected {
                XCTAssertEqual(LinkGuardFeatureAccessMatrix.accessLevel(for: appID, feature: feature), level, "\(appID.rawValue) \(feature.rawValue)")
            }
        }

        assertAccess(.globalMapOverview, .primary, .primary, .limited, .none, .limited, .none)
        assertAccess(.sectorCreation, .limited, .primary, .primary, .none, .none, .none)
        assertAccess(.subSectorCreation, .none, .limited, .primary, .none, .none, .none)
        assertAccess(.pointMarker, .limited, .primary, .primary, .primary, .primary, .limited)
        assertAccess(.lineMarker, .limited, .primary, .primary, .limited, .none, .none)
        assertAccess(.areaMarker, .limited, .primary, .primary, .none, .none, .none)
        assertAccess(.hazardZoneManagement, .limited, .primary, .primary, .none, .none, .none)
        assertAccess(.searchProgressColoring, .limited, .primary, .primary, .none, .none, .none)
        assertAccess(.worksiteMarkerSystem, .limited, .primary, .primary, .limited, .limited, .none)
        assertAccess(.offlineMap, .limited, .primary, .primary, .primary, .limited, .limited)

        assertAccess(.personnelOverview, .primary, .primary, .primary, .none, .limited, .none)
        assertAccess(.gpsTracking, .primary, .primary, .primary, .primary, .primary, .primary)
        assertAccess(.personnelEntryLog, .limited, .primary, .primary, .limited, .limited, .none)
        assertAccess(.teamCapabilityOverview, .primary, .primary, .primary, .none, .limited, .none)
        assertAccess(.personnelStatusUpdate, .limited, .primary, .primary, .limited, .limited, .none)
        assertAccess(.safetyControlBoard, .limited, .primary, .primary, .none, .none, .none)
        assertAccess(.taskAssignment, .limited, .primary, .primary, .none, .none, .none)
        assertAccess(.taskReport, .limited, .primary, .primary, .primary, .limited, .limited)

        assertAccess(.patientCreation, .none, .limited, .primary, .limited, .primary, .none)
        assertAccess(.startTriage, .none, .limited, .primary, .none, .primary, .none)
        assertAccess(.patientLocation, .limited, .primary, .primary, .limited, .primary, .none)
        assertAccess(.patientPhoto, .none, .limited, .primary, .limited, .primary, .none)
        assertAccess(.patientStatusUpdate, .none, .limited, .primary, .none, .primary, .none)
        assertAccess(.medicalEvacuation, .none, .limited, .none, .none, .primary, .none)
        assertAccess(.hospitalCapacityView, .limited, .primary, .none, .none, .primary, .none)
        assertAccess(.patientHistory, .none, .limited, .primary, .none, .primary, .none)

        assertAccess(.communicationChannel, .primary, .primary, .primary, .primary, .primary, .limited)
        assertAccess(.radioMonitoring, .primary, .primary, .limited, .none, .none, .none)
        assertAccess(.speechTranscription, .limited, .primary, .primary, .limited, .limited, .none)
        assertAccess(.voiceReport, .limited, .primary, .primary, .primary, .limited, .limited)
        assertAccess(.realtimeTranslation, .limited, .primary, .primary, .primary, .primary, .limited)
        assertAccess(.voiceTranslation, .none, .limited, .primary, .primary, .primary, .none)
        assertAccess(.photoReport, .limited, .primary, .primary, .primary, .primary, .primary)
        assertAccess(.multiPointPhotoReport, .limited, .primary, .primary, .limited, .limited, .none)
        assertAccess(.alertPush, .primary, .primary, .primary, .primary, .primary, .limited)
        assertAccess(.alertRead, .limited, .primary, .primary, .primary, .primary, .limited)
        assertAccess(.sosSending, .limited, .primary, .primary, .primary, .primary, .limited)
        assertAccess(.sosDetail, .limited, .primary, .primary, .limited, .primary, .none)

        assertAccess(.aiDecisionAnalysis, .primary, .primary, .limited, .none, .none, .none)
        assertAccess(.aiPatientWarning, .limited, .primary, .limited, .none, .primary, .none)
        assertAccess(.aiChat, .primary, .primary, .limited, .none, .none, .none)
        assertAccess(.quickCommand, .limited, .primary, .primary, .none, .none, .none)
        assertAccess(.briefing, .limited, .primary, .primary, .none, .none, .none)
        assertAccess(.commandDispatch, .primary, .primary, .limited, .none, .none, .none)
        assertAccess(.commandAuthoritySwitch, .primary, .primary, .none, .none, .none, .none)
        assertAccess(.eventLog, .primary, .primary, .limited, .none, .limited, .none)
        assertAccess(.resourceManagement, .primary, .primary, .limited, .none, .limited, .none)
        assertAccess(.pwsIntegration, .primary, .primary, .limited, .none, .none, .none)

        XCTAssertEqual(checkedFeatures, Set(LinkGuardFeature.allCases))
        XCTAssertEqual(LinkGuardFeatureAccessMatrix.accessLevel(for: .teamLeaderIPad, feature: .subSectorCreation), .primary)
        XCTAssertEqual(LinkGuardFeatureAccessMatrix.accessLevel(for: .sccIPad, feature: .startTriage), .limited)
        XCTAssertEqual(LinkGuardFeatureAccessMatrix.accessLevel(for: .emtIPad, feature: .medicalEvacuation), .primary)
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

    func testHTTPEnvelopeTransportBuildsNetworkRequest() throws {
        let teamLeader = runtime(appID: .teamLeader)
        let task = FieldTask(
            id: "TASK-NET-1",
            incidentID: "INC-1",
            type: .recon,
            status: .assigned,
            priority: .medium,
            summary: "Network request check",
            createdAt: fixedDate
        )
        let envelope = try teamLeader.makeEnvelope(
            messageType: .taskUpsert,
            payload: task,
            createdAt: fixedDate,
            idempotencyKey: "task-network-1"
        )
        let transport = HTTPEnvelopeTransport(endpointURL: URL(string: "https://sync.linkguard.local/envelopes")!, bearerToken: "token")
        let batch = try transport.makeBatch(envelopes: [envelope], from: teamLeader.device, at: fixedDate)
        let request = try transport.makeRequest(for: batch)
        let body = try XCTUnwrap(request.httpBody)
        let decodedBatch = try LinkGuardJSON.decode(SyncTransportBatch.self, from: body)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(decodedBatch.device.id, teamLeader.device.id)
        XCTAssertEqual(decodedBatch.envelopes.first?.idempotencyKey, "task-network-1")
    }

    func testFileBackedOfflineSyncPersistsAndFlushesQueuedEnvelopes() async throws {
        let teamLeader = runtime(appID: .teamLeader)
        let store = FileBackedLocalOperationCacheStore(fileURL: try temporaryCacheURL())
        let task = FieldTask(
            id: "TASK-OFFLINE-1",
            incidentID: "INC-1",
            type: .search,
            status: .assigned,
            priority: .high,
            summary: "Persisted offline task",
            createdAt: fixedDate
        )
        let envelope = try teamLeader.makeEnvelope(
            messageType: .taskUpsert,
            payload: task,
            createdAt: fixedDate,
            idempotencyKey: "offline-task-1"
        )
        var cache = LocalOperationCache(connectivity: .offline)
        cache.queue(envelope, at: fixedDate)
        _ = try store.save(cache, at: fixedDate)

        let coordinator = OfflineSyncCoordinator(store: store, transport: AcceptingTransport(), device: teamLeader.device)
        let result = try await coordinator.recoverAndSync(
            connectivity: .online,
            trigger: .connectivityRecovered,
            now: fixedDate.addingTimeInterval(30)
        )
        let reloaded = try store.load()

        XCTAssertTrue(result.attempted)
        XCTAssertEqual(result.deliveredEnvelopeIDs, [envelope.id])
        XCTAssertEqual(result.remainingPendingCount, 0)
        XCTAssertEqual(reloaded.pendingCount, 0)
        XCTAssertEqual(reloaded.lastSyncAt, fixedDate.addingTimeInterval(30))
        XCTAssertEqual(reloaded.connectivity, .online)
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

    func testCurrentVersionInfoMatchesReleaseBaseline() throws {
        let versionInfo = LinkGuardVersionInfo.current

        XCTAssertEqual(versionInfo.product, "LinkGuard")
        XCTAssertEqual(versionInfo.shortVersion, "\(versionInfo.version.major).\(versionInfo.version.minor).\(versionInfo.version.patch)")
        XCTAssertGreaterThan(versionInfo.buildNumber, 0)
        XCTAssertTrue(ReleaseChannel.allCases.contains(versionInfo.releaseChannel))
        XCTAssertEqual(versionInfo.gitTag, "v\(versionInfo.version.stringValue)")
        XCTAssertEqual(versionInfo.displayVersion, "\(versionInfo.version.stringValue) (\(versionInfo.buildNumber))")
    }

    func testAppSettingsInfoExposesBuildVersionForSettings() {
        let settingsInfo = LinkGuardAppSettingsInfo(
            device: DeviceIdentity(id: "DEVICE-UCC", appID: .ucc, platform: .mac, displayName: "UCC Console")
        )
        let itemValues = Dictionary(uniqueKeysWithValues: settingsInfo.items.map { ($0.key, $0.value) })
        let versionInfo = LinkGuardVersionInfo.current

        XCTAssertEqual(itemValues["app"], "LinkGuard-UCC")
        XCTAssertEqual(itemValues["device"], "UCC Console")
        XCTAssertEqual(itemValues["version"], versionInfo.version.stringValue)
        XCTAssertEqual(itemValues["build"], String(versionInfo.buildNumber))
        XCTAssertEqual(itemValues["gitTag"], versionInfo.gitTag)
        XCTAssertEqual(settingsInfo.displayVersion, versionInfo.displayVersion)
    }

    func testSemanticVersionParser() throws {
        let alpha = try XCTUnwrap(SemanticVersion(string: "0.3.0-alpha.1"))
        let field = try XCTUnwrap(SemanticVersion(string: "0.3.1-1"))
        let stable = try XCTUnwrap(SemanticVersion(string: "1.2.3"))

        XCTAssertEqual(alpha.major, 0)
        XCTAssertEqual(alpha.minor, 3)
        XCTAssertEqual(alpha.patch, 0)
        XCTAssertEqual(alpha.prereleaseIdentifiers, ["alpha", "1"])
        XCTAssertEqual(alpha.stringValue, "0.3.0-alpha.1")
        XCTAssertEqual(field.patch, 1)
        XCTAssertEqual(field.prereleaseIdentifiers, ["1"])
        XCTAssertEqual(field.stringValue, "0.3.1-1")
        XCTAssertEqual(stable.prereleaseIdentifiers, [])
        XCTAssertEqual(stable.stringValue, "1.2.3")
        XCTAssertNil(SemanticVersion(string: "0.3"))
    }

    func testFieldOperationalPrinciplesPrioritizeReliabilityBeforeAI() throws {
        let principles = FieldOperationalPrinciples.firefighterInterview2026

        XCTAssertTrue(FieldOperationalPrinciples.primaryStatement.contains("不是 AI"))
        XCTAssertEqual(principles.first?.id, "connection-continuity")
        XCTAssertEqual(principles.map(\.id).prefix(3), ["connection-continuity", "crash-resistance", "offline-capable"])
        XCTAssertEqual(FieldOperationalPrinciples.principle(id: "large-buttons")?.title, "大按鈕")
        XCTAssertTrue(FieldOperationalPrinciples.primaryActionFitsTimeBudget(seconds: 3))
        XCTAssertFalse(FieldOperationalPrinciples.primaryActionFitsTimeBudget(seconds: 3.1))
        XCTAssertTrue(FieldOperationalPrinciples.primaryButtonFitsGloveUse(hitTargetPoints: 56))
        XCTAssertFalse(FieldOperationalPrinciples.primaryButtonFitsGloveUse(hitTargetPoints: 44))
        XCTAssertTrue(FieldOperationalPrinciples.commandFlowFitsFieldUse(stepCount: 3))
        XCTAssertFalse(FieldOperationalPrinciples.commandFlowFitsFieldUse(stepCount: 4))
        XCTAssertTrue(FieldOperationalPrinciples.contrastFitsNightUse(ratio: 7))
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

    func testPhaseOneLoginAccountPermissionsFollowICSRole() throws {
        let account = UserAccount(
            id: "ACCOUNT-SCC",
            personID: "PERSON-SCC",
            displayName: "Sector Commander",
            callSign: "SCC-1",
            allowedAppIDs: [.scc],
            defaultPosition: .operationsSectionChief,
            credentialDigest: "digest-scc"
        )
        var directory = AccountDirectory(accounts: [account])
        let sccDevice = DeviceIdentity(id: "DEVICE-SCC-AUTH", appID: .scc, platform: .mac, displayName: "SCC Console")
        let teamMemberDevice = DeviceIdentity(id: "DEVICE-TE-AUTH", appID: .teamMember, platform: .iPhone, displayName: "TE Phone")

        let session = try directory.login(
            accountID: account.id,
            credentialDigest: "digest-scc",
            device: sccDevice,
            issuedAt: fixedDate,
            sessionID: "SESSION-SCC"
        )

        XCTAssertTrue(session.allows(.issueCommand, at: fixedDate))
        XCTAssertTrue(session.allows(.assignRole, at: fixedDate))
        XCTAssertFalse(session.allows(.manageMedicalPatient, at: fixedDate))
        XCTAssertNoThrow(try directory.authorize(sessionID: session.id, permission: .manageMap, at: fixedDate))
        XCTAssertThrowsError(
            try directory.login(
                accountID: account.id,
                credentialDigest: "digest-scc",
                device: teamMemberDevice,
                issuedAt: fixedDate,
                sessionID: "SESSION-DENIED"
            )
        ) { error in
            XCTAssertEqual(error as? AccountAccessError, .appNotAllowed(accountID: account.id, appID: .teamMember))
        }
    }

    func testPhaseOneOfflineQueuePersistsAndFlushesWhenOnline() throws {
        let teamMember = runtime(appID: .teamMember)
        let hub = InMemoryTransportHub(runtimes: allAppRuntimes())
        let offlineTask = FieldTask(
            id: "TASK-OFFLINE",
            incidentID: "INC-1",
            worksiteID: "WORKSITE-1",
            assignedTeamID: "TEAM-1",
            type: .recon,
            status: .inProgress,
            priority: .high,
            summary: "Offline recon update",
            createdAt: fixedDate
        )

        let envelope = try hub.queueOffline(
            messageType: .taskUpsert,
            payload: offlineTask,
            from: teamMember.device.id,
            createdAt: fixedDate,
            idempotencyKey: "offline-task"
        )
        var cache = LocalOperationCache(connectivity: .offline)
        cache.queue(envelope, at: fixedDate)
        let restoredCache = try LocalOperationCache.decoded(from: cache.encoded())

        XCTAssertEqual(restoredCache.pendingCount, 1)
        XCTAssertFalse(restoredCache.makeSyncPlan().shouldAttemptSync)
        XCTAssertEqual(hub.runtime(for: teamMember.device.id)?.pendingOutboundCount, 1)

        var onlineCache = restoredCache
        onlineCache.markConnectivity(.online)
        XCTAssertTrue(onlineCache.makeSyncPlan().shouldAttemptSync)

        let receipts = try hub.flushQueuedOutbound(for: teamMember.device.id, deliveredAt: fixedDate.addingTimeInterval(30))

        XCTAssertFalse(receipts.isEmpty)
        XCTAssertEqual(hub.runtime(for: teamMember.device.id)?.pendingOutboundCount, 0)
        XCTAssertEqual(hub.runtime(for: "DEVICE-LinkGuard-UCC")?.snapshot.tasks["TASK-OFFLINE"]?.status, .inProgress)
    }

    func testPhaseOneMapLayerTracksGPSGeometryAndOfflinePacks() {
        let coordinate = GeoCoordinate(latitude: 25.0330, longitude: 121.5654, accuracyMeters: 4)
        let secondCoordinate = GeoCoordinate(latitude: 25.0340, longitude: 121.5660)
        let thirdCoordinate = GeoCoordinate(latitude: 25.0335, longitude: 121.5670)
        var mapLayer = MapLayerState()
        let fix = GPSFix(coordinate: coordinate, source: .deviceGPS, capturedAt: fixedDate, headingDegrees: 90)
        let polygon = MapGeometry.polygon([coordinate, secondCoordinate, thirdCoordinate])
        let feature = MapFeature(
            id: "MAP-POLYGON",
            incidentID: "INC-1",
            featureType: .hazardPolygon,
            coordinateMode: .gps,
            geometry: polygon,
            severity: .high,
            title: "Unsafe wall",
            createdBy: "DEVICE-TL",
            updatedAt: fixedDate
        )
        let pack = OfflineMapPack(
            id: "PACK-1",
            incidentID: "INC-1",
            name: "Taipei grid",
            bounds: MapBoundingBox(minimumLatitude: 25.0, minimumLongitude: 121.5, maximumLatitude: 25.1, maximumLongitude: 121.6),
            minimumZoom: 12,
            maximumZoom: 18,
            status: .available,
            byteSize: 2_048,
            downloadedAt: fixedDate
        )

        mapLayer.updateGPS(deviceID: "DEVICE-TL", fix: fix)
        mapLayer.upsertFeature(feature)
        mapLayer.upsertOfflinePack(pack)

        XCTAssertTrue(MapGeometry.point(coordinate).isValidForDisplay)
        XCTAssertTrue(MapGeometry.polyline([coordinate, secondCoordinate]).isValidForDisplay)
        XCTAssertTrue(polygon.isValidForDisplay)
        XCTAssertTrue(polygon.containsGPSCoordinates)
        XCTAssertEqual(mapLayer.gpsFixesByDeviceID["DEVICE-TL"]?.coordinate.latitude, coordinate.latitude)
        XCTAssertEqual(mapLayer.features(for: "INC-1").first?.featureType, .hazardPolygon)
        XCTAssertEqual(mapLayer.availableOfflinePack(containing: coordinate)?.id, "PACK-1")
    }

    func testOfflineMapPackProducesTileManifestAndDownloadRequests() throws {
        let pack = OfflineMapPack(
            id: "PACK-TILES-1",
            incidentID: "INC-1",
            name: "A1 offline tiles",
            bounds: MapBoundingBox(
                minimumLatitude: 25.032,
                minimumLongitude: 121.564,
                maximumLatitude: 25.036,
                maximumLongitude: 121.568
            ),
            minimumZoom: 15,
            maximumZoom: 15,
            status: .requested
        )
        let manifest = try pack.tileManifest(maxTileCount: 100)
        let requests = manifest.downloadRequests(using: MapTileURLTemplate(template: "https://tiles.linkguard.local/{z}/{x}/{y}.png"))
        var progress = OfflineMapTileDownloadProgress(packID: pack.id, totalTileCount: manifest.totalTileCount, updatedAt: fixedDate)

        progress.recordDownloaded(at: fixedDate.addingTimeInterval(1))

        XCTAssertFalse(manifest.tileCoordinates.isEmpty)
        XCTAssertEqual(requests.count, manifest.totalTileCount)
        XCTAssertTrue(requests.first?.url.absoluteString.contains("/15/") == true)
        XCTAssertGreaterThan(progress.fractionComplete, 0)
    }

    func testPhaseOneSOSBroadcastsLocationAndWritesAuditLog() throws {
        let teamMember = runtime(appID: .teamMember)
        let hub = InMemoryTransportHub(runtimes: allAppRuntimes())
        let sos = SOSReport(
            id: "SOS-1",
            incidentID: "INC-1",
            reporterDeviceID: teamMember.device.id,
            reporterAppID: teamMember.device.appID,
            location: GeoCoordinate(latitude: 25.0330, longitude: 121.5654, accuracyMeters: 3),
            dangerType: .trapped,
            note: "Void space entry blocked",
            createdAt: fixedDate
        )

        let receipts = try hub.send(
            messageType: .sosReportUpsert,
            payload: sos,
            from: teamMember.device.id,
            createdAt: fixedDate,
            idempotencyKey: "sos-1"
        )

        XCTAssertEqual(Set(receipts.map(\.recipientAppID)), Set(LinkGuardAppID.allCases))
        XCTAssertEqual(hub.runtime(for: "DEVICE-LinkGuard-UCC")?.snapshot.sosReports["SOS-1"]?.dangerType, .trapped)
        XCTAssertEqual(hub.runtime(for: "DEVICE-LinkGuard-SCC")?.snapshot.auditEvents.last?.action, .sendSOS)
        XCTAssertEqual(sos.asIncidentAlert().type, .sos)
    }

    func testFieldSOSActionCreatesMobileEnvelopeFromLatestGPSFix() throws {
        let teamMember = runtime(appID: .teamMember)
        let latestFix = GPSFix(
            coordinate: GeoCoordinate(latitude: 25.034, longitude: 121.566, accuracyMeters: 4),
            source: .deviceGPS,
            capturedAt: fixedDate
        )
        let action = FieldSOSAction(incidentID: "INC-1", dangerType: .trapped, note: "Pinned at A1")
        let envelope = try action.makeEnvelope(runtime: teamMember, latestGPSFix: latestFix, createdAt: fixedDate)
        let report = try envelope.decodePayload(SOSReport.self)

        XCTAssertEqual(envelope.messageType, .sosReportUpsert)
        XCTAssertEqual(envelope.priority, .critical)
        XCTAssertEqual(report.reporterDeviceID, teamMember.device.id)
        XCTAssertEqual(report.location.accuracyMeters, 4)
        XCTAssertThrowsError(try action.makeReport(runtime: runtime(appID: .ucc), latestGPSFix: latestFix, createdAt: fixedDate)) { error in
            XCTAssertEqual(error as? FieldSOSError, .requiresMobileOrTabletApp(.ucc))
        }
    }

    func testAARExporterFiltersAuditEventsAndCreatesCSV() throws {
        var snapshot = OperationSnapshot()
        snapshot.record(AuditEvent(
            id: "AUD-1",
            incidentID: "INC-1",
            actorID: "DEVICE-TL",
            actorRole: .teamLeader,
            appID: .teamLeader,
            deviceID: "DEVICE-TL",
            action: .safetyControl,
            targetType: "safetyZone",
            targetID: "ZONE-1",
            createdAt: fixedDate
        ))
        snapshot.record(AuditEvent(
            id: "AUD-2",
            incidentID: "INC-1",
            actorID: "DEVICE-TE",
            actorRole: .teamMember,
            appID: .teamMember,
            deviceID: "DEVICE-TE",
            action: .communication,
            targetType: "voiceReport",
            targetID: "VOICE-1",
            createdAt: fixedDate.addingTimeInterval(5)
        ))

        let query = AuditEventQuery(incidentID: "INC-1", actions: [.safetyControl])
        let bundle = AARExporter.bundle(from: snapshot, query: query, generatedAt: fixedDate.addingTimeInterval(60))
        let csv = try XCTUnwrap(String(data: try AARExporter.export(bundle, format: .csv), encoding: .utf8))
        let jsonBundle = try LinkGuardJSON.decode(AARExportBundle.self, from: try AARExporter.export(bundle, format: .json))

        XCTAssertEqual(bundle.auditEvents.map(\.id), ["AUD-1"])
        XCTAssertTrue(csv.contains("safetyControl,safetyZone,ZONE-1"))
        XCTAssertEqual(jsonBundle.auditEvents.count, 1)
    }

    func testPhaseOneMapUpdateAutoCreatesEventLog() throws {
        let teamLeader = runtime(appID: .teamLeader)
        let hub = InMemoryTransportHub(runtimes: allAppRuntimes())
        let feature = MapFeature(
            id: "MAP-POINT",
            incidentID: "INC-1",
            featureType: .victimPoint,
            coordinateMode: .gps,
            geometry: .point(GeoCoordinate(latitude: 25.0330, longitude: 121.5654)),
            severity: .critical,
            title: "Voice contact",
            createdBy: teamLeader.device.id,
            updatedAt: fixedDate
        )

        _ = try hub.send(
            messageType: .mapFeatureUpsert,
            payload: feature,
            from: teamLeader.device.id,
            createdAt: fixedDate,
            idempotencyKey: "map-point"
        )

        let sccAudit = hub.runtime(for: "DEVICE-LinkGuard-SCC")?.snapshot.auditEvents.last
        XCTAssertEqual(sccAudit?.action, .mapUpdate)
        XCTAssertEqual(sccAudit?.targetType, "mapFeature")
        XCTAssertEqual(sccAudit?.targetID, "MAP-POINT")
    }

    func testPhaseTwoSectorSubSectorWorksiteHierarchyFlowsToFieldApps() throws {
        let scc = runtime(appID: .scc)
        let hub = InMemoryTransportHub(runtimes: allAppRuntimes())
        let sector = Sector(id: "SECTOR-A", incidentID: "INC-1", name: "Sector A", commanderID: scc.device.id)
        let subSector = SubSector(
            id: "SUB-A1",
            incidentID: "INC-1",
            sectorID: sector.id,
            name: "Sub-sector A1",
            commanderID: "DEVICE-LinkGuard-TL",
            worksiteIDs: ["WORKSITE-A1-01"]
        )
        let worksite = Worksite(
            id: "WORKSITE-A1-01",
            incidentID: "INC-1",
            sectorID: sector.id,
            subSectorID: subSector.id,
            name: "A1 North Void",
            location: GeoCoordinate(latitude: 25.033, longitude: 121.565),
            asrLevel: .asr2,
            status: .assigned,
            assignedTeamIDs: ["TEAM-1"],
            hazardSummary: "Unstable slab"
        )

        _ = try hub.send(messageType: .sectorUpsert, payload: sector, from: scc.device.id, createdAt: fixedDate, idempotencyKey: "sector-a")
        _ = try hub.send(messageType: .subSectorUpsert, payload: subSector, from: scc.device.id, createdAt: fixedDate, idempotencyKey: "sub-a1")
        _ = try hub.send(messageType: .worksiteUpsert, payload: worksite, from: scc.device.id, createdAt: fixedDate, idempotencyKey: "worksite-a1")

        let tlSnapshot = try XCTUnwrap(hub.runtime(for: "DEVICE-LinkGuard-TL")?.snapshot)
        XCTAssertEqual(tlSnapshot.subSectors["SUB-A1"]?.sectorID, "SECTOR-A")
        XCTAssertEqual(tlSnapshot.worksites["WORKSITE-A1-01"]?.subSectorID, "SUB-A1")
        XCTAssertEqual(tlSnapshot.worksites(inSubSector: "SUB-A1").map(\.id), ["WORKSITE-A1-01"])
    }

    func testFieldTLControllerQueuesSectorWorksiteAndPersonnelStatus() throws {
        var controller = FieldAppController(
            appID: .teamLeader,
            platform: .iPhone,
            deviceID: "IOS-TL-TEST",
            displayName: "TL Test",
            now: fixedDate
        )

        let sectorEnvelopes = try controller.queueSectorPlan(now: fixedDate.addingTimeInterval(1))
        let statusEnvelope = try controller.queuePersonnelStatus(
            operationalState: .inWorksite,
            connectivity: .online,
            batteryLevel: 0.83,
            now: fixedDate.addingTimeInterval(2)
        )

        XCTAssertEqual(sectorEnvelopes.map(\.messageType), [.sectorUpsert, .subSectorUpsert, .worksiteUpsert])
        XCTAssertEqual(statusEnvelope.messageType, .personnelStatusUpsert)
        XCTAssertEqual(controller.pendingEnvelopeCount, 4)
        XCTAssertTrue(RoleProfileCatalog.profile(for: .teamLeader).allows(.manageIncident))
    }

    func testFieldTLAndEMTMedicalActionsFollowFeatureMatrix() throws {
        var teamLeader = FieldAppController(
            appID: .teamLeader,
            platform: .iPhone,
            deviceID: "IOS-TL-MED-TEST",
            displayName: "TL Medical Test",
            now: fixedDate
        )
        var emt = FieldAppController(
            appID: .emt,
            platform: .iPhone,
            deviceID: "IOS-EMT-MED-TEST",
            displayName: "EMT Medical Test",
            now: fixedDate
        )

        let tlPatient = try teamLeader.queuePatientUpload(displayCode: "A023", triageCategory: .red, injurySummary: "Leg bleed", now: fixedDate.addingTimeInterval(1))
        let tlStart = try teamLeader.queueStartTriage(displayCode: "A024", category: .yellow, respiratoryRate: 24, pulseRate: 104, gcs: 15, injurySummary: "Ambulatory", now: fixedDate.addingTimeInterval(2))
        let tlStatus = try teamLeader.queuePatientStatusUpdate(patientID: "PATIENT-A023", displayCode: "A023", triageCategory: .yellow, injurySummary: "Bleeding controlled", now: fixedDate.addingTimeInterval(3))
        let emtEvac = try emt.queueEvacuationRequest(patientID: "PATIENT-A023", destinationHospitalID: "HOSPITAL-1", now: fixedDate.addingTimeInterval(4))

        XCTAssertEqual([tlPatient.messageType, tlStart.messageType, tlStatus.messageType, emtEvac.messageType], [
            .patientUpsert,
            .patientUpsert,
            .patientUpsert,
            .evacuationRequestUpsert
        ])
        XCTAssertThrowsError(try teamLeader.queueEvacuationRequest(patientID: "PATIENT-A023", destinationHospitalID: nil, now: fixedDate.addingTimeInterval(5)))
        XCTAssertTrue(emt.canUseFeature(.patientCreation))
        XCTAssertTrue(emt.canUseFeature(.hospitalCapacityView))
        XCTAssertTrue(emt.canUseFeature(.voiceTranslation))
        XCTAssertFalse(emt.canUseFeature(.radioMonitoring))
        XCTAssertFalse(emt.canUseFeature(.hazardZoneManagement))
        XCTAssertThrowsError(try emt.queueSafetyZone(now: fixedDate.addingTimeInterval(6)))
    }

    func testPhaseTwoPersonnelOverviewTracksGPSStateAndConnectivity() throws {
        let teamMember = runtime(appID: .teamMember)
        let hub = InMemoryTransportHub(runtimes: allAppRuntimes())
        let report = PersonnelStatusReport(
            id: "STATUS-TE-1",
            incidentID: "INC-1",
            personID: "PERSON-TE-1",
            deviceID: teamMember.device.id,
            appID: teamMember.device.appID,
            role: .teamMember,
            operationalState: .inWorksite,
            connectivity: .online,
            location: GeoCoordinate(latitude: 25.034, longitude: 121.566, accuracyMeters: 5),
            currentSectorID: "SECTOR-A",
            currentSubSectorID: "SUB-A1",
            currentWorksiteID: "WORKSITE-A1-01",
            currentTaskID: "TASK-A1",
            batteryLevel: 0.72,
            updatedAt: fixedDate
        )

        let receipts = try hub.send(
            messageType: .personnelStatusUpsert,
            payload: report,
            from: teamMember.device.id,
            createdAt: fixedDate,
            idempotencyKey: "status-te-1"
        )
        let recipientApps = Set(receipts.map(\.recipientAppID))
        let uccSnapshot = try XCTUnwrap(hub.runtime(for: "DEVICE-LinkGuard-UCC")?.snapshot)
        let latest = uccSnapshot.latestPersonnelStatuses(onlineWithin: 60, now: fixedDate.addingTimeInterval(30))

        XCTAssertEqual(recipientApps, [.ucc, .scc, .sccIPad, .teamLeader, .teamLeaderIPad])
        XCTAssertEqual(latest.first?.operationalState, .inWorksite)
        XCTAssertEqual(latest.first?.connectivity, .online)
        XCTAssertEqual(latest.first?.location?.accuracyMeters, 5)
        XCTAssertNil(hub.runtime(for: teamMember.device.id)?.snapshot.personnelStatusReports["STATUS-TE-1"])
    }

    func testPhaseTwoTaskDispatchStatusUpdateAndPhotoReport() throws {
        let teamLeader = runtime(appID: .teamLeader)
        let teamMember = runtime(appID: .teamMember)
        let hub = InMemoryTransportHub(runtimes: allAppRuntimes())
        let assignedTask = FieldTask(
            id: "TASK-A1",
            incidentID: "INC-1",
            worksiteID: "WORKSITE-A1-01",
            assignedTeamID: "TEAM-1",
            type: .search,
            status: .assigned,
            priority: .high,
            summary: "Search A1 void",
            createdAt: fixedDate
        )
        let acceptedTask = FieldTask(
            id: assignedTask.id,
            incidentID: assignedTask.incidentID,
            worksiteID: assignedTask.worksiteID,
            assignedTeamID: assignedTask.assignedTeamID,
            type: assignedTask.type,
            status: .accepted,
            priority: assignedTask.priority,
            summary: assignedTask.summary,
            createdAt: fixedDate
        )
        let photo = PhotoReport(
            id: "PHOTO-1",
            incidentID: "INC-1",
            reporterDeviceID: teamMember.device.id,
            worksiteID: "WORKSITE-A1-01",
            taskID: assignedTask.id,
            photoAttachmentID: "ATTACH-PHOTO-1",
            location: GeoCoordinate(latitude: 25.0342, longitude: 121.5662, accuracyMeters: 3),
            capturedAt: fixedDate.addingTimeInterval(45),
            caption: "Victim voice contact marker",
            checksum: "sha256:abc"
        )

        _ = try hub.send(messageType: .taskUpsert, payload: assignedTask, from: teamLeader.device.id, createdAt: fixedDate, idempotencyKey: "task-a1-assigned")
        _ = try hub.send(messageType: .taskUpsert, payload: acceptedTask, from: teamMember.device.id, createdAt: fixedDate.addingTimeInterval(30), idempotencyKey: "task-a1-accepted")
        _ = try hub.send(messageType: .photoReportUpsert, payload: photo, from: teamMember.device.id, createdAt: fixedDate.addingTimeInterval(45), idempotencyKey: "photo-1")

        let sccSnapshot = try XCTUnwrap(hub.runtime(for: "DEVICE-LinkGuard-SCC")?.snapshot)
        XCTAssertEqual(sccSnapshot.tasks["TASK-A1"]?.status, .accepted)
        XCTAssertEqual(sccSnapshot.photoReports["PHOTO-1"]?.photoAttachmentID, "ATTACH-PHOTO-1")
        XCTAssertEqual(sccSnapshot.photoReports["PHOTO-1"]?.location.accuracyMeters, 3)
        XCTAssertEqual(sccSnapshot.auditEvents.last?.targetType, "photoReport")
    }

    func testFieldTEControllerQueuesDetailedAuthorizedReports() throws {
        var controller = FieldAppController(
            appID: .teamMember,
            platform: .iPhone,
            deviceID: "IOS-TE-TEST",
            displayName: "TE Test",
            now: fixedDate
        )

        let photo = try controller.queuePhotoReport(
            photoAttachmentID: "ATTACH-TE-1",
            caption: "A1 entry",
            checksum: "sha256:te",
            now: fixedDate.addingTimeInterval(1)
        )
        let patient = try controller.queuePatientUpload(
            displayCode: "A023",
            triageCategory: .red,
            injurySummary: "Leg bleed",
            now: fixedDate.addingTimeInterval(2)
        )
        let sos = try controller.queueSOS(dangerType: .trapped, note: "Pinned", now: fixedDate.addingTimeInterval(3))
        let task = try controller.queueTaskStatus(.inProgress, now: fixedDate.addingTimeInterval(4))
        let entry = try controller.queueSafetyEntry(.checkIn, now: fixedDate.addingTimeInterval(5))
        let chat = try controller.queueGroupChat(body: "A1 status update", now: fixedDate.addingTimeInterval(6))
        let voice = try controller.queueVoiceReport(transcript: "A1 voice update", durationSeconds: 5, now: fixedDate.addingTimeInterval(7))
        let point = try controller.queueMapMarker(featureType: .victimPoint, geometryType: .point, title: "Victim point", now: fixedDate.addingTimeInterval(8))
        let line = try controller.queueMapMarker(featureType: .evacuationRoute, geometryType: .polyline, title: "Evac line", now: fixedDate.addingTimeInterval(9))

        XCTAssertEqual([photo.messageType, patient.messageType, sos.messageType, task.messageType, entry.messageType, chat.messageType, voice.messageType, point.messageType, line.messageType], [
            .photoReportUpsert,
            .patientUpsert,
            .sosReportUpsert,
            .taskUpsert,
            .safetyEntryLogUpsert,
            .groupChatMessageAppend,
            .voiceReportAppend,
            .mapFeatureUpsert,
            .mapFeatureUpsert
        ])
        XCTAssertEqual(controller.pendingEnvelopeCount, 9)
        XCTAssertFalse(controller.canSend(.sectorUpsert))
        XCTAssertTrue(controller.canSend(.voiceReportAppend))
        XCTAssertFalse(controller.canUseFeature(.radioMonitoring))
        XCTAssertThrowsError(try controller.queueSectorPlan(now: fixedDate.addingTimeInterval(10)))
        XCTAssertThrowsError(try controller.queueSafetyZone(now: fixedDate.addingTimeInterval(11)))
        XCTAssertThrowsError(try controller.queueMapMarker(featureType: .hazardPolygon, geometryType: .polygon, title: "Hazard area", now: fixedDate.addingTimeInterval(12)))
        XCTAssertThrowsError(try controller.queueStartTriage(displayCode: "A024", category: .yellow, respiratoryRate: 24, pulseRate: 104, gcs: 15, injurySummary: "Ambulatory", now: fixedDate.addingTimeInterval(13)))
        XCTAssertThrowsError(try controller.queuePatientStatusUpdate(patientID: "PATIENT-A023", displayCode: "A023", triageCategory: .yellow, injurySummary: "Bleeding controlled", now: fixedDate.addingTimeInterval(14)))
    }

    func testVolunteerFieldAccessUsesLimitedCommunicationAndMapRules() throws {
        var controller = FieldAppController(
            appID: .volunteer,
            platform: .iPhone,
            deviceID: "IOS-VO-TEST",
            displayName: "VO Test",
            now: fixedDate
        )

        let photo = try controller.queuePhotoReport(photoAttachmentID: "ATTACH-VO-1", caption: "VO photo", checksum: nil, now: fixedDate.addingTimeInterval(1))
        let sos = try controller.queueSOS(dangerType: .trapped, note: "Lost", now: fixedDate.addingTimeInterval(2))
        let chat = try controller.queueGroupChat(body: "VO update", now: fixedDate.addingTimeInterval(3))
        let voice = try controller.queueVoiceReport(transcript: "VO voice", durationSeconds: 4, now: fixedDate.addingTimeInterval(4))
        let point = try controller.queueMapMarker(featureType: .assemblyPoint, geometryType: .point, title: "VO point", now: fixedDate.addingTimeInterval(5))

        XCTAssertEqual([photo.messageType, sos.messageType, chat.messageType, voice.messageType, point.messageType], [
            .photoReportUpsert,
            .sosReportUpsert,
            .groupChatMessageAppend,
            .voiceReportAppend,
            .mapFeatureUpsert
        ])
        XCTAssertFalse(controller.canUseFeature(.radioMonitoring))
        XCTAssertThrowsError(try controller.queuePatientUpload(displayCode: "A023", triageCategory: .red, injurySummary: "Leg bleed", now: fixedDate.addingTimeInterval(6)))
        XCTAssertThrowsError(try controller.queueMapMarker(featureType: .evacuationRoute, geometryType: .polyline, title: "VO line", now: fixedDate.addingTimeInterval(7)))
        XCTAssertThrowsError(try controller.queueMapMarker(featureType: .hazardPolygon, geometryType: .polygon, title: "VO area", now: fixedDate.addingTimeInterval(8)))
    }

    func testPhaseTwoSafetyControlTracksZonesAndEntryLogs() throws {
        let teamLeader = runtime(appID: .teamLeader)
        let teamMember = runtime(appID: .teamMember)
        let hub = InMemoryTransportHub(runtimes: allAppRuntimes())
        let coordinates = [
            GeoCoordinate(latitude: 25.0330, longitude: 121.5650),
            GeoCoordinate(latitude: 25.0335, longitude: 121.5660),
            GeoCoordinate(latitude: 25.0328, longitude: 121.5664)
        ]
        let zone = SafetyZone(
            id: "ZONE-HOT-A1",
            incidentID: "INC-1",
            zoneType: .hotZone,
            title: "A1 hot zone",
            geometry: .polygon(coordinates),
            severity: .critical,
            updatedBy: teamLeader.device.id,
            updatedAt: fixedDate
        )
        let entry = SafetyEntryLog(
            id: "ENTRY-1",
            incidentID: "INC-1",
            zoneID: zone.id,
            personID: "PERSON-TE-1",
            deviceID: teamMember.device.id,
            action: .checkIn,
            location: coordinates[0],
            recordedAt: fixedDate.addingTimeInterval(15),
            recordedBy: teamMember.device.id,
            note: "Entering with TL approval"
        )

        _ = try hub.send(messageType: .safetyZoneUpsert, payload: zone, from: teamLeader.device.id, createdAt: fixedDate, idempotencyKey: "zone-hot-a1")
        _ = try hub.send(messageType: .safetyEntryLogUpsert, payload: entry, from: teamMember.device.id, createdAt: fixedDate.addingTimeInterval(15), idempotencyKey: "entry-1")

        let uccSnapshot = try XCTUnwrap(hub.runtime(for: "DEVICE-LinkGuard-UCC")?.snapshot)
        XCTAssertEqual(uccSnapshot.safetyZones["ZONE-HOT-A1"]?.severity, .critical)
        XCTAssertTrue(uccSnapshot.safetyZones["ZONE-HOT-A1"]?.geometry.isValidForDisplay == true)
        XCTAssertEqual(uccSnapshot.safetyEntryLogs["ENTRY-1"]?.action, .checkIn)
        XCTAssertEqual(uccSnapshot.auditEvents.last?.action, .safetyControl)
    }

    func testPhaseTwoGroupChatAndVoiceReportsReachCommunicationRoute() throws {
        let teamLeader = runtime(appID: .teamLeader)
        let hub = InMemoryTransportHub(runtimes: allAppRuntimes())
        let chat = GroupChatMessage(
            id: "CHAT-1",
            incidentID: "INC-1",
            groupID: "GROUP-A1",
            senderDeviceID: teamLeader.device.id,
            senderRole: .teamLeader,
            body: "Need shoring at A1 entry",
            priority: .high,
            sentAt: fixedDate,
            location: GeoCoordinate(latitude: 25.034, longitude: 121.566)
        )
        let voice = VoiceReport(
            id: "VOICE-1",
            incidentID: "INC-1",
            groupID: "GROUP-A1",
            senderDeviceID: teamLeader.device.id,
            audioAttachmentID: "AUDIO-1",
            transcript: "Need shoring at A1 entry",
            durationSeconds: 8.5,
            priority: .high,
            recordedAt: fixedDate.addingTimeInterval(5),
            location: GeoCoordinate(latitude: 25.034, longitude: 121.566)
        )

        let chatReceipts = try hub.send(messageType: .groupChatMessageAppend, payload: chat, from: teamLeader.device.id, createdAt: fixedDate, idempotencyKey: "chat-1")
        let voiceReceipts = try hub.send(messageType: .voiceReportAppend, payload: voice, from: teamLeader.device.id, createdAt: fixedDate.addingTimeInterval(5), idempotencyKey: "voice-1")

        XCTAssertEqual(Set(chatReceipts.map(\.recipientAppID)), Set(LinkGuardAppID.allCases))
        XCTAssertEqual(Set(voiceReceipts.map(\.recipientAppID)), Set(LinkGuardAppID.allCases))
        XCTAssertEqual(hub.runtime(for: "DEVICE-LinkGuard-EMT")?.snapshot.groupChatMessages["CHAT-1"]?.body, "Need shoring at A1 entry")
        XCTAssertEqual(hub.runtime(for: "DEVICE-LinkGuard-UCC")?.snapshot.voiceReports["VOICE-1"]?.durationSeconds, 8.5)
        XCTAssertEqual(hub.runtime(for: "DEVICE-LinkGuard-SCC")?.snapshot.auditEvents.last?.action, .communication)
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

    func testMacUCCUIInheritsRuntimeBlueprintAndSnapshot() throws {
        var snapshot = OperationSnapshot()
        let alert = IncidentAlert(
            id: "ALERT-MAC",
            incidentID: "INC-1",
            type: .collapseRisk,
            priority: .high,
            title: "Collapse Risk",
            body: "Shore before entry",
            issuedBy: "DEVICE-UCC",
            issuedAt: fixedDate
        )
        let envelope = try SyncEnvelope.make(
            messageType: .alertUpsert,
            sourceAppID: .ucc,
            sourceDeviceID: "DEVICE-UCC",
            priority: .high,
            createdAt: fixedDate,
            idempotencyKey: "mac-alert",
            payload: alert
        )
        try snapshot.apply(envelope)

        let state = try MacSystemUIFactory.makeState(appID: .ucc, deviceID: "DEVICE-UCC", snapshot: snapshot)
        let sections = state.navigationItems.map(\.section)

        XCTAssertEqual(state.runtime.device.platform, .mac)
        XCTAssertEqual(state.runtime.blueprint.appID, .ucc)
        XCTAssertTrue(sections.contains(.finance))
        XCTAssertTrue(sections.contains(.afterActionReview))
        XCTAssertEqual(state.metrics.first { $0.id == "alerts" }?.value, "1")
        XCTAssertTrue(state.quickActions.contains { $0.id == "issue-command" && $0.isEnabled })
        XCTAssertTrue(state.inheritedModules.first { $0.section == .command }?.inheritedFrom.contains("TransportTopology") == true)
        XCTAssertEqual(state.settingsItems.first { $0.key == "version" }?.value, LinkGuardVersionInfo.current.version.stringValue)
        XCTAssertEqual(state.settingsItems.first { $0.key == "build" }?.value, String(LinkGuardVersionInfo.current.buildNumber))
    }

    func testMacSCCUIUsesSCCScopeInsteadOfUCCMirror() throws {
        let state = try MacSystemUIFactory.makeState(appID: .scc, deviceID: "DEVICE-SCC")
        let sections = state.navigationItems.map(\.section)

        XCTAssertEqual(state.runtime.profile.displayName, "SCC")
        XCTAssertTrue(sections.contains(.command))
        XCTAssertTrue(sections.contains(.operations))
        XCTAssertFalse(sections.contains(.finance))
        XCTAssertFalse(state.quickActions.contains { $0.id == "finance" })
        XCTAssertEqual(LinkGuardFeatureAccessMatrix.accessLevel(for: .scc, feature: .medicalEvacuation), .limited)
        XCTAssertTrue(state.transportRoutes.contains { $0.messageType == .evacuationRequestUpsert && $0.receives && $0.canSend })
    }

    func testMacUIRejectsNonMacApps() throws {
        XCTAssertThrowsError(try MacSystemUIFactory.makeState(appID: .teamLeader, deviceID: "DEVICE-TL")) { error in
            XCTAssertEqual(error as? MacSystemUIError, .unsupportedApp(.teamLeader))
        }
    }
}
