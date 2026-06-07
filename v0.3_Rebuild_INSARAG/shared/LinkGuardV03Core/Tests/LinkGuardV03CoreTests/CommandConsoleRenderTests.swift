#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import LinkGuardV03Core
@testable import LinkGuardV03MacUI

/// Proves the v0.3 command console actually renders: seeds a realistic two-incident
/// scenario, then renders EVERY UCC (12) and SCC (22) module to a PNG via
/// ImageRenderer. Rendering forces each view's `body` to evaluate, so a trap in any
/// module fails the test. PNGs are written to /tmp/console_render for inspection.
final class CommandConsoleRenderTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_717_600_000)
    private let outDir = "/tmp/console_render"

    @MainActor
    func testRenderAllUCCModules() throws {
        let state = try seededState(appID: .ucc)
        let count = try renderModules(CommandConsoleCatalog.uccModules, state: state)
        XCTAssertEqual(count, 12, "All 12 UCC modules must render")
        renderFullConsole(state, name: "UCC-console")
    }

    @MainActor
    func testRenderAllSCCModules() throws {
        let state = try seededState(appID: .scc)
        let count = try renderModules(CommandConsoleCatalog.sccModules, state: state)
        XCTAssertEqual(count, 22, "All 22 SCC modules must render")
        renderFullConsole(state, name: "SCC-console")
    }

    // MARK: Rendering

    @MainActor
    private func renderModules(_ modules: [CommandConsoleModule], state: MacSystemUIState) throws -> Int {
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        var rendered = 0
        for module in modules {
            // Render the module body content directly (no ScrollView — ImageRenderer
            // does not draw scrollable content) at a tall frame so everything is visible.
            let view = VStack(alignment: .leading, spacing: 0) {
                ConsoleModuleRouter(module: module, state: state)
                    .padding(20)
                Spacer(minLength: 0)
            }
            .frame(width: 1180, height: 1500, alignment: .topLeading)
            .background(CCTheme.background)
            .environment(\.colorScheme, .dark)
            let path = "\(outDir)/\(module.appID == .ucc ? "UCC" : "SCC")-\(String(format: "%02d", module.phaseNumber))-\(module.kind.rawValue).png"
            XCTAssertTrue(writePNG(view, to: path), "module \(module.phaseLabel) \(module.title) failed to render")
            rendered += 1
        }
        return rendered
    }

    @MainActor
    private func renderFullConsole(_ state: MacSystemUIState, name: String) {
        let view = MacCommandConsoleView(state: state).frame(width: 1320, height: 860)
        _ = writePNG(view, to: "\(outDir)/\(name).png")
    }

    @MainActor
    private func writePNG(_ view: some View, to path: String) -> Bool {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        do { try png.write(to: URL(fileURLWithPath: path)); return true } catch { return false }
    }

    // MARK: Seed

    private func seededState(appID: LinkGuardAppID) throws -> MacSystemUIState {
        var runtime = LinkGuardAppRuntime(device: DeviceIdentity(
            id: LinkGuardID("MAC-\(appID.rawValue)"), appID: appID, platform: .mac, displayName: "\(appID.rawValue) Console"))
        var seq = 0
        func recv<P: Encodable>(_ type: SyncMessageType, _ app: LinkGuardAppID, _ dev: String, _ payload: P) throws {
            seq += 1
            let env = try SyncEnvelope.make(messageType: type, sourceAppID: app, sourceDeviceID: LinkGuardID(dev),
                                            priority: .high, createdAt: base.addingTimeInterval(Double(seq)),
                                            idempotencyKey: "seed-\(seq)", payload: payload)
            try runtime.receive(env)
        }
        func gc(_ lat: Double, _ lon: Double) -> GeoCoordinate { GeoCoordinate(latitude: lat, longitude: lon, accuracyMeters: 5) }

        // Two incidents (≈ two SCC nodes)
        try recv(.incidentUpsert, .ucc, "DEV-UCC", Incident(id: "INC-1", displayName: "花蓮港口路 7 樓倒塌", status: .active, createdAt: base, createdBy: "UCC-1", commandPostLocation: gc(23.976, 121.604)))
        try recv(.incidentUpsert, .ucc, "DEV-UCC", Incident(id: "INC-2", displayName: "台北信義區瓦斯氣爆", status: .active, createdAt: base, createdBy: "UCC-1", commandPostLocation: gc(25.033, 121.565)))

        // Sectors A/B/C + sub-sector D1
        try recv(.sectorUpsert, .scc, "DEV-SCC", Sector(id: "SEC-A", incidentID: "INC-1", name: "A 區", commanderID: "P-CMD-A"))
        try recv(.sectorUpsert, .scc, "DEV-SCC", Sector(id: "SEC-B", incidentID: "INC-1", name: "B 區", commanderID: "P-CMD-B"))
        try recv(.sectorUpsert, .scc, "DEV-SCC", Sector(id: "SEC-C", incidentID: "INC-2", name: "C 區"))
        try recv(.subSectorUpsert, .scc, "DEV-SCC", SubSector(id: "SUB-D1", incidentID: "INC-1", sectorID: "SEC-A", name: "D1", commanderID: "P-TL-1", worksiteIDs: ["WS-1"]))

        // Worksites
        try recv(.worksiteUpsert, .scc, "DEV-SCC", Worksite(id: "WS-1", incidentID: "INC-1", sectorID: "SEC-A", subSectorID: "SUB-D1", name: "A1 北側塌陷", location: gc(23.977, 121.605), asrLevel: .asr2, status: .inProgress, assignedTeamIDs: ["TEAM-1"], hazardSummary: "懸吊樓板"))
        try recv(.worksiteUpsert, .scc, "DEV-SCC", Worksite(id: "WS-2", incidentID: "INC-1", sectorID: "SEC-A", name: "A2 停車場", location: gc(23.978, 121.606), asrLevel: .asr3, status: .blocked, assignedTeamIDs: [], hazardSummary: "瓦斯外洩"))
        try recv(.worksiteUpsert, .scc, "DEV-SCC", Worksite(id: "WS-3", incidentID: "INC-2", sectorID: "SEC-C", name: "C1 騎樓", location: gc(25.034, 121.566), asrLevel: .asr1, status: .completed, assignedTeamIDs: ["TEAM-2"]))

        // Tasks
        try recv(.taskUpsert, .scc, "DEV-SCC", FieldTask(id: "TK-1", incidentID: "INC-1", type: .rescue, status: .inProgress, priority: .critical, summary: "A1 受困者破壞取出", createdAt: base))
        try recv(.taskUpsert, .scc, "DEV-SCC", FieldTask(id: "TK-2", incidentID: "INC-1", type: .search, status: .assigned, priority: .high, summary: "A2 二次搜索", createdAt: base))
        try recv(.taskUpsert, .scc, "DEV-SCC", FieldTask(id: "TK-3", incidentID: "INC-1", type: .safetyCheck, status: .blocked, priority: .high, summary: "瓦斯區結構評估", createdAt: base))

        // Personnel
        try recv(.personnelStatusUpsert, .teamMember, "DEV-TE1", PersonnelStatusReport(id: "PS-1", incidentID: "INC-1", personID: "搜救員 王", deviceID: "DEV-TE1", appID: .teamMember, role: .teamMember, operationalState: .inWorksite, connectivity: .online, location: gc(23.977, 121.605), currentWorksiteID: "WS-1", batteryLevel: 0.72, updatedAt: base))
        try recv(.personnelStatusUpsert, .teamLeader, "DEV-TL1", PersonnelStatusReport(id: "PS-2", incidentID: "INC-1", personID: "小隊長 李", deviceID: "DEV-TL1", appID: .teamLeader, role: .teamLeader, operationalState: .assigned, connectivity: .online, location: gc(23.976, 121.604), batteryLevel: 0.55, updatedAt: base))
        try recv(.personnelStatusUpsert, .teamMember, "DEV-TE2", PersonnelStatusReport(id: "PS-3", incidentID: "INC-1", personID: "搜救員 陳", deviceID: "DEV-TE2", appID: .teamMember, role: .teamMember, operationalState: .mayday, connectivity: .degraded, location: gc(23.978, 121.606), batteryLevel: 0.18, updatedAt: base))

        // SOS
        try recv(.sosReportUpsert, .teamMember, "DEV-TE2", SOSReport(id: "SOS-1", incidentID: "INC-1", reporterDeviceID: "DEV-TE2", reporterAppID: .teamMember, location: gc(23.978, 121.606), dangerType: .collapseRisk, severity: .critical, note: "二次倒塌風險", status: .active, createdAt: base))
        try recv(.sosReportUpsert, .volunteer, "DEV-VO1", SOSReport(id: "SOS-2", incidentID: "INC-2", reporterDeviceID: "DEV-VO1", reporterAppID: .volunteer, location: gc(25.034, 121.566), dangerType: .trapped, severity: .high, note: "受困騎樓", status: .responding, createdAt: base))

        // Patients (all triage colors)
        try recv(.patientUpsert, .emt, "DEV-EMT", PatientRecord(id: "PT-1", incidentID: "INC-1", displayCode: "P-001", triageCategory: .red, injurySummary: "下肢壓砸出血", location: gc(23.977, 121.605), latestVitals: VitalSigns(heartRate: 124, respiratoryRate: 28, spo2: 90, gcs: 13, recordedAt: base), updatedAt: base))
        try recv(.patientUpsert, .emt, "DEV-EMT", PatientRecord(id: "PT-2", incidentID: "INC-1", displayCode: "P-002", triageCategory: .yellow, injurySummary: "上肢骨折", updatedAt: base))
        try recv(.patientUpsert, .emt, "DEV-EMT", PatientRecord(id: "PT-3", incidentID: "INC-2", displayCode: "P-003", triageCategory: .green, injurySummary: "輕微擦傷", updatedAt: base))
        try recv(.patientUpsert, .emt, "DEV-EMT", PatientRecord(id: "PT-4", incidentID: "INC-1", displayCode: "P-004", triageCategory: .black, injurySummary: "OHCA", updatedAt: base))

        // Safety zones
        try recv(.safetyZoneUpsert, .scc, "DEV-SCC", SafetyZone(id: "SZ-1", incidentID: "INC-1", zoneType: .collapseRisk, title: "A2 倒塌風險區", geometry: .polygon([gc(23.978, 121.606), gc(23.979, 121.607), gc(23.978, 121.607)]), severity: .critical, updatedBy: "DEV-SCC", updatedAt: base))
        try recv(.safetyZoneUpsert, .scc, "DEV-SCC", SafetyZone(id: "SZ-2", incidentID: "INC-1", zoneType: .noEntry, title: "瓦斯禁入區", geometry: .polygon([gc(23.977, 121.606), gc(23.978, 121.606), gc(23.977, 121.607)]), severity: .high, updatedBy: "DEV-SCC", updatedAt: base))

        // Map features (point/line/polygon)
        try recv(.mapFeatureUpsert, .scc, "DEV-SCC", MapFeature(id: "MF-1", incidentID: "INC-1", featureType: .assemblyPoint, coordinateMode: .gps, geometry: .point(gc(23.975, 121.603)), severity: .low, title: "集結點", createdBy: "DEV-SCC", updatedAt: base))
        try recv(.mapFeatureUpsert, .scc, "DEV-SCC", MapFeature(id: "MF-2", incidentID: "INC-1", featureType: .evacuationRoute, coordinateMode: .gps, geometry: .polyline([gc(23.975, 121.603), gc(23.976, 121.604)]), severity: .medium, title: "撤離動線", createdBy: "DEV-SCC", updatedAt: base))
        try recv(.mapFeatureUpsert, .scc, "DEV-SCC", MapFeature(id: "MF-3", incidentID: "INC-1", featureType: .medicalStation, coordinateMode: .gps, geometry: .point(gc(23.974, 121.602)), severity: .low, title: "前進醫療站", createdBy: "DEV-SCC", updatedAt: base))

        // Alerts
        try recv(.alertUpsert, .ucc, "DEV-UCC", IncidentAlert(id: "AL-1", incidentID: "INC-1", type: .collapseRisk, priority: .critical, title: "餘震二次倒塌警告", body: "A2 區暫停進入", issuedBy: "UCC-1", issuedAt: base))
        try recv(.alertUpsert, .ucc, "DEV-UCC", IncidentAlert(id: "AL-2", incidentID: "INC-1", type: .weather, priority: .high, title: "豪雨特報", body: "1800 後強降雨", issuedBy: "UCC-1", issuedAt: base))

        // Photos
        try recv(.photoReportUpsert, .teamMember, "DEV-TE1", PhotoReport(id: "PH-1", incidentID: "INC-1", reporterDeviceID: "DEV-TE1", worksiteID: "WS-1", photoAttachmentID: "ATT-1", location: gc(23.977, 121.605), capturedAt: base, caption: "A1 生命跡象孔位"))

        // Medical logistics
        try recv(.hospitalCapacityUpsert, .ucc, "DEV-UCC", HospitalCapacity(id: "HOSP-1", name: "花蓮慈濟醫院", emergencyCapacity: 8, traumaCapacity: 4, burnCapacity: 2, pediatricCapacity: 3, updatedAt: base))
        try recv(.hospitalCapacityUpsert, .ucc, "DEV-UCC", HospitalCapacity(id: "HOSP-2", name: "部立花蓮醫院", emergencyCapacity: 5, traumaCapacity: 2, burnCapacity: 0, pediatricCapacity: 2, updatedAt: base))
        try recv(.evacuationRequestUpsert, .emt, "DEV-EMT", EvacuationRequest(id: "EV-1", patientID: "PT-1", priority: .critical, destinationHospitalID: "HOSP-1", status: .pending, requestedAt: base))

        // Team capability
        try recv(.teamCapabilityReportUpsert, .scc, "DEV-SCC", USARTeamCapabilityReport(id: "TC-1", incidentID: "INC-1", reporterDeviceID: "DEV-SCC", reporterName: "TW-01", team: USARTeamInformationSection(teamCode: "TW-USAR-01", country: "TWN", teamName: "桃園特搜", totalMembers: 14, searchDogCount: 2, responseType: .heavy, classificationStatus: .classified), supportNeeds: USARTeamSupportNeedsSection(needsGroundTransport: true, equipmentWeightTons: 6.0), contacts: USARTeamContactsSection(teamContactNameOrRole: "領隊"), createdAt: base))
        try recv(.teamCapabilityReportUpsert, .scc, "DEV-SCC", USARTeamCapabilityReport(id: "TC-2", incidentID: "INC-1", reporterDeviceID: "DEV-SCC", reporterName: "TW-02", team: USARTeamInformationSection(teamCode: "TW-USAR-02", country: "TWN", teamName: "台中特搜", totalMembers: 9, searchDogCount: 1, responseType: .medium, classificationStatus: .notClassified), supportNeeds: USARTeamSupportNeedsSection(), contacts: USARTeamContactsSection(teamContactNameOrRole: "副領隊"), createdAt: base))

        // Safety entry log
        try recv(.safetyEntryLogUpsert, .teamMember, "DEV-TE1", SafetyEntryLog(id: "EN-1", incidentID: "INC-1", zoneID: "SZ-1", personID: "搜救員 王", deviceID: "DEV-TE1", action: .checkIn, location: gc(23.978, 121.606), recordedAt: base, recordedBy: "DEV-TL1", note: "TL 核准進入"))

        // Voice
        try recv(.voiceReportAppend, .teamLeader, "DEV-TL1", VoiceReport(id: "VO-1", incidentID: "INC-1", groupID: "GRP-A", senderDeviceID: "DEV-TL1", audioAttachmentID: "AU-1", transcript: "A1 入口需要支撐器材", durationSeconds: 7.0, priority: .high, recordedAt: base, location: gc(23.977, 121.605)))

        // Command + decision + role
        try recv(.commandUpsert, .ucc, "DEV-UCC", OperationalCommand(id: "CMD-1", incidentID: "INC-1", type: .worksiteAssignment, status: .issued, priority: .high, title: "桃園特搜進駐 A1", body: "立即破壞取出", issuedBy: "UCC-1", issuedAt: base, targetRole: .teamLeader))
        try recv(.decisionRecordUpsert, .ucc, "DEV-UCC", DecisionRecord(id: "DR-1", incidentID: "INC-1", title: "A2 區暫停搜救", reason: "瓦斯濃度過高，等待管制", decidedBy: "UCC-1", decidedAt: base))
        try recv(.roleAssignmentUpsert, .ucc, "DEV-UCC", RoleAssignment(id: "RA-1", personID: "小隊長 李", deviceID: "DEV-TL1", position: .teamLeader, scope: .sector, scopeID: "SEC-A", assignedBy: "UCC-1", startsAt: base))

        return try MacSystemUIFactory.makeState(for: runtime)
    }
}
#endif
