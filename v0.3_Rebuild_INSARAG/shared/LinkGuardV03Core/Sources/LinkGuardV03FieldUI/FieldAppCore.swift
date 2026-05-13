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

public struct FieldMissionSummary: Codable, Hashable, Sendable {
    public var incidentName: String
    public var worksiteName: String
    public var openTaskCount: Int
    public var assignedTaskCount: Int
    public var personnelCount: Int
    public var onlinePersonnelCount: Int
    public var safetyZoneCount: Int
    public var photoReportCount: Int
    public var disasterReportCount: Int
    public var patientCount: Int
    public var sosCount: Int

    public init(
        incidentName: String,
        worksiteName: String,
        openTaskCount: Int,
        assignedTaskCount: Int,
        personnelCount: Int,
        onlinePersonnelCount: Int,
        safetyZoneCount: Int,
        photoReportCount: Int,
        disasterReportCount: Int,
        patientCount: Int,
        sosCount: Int
    ) {
        self.incidentName = incidentName
        self.worksiteName = worksiteName
        self.openTaskCount = openTaskCount
        self.assignedTaskCount = assignedTaskCount
        self.personnelCount = personnelCount
        self.onlinePersonnelCount = onlinePersonnelCount
        self.safetyZoneCount = safetyZoneCount
        self.photoReportCount = photoReportCount
        self.disasterReportCount = disasterReportCount
        self.patientCount = patientCount
        self.sosCount = sosCount
    }
}

public struct FieldInboxItem: Codable, Hashable, Sendable, Identifiable {
    public var id: LinkGuardID
    public var title: String
    public var detail: String
    public var systemImageName: String
    public var priority: PriorityLevel

    public init(id: LinkGuardID, title: String, detail: String, systemImageName: String, priority: PriorityLevel) {
        self.id = id
        self.title = title
        self.detail = detail
        self.systemImageName = systemImageName
        self.priority = priority
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
        seedMissionState(now: now)
    }

    public var profile: RoleProfile { runtime.profile }
    public var blueprint: AppBlueprint { runtime.blueprint }
    public var teamMemberPhases: [TeamMemberPhase] { TeamMemberPhaseCatalog.phases(for: runtime.device.appID) }
    public var executableTeamMemberPhases: [TeamMemberPhase] { teamMemberPhases.filter(TeamMemberPhaseCatalog.isExecutableByTeamMember) }
    public var emtMedicalPhases: [EMTMedicalPhase] { EMTMedicalPhaseCatalog.phases(for: runtime.device.appID) }
    public var executableEMTMedicalPhases: [EMTMedicalPhase] { emtMedicalPhases.filter(EMTMedicalPhaseCatalog.isExecutableByEMT) }
    public var pendingEnvelopeCount: Int { localCache.pendingCount }
    public var missionSummary: FieldMissionSummary {
        let snapshot = runtime.snapshot
        let openTasks = snapshot.tasks.values.filter { $0.status != .completed && $0.status != .cancelled }
        let assignedTasks = snapshot.tasks.values.filter { $0.status == .assigned || $0.status == .accepted || $0.status == .inProgress }
        let personnel = snapshot.personnelStatusReports.values
        let onlinePersonnel = personnel.filter { $0.connectivity == .online || $0.connectivity == .degraded }
        return FieldMissionSummary(
            incidentName: snapshot.incidents[context.incidentID]?.displayName ?? context.incidentID.rawValue,
            worksiteName: snapshot.worksites[context.worksiteID]?.name ?? context.worksiteID.rawValue,
            openTaskCount: openTasks.count,
            assignedTaskCount: assignedTasks.count,
            personnelCount: personnel.count,
            onlinePersonnelCount: onlinePersonnel.count,
            safetyZoneCount: snapshot.safetyZones.count,
            photoReportCount: snapshot.photoReports.count,
            disasterReportCount: snapshot.disasterReports.count,
            patientCount: snapshot.patients.count,
            sosCount: snapshot.sosReports.count
        )
    }

