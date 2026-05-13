import Foundation
import LinkGuardV03Core

public enum FieldAppError: Error, Equatable, Sendable {
    case missingGPSFix
    case featureUnavailable(appID: LinkGuardAppID, feature: LinkGuardFeature)
}

public struct FieldOperationalContext: Codable, Hashable, Sendable {
    public var incidentID: LinkGuardID
    public var sectorID: LinkGuardID
    public var subSectorID: LinkGuardID
    public var worksiteID: LinkGuardID
    public var teamID: LinkGuardID
    public var taskID: LinkGuardID
    public var groupID: LinkGuardID
    public var zoneID: LinkGuardID
    public var personID: LinkGuardID

    public init(
        incidentID: LinkGuardID,
        sectorID: LinkGuardID,
        subSectorID: LinkGuardID,
        worksiteID: LinkGuardID,
        teamID: LinkGuardID,
        taskID: LinkGuardID,
        groupID: LinkGuardID,
        zoneID: LinkGuardID,
        personID: LinkGuardID
    ) {
        self.incidentID = incidentID
        self.sectorID = sectorID
        self.subSectorID = subSectorID
        self.worksiteID = worksiteID
        self.teamID = teamID
        self.taskID = taskID
        self.groupID = groupID
        self.zoneID = zoneID
        self.personID = personID
    }

    public static func fieldDefault(for device: DeviceIdentity) -> FieldOperationalContext {
        FieldOperationalContext(
            incidentID: "INC-FIELD-001",
            sectorID: "SECTOR-A",
            subSectorID: "SUB-A1",
            worksiteID: "WORKSITE-A1-01",
            teamID: "TEAM-ALPHA",
            taskID: "TASK-A1-SEARCH",
            groupID: "GROUP-A1",
            zoneID: "ZONE-HOT-A1",
            personID: LinkGuardID("PERSON-\(device.id.rawValue)")
        )
    }
}

public struct FieldQueuedEnvelopeSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: LinkGuardID
    public var messageType: SyncMessageType
    public var priority: PriorityLevel
    public var createdAt: Date

    public init(envelope: SyncEnvelope) {
        self.id = envelope.id
        self.messageType = envelope.messageType
        self.priority = envelope.priority
        self.createdAt = envelope.createdAt
    }
}

public struct FieldAppController: Sendable {
    public var runtime: LinkGuardAppRuntime
    public private(set) var localCache: LocalOperationCache
    public private(set) var mapLayer: MapLayerState
    public var context: FieldOperationalContext
    public private(set) var latestGPSFix: GPSFix?
    public private(set) var queuedSummaries: [FieldQueuedEnvelopeSummary]

    public init(
        appID: LinkGuardAppID,
        platform: AppPlatform,
        deviceID: LinkGuardID,
        displayName: String,
        context: FieldOperationalContext? = nil,
        now: Date = Date()
    ) {
        let device = DeviceIdentity(id: deviceID, appID: appID, platform: platform, displayName: displayName)
        self.runtime = LinkGuardAppRuntime(device: device)
        self.localCache = LocalOperationCache(connectivity: .offline)
        self.mapLayer = MapLayerState()
        self.context = context ?? .fieldDefault(for: device)
        self.latestGPSFix = nil
        self.queuedSummaries = []
        recordGPSFix(
            GPSFix(
                coordinate: GeoCoordinate(latitude: 25.033, longitude: 121.565, accuracyMeters: 8),
                source: .manual,
                capturedAt: now
            )
        )
    }

    public var profile: RoleProfile { runtime.profile }
    public var blueprint: AppBlueprint { runtime.blueprint }
    public var pendingEnvelopeCount: Int { localCache.pendingCount }

    public func canSend(_ messageType: SyncMessageType) -> Bool {
        runtime.canSend(messageType)
    }

    public func accessLevel(for feature: LinkGuardFeature) -> FeatureAccessLevel {
        LinkGuardFeatureAccessMatrix.accessLevel(for: runtime.device.appID, feature: feature)
    }

    public func canSeeFeature(_ feature: LinkGuardFeature) -> Bool {
        accessLevel(for: feature).isAvailable
    }

