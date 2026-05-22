import XCTest
@testable import LinkGuardV03Core
@testable import LinkGuardV03FieldUI
@testable import LinkGuardV03MacUI

final class LinkGuardV03CoreTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_799_712_000)

    private func fieldGPSFix(capturedAt: Date? = nil) -> GPSFix {
        GPSFix(
            coordinate: GeoCoordinate(latitude: 25.033, longitude: 121.565, accuracyMeters: 8),
            source: .manual,
            capturedAt: capturedAt ?? fixedDate
        )
    }

    private enum TestTransportError: Error, Equatable {
        case forcedFailure
    }

    private struct AcceptingTransport: SyncTransportClient {
        func deliver(_ envelopes: [SyncEnvelope], from device: DeviceIdentity, at date: Date) async throws -> SyncTransportResponse {
            SyncTransportResponse(
                receipts: envelopes.map { envelope in
                    SyncTransportReceipt(envelopeID: envelope.id, accepted: true, receivedAt: date)
                }
            )
        }
    }

    private struct FailingTransport: SyncTransportClient {
        func deliver(_ envelopes: [SyncEnvelope], from device: DeviceIdentity, at date: Date) async throws -> SyncTransportResponse {
            throw TestTransportError.forcedFailure
        }
    }

    private struct EmptyReceiptTransport: SyncTransportClient {
        func deliver(_ envelopes: [SyncEnvelope], from device: DeviceIdentity, at date: Date) async throws -> SyncTransportResponse {
            SyncTransportResponse(receipts: [])
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

    func testVolunteerCapabilityBlueprintDefinesTenLowComplexityPhases() {
        XCTAssertEqual(LinkGuardVolunteerBlueprint.appID, .volunteer)
        XCTAssertEqual(LinkGuardVolunteerBlueprint.positioning, "Lowest operation complexity disaster reporting tool")
        XCTAssertEqual(LinkGuardVolunteerBlueprint.phases.map(\.phaseNumber), Array(1...10))
        XCTAssertEqual(LinkGuardVolunteerBlueprint.supportedLanguages.map(\.rawValue), ["zh-Hant", "en", "ja", "ko", "vi"])
        XCTAssertTrue(LinkGuardVolunteerBlueprint.audiences.contains(.civilianVolunteer))
        XCTAssertTrue(LinkGuardVolunteerBlueprint.audiences.contains(.disasterAssistanceWorker))
        XCTAssertTrue(LinkGuardVolunteerBlueprint.audiences.contains(.logisticsSupporter))

        let phaseFive = LinkGuardVolunteerBlueprint.phase(number: 5)
        XCTAssertEqual(phaseFive?.moduleName, "Disaster Report")
        XCTAssertEqual(phaseFive?.requiredFeatures, [.disasterReport])
        XCTAssertEqual(phaseFive?.primaryMessageTypes, [.disasterReportUpsert])

        for phase in LinkGuardVolunteerBlueprint.phases {
            XCTAssertFalse(phase.requiredPermissions.contains(.issueCommand), "VO phase \(phase.phaseNumber) must not require command authority")
            for feature in phase.requiredFeatures {
                XCTAssertTrue(LinkGuardVolunteerBlueprint.isFeatureAvailableForVolunteer(feature), "Missing VO feature gate for \(feature.rawValue)")
            }
            for messageType in phase.primaryMessageTypes {
                XCTAssertTrue(runtime(appID: .volunteer).canSend(messageType), "VO cannot send \(messageType.rawValue)")
            }
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

        assertAccess(.accountIdentity, .primary, .primary, .primary, .primary, .primary, .primary)
        assertAccess(.disasterReport, .limited, .primary, .primary, .primary, .limited, .primary)
        assertAccess(.offlineDraftQueue, .limited, .primary, .primary, .primary, .primary, .primary)
        assertAccess(.hazardWarning, .limited, .primary, .primary, .primary, .primary, .primary)
        assertAccess(.simplifiedMode, .none, .none, .limited, .primary, .limited, .primary)

        assertAccess(.globalMapOverview, .primary, .limited, .limited, .none, .limited, .none)
        assertAccess(.sectorCreation, .limited, .primary, .primary, .none, .none, .none)
        assertAccess(.subSectorCreation, .none, .primary, .primary, .none, .none, .none)
        assertAccess(.pointMarker, .limited, .primary, .primary, .primary, .primary, .limited)
        assertAccess(.lineMarker, .limited, .primary, .primary, .limited, .none, .none)
        assertAccess(.areaMarker, .limited, .primary, .primary, .none, .none, .none)
        assertAccess(.hazardZoneManagement, .limited, .primary, .primary, .none, .none, .none)
        assertAccess(.searchProgressColoring, .limited, .primary, .primary, .none, .none, .none)
        assertAccess(.worksiteMarkerSystem, .none, .primary, .primary, .limited, .limited, .none)
        assertAccess(.offlineMap, .limited, .primary, .primary, .primary, .limited, .limited)

        assertAccess(.personnelOverview, .primary, .primary, .primary, .none, .limited, .none)
        assertAccess(.gpsTracking, .limited, .primary, .primary, .primary, .primary, .limited)
        assertAccess(.personnelEntryLog, .none, .primary, .primary, .limited, .limited, .none)
        assertAccess(.teamCapabilityOverview, .limited, .primary, .primary, .none, .limited, .none)
        assertAccess(.personnelStatusUpdate, .limited, .primary, .primary, .limited, .limited, .none)
        assertAccess(.safetyControlBoard, .limited, .primary, .primary, .none, .none, .none)
        assertAccess(.taskAssignment, .limited, .primary, .primary, .none, .none, .none)
        assertAccess(.taskReport, .limited, .primary, .primary, .primary, .limited, .limited)

        assertAccess(.patientCreation, .none, .limited, .primary, .limited, .primary, .none)
        assertAccess(.startTriage, .none, .limited, .primary, .none, .primary, .none)
        assertAccess(.patientLocation, .limited, .primary, .primary, .limited, .primary, .none)
        assertAccess(.patientPhoto, .none, .limited, .primary, .limited, .primary, .none)
        assertAccess(.patientStatusUpdate, .none, .limited, .primary, .none, .primary, .none)
        assertAccess(.medicalEvacuation, .primary, .limited, .none, .none, .primary, .none)
        assertAccess(.hospitalCapacityView, .primary, .limited, .none, .none, .primary, .none)
        assertAccess(.patientHistory, .none, .limited, .primary, .none, .primary, .none)

        assertAccess(.communicationChannel, .primary, .primary, .primary, .primary, .primary, .limited)
        assertAccess(.radioMonitoring, .primary, .primary, .limited, .none, .none, .none)
        assertAccess(.speechTranscription, .primary, .primary, .primary, .limited, .limited, .none)
        assertAccess(.voiceReport, .primary, .primary, .primary, .primary, .limited, .primary)
        assertAccess(.realtimeTranslation, .limited, .primary, .primary, .primary, .primary, .primary)
        assertAccess(.voiceTranslation, .none, .limited, .primary, .primary, .primary, .none)
        assertAccess(.photoReport, .limited, .primary, .primary, .primary, .primary, .primary)
        assertAccess(.multiPointPhotoReport, .limited, .primary, .primary, .limited, .limited, .none)
        assertAccess(.alertPush, .primary, .primary, .primary, .primary, .primary, .limited)
        assertAccess(.alertRead, .limited, .primary, .primary, .primary, .primary, .primary)
        assertAccess(.sosSending, .limited, .primary, .primary, .primary, .primary, .primary)
        assertAccess(.sosDetail, .limited, .primary, .primary, .limited, .primary, .none)

        assertAccess(.aiDecisionAnalysis, .primary, .limited, .limited, .none, .none, .none)
        assertAccess(.aiPatientWarning, .limited, .primary, .limited, .none, .primary, .none)
        assertAccess(.aiChat, .primary, .primary, .limited, .none, .none, .none)
        assertAccess(.quickCommand, .limited, .primary, .primary, .none, .none, .none)
        assertAccess(.briefing, .limited, .primary, .primary, .none, .none, .none)
        assertAccess(.commandDispatch, .primary, .primary, .limited, .none, .none, .none)
        assertAccess(.commandAuthoritySwitch, .primary, .limited, .none, .none, .none, .none)
        assertAccess(.eventLog, .primary, .primary, .limited, .none, .limited, .none)
        assertAccess(.disasterStatistics, .primary, .limited, .limited, .none, .limited, .none)
        assertAccess(.resourceManagement, .primary, .limited, .limited, .none, .limited, .none)
        assertAccess(.pwsIntegration, .primary, .limited, .limited, .none, .none, .none)
        assertAccess(.emicIntegration, .primary, .none, .none, .none, .none, .none)
        assertAccess(.agencyMessaging, .primary, .limited, .none, .none, .none, .none)
        assertAccess(.ceocMissionDispatch, .primary, .limited, .none, .none, .none, .none)
        assertAccess(.eocActivationManagement, .primary, .none, .none, .none, .none, .none)
        assertAccess(.medicalOperationalSummary, .primary, .limited, .limited, .none, .primary, .none)
        assertAccess(.commandCenterRedundancy, .primary, .primary, .none, .none, .none, .none)
        assertAccess(.internationalCoordination, .primary, .limited, .none, .none, .none, .none)

        assertAccess(.multiDisasterSwitch, .primary, .none, .none, .none, .none, .none)
        assertAccess(.globalHeatAnalysis, .primary, .none, .none, .none, .none, .none)
        assertAccess(.aiStrategicAnalysis, .primary, .limited, .limited, .none, .none, .none)
        assertAccess(.aiFieldRiskAnalysis, .limited, .primary, .limited, .none, .none, .none)
        assertAccess(.searchAreaManagement, .none, .primary, .primary, .limited, .none, .none)
        assertAccess(.clearedAreaMarking, .limited, .primary, .primary, .limited, .none, .none)
        assertAccess(.searchRouteManagement, .none, .primary, .primary, .limited, .none, .none)
        assertAccess(.evacuationRouteManagement, .none, .primary, .primary, .limited, .limited, .none)
        assertAccess(.teamMemberRealtimeLocation, .none, .primary, .primary, .primary, .none, .none)
        assertAccess(.teamLeaderRealtimeLocation, .limited, .primary, .primary, .none, .none, .none)
        assertAccess(.emtLocationManagement, .limited, .primary, .limited, .none, .primary, .none)
        assertAccess(.lastLocationTracking, .none, .primary, .limited, .none, .none, .none)
        assertAccess(.missingContactAlert, .none, .primary, .limited, .none, .none, .none)
        assertAccess(.crossRegionResourceDispatch, .primary, .limited, .limited, .none, .limited, .none)
        assertAccess(.heavyTeamDispatch, .primary, .none, .none, .none, .none, .none)
        assertAccess(.emtCrossRegionDispatch, .primary, .limited, .none, .none, .limited, .none)
        assertAccess(.droneDispatch, .primary, .limited, .limited, .none, .none, .none)
        assertAccess(.temporaryBaseSetup, .limited, .primary, .primary, .limited, .limited, .none)
        assertAccess(.commandPostManagement, .primary, .primary, .limited, .none, .none, .none)
        assertAccess(.photoWall, .limited, .primary, .limited, .none, .none, .none)
        assertAccess(.liveFieldPhoto, .none, .primary, .primary, .primary, .limited, .limited)
        assertAccess(.aarReplay, .primary, .limited, .none, .none, .none, .none)
        assertAccess(.globalStatisticsDashboard, .primary, .none, .none, .none, .none, .none)
        assertAccess(.fieldSituationDashboard, .limited, .primary, .limited, .none, .none, .none)
        assertAccess(.loraRelayManagement, .limited, .primary, .limited, .none, .none, .none)
        assertAccess(.highPressureMode, .none, .primary, .primary, .primary, .primary, .limited)
        assertAccess(.bigButtonMode, .none, .primary, .primary, .primary, .primary, .limited)
        assertAccess(.nightMode, .limited, .primary, .limited, .limited, .limited, .limited)
        assertAccess(.gloveMode, .none, .primary, .primary, .primary, .primary, .none)
        assertAccess(.voiceOperationMode, .limited, .primary, .limited, .limited, .limited, .limited)
        assertAccess(.multiSCCMonitoring, .primary, .none, .none, .none, .none, .none)
        assertAccess(.sccStatusMonitoring, .primary, .none, .none, .none, .none, .none)
        assertAccess(.fieldSafetyRealtimeManagement, .none, .primary, .limited, .none, .none, .none)
        assertAccess(.structuralHazardMonitoring, .limited, .primary, .limited, .none, .none, .none)
        assertAccess(.secondaryCollapseWarning, .limited, .primary, .limited, .none, .none, .none)
        assertAccess(.rescueCompletionStatistics, .primary, .limited, .limited, .none, .none, .none)
        assertAccess(.medicalCapacityAnalysis, .primary, .limited, .none, .none, .limited, .none)
        assertAccess(.roadDisruptionAnalysis, .primary, .limited, .limited, .none, .none, .none)
        assertAccess(.regionalWorkforceGapAnalysis, .primary, .none, .none, .none, .none, .none)
        assertAccess(.fieldStaffShortageAlert, .limited, .primary, .limited, .none, .none, .none)

        XCTAssertEqual(checkedFeatures, Set(LinkGuardFeature.allCases))
        XCTAssertEqual(LinkGuardFeatureAccessMatrix.accessLevel(for: .teamLeaderIPad, feature: .subSectorCreation), .primary)
        XCTAssertEqual(LinkGuardFeatureAccessMatrix.accessLevel(for: .sccIPad, feature: .startTriage), .limited)
        XCTAssertEqual(LinkGuardFeatureAccessMatrix.accessLevel(for: .emtIPad, feature: .medicalEvacuation), .primary)
    }

    func testUCCSCCCapabilityMatrixCapturesStrategicVsTacticalBoundaries() {
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "multiDisasterSwitch")?.ucc, .primary)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "multiDisasterSwitch")?.scc, .unavailable)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "subSectorCreation")?.ucc, .unavailable)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "subSectorCreation")?.scc, .primary)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "pttMonitoring")?.ucc, .primary)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "pttMonitoring")?.scc, .primary)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "emic")?.ucc, .primary)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "emic")?.scc, .unavailable)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "agencyMessaging")?.ucc, .primary)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "agencyMessaging")?.scc, .assisted)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "ceocMissionDispatch")?.ucc, .primary)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "ceocMissionDispatch")?.scc, .assisted)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "eocActivationManagement")?.ucc, .primary)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "eocActivationManagement")?.scc, .unavailable)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "medicalOperationalSummary")?.ucc, .primary)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "medicalOperationalSummary")?.scc, .assisted)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "fieldSafetyRealtime")?.ucc, .unavailable)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "fieldSafetyRealtime")?.scc, .primary)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "multiSCCMonitoring")?.ucc, .primary)
        XCTAssertEqual(UCCSCCCapabilityMatrix.scope(for: "multiSCCMonitoring")?.scc, .unavailable)
    }

    func testFeatureAccessLevelsFollowUCCSCCCapabilityContract() {
        let mappedFeatures: [LinkGuardFeature] = [
            .globalMapOverview,
            .sectorCreation,
            .subSectorCreation,
            .pointMarker,
            .lineMarker,
            .areaMarker,
            .searchProgressColoring,
            .hazardZoneManagement,
            .worksiteMarkerSystem,
            .offlineMap,
            .offlineDraftQueue,
            .gpsTracking,
            .personnelEntryLog,
            .teamCapabilityOverview,
            .taskAssignment,
            .patientLocation,
            .medicalEvacuation,
            .hospitalCapacityView,
            .communicationChannel,
            .radioMonitoring,
            .speechTranscription,
            .voiceReport,
            .photoReport,
            .sosSending,
            .sosDetail,
            .aiDecisionAnalysis,
            .aiPatientWarning,
            .commandAuthoritySwitch,
            .disasterStatistics,
            .resourceManagement,
            .pwsIntegration,
            .emicIntegration,
            .agencyMessaging,
            .ceocMissionDispatch,
            .eocActivationManagement,
            .medicalOperationalSummary,
            .commandCenterRedundancy,
            .multiDisasterSwitch,
            .globalHeatAnalysis,
            .aiStrategicAnalysis,
            .aiFieldRiskAnalysis,
            .searchAreaManagement,
            .clearedAreaMarking,
            .searchRouteManagement,
            .evacuationRouteManagement,
            .teamMemberRealtimeLocation,
            .teamLeaderRealtimeLocation,
            .emtLocationManagement,
            .lastLocationTracking,
            .missingContactAlert,
            .crossRegionResourceDispatch,
            .heavyTeamDispatch,
            .emtCrossRegionDispatch,
            .droneDispatch,
            .temporaryBaseSetup,
            .commandPostManagement,
            .photoWall,
            .liveFieldPhoto,
            .aarReplay,
            .globalStatisticsDashboard,
            .fieldSituationDashboard,
            .loraRelayManagement,
            .highPressureMode,
            .bigButtonMode,
            .nightMode,
            .gloveMode,
            .voiceOperationMode,
            .multiSCCMonitoring,
            .sccStatusMonitoring,
            .fieldSafetyRealtimeManagement,
            .structuralHazardMonitoring,
            .secondaryCollapseWarning,
            .rescueCompletionStatistics,
            .medicalCapacityAnalysis,
            .roadDisruptionAnalysis,
            .regionalWorkforceGapAnalysis,
            .fieldStaffShortageAlert
        ]

        for feature in mappedFeatures {
            guard let uccScope = UCCSCCCapabilityMatrix.expectedScope(for: feature, appID: .ucc),
                  let sccScope = UCCSCCCapabilityMatrix.expectedScope(for: feature, appID: .scc) else {
                XCTFail("Missing capability mapping for feature \(feature.rawValue)")
                continue
            }
            XCTAssertEqual(LinkGuardFeatureAccessMatrix.accessLevel(for: .ucc, feature: feature), uccScope.accessLevel, "UCC scope mismatch for \(feature.rawValue)")
            XCTAssertEqual(LinkGuardFeatureAccessMatrix.accessLevel(for: .scc, feature: feature), sccScope.accessLevel, "SCC scope mismatch for \(feature.rawValue)")
        }
    }

    func testUCCPhaseCatalogMatchesRequestedRoadmap() {
        let phases = UCCPhaseCatalog.phases

        XCTAssertEqual(UCCPhaseCatalog.positioning, "跨區域戰略指揮平台")
        XCTAssertEqual(UCCPhaseCatalog.audiences, [.fireDepartment, .emergencyOperationsCenter, .jointResponseCenter])
        XCTAssertEqual(phases.map(\.id), UCCPhaseID.allCases)
        XCTAssertEqual(phases.map(\.moduleName), [
            "全區儀表板",
            "ICS架構",
            "跨區調度",
            "AI分析",
            "災情統計",
            "電台監聽",
            "事件日誌",
            "PWS整合",
            "EMIC整合",
            "資源總控",
            "安全管制",
            "多指揮中心",
            "國際協作"
        ])
        XCTAssertEqual(phases.map(\.purpose), [
            "戰情中心",
            "指揮體系",
            "資源協同",
            "高階指揮",
            "決策依據",
            "通訊掌握",
            "災後檢討",
            "提前應變",
            "政府協同",
            "戰略配置",
            "全區安全",
            "容錯能力",
            "國際接軌"
        ])
        XCTAssertEqual(UCCPhaseCatalog.phase(id: .phase1).label, "UCC Phase 1")
        XCTAssertEqual(UCCPhaseCatalog.phase(id: .phase13).capability, "INSARAG模式")
        XCTAssertEqual(UCCPhaseCatalog.sharedCoreBackedPhases.map(\.id), [.phase1, .phase2, .phase3, .phase4, .phase5, .phase7, .phase10, .phase11])
        XCTAssertEqual(UCCPhaseCatalog.integrationPlannedPhases.map(\.id), [.phase6, .phase8, .phase9])
        XCTAssertEqual(UCCPhaseCatalog.strategicProductPlannedPhases.map(\.id), [.phase12, .phase13])
    }

    func testUCCPhasesMatchProfileAndFeatureGates() {
        let profile = RoleProfileCatalog.profile(for: .ucc)
        let phases = UCCPhaseCatalog.phases(for: .ucc)

        XCTAssertEqual(UCCPhaseCatalog.phases(for: .scc), [])
        XCTAssertEqual(phases.map(\.id), UCCPhaseID.allCases)
        for phase in phases {
            XCTAssertTrue(UCCPhaseCatalog.isVisibleInUCC(phase), phase.label)
            for permission in phase.requiredPermissions {
                XCTAssertTrue(profile.allows(permission), "\(phase.label) requires \(permission.rawValue)")
            }
            for section in phase.primarySections {
                XCTAssertTrue(profile.defaultSections.contains(section), "\(phase.label) requires \(section.rawValue)")
            }
        }
    }

    func testUCCPhaseNineCarriesCEOCEMICDataContracts() {
        let phase = UCCPhaseCatalog.phase(id: .phase9)

        XCTAssertTrue(phase.requiredFeatures.contains(.emicIntegration))
        XCTAssertTrue(phase.requiredFeatures.contains(.agencyMessaging))
        XCTAssertTrue(phase.requiredFeatures.contains(.ceocMissionDispatch))
        XCTAssertTrue(phase.requiredFeatures.contains(.eocActivationManagement))
        XCTAssertTrue(phase.relatedMessageTypes.contains(.operationalPeriodUpsert))
        XCTAssertTrue(phase.relatedMessageTypes.contains(.agencyMessageUpsert))
        XCTAssertTrue(phase.relatedMessageTypes.contains(.ceocMissionUpsert))
    }

    func testSCCPhaseCatalogMatchesRequestedRoadmap() {
        let phases = SCCPhaseCatalog.phases

        XCTAssertEqual(LinkGuardSCCVersion.appID, .scc)
        XCTAssertEqual(LinkGuardSCCVersion.appName, "LinkGuard-SCC")
        XCTAssertEqual(LinkGuardSCCVersion.editionName, "現場指揮中心版本")
        XCTAssertEqual(LinkGuardSCCVersion.targetUsers, ["現場指揮官", "特搜隊現場總指揮", "分區統籌官", "災區前進指揮所"])
        XCTAssertEqual(LinkGuardSCCVersion.corePositioning, "災區現場戰術指揮中心")
        XCTAssertEqual(phases.map(\.id), SCCPhaseID.allCases)
        XCTAssertEqual(phases.map(\.moduleName), [
            "現場戰情儀表板",
            "分區管理",
            "子區域管理",
            "地圖點線面",
            "嚴重度分色",
            "搜救狀態管理",
            "人員配置",
            "任務派遣",
            "隊伍能力表",
            "SOS統整",
            "傷患統整",
            "START統計",
            "臨時據點",
            "安全管制",
            "人員進出管理",
            "會報系統",
            "電台監聽",
            "多隊伍協調",
            "AI決策輔助",
            "AI風險分析",
            "離線指揮",
            "LoRa中繼",
            "多裝置同步",
            "UCC同步",
            "AAR紀錄"
        ])
        XCTAssertEqual(phases.map(\.purpose), [
            "建立現場戰情中心",
            "災區切割管理",
            "大型倒塌管理",
            "視覺化災區",
            "危險程度判讀",
            "區域管理",
            "現場調度",
            "戰術指揮",
            "最佳化派遣",
            "緊急應變",
            "醫療協調",
            "MCI管理",
            "現場部署",
            "搜救安全",
            "人員安全",
            "指揮同步",
            "通訊管理",
            "大型災害協同",
            "降低指揮負荷",
            "搜救安全",
            "通訊中斷備援",
            "基地台失效備援",
            "現場協同",
            "上下層協同",
            "檢討與訓練"
        ])
        XCTAssertEqual(SCCPhaseCatalog.phase(id: .phase1).label, "SCC Phase 1")
        XCTAssertEqual(SCCPhaseCatalog.phase(id: .phase25).capability, "災後回放分析")
        XCTAssertEqual(SCCPhaseCatalog.coreBackedPhases.map(\.id), [.phase1, .phase2, .phase3, .phase4, .phase5, .phase6, .phase7, .phase8, .phase9, .phase10, .phase11, .phase12, .phase13, .phase14, .phase15, .phase16, .phase18, .phase19, .phase21, .phase25])
        XCTAssertEqual(SCCPhaseCatalog.integrationPlannedPhases.map(\.id), [.phase17, .phase22])
        XCTAssertEqual(SCCPhaseCatalog.productPlannedPhases.map(\.id), [.phase20, .phase23, .phase24])
    }

    func testSCCPhasesMatchProfileAndFeatureGates() {
        let profile = RoleProfileCatalog.profile(for: .scc)
        let phases = SCCPhaseCatalog.phases(for: .scc)

        XCTAssertEqual(SCCPhaseCatalog.phases(for: .sccIPad).map(\.id), SCCPhaseID.allCases)
        XCTAssertEqual(SCCPhaseCatalog.phases(for: .teamLeader), [])
        for phase in phases {
            XCTAssertTrue(SCCPhaseCatalog.isVisibleInSCC(phase), phase.label)
            for permission in phase.requiredPermissions {
                XCTAssertTrue(profile.allows(permission), "\(phase.label) requires \(permission.rawValue)")
            }
            for section in phase.primarySections {
                XCTAssertTrue(profile.defaultSections.contains(section), "\(phase.label) requires \(section.rawValue)")
            }
        }
    }

    func testSCCUsesOperationalMedicalSummaryInsteadOfClinicalPatientPayloads() {
        let casualtyOverview = SCCPhaseCatalog.phase(id: .phase11)
        let startStatistics = SCCPhaseCatalog.phase(id: .phase12)

        XCTAssertTrue(casualtyOverview.requiredFeatures.contains(.medicalOperationalSummary))
        XCTAssertTrue(startStatistics.requiredFeatures.contains(.medicalOperationalSummary))
        XCTAssertTrue(casualtyOverview.relatedMessageTypes.contains(.patientOperationalSummaryUpsert))
        XCTAssertTrue(startStatistics.relatedMessageTypes.contains(.patientOperationalSummaryUpsert))
        XCTAssertFalse(casualtyOverview.relatedMessageTypes.contains(.patientUpsert))
        XCTAssertFalse(startStatistics.relatedMessageTypes.contains(.patientUpsert))
    }

    func testCEOCEMICContractsRoundTripThroughSnapshotAndRouting() throws {
        let incidentID = LinkGuardID("INC-CEOC-001")
        let uccAgency = AgencyIdentity(id: "AG-UCC", displayName: "UCC", jurisdiction: "National")
        let sccAgency = AgencyIdentity(id: "AG-SCC", displayName: "SCC", jurisdiction: "Local")
        let report = DisasterReport(
            id: "DR-CEOC-001",
            incidentID: incidentID,
            reporterDeviceID: "DEV-VO-001",
            reporterAppID: .volunteer,
            kind: .collapse,
            location: GeoCoordinate(latitude: 24.147, longitude: 120.673, accuracyMeters: 12),
            severity: .critical,
            summary: "Collapsed residential block",
            createdAt: fixedDate,
            sourceAgency: sccAgency,
            verificationStatus: .verified,
            verifiedByAgency: uccAgency,
            verifiedByPersonID: "PERSON-UCC-01",
            verifiedAt: fixedDate,
            affectedAreaSummary: "North district grid A3",
            victimEstimate: 12,
            emicReferenceID: "EMIC-20260522-001"
        )
        let agencyMessage = AgencyMessage(
            id: "AM-001",
            incidentID: incidentID,
            fromAgency: sccAgency,
            toAgency: uccAgency,
            kind: .situationReply,
            subject: "CEOC verification update",
            body: "Initial report verified by local command.",
            verificationStatus: .verified,
            relatedDisasterReportID: report.id,
            sentAt: fixedDate
        )
        let mission = CEOCMission(
            id: "MISSION-001",
            incidentID: incidentID,
            missionNumber: "CEOC-M-001",
            issuingAgency: uccAgency,
            receivingAgency: sccAgency,
            taskDescription: "Deploy heavy USAR intake team to sector A.",
            priority: .critical,
            status: .dispatched,
            relatedDisasterReportID: report.id,
            issuedAt: fixedDate,
            dispatchedAt: fixedDate
        )
        let operationalPeriod = OperationalPeriod(
            id: "OP-001",
            incidentID: incidentID,
            startsAt: fixedDate,
            endsAt: fixedDate.addingTimeInterval(43_200),
            objectives: ["Stabilize sector A", "Complete CEOC verification loop"],
            safetyMessage: "Aftershock watch",
            weatherForecast: "Heavy rain after 1800",
            communicationsPlanSummary: "UCC-SCC voice primary, packet sync secondary",
            medicalPlanSummary: "Route red/yellow patients to assigned hospitals",
            resourceSummary: "Heavy USAR and EMT strike teams staged",
            eocActivationLevel: .level1,
            meetingRecordIDs: ["MEET-001"]
        )
        let patientSummary = PatientOperationalSummary(
            id: "PSUM-001",
            incidentID: incidentID,
            patientID: "PAT-001",
            displayCode: "P-001",
            triageCategory: .red,
            location: GeoCoordinate(latitude: 24.148, longitude: 120.674),
            evacuationStatus: .assigned,
            destinationHospitalID: "HOSP-001",
            updatedAt: fixedDate
        )

        let envelopes = try [
            SyncEnvelope.make(messageType: .disasterReportUpsert, sourceAppID: .volunteer, sourceDeviceID: "DEV-VO-001", priority: .critical, createdAt: fixedDate, idempotencyKey: "DR-CEOC-001", payload: report),
            SyncEnvelope.make(messageType: .agencyMessageUpsert, sourceAppID: .scc, sourceDeviceID: "DEV-SCC-001", priority: .high, createdAt: fixedDate, idempotencyKey: "AM-001", payload: agencyMessage),
            SyncEnvelope.make(messageType: .ceocMissionUpsert, sourceAppID: .ucc, sourceDeviceID: "DEV-UCC-001", priority: .critical, createdAt: fixedDate, idempotencyKey: "MISSION-001", payload: mission),
            SyncEnvelope.make(messageType: .operationalPeriodUpsert, sourceAppID: .ucc, sourceDeviceID: "DEV-UCC-001", priority: .low, createdAt: fixedDate, idempotencyKey: "OP-001", payload: operationalPeriod),
            SyncEnvelope.make(messageType: .patientOperationalSummaryUpsert, sourceAppID: .emt, sourceDeviceID: "DEV-EMT-001", priority: .high, createdAt: fixedDate, idempotencyKey: "PSUM-001", payload: patientSummary)
        ]

        var snapshot = OperationSnapshot()
        for envelope in envelopes {
            try snapshot.apply(envelope)
        }

        XCTAssertEqual(snapshot.disasterReports[report.id]?.emicReferenceID, "EMIC-20260522-001")
        XCTAssertEqual(snapshot.disasterReports[report.id]?.verificationStatus, .verified)
        XCTAssertEqual(snapshot.agencyMessages[agencyMessage.id]?.relatedDisasterReportID, report.id)
        XCTAssertEqual(snapshot.ceocMissions[mission.id]?.status, .dispatched)
        XCTAssertEqual(snapshot.operationalPeriods[operationalPeriod.id]?.eocActivationLevel, .level1)
        XCTAssertEqual(snapshot.patientOperationalSummaries[patientSummary.id]?.triageCategory, .red)

        let agencyEnvelope = envelopes[1]
        XCTAssertTrue(TransportTopology.canDeliver(agencyEnvelope, to: .ucc))
        XCTAssertTrue(TransportTopology.canDeliver(agencyEnvelope, to: .scc))
        XCTAssertFalse(TransportTopology.canDeliver(agencyEnvelope, to: .teamLeader))
        XCTAssertTrue(runtime(appID: .ucc).canSend(.agencyMessageUpsert))
        XCTAssertTrue(runtime(appID: .scc).canSend(.ceocMissionUpsert))
        XCTAssertFalse(runtime(appID: .teamLeader).canSend(.agencyMessageUpsert))

        let summaryEnvelope = envelopes[4]
        XCTAssertTrue(TransportTopology.canDeliver(summaryEnvelope, to: .ucc))
        XCTAssertTrue(TransportTopology.canDeliver(summaryEnvelope, to: .scc))
        XCTAssertTrue(TransportTopology.canDeliver(summaryEnvelope, to: .emt))
        XCTAssertFalse(TransportTopology.canDeliver(summaryEnvelope, to: .volunteer))

        let summaryJSON = String(data: try LinkGuardJSON.encode(patientSummary), encoding: .utf8) ?? ""
        XCTAssertFalse(summaryJSON.contains("heartRate"))
        XCTAssertFalse(summaryJSON.contains("latestVitals"))
        XCTAssertFalse(summaryJSON.contains("injurySummary"))
    }

    func testTeamMemberPhaseCatalogMatchesRequestedRoadmap() {
        let phases = TeamMemberPhaseCatalog.phases

        XCTAssertEqual(phases.map(\.id), TeamMemberPhaseID.allCases)
        XCTAssertEqual(phases.map(\.moduleName), [
            "任務接收",
            "GPS定位",
            "SOS功能",
            "照片回報",
            "危險標記",
            "分區資訊",
            "任務回報",
            "離線模式",
            "語音回報",
            "安全管制",
            "LoRa整合",
            "高壓模式"
        ])
        XCTAssertEqual(phases.map(\.purpose), [
            "任務執行",
            "隊伍掌握",
            "人員安全",
            "現場資訊",
            "安全警示",
            "搜救定位",
            "指揮同步",
            "災後穩定",
            "高壓操作",
            "人員管理",
            "斷網運作",
            "高可靠性"
        ])
        XCTAssertEqual(TeamMemberPhaseCatalog.phase(id: .phase1).label, "TE Phase 1")
        XCTAssertEqual(TeamMemberPhaseCatalog.phase(id: .phase12).capability, "手套操作、大按鈕")
        XCTAssertEqual(TeamMemberPhaseCatalog.plannedPhases.map(\.id), [.phase11])
        XCTAssertEqual(TeamMemberPhaseCatalog.fieldPrinciplePhases.map(\.id), [.phase12])
    }

    func testTeamMemberCoreBackedPhasesMatchFeatureGates() {
        let controller = FieldAppController(
            appID: .teamMember,
            platform: .iPhone,
            deviceID: "IOS-TE-PHASE-TEST",
            displayName: "TE Phase Test",
            now: fixedDate
        )
        let coreBackedPhases = TeamMemberPhaseCatalog.coreBackedPhases

        XCTAssertEqual(controller.teamMemberPhases.map(\.id), TeamMemberPhaseID.allCases)
        XCTAssertEqual(coreBackedPhases.map(\.id), [.phase1, .phase2, .phase3, .phase4, .phase5, .phase6, .phase7, .phase8, .phase9, .phase10])
        XCTAssertEqual(controller.executableTeamMemberPhases.map(\.id), coreBackedPhases.map(\.id))
        for phase in coreBackedPhases {
            XCTAssertTrue(TeamMemberPhaseCatalog.isExecutableByTeamMember(phase), phase.label)
            for feature in phase.requiredFeatures {
                XCTAssertTrue(controller.canSeeFeature(feature), "\(phase.label) requires \(feature.rawValue)")
            }
        }
        XCTAssertFalse(TeamMemberPhaseCatalog.isExecutableByTeamMember(TeamMemberPhaseCatalog.phase(id: .phase11)))
        XCTAssertFalse(TeamMemberPhaseCatalog.isExecutableByTeamMember(TeamMemberPhaseCatalog.phase(id: .phase12)))
        XCTAssertEqual(FieldOperationalPrinciples.principle(id: "large-buttons")?.title, "大按鈕")
    }

    func testTeamLeaderAndTeamMemberShareFieldWorkflowCatalog() {
        let teamLeaderController = FieldAppController(
            appID: .teamLeader,
            platform: .iPhone,
            deviceID: "IOS-TL-PHASE-TEST",
            displayName: "TL Phase Test",
            now: fixedDate
        )
        let teamMemberController = FieldAppController(
            appID: .teamMember,
            platform: .iPhone,
            deviceID: "IOS-TE-PHASE-TEST",
            displayName: "TE Phase Test",
            now: fixedDate
        )

        XCTAssertEqual(TeamMemberPhaseCatalog.phases(for: .teamLeader).map(\.id), TeamMemberPhaseID.allCases)
        XCTAssertEqual(TeamMemberPhaseCatalog.phases(for: .teamMember).map(\.id), TeamMemberPhaseID.allCases)
        XCTAssertEqual(teamLeaderController.teamMemberPhases.map(\.id), teamMemberController.teamMemberPhases.map(\.id))
        XCTAssertEqual(teamLeaderController.executableTeamMemberPhases.map(\.id), TeamMemberPhaseCatalog.coreBackedPhases.map(\.id))
        XCTAssertEqual(teamMemberController.executableTeamMemberPhases.map(\.id), TeamMemberPhaseCatalog.coreBackedPhases.map(\.id))
    }

    func testTeamLeaderAndTeamMemberShareLaunchIdentityOptions() {
        let expectedCodes = ["TL-01", "TL-02", "TE-01", "TE-02"]
        let expectedLabels = ["TL-01 / 分隊長", "TL-02 / 副分隊長", "TE-01 / 搜索員", "TE-02 / 救援員"]

        XCTAssertEqual(FieldLaunchIdentityOption.options(for: .teamLeader).map(\.code), expectedCodes)
        XCTAssertEqual(FieldLaunchIdentityOption.options(for: .teamMember).map(\.code), expectedCodes)
        XCTAssertEqual(FieldLaunchIdentityOption.options(for: .teamLeader).map(\.displayLabel), expectedLabels)
        XCTAssertEqual(FieldLaunchIdentityOption.options(for: .teamMember).map(\.displayLabel), expectedLabels)
    }

    func testEMTMedicalPhaseCatalogMatchesRequestedRoadmap() {
        let phases = EMTMedicalPhaseCatalog.phases

        XCTAssertEqual(LinkGuardEMTMedicalVersion.appName, "LinkGuard-EMT")
        XCTAssertEqual(LinkGuardEMTMedicalVersion.editionName, "醫療版本")
        XCTAssertEqual(LinkGuardEMTMedicalVersion.targetUsers, ["EMT", "醫療後送人員", "醫療支援組"])
        XCTAssertEqual(LinkGuardEMTMedicalVersion.corePositioning, "醫療後送與傷患管理系統")
        XCTAssertEqual(phases.map(\.id), EMTMedicalPhaseID.allCases)
        XCTAssertEqual(phases.map(\.moduleName), [
            "傷患建立",
            "START檢傷",
            "生理監測",
            "傷患狀態更新",
            "後送管理",
            "醫療照片",
            "醫療語音紀錄",
            "離線模式",
            "多語翻譯",
            "醫療AI預警",
            "醫院資訊",
            "手錶整合"
        ])
        XCTAssertEqual(phases.map(\.capability), [
            "傷患資料",
            "紅黃綠黑分類",
            "心率血氧",
            "病況更新",
            "醫院派送",
            "傷勢照片",
            "語音輸入",
            "離線病歷",
            "外籍患者",
            "惡化預測",
            "可收治醫院",
            "Apple Watch等"
        ])
        XCTAssertEqual(phases.map(\.purpose), [
            "傷患管理",
            "醫療排序",
            "傷患監控",
            "醫療同步",
            "醫療調度",
            "醫療紀錄",
            "高壓輸入",
            "災後運作",
            "國際災援",
            "緊急優先",
            "後送決策",
            "生理感測"
        ])
        XCTAssertEqual(EMTMedicalPhaseCatalog.phase(id: .phase1).label, "EMT Phase 1")
        XCTAssertEqual(EMTMedicalPhaseCatalog.phase(id: .phase12).capability, "Apple Watch等")
        XCTAssertEqual(EMTMedicalPhaseCatalog.plannedPhases.map(\.id), [.phase10])
        XCTAssertEqual(EMTMedicalPhaseCatalog.deviceIntegrationPhases.map(\.id), [.phase12])
    }

    func testEMTMedicalCoreBackedPhasesMatchFeatureGates() {
        let controller = FieldAppController(
            appID: .emt,
            platform: .iPhone,
            deviceID: "IOS-EMT-PHASE-TEST",
            displayName: "EMT Phase Test",
            now: fixedDate
        )
        let coreBackedPhases = EMTMedicalPhaseCatalog.coreBackedPhases

        XCTAssertEqual(EMTMedicalPhaseCatalog.phases(for: .teamLeader), [])
        XCTAssertEqual(controller.emtMedicalPhases.map(\.id), EMTMedicalPhaseID.allCases)
        XCTAssertEqual(coreBackedPhases.map(\.id), [.phase1, .phase2, .phase3, .phase4, .phase5, .phase6, .phase7, .phase8, .phase9, .phase11])
        XCTAssertEqual(controller.executableEMTMedicalPhases.map(\.id), coreBackedPhases.map(\.id))
        for phase in coreBackedPhases {
            XCTAssertTrue(EMTMedicalPhaseCatalog.isExecutableByEMT(phase), phase.label)
            for feature in phase.requiredFeatures {
                XCTAssertTrue(controller.canSeeFeature(feature), "\(phase.label) requires \(feature.rawValue)")
            }
        }
        XCTAssertFalse(EMTMedicalPhaseCatalog.isExecutableByEMT(EMTMedicalPhaseCatalog.phase(id: .phase10)))
        XCTAssertFalse(EMTMedicalPhaseCatalog.isExecutableByEMT(EMTMedicalPhaseCatalog.phase(id: .phase12)))
    }

    func testFieldLaunchIdentityOptionsRemainDisplayOnly() {
        let emtOptions = FieldLaunchIdentityOption.options(for: .emtIPad)
        let selectedIdentity = emtOptions[1]
        let controller = FieldAppController(
            appID: .emtIPad,
            platform: .iPad,
            deviceID: "IPAD-EMT-IDENTITY-TEST",
            displayName: "EMT Identity Test",
            now: fixedDate
        )

        XCTAssertEqual(emtOptions.map(\.code), ["EMT-01", "EMT-02"])
        XCTAssertEqual(selectedIdentity.displayLabel, "EMT-02 / 救護員")
        XCTAssertEqual(controller.runtime.device.appID, .emtIPad)
        XCTAssertEqual(controller.profile.appID, .emtIPad)
        XCTAssertTrue(controller.canUseFeature(.patientCreation))
        XCTAssertTrue(controller.canUseFeature(.sosSending))
        XCTAssertEqual(FieldLaunchIdentityOption.options(for: .teamLeaderIPad).map(\.code), ["TL-01", "TL-02"])
        XCTAssertEqual(FieldLaunchIdentityOption.options(for: .sccIPad).map(\.code), ["SCC-01", "SCC-OPS", "SCC-SAFE"])
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

    func testOfflineSyncWaitsForRetryIntervalAfterFailure() async throws {
        let teamLeader = runtime(appID: .teamLeader)
        let store = FileBackedLocalOperationCacheStore(fileURL: try temporaryCacheURL())
        let task = FieldTask(
            id: "TASK-RETRY-1",
            incidentID: "INC-1",
            type: .search,
            status: .assigned,
            priority: .high,
            summary: "Retry interval task",
            createdAt: fixedDate
        )
        let envelope = try teamLeader.makeEnvelope(
            messageType: .taskUpsert,
            payload: task,
            createdAt: fixedDate,
            idempotencyKey: "retry-task-1"
        )
        var cache = LocalOperationCache(connectivity: .offline)
        cache.queue(envelope, at: fixedDate)
        _ = try store.save(cache, at: fixedDate)

        let failingCoordinator = OfflineSyncCoordinator(
            store: store,
            transport: FailingTransport(),
            device: teamLeader.device,
            policy: BackgroundSyncPolicy(batchLimit: 10, minimumRetryInterval: 30)
        )
        do {
            _ = try await failingCoordinator.flushPending(
                connectivity: .online,
                trigger: .connectivityRecovered,
                now: fixedDate.addingTimeInterval(10)
            )
            XCTFail("Expected transport failure")
        } catch TestTransportError.forcedFailure {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let waitingPlan = try failingCoordinator.plan(
            connectivity: .online,
            trigger: .backgroundRefresh,
            now: fixedDate.addingTimeInterval(20)
        )
        let waitingResult = try await failingCoordinator.flushPending(
            connectivity: .online,
            trigger: .backgroundRefresh,
            now: fixedDate.addingTimeInterval(20)
        )
        let reloaded = try store.load()

        XCTAssertFalse(waitingPlan.shouldAttemptSync)
        XCTAssertEqual(waitingPlan.pendingEnvelopeIDs, [])
        XCTAssertEqual(waitingPlan.reason, "waiting for retry interval")
        XCTAssertFalse(waitingResult.attempted)
        XCTAssertEqual(waitingResult.remainingPendingCount, 1)
        XCTAssertEqual(reloaded.outboundQueue.entries.first?.state, .failed)
        XCTAssertEqual(reloaded.outboundQueue.entries.first?.attempts, 1)
    }

    func testManualOfflineSyncRetryBypassesRetryInterval() async throws {
        let teamLeader = runtime(appID: .teamLeader)
        let store = FileBackedLocalOperationCacheStore(fileURL: try temporaryCacheURL())
        let task = FieldTask(
            id: "TASK-MANUAL-RETRY-1",
            incidentID: "INC-1",
            type: .search,
            status: .assigned,
            priority: .high,
            summary: "Manual retry task",
            createdAt: fixedDate
        )
        let envelope = try teamLeader.makeEnvelope(
            messageType: .taskUpsert,
            payload: task,
            createdAt: fixedDate,
            idempotencyKey: "manual-retry-task-1"
        )
        var cache = LocalOperationCache(connectivity: .offline)
        cache.queue(envelope, at: fixedDate)
        cache.markSending(envelope.id, at: fixedDate.addingTimeInterval(10))
        cache.markFailed(envelope.id, error: "offline", at: fixedDate.addingTimeInterval(10))
        _ = try store.save(cache, at: fixedDate.addingTimeInterval(10))

        let coordinator = OfflineSyncCoordinator(
            store: store,
            transport: AcceptingTransport(),
            device: teamLeader.device,
            policy: BackgroundSyncPolicy(batchLimit: 10, minimumRetryInterval: 60)
        )
        let result = try await coordinator.flushPending(
            connectivity: .degraded,
            trigger: .manualRetry,
            now: fixedDate.addingTimeInterval(20)
        )
        let reloaded = try store.load()

        XCTAssertTrue(result.attempted)
        XCTAssertEqual(result.deliveredEnvelopeIDs, [envelope.id])
        XCTAssertEqual(result.remainingPendingCount, 0)
        XCTAssertEqual(reloaded.pendingCount, 0)
        XCTAssertEqual(reloaded.lastSyncAt, fixedDate.addingTimeInterval(20))
    }

    func testOfflineSyncMarksMissingTransportReceiptAsFailed() async throws {
        let teamLeader = runtime(appID: .teamLeader)
        let store = FileBackedLocalOperationCacheStore(fileURL: try temporaryCacheURL())
        let task = FieldTask(
            id: "TASK-MISSING-RECEIPT-1",
            incidentID: "INC-1",
            type: .search,
            status: .assigned,
            priority: .high,
            summary: "Missing receipt task",
            createdAt: fixedDate
        )
        let envelope = try teamLeader.makeEnvelope(
            messageType: .taskUpsert,
            payload: task,
            createdAt: fixedDate,
            idempotencyKey: "missing-receipt-task-1"
        )
        var cache = LocalOperationCache(connectivity: .offline)
        cache.queue(envelope, at: fixedDate)
        _ = try store.save(cache, at: fixedDate)

        let coordinator = OfflineSyncCoordinator(store: store, transport: EmptyReceiptTransport(), device: teamLeader.device)
        let result = try await coordinator.flushPending(
            connectivity: .online,
            trigger: .connectivityRecovered,
            now: fixedDate.addingTimeInterval(30)
        )
        let reloaded = try store.load()

        XCTAssertTrue(result.attempted)
        XCTAssertEqual(result.deliveredEnvelopeIDs, [])
        XCTAssertEqual(result.failedEnvelopeIDs, [envelope.id])
        XCTAssertEqual(result.remainingPendingCount, 1)
        XCTAssertEqual(reloaded.outboundQueue.entries.first?.state, .failed)
        XCTAssertEqual(reloaded.outboundQueue.entries.first?.lastError, "missing transport receipt")
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

    func testAccountLoginSupportsIdentifierLookupAndAmbiguityGuard() throws {
        let sccAccount = UserAccount(
            id: "ACCOUNT-SCC-2",
            personID: "PERSON-SCC-2",
            displayName: "Sector Commander 2",
            callSign: "SCC-2",
            allowedAppIDs: [.scc],
            defaultPosition: .operationsSectionChief,
            credentialDigest: "digest-scc-2"
        )
        let duplicateCallSign = UserAccount(
            id: "ACCOUNT-SCC-3",
            personID: "PERSON-SCC-3",
            displayName: "Sector Commander 3",
            callSign: "SCC-2",
            allowedAppIDs: [.scc],
            defaultPosition: .operationsSectionChief,
            credentialDigest: "digest-scc-3"
        )
        var directory = AccountDirectory(accounts: [sccAccount])
        let sccDevice = DeviceIdentity(id: "DEVICE-SCC-LOGIN", appID: .scc, platform: .mac, displayName: "SCC Console")

        let byPersonSession = try directory.login(
            identifier: sccAccount.personID.rawValue,
            credentialDigest: "digest-scc-2",
            device: sccDevice,
            issuedAt: fixedDate,
            sessionID: "SESSION-BY-PERSON"
        )
        XCTAssertEqual(byPersonSession.accountID, sccAccount.id)

        let byCallSignSession = try directory.login(
            identifier: "scc-2",
            credentialDigest: "digest-scc-2",
            device: sccDevice,
            issuedAt: fixedDate,
            sessionID: "SESSION-BY-CALLSIGN"
        )
        XCTAssertEqual(byCallSignSession.accountID, sccAccount.id)

        directory.upsert(duplicateCallSign)
        XCTAssertThrowsError(
            try directory.account(for: "SCC-2")
        ) { error in
            XCTAssertEqual(error as? AccountAccessError, .ambiguousIdentifier("SCC-2"))
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
            initialGPSFix: fieldGPSFix(),
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

    func testFieldTLQueuesFormalUSARTeamCapabilityReport() throws {
        var controller = FieldAppController(
            appID: .teamLeader,
            platform: .iPhone,
            deviceID: "IOS-TL-USAR-PROFILE",
            displayName: "TL USAR Profile",
            now: fixedDate
        )

        let envelope = try controller.queueTeamCapabilityReport(now: fixedDate.addingTimeInterval(1))
        let report = try envelope.decodePayload(USARTeamCapabilityReport.self)

        XCTAssertEqual(envelope.messageType, .teamCapabilityReportUpsert)
        XCTAssertEqual(report.team.teamCode, "TEAM-ALPHA")
        XCTAssertEqual(report.team.country, "TWN")
        XCTAssertEqual(report.team.responseType, .medium)
        XCTAssertEqual(report.team.classificationStatus, .classified)
        XCTAssertTrue(report.team.hasTechnicalSearch)
        XCTAssertTrue(report.team.hasRescueCapability)
        XCTAssertTrue(report.supportNeeds.needsGroundTransport)
        XCTAssertEqual(controller.missionSummary.teamCapabilityReportCount, 1)
        XCTAssertEqual(controller.runtime.snapshot.teamCapabilityReports[report.id]?.contacts.teamContactNameOrRole, "TL USAR Profile")
        XCTAssertEqual(controller.pendingEnvelopeCount, 1)

        var scc = runtime(appID: .scc)
        try scc.receive(envelope)
        XCTAssertEqual(scc.snapshot.teamCapabilityReports[report.id]?.personnelSummary, "出隊 8 · 搜救犬 1")
        XCTAssertEqual(scc.snapshot.auditEvents.last?.targetType, "teamCapabilityReport")
    }

    func testFieldControllerStartsWithoutSyntheticGPSFix() throws {
        var controller = FieldAppController(
            appID: .teamMember,
            platform: .iPhone,
            deviceID: "IOS-TE-NO-GPS-TEST",
            displayName: "TE No GPS Test",
            now: fixedDate
        )

        XCTAssertNil(controller.latestGPSFix)
        XCTAssertThrowsError(try controller.queueGPSReport(now: fixedDate.addingTimeInterval(1)))
        XCTAssertThrowsError(try controller.queuePhotoReport(photoAttachmentID: "ATTACH-NO-GPS", caption: nil, checksum: nil, now: fixedDate.addingTimeInterval(2)))
        XCTAssertThrowsError(try controller.queueSOS(dangerType: .trapped, note: nil, now: fixedDate.addingTimeInterval(3)))

        controller.recordGPSFix(fieldGPSFix(capturedAt: fixedDate.addingTimeInterval(4)))
        let gps = try controller.queueGPSReport(now: fixedDate.addingTimeInterval(5))
        let report = try gps.decodePayload(PersonnelStatusReport.self)
        let location = try XCTUnwrap(report.location)
        XCTAssertEqual(location.latitude, 25.033, accuracy: 0.0001)
        XCTAssertEqual(location.longitude, 121.565, accuracy: 0.0001)
    }

    func testFieldControllerPersistsAndRestoresQueuedOutbox() throws {
        let store = FileBackedLocalOperationCacheStore(fileURL: try temporaryCacheURL())
        var controller = FieldAppController(
            appID: .teamMember,
            platform: .iPhone,
            deviceID: "IOS-TE-PERSIST-TEST",
            displayName: "TE Persist Test",
            initialGPSFix: fieldGPSFix(),
            localCacheStore: store,
            now: fixedDate
        )

        let envelope = try controller.queueSOS(
            dangerType: .trapped,
            note: "Persist me",
            now: fixedDate.addingTimeInterval(1)
        )

        XCTAssertNil(controller.lastPersistenceError)
        XCTAssertEqual(controller.pendingEnvelopeCount, 1)
        let savedCache = try store.load()
        XCTAssertEqual(savedCache.pendingCount, 1)
        XCTAssertEqual(savedCache.outboundQueue.entries.first?.envelope.id, envelope.id)

        let restoredController = FieldAppController(
            appID: .teamMember,
            platform: .iPhone,
            deviceID: "IOS-TE-PERSIST-TEST",
            displayName: "TE Persist Test",
            localCacheStore: store,
            now: fixedDate.addingTimeInterval(2)
        )

        XCTAssertNil(restoredController.lastPersistenceError)
        XCTAssertEqual(restoredController.pendingEnvelopeCount, 1)
        XCTAssertEqual(restoredController.runtime.pendingOutboundCount, 1)
        XCTAssertEqual(restoredController.queuedSummaries.first?.id, envelope.id)
        XCTAssertEqual(restoredController.queuedSummaries.first?.messageType, .sosReportUpsert)
    }

    func testFieldControllerManualSyncFlushesPersistedOutbox() async throws {
        let store = FileBackedLocalOperationCacheStore(fileURL: try temporaryCacheURL())
        var controller = FieldAppController(
            appID: .teamMember,
            platform: .iPhone,
            deviceID: "IOS-TE-SYNC-TEST",
            displayName: "TE Sync Test",
            initialGPSFix: fieldGPSFix(),
            localCacheStore: store,
            now: fixedDate
        )

        let envelope = try controller.queueSOS(
            dangerType: .trapped,
            note: "Sync me",
            now: fixedDate.addingTimeInterval(1)
        )

        let result = try await controller.syncQueuedEnvelopes(
            transport: AcceptingTransport(),
            now: fixedDate.addingTimeInterval(2)
        )

        XCTAssertTrue(result.attempted)
        XCTAssertEqual(result.deliveredEnvelopeIDs, [envelope.id])
        XCTAssertEqual(result.failedEnvelopeIDs, [])
        XCTAssertEqual(result.remainingPendingCount, 0)
        XCTAssertEqual(controller.pendingEnvelopeCount, 0)
        XCTAssertEqual(controller.runtime.pendingOutboundCount, 0)
        XCTAssertEqual(controller.queuedSummaries, [])
        XCTAssertEqual(controller.lastSyncResult?.deliveredEnvelopeIDs, [envelope.id])
        XCTAssertNil(controller.lastSyncError)
        XCTAssertEqual(try store.load().pendingCount, 0)
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
        let emtHospital = try emt.queueHospitalCapacityUpdate(emergencyCapacity: 8, traumaCapacity: 3, burnCapacity: 1, pediatricCapacity: 2, now: fixedDate.addingTimeInterval(5))
        let hospital = try emtHospital.decodePayload(HospitalCapacity.self)

        XCTAssertEqual([tlPatient.messageType, tlStart.messageType, tlStatus.messageType, emtEvac.messageType, emtHospital.messageType], [
            .patientUpsert,
            .patientUpsert,
            .patientUpsert,
            .evacuationRequestUpsert,
            .hospitalCapacityUpsert
        ])
        XCTAssertEqual(hospital.emergencyCapacity, 8)
        XCTAssertEqual(hospital.traumaCapacity, 3)
        XCTAssertThrowsError(try teamLeader.queueEvacuationRequest(patientID: "PATIENT-A023", destinationHospitalID: nil, now: fixedDate.addingTimeInterval(6)))
        XCTAssertTrue(emt.canUseFeature(.patientCreation))
        XCTAssertTrue(emt.canUseFeature(.hospitalCapacityView))
        XCTAssertTrue(emt.canUseFeature(.voiceTranslation))
        XCTAssertFalse(emt.canUseFeature(.radioMonitoring))
        XCTAssertFalse(emt.canUseFeature(.hazardZoneManagement))
        XCTAssertThrowsError(try emt.queueSafetyZone(now: fixedDate.addingTimeInterval(7)))
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
            initialGPSFix: fieldGPSFix(),
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
            initialGPSFix: fieldGPSFix(),
            now: fixedDate
        )

        let gps = try controller.queueGPSReport(now: fixedDate.addingTimeInterval(1))
        let photo = try controller.queuePhotoReport(photoAttachmentID: "ATTACH-VO-1", caption: "VO photo", checksum: nil, now: fixedDate.addingTimeInterval(2))
        let disaster = try controller.queueDisasterReport(kind: .collapse, summary: "Collapsed wall", now: fixedDate.addingTimeInterval(3))
        let sos = try controller.queueSOS(dangerType: .trapped, note: "Lost", now: fixedDate.addingTimeInterval(4))
        let chat = try controller.queueGroupChat(body: "VO update", now: fixedDate.addingTimeInterval(5))
        let voice = try controller.queueVoiceReport(transcript: "VO voice", durationSeconds: 4, now: fixedDate.addingTimeInterval(6))
        let point = try controller.queueMapMarker(featureType: .assemblyPoint, geometryType: .point, title: "VO point", now: fixedDate.addingTimeInterval(7))

        XCTAssertEqual([gps.messageType, photo.messageType, disaster.messageType, sos.messageType, chat.messageType, voice.messageType, point.messageType], [
            .personnelStatusUpsert,
            .photoReportUpsert,
            .disasterReportUpsert,
            .sosReportUpsert,
            .groupChatMessageAppend,
            .voiceReportAppend,
            .mapFeatureUpsert
        ])
        XCTAssertEqual(controller.missionSummary.disasterReportCount, 1)
        XCTAssertEqual(controller.pendingEnvelopeCount, 7)
        XCTAssertEqual(controller.accessLevel(for: .gpsTracking), .limited)
        XCTAssertTrue(controller.canUseFeature(.gpsTracking))
        XCTAssertFalse(controller.canUseFeature(.personnelOverview))
        XCTAssertFalse(controller.canUseFeature(.teamCapabilityOverview))
        XCTAssertFalse(controller.canUseFeature(.teamMemberRealtimeLocation))
        XCTAssertFalse(controller.canUseFeature(.teamLeaderRealtimeLocation))
        XCTAssertFalse(controller.canUseFeature(.emtLocationManagement))
        XCTAssertFalse(controller.canUseFeature(.radioMonitoring))
        XCTAssertThrowsError(try controller.queuePatientUpload(displayCode: "A023", triageCategory: .red, injurySummary: "Leg bleed", now: fixedDate.addingTimeInterval(8)))
        XCTAssertThrowsError(try controller.queueMapMarker(featureType: .evacuationRoute, geometryType: .polyline, title: "VO line", now: fixedDate.addingTimeInterval(9)))
        XCTAssertThrowsError(try controller.queueMapMarker(featureType: .hazardPolygon, geometryType: .polygon, title: "VO area", now: fixedDate.addingTimeInterval(10)))
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

    func testVolunteerDisasterReportFlowsThroughFieldReportsChain() throws {
        let volunteer = runtime(appID: .volunteer)
        let hub = InMemoryTransportHub(runtimes: allAppRuntimes())
        let report = DisasterReport(
            id: "DISASTER-VO-1",
            incidentID: "INC-1",
            reporterDeviceID: volunteer.device.id,
            reporterAppID: .volunteer,
            kind: .fire,
            location: GeoCoordinate(latitude: 25.033, longitude: 121.565, accuracyMeters: 10),
            severity: .high,
            summary: "Smoke from collapsed storefront",
            createdAt: fixedDate
        )

        let receipts = try hub.send(
            messageType: .disasterReportUpsert,
            payload: report,
            from: volunteer.device.id,
            createdAt: fixedDate,
            idempotencyKey: "vo-disaster-1"
        )
        let recipientApps = Set(receipts.map(\.recipientAppID))

        XCTAssertTrue(recipientApps.isSuperset(of: [.ucc, .scc, .sccIPad, .teamLeader, .teamLeaderIPad, .teamMember, .volunteer]))
        XCTAssertFalse(recipientApps.contains(.emt))
        XCTAssertFalse(recipientApps.contains(.emtIPad))
        XCTAssertEqual(hub.runtime(for: "DEVICE-LinkGuard-SCC")?.snapshot.disasterReports["DISASTER-VO-1"]?.kind, .fire)
        let sccAudit = hub.runtime(for: "DEVICE-LinkGuard-SCC")?.snapshot.auditEvents.last
        XCTAssertEqual(sccAudit?.targetType, "disasterReport")
        XCTAssertEqual(sccAudit?.action, .submitReport)
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
        let teamReport = USARTeamCapabilityReport(
            id: "USAR-MAC-PROFILE",
            incidentID: "INC-1",
            reporterDeviceID: "DEVICE-TL",
            reporterName: "TL Profile",
            team: USARTeamInformationSection(
                teamCode: "TW-TL-01",
                country: "TWN",
                teamName: "Mac Visible USAR Team",
                totalMembers: 12,
                searchDogCount: 2,
                responseType: .heavy,
                classificationStatus: .classified
            ),
            supportNeeds: USARTeamSupportNeedsSection(needsGroundTransport: true, equipmentWeightTons: 4.5),
            contacts: USARTeamContactsSection(teamContactNameOrRole: "TL Profile"),
            createdAt: fixedDate.addingTimeInterval(1)
        )
        let teamEnvelope = try SyncEnvelope.make(
            messageType: .teamCapabilityReportUpsert,
            sourceAppID: .teamLeader,
            sourceDeviceID: "DEVICE-TL",
            priority: .high,
            createdAt: fixedDate.addingTimeInterval(1),
            idempotencyKey: "mac-team-profile",
            payload: teamReport
        )
        try snapshot.apply(teamEnvelope)

        let state = try MacSystemUIFactory.makeState(appID: .ucc, deviceID: "DEVICE-UCC", snapshot: snapshot)
        let sections = state.navigationItems.map(\.section)

        XCTAssertEqual(state.runtime.device.platform, .mac)
        XCTAssertEqual(state.runtime.blueprint.appID, .ucc)
        XCTAssertTrue(sections.contains(.finance))
        XCTAssertTrue(sections.contains(.afterActionReview))
        XCTAssertEqual(state.metrics.first { $0.id == "alerts" }?.value, "1")
        XCTAssertEqual(state.metrics.first { $0.id == "team-capability" }?.value, "1")
        XCTAssertEqual(state.teamCapabilityReports.first?.team.teamName, "Mac Visible USAR Team")
        XCTAssertTrue(state.quickActions.contains { $0.id == "issue-command" && $0.isEnabled })
        XCTAssertTrue(state.inheritedModules.first { $0.section == .command }?.inheritedFrom.contains("TransportTopology") == true)
        XCTAssertTrue(state.transportRoutes.contains { $0.messageType == .teamCapabilityReportUpsert && $0.receives })
        XCTAssertEqual(state.settingsItems.first { $0.key == "version" }?.value, LinkGuardVersionInfo.current.version.stringValue)
        XCTAssertEqual(state.settingsItems.first { $0.key == "build" }?.value, String(LinkGuardVersionInfo.current.buildNumber))

        let architecture = try XCTUnwrap(state.uccICSArchitecture)
        XCTAssertEqual(architecture.commandAuthority, .global)
        XCTAssertEqual(architecture.lanes.map(\.section), [.command, .operations, .planning, .logistics, .finance, .afterActionReview])
        XCTAssertTrue(architecture.lanes.first { $0.section == .command }?.primaryPositions.contains(.incidentCommander) == true)
        XCTAssertTrue(architecture.lanes.first { $0.section == .operations }?.authorityBoundary.contains("SCC/TL") == true)
        XCTAssertTrue(architecture.boundaryRules.contains { $0.id == "scc-tactical-authority" })
    }

    func testMacSCCUIUsesSCCScopeInsteadOfUCCMirror() throws {
        let state = try MacSystemUIFactory.makeState(appID: .scc, deviceID: "DEVICE-SCC")
        let sections = state.navigationItems.map(\.section)

        XCTAssertEqual(state.runtime.profile.displayName, "SCC")
        XCTAssertTrue(sections.contains(.command))
        XCTAssertTrue(sections.contains(.operations))
        XCTAssertFalse(sections.contains(.finance))
        XCTAssertFalse(state.quickActions.contains { $0.id == "finance" })
        XCTAssertNil(state.uccICSArchitecture)
        XCTAssertEqual(LinkGuardFeatureAccessMatrix.accessLevel(for: .scc, feature: .medicalEvacuation), .limited)
        XCTAssertTrue(state.transportRoutes.contains { $0.messageType == .evacuationRequestUpsert && $0.receives && $0.canSend })
    }

    func testMacSCCStateReceivesFieldSOSSyncBatch() throws {
        var fieldController = FieldAppController(
            appID: .teamMember,
            platform: .iPhone,
            deviceID: "IOS-TE-SOS-SYNC",
            displayName: "TE SOS Sync",
            initialGPSFix: fieldGPSFix(),
            now: fixedDate
        )
        let envelope = try fieldController.queueSOS(
            dangerType: .trapped,
            note: "Need extraction",
            now: fixedDate.addingTimeInterval(1)
        )
        let report = try envelope.decodePayload(SOSReport.self)
        let batch = SyncTransportBatch(
            device: fieldController.runtime.device,
            generatedAt: fixedDate.addingTimeInterval(2),
            envelopes: [envelope]
        )
        var state = try MacSystemUIFactory.makeState(appID: .scc, deviceID: "DEVICE-SCC")

        let response = state.receive(batch, receivedAt: fixedDate.addingTimeInterval(3))

        XCTAssertEqual(response.receipts, [
            SyncTransportReceipt(envelopeID: envelope.id, accepted: true, receivedAt: fixedDate.addingTimeInterval(3))
        ])
        XCTAssertEqual(state.runtime.snapshot.sosReports.count, 1)
        XCTAssertEqual(state.sosAlertItems.first?.id, report.id)
        XCTAssertEqual(state.sosAlertItems.first?.reporterAppID, .teamMember)
        XCTAssertEqual(state.sosAlertItems.first?.dangerType, .trapped)
        XCTAssertEqual(state.sosAlertItems.first?.note, "Need extraction")
        XCTAssertEqual(state.metrics.first { $0.id == "alerts" }?.value, "1")
        XCTAssertEqual(state.inheritedModules.first { $0.section == .command }?.recordCount, 1)
    }

    func testMacUIRejectsNonMacApps() throws {
        XCTAssertThrowsError(try MacSystemUIFactory.makeState(appID: .teamLeader, deviceID: "DEVICE-TL")) { error in
            XCTAssertEqual(error as? MacSystemUIError, .unsupportedApp(.teamLeader))
        }
    }

    func testMacIdentitySelectionDisplaysSessionWithoutChangingFeatures() throws {
        let snapshot = OperationSnapshot()
        let baseState = try MacSystemUIFactory.makeState(
            appID: .ucc,
            deviceID: "DEVICE-UCC-ID",
            displayName: "LinkGuard UCC Console",
            snapshot: snapshot
        )

        let result = try MacSystemUIFactory.selectIdentityAndMakeState(
            directory: .demo,
            identifier: "CS-01",
            appID: .ucc,
            deviceID: "DEVICE-UCC-ID",
            displayName: "LinkGuard UCC Console",
            selectedAt: fixedDate,
            sessionID: "IDENTITY-CS-01",
            snapshot: snapshot,
            versionInfo: baseState.settingsInfo.versionInfo
        )

        XCTAssertEqual(result.session.id, "IDENTITY-CS-01")
        XCTAssertEqual(result.state.loginSession?.displayName, "指揮幕僚 (Command Staff)")
        XCTAssertEqual(result.state.quickActions.map { "\($0.id):\($0.isEnabled)" }, baseState.quickActions.map { "\($0.id):\($0.isEnabled)" })
        XCTAssertEqual(result.state.transportRoutes.map { "\($0.id):\($0.canSend)" }, baseState.transportRoutes.map { "\($0.id):\($0.canSend)" })
        XCTAssertEqual(
            result.state.inheritedModules.map { "\($0.section.rawValue):\($0.enabledPermissions.map(\.rawValue).sorted().joined(separator: ","))" },
            baseState.inheritedModules.map { "\($0.section.rawValue):\($0.enabledPermissions.map(\.rawValue).sorted().joined(separator: ","))" }
        )
    }

    func testMacAuthenticatedStateAppliesSessionPermissionConstraints() throws {
        let account = UserAccount(
            id: "ACCOUNT-UCC-AUTH",
            personID: "PERSON-UCC-AUTH",
            displayName: "UCC Commander",
            callSign: "UCC-COMMAND",
            allowedAppIDs: [.ucc],
            defaultPosition: .incidentCommander,
            credentialDigest: "digest-ucc",
            revokedPermissions: [.issueCommand]
        )
        var directory = AccountDirectory(accounts: [account])

        let result = try MacSystemUIFactory.loginAndMakeState(
            directory: &directory,
            identifier: "ucc-command",
            credentialDigest: "digest-ucc",
            appID: .ucc,
            deviceID: "DEVICE-UCC-AUTH",
            issuedAt: fixedDate,
            sessionID: "SESSION-UCC-AUTH"
        )

        XCTAssertEqual(result.session.id, "SESSION-UCC-AUTH")
        XCTAssertEqual(result.state.loginSession?.id, "SESSION-UCC-AUTH")
        XCTAssertFalse(result.session.permissions.contains(.issueCommand))
        XCTAssertTrue(result.session.permissions.contains(.sendSOS))

        let issueCommandAction = try XCTUnwrap(result.state.quickActions.first { $0.id == "issue-command" })
        XCTAssertFalse(issueCommandAction.isEnabled)

        let sendSOSAction = try XCTUnwrap(result.state.quickActions.first { $0.id == "send-sos" })
        XCTAssertTrue(sendSOSAction.isEnabled)

        let commandRoute = try XCTUnwrap(result.state.transportRoutes.first { $0.messageType == .commandUpsert })
        XCTAssertFalse(commandRoute.canSend)

        let sosRoute = try XCTUnwrap(result.state.transportRoutes.first { $0.messageType == .sosReportUpsert })
        XCTAssertTrue(sosRoute.canSend)
    }

    // MARK: - Map System Types Tests

    func testMapPointTypesComplete() {
        let pointTypes = MapPointType.allCases
        let expectedCount = 8
        XCTAssertEqual(pointTypes.count, expectedCount, "地圖點類型應有 \(expectedCount) 種")
        
        // 驗證所有必須的點類型都存在
        XCTAssertTrue(pointTypes.contains(.sos))
        XCTAssertTrue(pointTypes.contains(.victim))
        XCTAssertTrue(pointTypes.contains(.survivor))
        XCTAssertTrue(pointTypes.contains(.rescueTeamMember))
        XCTAssertTrue(pointTypes.contains(.hazardPoint))
        XCTAssertTrue(pointTypes.contains(.assemblyPoint))
        XCTAssertTrue(pointTypes.contains(.medicalStation))
        XCTAssertTrue(pointTypes.contains(.commandPost))
        
        // 驗證每個點類型都有顯示名稱和顏色
        for pointType in pointTypes {
            XCTAssertFalse(pointType.displayName.isEmpty, "\(pointType) 應有顯示名稱")
            XCTAssertFalse(pointType.systemColor.isEmpty, "\(pointType) 應有系統色碼")
        }
    }

    func testMapLineTypesComplete() {
        let lineTypes = MapLineType.allCases
        let expectedCount = 6
        XCTAssertEqual(lineTypes.count, expectedCount, "地圖線類型應有 \(expectedCount) 種")
        
        // 驗證所有必須的線類型都存在
        XCTAssertTrue(lineTypes.contains(.evacuationRoute))
        XCTAssertTrue(lineTypes.contains(.hazardousRoute))
        XCTAssertTrue(lineTypes.contains(.searchPath))
        XCTAssertTrue(lineTypes.contains(.supplyRoute))
        XCTAssertTrue(lineTypes.contains(.cordonLine))
        XCTAssertTrue(lineTypes.contains(.passageway))
        
        // 驗證每個線類型都有顯示名稱和顏色
        for lineType in lineTypes {
            XCTAssertFalse(lineType.displayName.isEmpty, "\(lineType) 應有顯示名稱")
            XCTAssertFalse(lineType.systemColor.isEmpty, "\(lineType) 應有系統色碼")
        }
    }

    func testMapPolygonTypesComplete() {
        let polygonTypes = MapPolygonType.allCases
        let expectedCount = 7
        XCTAssertEqual(polygonTypes.count, expectedCount, "地圖面類型應有 \(expectedCount) 種")
        
        // 驗證所有必須的面類型都存在
        XCTAssertTrue(polygonTypes.contains(.collapsedArea))
        XCTAssertTrue(polygonTypes.contains(.searchArea))
        XCTAssertTrue(polygonTypes.contains(.subzone))
        XCTAssertTrue(polygonTypes.contains(.hazardousZone))
        XCTAssertTrue(polygonTypes.contains(.cleanedArea))
        XCTAssertTrue(polygonTypes.contains(.fireZone))
        XCTAssertTrue(polygonTypes.contains(.chemicalHazard))
        
        // 驗證每個面類型都有顯示名稱和顏色
        for polygonType in polygonTypes {
            XCTAssertFalse(polygonType.displayName.isEmpty, "\(polygonType) 應有顯示名稱")
            XCTAssertFalse(polygonType.systemColor.isEmpty, "\(polygonType) 應有系統色碼")
        }
    }

    func testICSectionSystemComplete() {
        let sections = ICSMapArea.allCases
        XCTAssertEqual(sections.count, 6, "ICS 分區應有 6 個分區（A/B/C/D1/D2/D3）")
        
        // 驗證主區
        XCTAssertTrue(sections.contains(.sectionA))
        XCTAssertTrue(sections.contains(.sectionB))
        XCTAssertTrue(sections.contains(.sectionC))
        
        // 驗證子區
        XCTAssertTrue(sections.contains(.sectionD1))
        XCTAssertTrue(sections.contains(.sectionD2))
        XCTAssertTrue(sections.contains(.sectionD3))
        
        // 驗證主區有子區
        XCTAssertEqual(ICSMapArea.sectionA.subsections.count, 3)
        XCTAssertTrue(ICSMapArea.sectionA.subsections.contains(.sectionD1))
        XCTAssertTrue(ICSMapArea.sectionA.subsections.contains(.sectionD2))
        XCTAssertTrue(ICSMapArea.sectionA.subsections.contains(.sectionD3))
        
        // 驗證子區無子區
        XCTAssertEqual(ICSMapArea.sectionD1.subsections.count, 0)
    }

    func testSearchStateComplete() {
        let states = SearchState.allCases
        let expectedCount = 6
        XCTAssertEqual(states.count, expectedCount, "搜救狀態應有 \(expectedCount) 種")
        
        // 驗證所有必須的狀態都存在
        XCTAssertTrue(states.contains(.unconfirmed))
        XCTAssertTrue(states.contains(.searching))
        XCTAssertTrue(states.contains(.cleared))
        XCTAssertTrue(states.contains(.highRisk))
        XCTAssertTrue(states.contains(.forbidden))
        XCTAssertTrue(states.contains(.secondSearch))
        
        // 驗證每個狀態都有顯示名稱和顏色
        for state in states {
            XCTAssertFalse(state.displayName.isEmpty, "\(state) 應有顯示名稱")
            XCTAssertFalse(state.systemColor.isEmpty, "\(state) 應有系統色碼")
        }
    }

    func testMapCoreFunctionsCatalog() {
        let functions = MapCoreFunction.allCases
        let expectedCount = 12
        XCTAssertEqual(functions.count, expectedCount, "地圖核心功能應有 \(expectedCount) 項")
        
        // 驗證所有必須的功能都存在
        XCTAssertTrue(functions.contains(.gpsPerson))
        XCTAssertTrue(functions.contains(.sectionManagement))
        XCTAssertTrue(functions.contains(.markupSystem))
        XCTAssertTrue(functions.contains(.searchState))
        XCTAssertTrue(functions.contains(.hazardZone))
        XCTAssertTrue(functions.contains(.victimLocation))
        XCTAssertTrue(functions.contains(.sosAlert))
        XCTAssertTrue(functions.contains(.personTracking))
        XCTAssertTrue(functions.contains(.taskLayer))
        XCTAssertTrue(functions.contains(.photoIntegration))
        XCTAssertTrue(functions.contains(.offlineMap))
        XCTAssertTrue(functions.contains(.aiAnalysis))
        
        // 驗證每個功能都有顯示名稱和用途
        for function in functions {
            XCTAssertFalse(function.displayName.isEmpty, "\(function) 應有顯示名稱")
            XCTAssertFalse(function.purpose.isEmpty, "\(function) 應有用途說明")
        }
    }

    func testMapSystemDesignPrinciplesComplete() {
        // 驗證必要功能清單
        XCTAssertEqual(MapSystemDesignPrinciples.requiredFeatures.count, 10, "應有 10 項必要功能")
        XCTAssertTrue(MapSystemDesignPrinciples.requiredFeatures.contains("大按鈕"))
        XCTAssertTrue(MapSystemDesignPrinciples.requiredFeatures.contains("少層級"))
        XCTAssertTrue(MapSystemDesignPrinciples.requiredFeatures.contains("自動儲存"))
        XCTAssertTrue(MapSystemDesignPrinciples.requiredFeatures.contains("一鍵SOS"))
        XCTAssertTrue(MapSystemDesignPrinciples.requiredFeatures.contains("黑夜模式"))
        
        // 驗證推薦技術棧
        XCTAssertEqual(MapSystemDesignPrinciples.recommendedTechStack.count, 8, "應有 8 項推薦技術")
        XCTAssertEqual(MapSystemDesignPrinciples.recommendedTechStack["地圖引擎"], "Mapbox")
        XCTAssertEqual(MapSystemDesignPrinciples.recommendedTechStack["離線地圖"], "MBTiles")
        XCTAssertEqual(MapSystemDesignPrinciples.recommendedTechStack["GPS"], "CoreLocation")
        
        // 驗證頁面層級
        XCTAssertEqual(MapSystemDesignPrinciples.pageHierarchy.count, 4)
        XCTAssertEqual(MapSystemDesignPrinciples.pageHierarchy[0], "1. 地圖")
    }

    func testMapMarkupFeatureStructure() {
        // 測試點標記
        let coordinate = MapCoordinate(latitude: 25.0, longitude: 121.0)
        let pointGeometry = MapMarkupFeature.MarkupGeometry.point(.sos, 25.0, 121.0)
        let pointFeature = MapMarkupFeature(
            incidentID: LinkGuardID("INC001"),
            sectionID: .sectionA,
            geometry: pointGeometry,
            searchState: .unconfirmed,
            title: "測試 SOS",
            createdBy: LinkGuardID("USER001")
        )
        
        XCTAssertEqual(pointFeature.title, "測試 SOS")
        XCTAssertEqual(pointFeature.sectionID, .sectionA)
        XCTAssertEqual(pointFeature.searchState, .unconfirmed)
        
        // 測試線標記
        let lineGeometry = MapMarkupFeature.MarkupGeometry.line(
            .evacuationRoute,
            [coordinate, MapCoordinate(latitude: 25.1, longitude: 121.1)]
        )
        let lineFeature = MapMarkupFeature(
            incidentID: LinkGuardID("INC001"),
            geometry: lineGeometry,
            title: "撤離路線",
            createdBy: LinkGuardID("USER001")
        )
        
        XCTAssertEqual(lineFeature.title, "撤離路線")
        
        // 測試面標記
        let polygonGeometry = MapMarkupFeature.MarkupGeometry.polygon(
            .collapsedArea,
            [
                coordinate,
                MapCoordinate(latitude: 25.1, longitude: 121.0),
                MapCoordinate(latitude: 25.1, longitude: 121.1),
                MapCoordinate(latitude: 25.0, longitude: 121.1)
            ]
        )
        let polygonFeature = MapMarkupFeature(
            incidentID: LinkGuardID("INC001"),
            geometry: polygonGeometry,
            title: "倒塌區",
            createdBy: LinkGuardID("USER001")
        )
        
        XCTAssertEqual(polygonFeature.title, "倒塌區")
    }

    func testPersonnelSafetyMarkerTracking() {
        let location = MapCoordinate(latitude: 25.0, longitude: 121.0)
        let marker = PersonnelSafetyMarker(
            memberID: LinkGuardID("MEMBER001"),
            currentLocation: location,
            status: .active,
            deviceBattery: 75.0,
            inDangerZone: false,
            sosTriggered: false
        )
        
        XCTAssertEqual(marker.status, .active)
        XCTAssertEqual(marker.deviceBattery, 75.0)
        XCTAssertFalse(marker.inDangerZone)
        XCTAssertFalse(marker.sosTriggered)
        
        // 測試 SOS 觸發
        let sosMarker = PersonnelSafetyMarker(
            memberID: LinkGuardID("MEMBER002"),
            currentLocation: location,
            status: .sos,
            sosTriggered: true
        )
        
        XCTAssertTrue(sosMarker.sosTriggered)
        XCTAssertEqual(sosMarker.status, .sos)
    }

    func testOfflineMapCacheManagement() {
        let bounds = MapBounds(minLat: 25.0, minLon: 121.0, maxLat: 25.5, maxLon: 121.5)
        let cache = OfflineMapCache(
            tileRegionID: "taipei-region",
            bounds: bounds,
            minZoom: 10,
            maxZoom: 18,
            cacheSize: 1024 * 1024 * 256
        )
        
        XCTAssertEqual(cache.tileRegionID, "taipei-region")
        XCTAssertEqual(cache.minZoom, 10)
        XCTAssertEqual(cache.maxZoom, 18)
        XCTAssertEqual(cache.cacheSize, 268435456) // 256 MB
        XCTAssertTrue(cache.isSynced)
    }
}