    public var inboxItems: [FieldInboxItem] {
        let taskItems = runtime.snapshot.tasks.values
            .filter { $0.status != .completed && $0.status != .cancelled }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.createdAt > rhs.createdAt
            }
            .prefix(4)
            .map { task in
                FieldInboxItem(
                    id: task.id,
                    title: task.summary,
                    detail: "\(task.type.rawValue) / \(task.status.rawValue)",
                    systemImageName: "checklist.checked",
                    priority: task.priority
                )
            }
        let sosItems = runtime.snapshot.sosReports.values
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(2)
            .map { report in
                FieldInboxItem(
                    id: report.id,
                    title: "SOS \(report.dangerType.rawValue)",
                    detail: report.reporterDeviceID.rawValue,
                    systemImageName: "sos.circle.fill",
                    priority: .critical
                )
            }
        return Array(taskItems + sosItems)
    }

    public var roleWorkflowTitle: String {
        switch runtime.device.appID {
        case .sccIPad:
            return "SCC iPad / Sector Control"
        case .teamLeader, .teamLeaderIPad:
            return "TL / Worksite Command"
        case .teamMember:
            return "TE / Task Execution"
        case .volunteer:
            return "VO / Support Reporting"
        case .emt, .emtIPad:
            return "EMT / Triage Flow"
        case .ucc, .scc:
            return "Command Field Preview"
        }
    }

    public var roleWorkflowSubtitle: String {
        switch runtime.device.appID {
        case .sccIPad:
            return "分區管理、人員總覽、安全管制"
        case .teamLeader, .teamLeaderIPad:
            return "分區、Worksite、任務派遣與回報閉環"
        case .teamMember:
            return "任務接收、GPS、照片、SOS 與狀態回報"
        case .volunteer:
            return "GPS、SOS、照片、災情與語音回報"
        case .emt, .emtIPad:
            return LinkGuardEMTMedicalVersion.corePositioning
        case .ucc, .scc:
            return "shared core envelope preview"
        }
    }

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

    public mutating func receive(_ envelope: SyncEnvelope) throws {
        try runtime.receive(envelope)
    }

    @discardableResult
    public mutating func queueGPSReport(now: Date) throws -> SyncEnvelope {
        try requireFeature(.gpsTracking)
        return try queuePersonnelLocation(state: .available, note: "GPS heartbeat", now: now)
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
    public mutating func queueTaskAssignment(summary: String = "Search A1 void and report victim contact", now: Date) throws -> SyncEnvelope {
        try requireFeature(.taskAssignment)
        let task = FieldTask(
            id: context.taskID,
            incidentID: context.incidentID,
            worksiteID: context.worksiteID,
            assignedTeamID: context.teamID,
            type: .search,
            status: .assigned,
            priority: .high,
            summary: summary,
            createdAt: now
        )
        let envelope = try runtime.makeEnvelope(
            messageType: .taskUpsert,
            payload: task,
            createdAt: now,
            idempotencyKey: idempotencyKey("task-assignment", now),
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
    public mutating func queueDisasterReport(
        kind: DisasterReportKind,
        severity: PriorityLevel = .high,
        summary: String? = nil,
        photoAttachmentIDs: [LinkGuardID] = [],
        now: Date
    ) throws -> SyncEnvelope {
        try requireFeature(.disasterReport)
        let report = DisasterReport(
            id: LinkGuardID.generated(prefix: "DISASTER"),
            incidentID: context.incidentID,
            reporterDeviceID: runtime.device.id,
            reporterAppID: runtime.device.appID,
            kind: kind,
            location: try currentCoordinate(),
            severity: severity,
            summary: summary,
            photoAttachmentIDs: photoAttachmentIDs,
            createdAt: now
        )
        let envelope = try runtime.makeEnvelope(
            messageType: .disasterReportUpsert,
            payload: report,
            priority: severity,
            createdAt: now,
            idempotencyKey: idempotencyKey("disaster-\(kind.rawValue)", now),
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

    @discardableResult
    public mutating func queueHospitalCapacityUpdate(
        hospitalID: LinkGuardID = "HOSPITAL-FIELD-1",
        name: String = "Receiving Hospital",
        emergencyCapacity: Int,
        traumaCapacity: Int,
        burnCapacity: Int = 0,
        pediatricCapacity: Int = 0,
        now: Date
    ) throws -> SyncEnvelope {
        try requireFeature(.hospitalCapacityView)
        let hospital = HospitalCapacity(
            id: hospitalID,
            name: name,
            emergencyCapacity: emergencyCapacity,
            traumaCapacity: traumaCapacity,
            burnCapacity: burnCapacity,
            pediatricCapacity: pediatricCapacity,
            updatedAt: now
        )
        let envelope = try runtime.makeEnvelope(
            messageType: .hospitalCapacityUpsert,
            payload: hospital,
            createdAt: now,
            idempotencyKey: idempotencyKey("hospital-\(hospitalID.rawValue)", now),
            sourceRole: defaultRole
        )
        return queue(envelope, at: now)
    }

    private mutating func queue(_ envelope: SyncEnvelope, at date: Date) -> SyncEnvelope {
        try? runtime.receive(envelope)
        localCache.queue(envelope, at: date)
        runtime.queueOutbound(envelope, queuedAt: date)
        queuedSummaries.insert(FieldQueuedEnvelopeSummary(envelope: envelope), at: 0)
        queuedSummaries = Array(queuedSummaries.prefix(8))
        return envelope
    }

    private mutating func queuePersonnelLocation(state: PersonnelOperationalState, note: String?, now: Date) throws -> SyncEnvelope {
        let report = PersonnelStatusReport(
            id: LinkGuardID("GPS-\(runtime.device.id.rawValue)"),
            incidentID: context.incidentID,
            personID: context.personID,
            deviceID: runtime.device.id,
            appID: runtime.device.appID,
            role: defaultRole,
            operationalState: state,
            connectivity: .online,
            location: latestGPSFix?.coordinate,
            currentSectorID: context.sectorID,
            currentSubSectorID: context.subSectorID,
            currentWorksiteID: context.worksiteID,
            currentTaskID: context.taskID,
            batteryLevel: nil,
            updatedAt: now,
            note: note
        )
        let envelope = try runtime.makeEnvelope(
            messageType: .personnelStatusUpsert,
            payload: report,
            createdAt: now,
            idempotencyKey: idempotencyKey("gps", now),
            sourceRole: defaultRole
        )
        return queue(envelope, at: now)
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

    private mutating func seedMissionState(now: Date) {
        let coordinate = latestGPSFix?.coordinate ?? GeoCoordinate(latitude: 25.033, longitude: 121.565, accuracyMeters: 8)
        let incident = Incident(
            id: context.incidentID,
            displayName: "INSARAG Field Drill",
            status: .active,
            createdAt: now,
            createdBy: "DEVICE-LinkGuard-SCC",
            commandPostLocation: coordinate
        )
        let sector = Sector(id: context.sectorID, incidentID: context.incidentID, name: "Sector A", commanderID: "DEVICE-LinkGuard-SCC")
        let subSector = SubSector(
            id: context.subSectorID,
            incidentID: context.incidentID,
            sectorID: context.sectorID,
            name: "Sub-sector A1",
            commanderID: "DEVICE-LinkGuard-TL",
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
            hazardSummary: "Unstable entry; maintain accountability"
        )
        let task = FieldTask(
            id: context.taskID,
            incidentID: context.incidentID,
            worksiteID: context.worksiteID,
            assignedTeamID: context.teamID,
            type: .search,
            status: .assigned,
            priority: .high,
            summary: "Search A1 void and report victim contact",
            createdAt: now
        )
        let zone = SafetyZone(
            id: context.zoneID,
            incidentID: context.incidentID,
            zoneType: .hotZone,
            title: "A1 hot zone",
            geometry: .polygon([
                coordinate,
                GeoCoordinate(latitude: coordinate.latitude + 0.00025, longitude: coordinate.longitude),
                GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude + 0.00025)
            ]),
            severity: .critical,
            updatedBy: "DEVICE-LinkGuard-SCC",
            updatedAt: now
        )
        let tlStatus = seededPersonnelStatus(id: "STATUS-SEED-TL", personID: "PERSON-TL-1", deviceID: "DEVICE-LinkGuard-TL", appID: .teamLeader, role: .teamLeader, state: .assigned, coordinate: coordinate, now: now)
        let teStatus = seededPersonnelStatus(id: "STATUS-SEED-TE", personID: "PERSON-TE-1", deviceID: "DEVICE-LinkGuard-TE", appID: .teamMember, role: .teamMember, state: .inWorksite, coordinate: coordinate, now: now)
        let emtStatus = seededPersonnelStatus(id: "STATUS-SEED-EMT", personID: "PERSON-EMT-1", deviceID: "DEVICE-LinkGuard-EMT", appID: .emt, role: .emt, state: .available, coordinate: coordinate, now: now)

        receiveSeed(.incidentUpsert, payload: incident, sourceAppID: .scc, sourceDeviceID: "DEVICE-LinkGuard-SCC", sourceRole: .sectorCommander, at: now, suffix: "incident")
        receiveSeed(.sectorUpsert, payload: sector, sourceAppID: .scc, sourceDeviceID: "DEVICE-LinkGuard-SCC", sourceRole: .sectorCommander, at: now, suffix: "sector")
        receiveSeed(.subSectorUpsert, payload: subSector, sourceAppID: .teamLeader, sourceDeviceID: "DEVICE-LinkGuard-TL", sourceRole: .teamLeader, at: now, suffix: "subsector")
        receiveSeed(.worksiteUpsert, payload: worksite, sourceAppID: .teamLeader, sourceDeviceID: "DEVICE-LinkGuard-TL", sourceRole: .teamLeader, at: now, suffix: "worksite")
        receiveSeed(.taskUpsert, payload: task, sourceAppID: .teamLeader, sourceDeviceID: "DEVICE-LinkGuard-TL", sourceRole: .teamLeader, at: now, suffix: "task")
        receiveSeed(.safetyZoneUpsert, payload: zone, sourceAppID: .scc, sourceDeviceID: "DEVICE-LinkGuard-SCC", sourceRole: .sectorCommander, at: now, suffix: "zone")
        receiveSeed(.personnelStatusUpsert, payload: tlStatus, sourceAppID: .teamLeader, sourceDeviceID: "DEVICE-LinkGuard-TL", sourceRole: .teamLeader, at: now, suffix: "status-tl")
        receiveSeed(.personnelStatusUpsert, payload: teStatus, sourceAppID: .teamMember, sourceDeviceID: "DEVICE-LinkGuard-TE", sourceRole: .teamMember, at: now, suffix: "status-te")
        receiveSeed(.personnelStatusUpsert, payload: emtStatus, sourceAppID: .emt, sourceDeviceID: "DEVICE-LinkGuard-EMT", sourceRole: .emt, at: now, suffix: "status-emt")
    }

    private func seededPersonnelStatus(
        id: LinkGuardID,
        personID: LinkGuardID,
        deviceID: LinkGuardID,
        appID: LinkGuardAppID,
        role: ICSPosition,
        state: PersonnelOperationalState,
        coordinate: GeoCoordinate,
        now: Date
    ) -> PersonnelStatusReport {
        PersonnelStatusReport(
            id: id,
            incidentID: context.incidentID,
            personID: personID,
            deviceID: deviceID,
            appID: appID,
            role: role,
            operationalState: state,
            connectivity: .online,
            location: coordinate,
            currentSectorID: context.sectorID,
            currentSubSectorID: context.subSectorID,
            currentWorksiteID: context.worksiteID,
            currentTaskID: context.taskID,
            batteryLevel: 0.82,
            updatedAt: now,
            note: "seeded field state"
        )
    }

    private mutating func receiveSeed<Payload: Encodable>(
        _ messageType: SyncMessageType,
        payload: Payload,
        sourceAppID: LinkGuardAppID,
        sourceDeviceID: LinkGuardID,
        sourceRole: ICSPosition,
        at date: Date,
        suffix: String
    ) {
        guard let envelope = try? SyncEnvelope.make(
            messageType: messageType,
            sourceAppID: sourceAppID,
            sourceDeviceID: sourceDeviceID,
            sourceRole: sourceRole,
            priority: AppLogicGate.defaultPriority(for: messageType),
            createdAt: date,
            idempotencyKey: "seed-\(runtime.device.id.rawValue)-\(suffix)",
            payload: payload
        ) else { return }
        try? runtime.receive(envelope)
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