    public func canUseFeature(_ feature: LinkGuardFeature) -> Bool {
        canSeeFeature(feature)
    }

    public mutating func recordGPSFix(_ fix: GPSFix) {
        latestGPSFix = fix
        mapLayer.updateGPS(deviceID: runtime.device.id, fix: fix)
    }

    @discardableResult
    public mutating func queueSectorPlan(now: Date) throws -> [SyncEnvelope] {
        try requireFeature(.sectorCreation)
        try requireFeature(.subSectorCreation)
        try requireFeature(.worksiteMarkerSystem)
        let coordinate = try currentCoordinate()
        let sector = Sector(
            id: context.sectorID,
            incidentID: context.incidentID,
            name: "Sector A",
            commanderID: runtime.device.id
        )
        let subSector = SubSector(
            id: context.subSectorID,
            incidentID: context.incidentID,
            sectorID: context.sectorID,
            name: "Sub-sector A1",
            commanderID: runtime.device.id,
            worksiteIDs: [context.worksiteID]
        )
        let worksite = Worksite(
            id: context.worksiteID,
            incidentID: context.incidentID,
            sectorID: context.sectorID,
            subSectorID: context.subSectorID,
            name: "A1 North Void",
            location: coordinate,
            asrLevel: .asr2,
            status: .assigned,
            assignedTeamIDs: [context.teamID],
            hazardSummary: "Unstable entry; keep check-in active"
        )
        let envelopes = try [
            runtime.makeEnvelope(messageType: .sectorUpsert, payload: sector, createdAt: now, idempotencyKey: idempotencyKey("sector", now), sourceRole: defaultRole),
            runtime.makeEnvelope(messageType: .subSectorUpsert, payload: subSector, createdAt: now, idempotencyKey: idempotencyKey("subsector", now), sourceRole: defaultRole),
            runtime.makeEnvelope(messageType: .worksiteUpsert, payload: worksite, createdAt: now, idempotencyKey: idempotencyKey("worksite", now), sourceRole: defaultRole)
        ]
        return envelopes.map { queue($0, at: now) }
    }

    @discardableResult
    public mutating func queuePersonnelStatus(
        operationalState: PersonnelOperationalState,
        connectivity: DeviceConnectivityStatus,
        batteryLevel: Double?,
        note: String? = nil,
        now: Date
    ) throws -> SyncEnvelope {
        try requireFeature(.personnelStatusUpdate)
        let report = PersonnelStatusReport(
            id: LinkGuardID("STATUS-\(runtime.device.id.rawValue)"),
            incidentID: context.incidentID,
            personID: context.personID,
            deviceID: runtime.device.id,
            appID: runtime.device.appID,
            role: defaultRole,
            operationalState: operationalState,
            connectivity: connectivity,
            location: latestGPSFix?.coordinate,
            currentSectorID: context.sectorID,
            currentSubSectorID: context.subSectorID,
            currentWorksiteID: context.worksiteID,
            currentTaskID: context.taskID,
            batteryLevel: batteryLevel,
            updatedAt: now,
            note: note
        )
        let envelope = try runtime.makeEnvelope(
            messageType: .personnelStatusUpsert,
            payload: report,
            createdAt: now,
            idempotencyKey: idempotencyKey("personnel", now),
            sourceRole: defaultRole
        )
        return queue(envelope, at: now)
    }

    @discardableResult
    public mutating func queueTaskStatus(_ status: TaskStatus, now: Date) throws -> SyncEnvelope {
        try requireFeature(.taskReport)
        let task = FieldTask(
            id: context.taskID,
            incidentID: context.incidentID,
            worksiteID: context.worksiteID,
            assignedTeamID: context.teamID,
            type: .search,
            status: status,
            priority: .high,
            summary: "Search A1 void and report victim contact",
            createdAt: now
        )
        let envelope = try runtime.makeEnvelope(
            messageType: .taskUpsert,
            payload: task,
            createdAt: now,
            idempotencyKey: idempotencyKey("task-\(status.rawValue)", now),
            sourceRole: defaultRole
        )
        return queue(envelope, at: now)
    }

    @discardableResult
    public mutating func queuePhotoReport(
        photoAttachmentID: LinkGuardID,
        caption: String?,
        checksum: String?,
        now: Date
    ) throws -> SyncEnvelope {
        try requireFeature(.photoReport)
        let photo = PhotoReport(
            id: LinkGuardID.generated(prefix: "PHOTO"),
            incidentID: context.incidentID,
            reporterDeviceID: runtime.device.id,
            worksiteID: context.worksiteID,
            taskID: context.taskID,
            photoAttachmentID: photoAttachmentID,
            location: try currentCoordinate(),
            capturedAt: now,
            caption: caption,
            checksum: checksum
        )
        let envelope = try runtime.makeEnvelope(
            messageType: .photoReportUpsert,
            payload: photo,
            createdAt: now,
            idempotencyKey: idempotencyKey("photo", now),
            sourceRole: defaultRole
        )
        return queue(envelope, at: now)
    }

    @discardableResult
    public mutating func queueSafetyZone(now: Date) throws -> SyncEnvelope {
        try requireFeature(.hazardZoneManagement)
        let coordinate = try currentCoordinate()
        let offset = 0.00025
        let zone = SafetyZone(
            id: context.zoneID,
            incidentID: context.incidentID,
            zoneType: .hotZone,
            title: "A1 hot zone",
            geometry: .polygon([
                coordinate,
                GeoCoordinate(latitude: coordinate.latitude + offset, longitude: coordinate.longitude),
                GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude + offset)
            ]),
            severity: .critical,
            updatedBy: runtime.device.id,
            updatedAt: now
        )
        let envelope = try runtime.makeEnvelope(
            messageType: .safetyZoneUpsert,
            payload: zone,
            createdAt: now,
            idempotencyKey: idempotencyKey("zone", now),
            sourceRole: defaultRole
        )
        return queue(envelope, at: now)
    }

    @discardableResult
    public mutating func queueSafetyEntry(_ action: SafetyEntryAction, now: Date) throws -> SyncEnvelope {
        try requireFeature(.personnelEntryLog)
        let entry = SafetyEntryLog(
            id: LinkGuardID.generated(prefix: "ENTRY"),
            incidentID: context.incidentID,
            zoneID: context.zoneID,
            personID: context.personID,
            deviceID: runtime.device.id,
            action: action,
            location: latestGPSFix?.coordinate,
            recordedAt: now,
            recordedBy: runtime.device.id,
            note: action == .checkIn ? "Field check-in" : "Field check-out"
        )
        let envelope = try runtime.makeEnvelope(
            messageType: .safetyEntryLogUpsert,
            payload: entry,
            createdAt: now,
            idempotencyKey: idempotencyKey("entry-\(action.rawValue)", now),
            sourceRole: defaultRole
        )
        return queue(envelope, at: now)
    }

    @discardableResult
    public mutating func queueGroupChat(body: String, priority: PriorityLevel = .medium, now: Date) throws -> SyncEnvelope {
        try requireFeature(.communicationChannel)
        let message = GroupChatMessage(
            id: LinkGuardID.generated(prefix: "CHAT"),
            incidentID: context.incidentID,
            groupID: context.groupID,
            senderDeviceID: runtime.device.id,
            senderRole: defaultRole,
            body: body,
            priority: priority,
            sentAt: now,
            location: latestGPSFix?.coordinate
        )
        let envelope = try runtime.makeEnvelope(
            messageType: .groupChatMessageAppend,
            payload: message,
            priority: priority,
            createdAt: now,
            idempotencyKey: idempotencyKey("chat", now),
            sourceRole: defaultRole
        )
        return queue(envelope, at: now)
    }

    @discardableResult
    public mutating func queueVoiceReport(transcript: String?, durationSeconds: Double, now: Date) throws -> SyncEnvelope {
        try requireFeature(.voiceReport)
        let report = VoiceReport(
            id: LinkGuardID.generated(prefix: "VOICE"),
            incidentID: context.incidentID,
            groupID: context.groupID,
            senderDeviceID: runtime.device.id,
            audioAttachmentID: LinkGuardID.generated(prefix: "AUDIO"),
            transcript: transcript,
            durationSeconds: durationSeconds,
            priority: .high,
            recordedAt: now,
            location: latestGPSFix?.coordinate
        )
        let envelope = try runtime.makeEnvelope(
            messageType: .voiceReportAppend,
            payload: report,
            createdAt: now,
            idempotencyKey: idempotencyKey("voice", now),
            sourceRole: defaultRole
        )
        return queue(envelope, at: now)
    }

    @discardableResult
    public mutating func queueSOS(dangerType: SOSDangerType, note: String?, now: Date) throws -> SyncEnvelope {
        try requireFeature(.sosSending)
        let action = FieldSOSAction(incidentID: context.incidentID, dangerType: dangerType, note: note)
        let envelope = try action.makeEnvelope(runtime: runtime, latestGPSFix: latestGPSFix, createdAt: now)
        return queue(envelope, at: now)
    }

    @discardableResult
    public mutating func queueMapMarker(featureType: MapFeatureType, geometryType: GeometryType, title: String, now: Date) throws -> SyncEnvelope {
        try requireFeature(featureForMapGeometry(geometryType))
        let coordinate = try currentCoordinate()
        let points = mapPoints(for: geometryType, from: coordinate)
        let feature = MapFeature(
            id: LinkGuardID.generated(prefix: "MAP"),
            incidentID: context.incidentID,
            featureType: featureType,
            coordinateMode: .gps,
            geometry: MapGeometry(type: geometryType, points: points),
            severity: .high,
            title: title,
            createdBy: runtime.device.id,
            updatedAt: now
        )
        let envelope = try runtime.makeEnvelope(
            messageType: .mapFeatureUpsert,
            payload: feature,
            createdAt: now,
            idempotencyKey: idempotencyKey("map-\(geometryType.rawValue)", now),
            sourceRole: defaultRole
        )
        return queue(envelope, at: now)
    }

    @discardableResult
    public mutating func queuePatientUpload(
        displayCode: String,
        triageCategory: TriageCategory,
        injurySummary: String,
        now: Date
    ) throws -> SyncEnvelope {
        try requireFeature(.patientCreation)
        let patient = patientRecord(
            patientID: LinkGuardID.generated(prefix: "PATIENT"),
            displayCode: displayCode,
            triageCategory: triageCategory,
            injurySummary: injurySummary,
            now: now
        )
        let envelope = try runtime.makeEnvelope(
            messageType: .patientUpsert,
            payload: patient,
            createdAt: now,
            idempotencyKey: idempotencyKey("patient-upload", now),
            sourceRole: defaultRole
        )
        return queue(envelope, at: now)
    }

    @discardableResult
    public mutating func queueStartTriage(
        displayCode: String,
        category: TriageCategory,
        respiratoryRate: Int?,
        pulseRate: Int?,
        gcs: Int?,
        injurySummary: String,
        now: Date
    ) throws -> SyncEnvelope {
        try requireFeature(.startTriage)
        var patient = patientRecord(
            patientID: LinkGuardID.generated(prefix: "START"),
            displayCode: displayCode,
            triageCategory: category,
            injurySummary: injurySummary,
            now: now
        )
        patient.latestVitals = VitalSigns(
            heartRate: pulseRate,
            respiratoryRate: respiratoryRate,
            gcs: gcs,
            recordedAt: now
        )
        let envelope = try runtime.makeEnvelope(
            messageType: .patientUpsert,
            payload: patient,
            createdAt: now,
            idempotencyKey: idempotencyKey("start-triage", now),
            sourceRole: defaultRole
        )
        return queue(envelope, at: now)
    }

    @discardableResult
    public mutating func queuePatientStatusUpdate(
        patientID: LinkGuardID,
        displayCode: String,
        triageCategory: TriageCategory,
        injurySummary: String,
        now: Date
    ) throws -> SyncEnvelope {
        try requireFeature(.patientStatusUpdate)
        let patient = patientRecord(
            patientID: patientID,
            displayCode: displayCode,
            triageCategory: triageCategory,
            injurySummary: injurySummary,
            now: now
        )
        let envelope = try runtime.makeEnvelope(
            messageType: .patientUpsert,
            payload: patient,
            createdAt: now,
            idempotencyKey: idempotencyKey("patient-status-\(patientID.rawValue)", now),
            sourceRole: defaultRole
        )
        return queue(envelope, at: now)
    }

    @discardableResult
    public mutating func queueEvacuationRequest(patientID: LinkGuardID, destinationHospitalID: LinkGuardID?, now: Date) throws -> SyncEnvelope {
        try requireFeature(.medicalEvacuation)
        let request = EvacuationRequest(
            id: LinkGuardID.generated(prefix: "EVAC"),
            patientID: patientID,
            priority: .high,
            destinationHospitalID: destinationHospitalID,
            status: .pending,
            requestedAt: now
        )
        let envelope = try runtime.makeEnvelope(
            messageType: .evacuationRequestUpsert,
            payload: request,
            createdAt: now,
            idempotencyKey: idempotencyKey("evac-\(patientID.rawValue)", now),
            sourceRole: defaultRole
        )
        return queue(envelope, at: now)
    }

    private mutating func queue(_ envelope: SyncEnvelope, at date: Date) -> SyncEnvelope {
        localCache.queue(envelope, at: date)
        runtime.queueOutbound(envelope, queuedAt: date)
        queuedSummaries.insert(FieldQueuedEnvelopeSummary(envelope: envelope), at: 0)
        queuedSummaries = Array(queuedSummaries.prefix(8))
        return envelope
    }

    private func currentCoordinate() throws -> GeoCoordinate {
        guard let coordinate = latestGPSFix?.coordinate else { throw FieldAppError.missingGPSFix }
        return coordinate
    }

    private func requireFeature(_ feature: LinkGuardFeature) throws {
        guard canUseFeature(feature) else {
            throw FieldAppError.featureUnavailable(appID: runtime.device.appID, feature: feature)
        }
    }

    private func featureForMapGeometry(_ geometryType: GeometryType) -> LinkGuardFeature {
        switch geometryType {
        case .point:
            return .pointMarker
        case .polyline:
            return .lineMarker
        case .polygon:
            return .areaMarker
        }
    }

    private func mapPoints(for geometryType: GeometryType, from coordinate: GeoCoordinate) -> [MapPoint] {
        let base = MapPoint(x: 0, y: 0, latitude: coordinate.latitude, longitude: coordinate.longitude)
        let second = MapPoint(x: 1, y: 0, latitude: coordinate.latitude + 0.0002, longitude: coordinate.longitude)
        let third = MapPoint(x: 0, y: 1, latitude: coordinate.latitude, longitude: coordinate.longitude + 0.0002)
        switch geometryType {
        case .point:
            return [base]
        case .polyline:
            return [base, second]
        case .polygon:
            return [base, second, third]
        }
    }

    private func patientRecord(
        patientID: LinkGuardID,
        displayCode: String,
        triageCategory: TriageCategory,
        injurySummary: String,
        now: Date
    ) -> PatientRecord {
        PatientRecord(
            id: patientID,
            incidentID: context.incidentID,
            displayCode: displayCode,
            triageCategory: triageCategory,
            injurySummary: injurySummary,
            location: latestGPSFix?.coordinate,
            careLocationID: context.worksiteID,
            updatedAt: now
        )
    }

    private var defaultRole: ICSPosition {
        switch runtime.device.appID {
        case .ucc:
            return .incidentCommander
        case .scc, .sccIPad:
            return .sectorCommander
        case .teamLeader, .teamLeaderIPad:
            return .teamLeader
        case .teamMember:
            return .teamMember
        case .volunteer:
            return .volunteer
        case .emt, .emtIPad:
            return .emt
        }
    }

    private func idempotencyKey(_ suffix: String, _ date: Date) -> String {
        "\(runtime.device.id.rawValue)-\(suffix)-\(Int(date.timeIntervalSince1970))"
    }
}