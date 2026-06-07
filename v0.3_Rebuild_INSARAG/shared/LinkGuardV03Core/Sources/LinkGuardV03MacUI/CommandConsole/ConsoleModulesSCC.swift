import SwiftUI
import LinkGuardV03Core

// MARK: - SCC Phase 1 · 現場戰情地圖

struct FieldSituationMapModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConsoleStatGrid(columns: 4, tiles: [
                ConsoleStatTile(title: "分區", value: "\(snapshot.sectors.count)", systemImage: "square.split.2x2.fill", accent: CCTheme.accent),
                ConsoleStatTile(title: "工址", value: "\(snapshot.worksites.count)", systemImage: "mappin.and.ellipse", accent: CCTheme.info),
                ConsoleStatTile(title: "待處理 SOS", value: "\(snapshot.activeSOSCount)", systemImage: "sos.circle.fill", accent: CCTheme.danger),
                ConsoleStatTile(title: "在線人員", value: "\(snapshot.onlinePersonnelCount)", systemImage: "person.fill.checkmark", accent: CCTheme.accent),
                ConsoleStatTile(title: "進行任務", value: "\(snapshot.openTasks.count)", systemImage: "checklist", accent: CCTheme.command),
                ConsoleStatTile(title: "危險區", value: "\(snapshot.safetyZones.count)", systemImage: "exclamationmark.octagon.fill", accent: CCTheme.warning),
                ConsoleStatTile(title: "傷患", value: "\(snapshot.patients.count)", systemImage: "cross.case.fill", accent: CCTheme.danger),
                ConsoleStatTile(title: "地圖標記", value: "\(snapshot.mapFeatures.count)", systemImage: "pencil.and.outline", accent: CCTheme.info)
            ])

            if let incident = primaryIncident {
                ConsolePanel("作戰事故", systemImage: "building.2.fill", accent: CCTheme.command) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(incident.displayName).font(.title3.weight(.bold)).foregroundColor(.white)
                        HStack(spacing: 8) {
                            ConsoleTag(incident.status.rawValue, color: CCTheme.command)
                            ConsoleTag("指揮所 \(ConsoleFormat.coordinate(incident.commandPostLocation))", color: CCTheme.muted)
                            ConsoleTag("建立 \(ConsoleFormat.stamp(incident.createdAt))", color: CCTheme.muted)
                        }
                    }
                }
            } else {
                ConsoleEmptyState(systemImage: "building.2", title: "尚無作戰事故", message: "等待現場建立事故或由同步鏈接收。")
            }

            ConsoleListSection(title: "現場工址", systemImage: "mappin.and.ellipse", items: snapshot.worksites.values.sorted { $0.status.consoleRank < $1.status.consoleRank }, maxRows: 12) { ws in
                ConsoleRow(title: ws.name,
                           subtitle: "\(ConsoleFormat.coordinate(ws.location)) · 隊伍 \(ws.assignedTeamIDs.count)" + (ws.hazardSummary.map { " · ⚠︎ \($0)" } ?? ""),
                           leadingSystemImage: "mappin.circle.fill", leadingColor: ws.status.consoleColor,
                           trailing: AnyView(HStack(spacing: 6) { ConsoleTag(ws.asrLevel.consoleLabel, color: CCTheme.muted); ConsoleTag(ws.status.consoleLabel, color: ws.status.consoleColor) }))
            }
        }
    }
}

// MARK: - SCC Phase 2 · 點線面系統

struct MapMarkupModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let features = snapshot.mapFeatures.values.sorted { $0.updatedAt > $1.updatedAt }
        let points = features.filter { $0.geometry.type == .point }
        let lines = features.filter { $0.geometry.type == .polyline }
        let areas = features.filter { $0.geometry.type == .polygon }
        VStack(alignment: .leading, spacing: 16) {
            ConsoleStatGrid(columns: 3, tiles: [
                ConsoleStatTile(title: "點標記", value: "\(points.count)", systemImage: "smallcircle.filled.circle", accent: CCTheme.accent),
                ConsoleStatTile(title: "線標記", value: "\(lines.count)", systemImage: "line.diagonal", accent: CCTheme.info),
                ConsoleStatTile(title: "面標記", value: "\(areas.count)", systemImage: "square.dashed", accent: CCTheme.warning)
            ])
            ConsoleListSection(title: "地圖標記", systemImage: "pencil.and.outline", items: features, maxRows: 30) { f in
                ConsoleRow(title: f.title,
                           subtitle: "\(f.featureType.consoleLabel) · \(f.geometry.points.count) 點 · 更新 \(ConsoleFormat.stamp(f.updatedAt))",
                           leadingSystemImage: f.featureType.systemImage, leadingColor: CCTheme.priorityColor(f.severity),
                           trailing: AnyView(ConsoleTag(f.geometry.type.consoleLabel, color: CCTheme.sectionTint(.operations))))
            }
        }
    }
}

// MARK: - SCC Phase 3 · 分區建立 (A/B/C)

struct SectorManagementModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let sectors = snapshot.sectors.values.sorted { $0.name < $1.name }
        VStack(alignment: .leading, spacing: 16) {
            ConsoleListSection(title: "主分區 (A/B/C)", systemImage: "square.split.2x2.fill", accent: CCTheme.accent, items: sectors) { sector in
                let subCount = snapshot.subSectors.values.filter { $0.sectorID == sector.id }.count
                let wsCount = snapshot.worksites.values.filter { $0.sectorID == sector.id }.count
                return ConsoleRow(title: sector.name,
                           subtitle: "指揮官 \(sector.commanderID?.rawValue ?? "未指派") · 子區 \(subCount) · 工址 \(wsCount)",
                           leadingSystemImage: "square.split.2x2.fill", leadingColor: CCTheme.accent)
            }
            ConsoleIntegrationNote(systemImage: "info.circle.fill", title: "分區建立權限",
                                   detail: "SCC 為分區建立的戰術核心（A/B/C 主分區）。建立/調整分區會以 sectorUpsert 同步到 UCC 與其它現場端，並寫入 audit trail。")
        }
    }
}

// MARK: - SCC Phase 4 · 子區建立 (D1/D2)

struct SubSectorManagementModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let subs = snapshot.subSectors.values.sorted { $0.name < $1.name }
        VStack(alignment: .leading, spacing: 16) {
            ConsoleListSection(title: "子區 (D1/D2…)", systemImage: "square.split.1x2.fill", accent: CCTheme.info, items: subs) { sub in
                let parent = snapshot.sectors[sub.sectorID]?.name ?? sub.sectorID.rawValue
                return ConsoleRow(title: sub.name,
                           subtitle: "上層分區 \(parent) · 工址 \(sub.worksiteIDs.count)",
                           leadingSystemImage: "square.split.1x2.fill", leadingColor: CCTheme.info,
                           trailing: AnyView(ConsoleTag("\(snapshot.worksites(inSubSector: sub.id).count) 工址", color: CCTheme.muted)))
            }
        }
    }
}

// MARK: - SCC Phase 5 · 搜救狀態圖層

struct SearchStatusLayerModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let worksites = snapshot.worksites.values.sorted { $0.status.consoleRank < $1.status.consoleRank }
        let cleared = worksites.filter { $0.status == .completed }.count
        let inProgress = worksites.filter { $0.status == .inProgress }.count
        let blocked = worksites.filter { $0.status == .blocked }.count
        VStack(alignment: .leading, spacing: 16) {
            ConsoleStatGrid(columns: 4, tiles: [
                ConsoleStatTile(title: "搜救中", value: "\(inProgress)", systemImage: "magnifyingglass.circle.fill", accent: CCTheme.info),
                ConsoleStatTile(title: "已淨空", value: "\(cleared)", systemImage: "checkmark.seal.fill", accent: CCTheme.accent),
                ConsoleStatTile(title: "受阻", value: "\(blocked)", systemImage: "xmark.octagon.fill", accent: CCTheme.danger),
                ConsoleStatTile(title: "總工址", value: "\(worksites.count)", systemImage: "mappin.and.ellipse", accent: CCTheme.muted)
            ])
            ConsoleListSection(title: "工址搜救狀態", systemImage: "circle.grid.cross.fill", items: worksites, maxRows: 40) { ws in
                ConsoleRow(title: ws.name,
                           subtitle: "\(ws.asrLevel.consoleLabel) · 隊伍 \(ws.assignedTeamIDs.count)",
                           leadingSystemImage: "circle.fill", leadingColor: ws.status.consoleColor,
                           trailing: AnyView(ConsoleTag(ws.status.consoleLabel, color: ws.status.consoleColor)))
            }
        }
    }
}

// MARK: - SCC Phase 6 · 危險區管理

struct HazardZoneModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConsoleListSection(title: "危險區與禁區", systemImage: "exclamationmark.octagon.fill", accent: CCTheme.danger, items: snapshot.activeHazardZones) { zone in
                ConsoleRow(title: zone.title,
                           subtitle: "嚴重度 \(zone.severity.consoleLabel) · 更新 \(ConsoleFormat.stamp(zone.updatedAt))",
                           leadingSystemImage: "exclamationmark.octagon.fill", leadingColor: zone.zoneType.consoleColor,
                           trailing: AnyView(HStack(spacing: 6) {
                               ConsoleTag(zone.zoneType.consoleLabel, color: zone.zoneType.consoleColor)
                               ConsoleTag(zone.isActive ? "啟用" : "停用", color: zone.isActive ? CCTheme.danger : CCTheme.muted)
                           }))
            }
            ConsoleListSection(title: "管制/危險地圖面", systemImage: "square.dashed", accent: CCTheme.warning,
                               items: snapshot.mapFeatures.values.filter { [.restrictedZone, .hazardPolygon, .collapsedAreaPolygon].contains($0.featureType) }.sorted { $0.updatedAt > $1.updatedAt }, maxRows: 20) { f in
                ConsoleRow(title: f.title, subtitle: ConsoleFormat.stamp(f.updatedAt),
                           leadingSystemImage: f.featureType.systemImage, leadingColor: CCTheme.warning,
                           trailing: AnyView(ConsoleTag(f.featureType.consoleLabel, color: CCTheme.warning)))
            }
        }
    }
}

// MARK: - SCC Phase 7 · GPS 人員定位

struct PersonnelTrackingModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !snapshot.maydayPersonnel.isEmpty {
                ConsolePanel("MAYDAY", systemImage: "sos.circle.fill", accent: CCTheme.danger) {
                    VStack(spacing: 6) {
                        ForEach(Array(snapshot.maydayPersonnel.enumerated()), id: \.offset) { _, p in
                            ConsoleRow(title: p.personID.rawValue,
                                       subtitle: "\(ConsoleFormat.coordinate(p.location)) · \(ConsoleFormat.stamp(p.updatedAt))",
                                       leadingSystemImage: "exclamationmark.triangle.fill", leadingColor: CCTheme.danger)
                        }
                    }
                }
            }
            ConsoleListSection(title: "人員即時定位", systemImage: "location.fill.viewfinder", items: snapshot.sortedPersonnel, maxRows: 40) { p in
                ConsoleRow(title: "\(p.role.consoleLabel) · \(p.personID.rawValue)",
                           subtitle: "\(ConsoleFormat.coordinate(p.location)) · 電量 \(p.batteryLevel.map { "\(Int($0 * 100))%" } ?? "—")",
                           leadingSystemImage: "dot.circle.and.hand.point.up.left.fill", leadingColor: p.operationalState.consoleColor,
                           trailing: AnyView(HStack(spacing: 6) {
                               ConsoleTag(p.operationalState.consoleLabel, color: p.operationalState.consoleColor)
                               ConsoleTag(p.connectivity.consoleLabel, color: p.connectivity.consoleColor)
                           }))
            }
        }
    }
}

// MARK: - SCC Phase 8 · SOS 管理 (field)

struct FieldSOSModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConsoleStatGrid(columns: 3, tiles: [
                ConsoleStatTile(title: "待處理", value: "\(snapshot.activeSOSCount)", systemImage: "sos.circle.fill", accent: CCTheme.danger),
                ConsoleStatTile(title: "處理中", value: "\(snapshot.sosReports.values.filter { $0.status == .responding }.count)", systemImage: "figure.run.circle.fill", accent: CCTheme.info),
                ConsoleStatTile(title: "已解除", value: "\(snapshot.sosReports.values.filter { $0.status == .resolved }.count)", systemImage: "checkmark.circle.fill", accent: CCTheme.accent)
            ])
            ConsoleListSection(title: "SOS 事件（依優先）", systemImage: "sos.circle.fill", accent: CCTheme.danger, items: snapshot.sortedSOS) { sos in
                ConsoleRow(title: "\(sos.dangerType.consoleLabel) · \(sos.severity.consoleLabel)",
                           subtitle: "\(sos.reporterAppID.rawValue) · \(ConsoleFormat.coordinate(sos.location)) · \(ConsoleFormat.stamp(sos.createdAt))" + (sos.note.map { " · \($0)" } ?? ""),
                           leadingSystemImage: "sos.circle.fill", leadingColor: sos.status.consoleColor,
                           trailing: AnyView(ConsoleTag(sos.status.consoleLabel, color: sos.status.consoleColor)))
            }
        }
    }
}

// MARK: - SCC Phase 9 · 任務派遣

struct TaskDispatchModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConsoleStatGrid(columns: 3, tiles: [
                ConsoleStatTile(title: "進行中", value: "\(snapshot.tasks.values.filter { $0.status == .inProgress }.count)", systemImage: "play.circle.fill", accent: CCTheme.info),
                ConsoleStatTile(title: "待接收", value: "\(snapshot.tasks.values.filter { $0.status == .assigned }.count)", systemImage: "paperplane.circle.fill", accent: CCTheme.accent),
                ConsoleStatTile(title: "受阻", value: "\(snapshot.tasks.values.filter { $0.status == .blocked }.count)", systemImage: "exclamationmark.circle.fill", accent: CCTheme.danger)
            ])
            ConsoleListSection(title: "任務派遣", systemImage: "arrow.triangle.branch", items: snapshot.sortedTasks, maxRows: 40) { task in
                let ws = task.worksiteID.flatMap { snapshot.worksites[$0]?.name }
                return ConsoleRow(title: task.summary,
                           subtitle: "\(task.type.consoleLabel) · 隊伍 \(task.assignedTeamID?.rawValue ?? "未指派")" + (ws.map { " · \($0)" } ?? ""),
                           leadingSystemImage: "arrow.triangle.branch", leadingColor: task.status.consoleColor,
                           trailing: AnyView(HStack(spacing: 6) {
                               ConsoleTag(task.priority.consoleLabel, color: CCTheme.priorityColor(task.priority))
                               ConsoleTag(task.status.consoleLabel, color: task.status.consoleColor)
                           }))
            }
        }
    }
}

// MARK: - SCC Phase 10 · 人員配置

struct PersonnelAssignmentModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let byState = Dictionary(grouping: snapshot.sortedPersonnel) { $0.operationalState }
        VStack(alignment: .leading, spacing: 16) {
            ConsoleStatGrid(columns: 4, tiles: [
                ConsoleStatTile(title: "待命", value: "\(byState[.available]?.count ?? 0)", systemImage: "person.fill", accent: CCTheme.muted),
                ConsoleStatTile(title: "工址內", value: "\(byState[.inWorksite]?.count ?? 0)", systemImage: "figure.walk", accent: CCTheme.info),
                ConsoleStatTile(title: "已派遣", value: "\(byState[.assigned]?.count ?? 0)", systemImage: "person.badge.shield.checkmark", accent: CCTheme.accent),
                ConsoleStatTile(title: "MAYDAY", value: "\(byState[.mayday]?.count ?? 0)", systemImage: "exclamationmark.triangle.fill", accent: CCTheme.danger)
            ])
            ConsoleListSection(title: "人員配置", systemImage: "person.3.sequence.fill", items: snapshot.sortedPersonnel, maxRows: 50) { p in
                let ws = p.currentWorksiteID.flatMap { snapshot.worksites[$0]?.name }
                return ConsoleRow(title: "\(p.role.consoleLabel) · \(p.personID.rawValue)",
                           subtitle: "裝置 \(p.appID.rawValue)" + (ws.map { " · \($0)" } ?? ""),
                           leadingSystemImage: "person.fill", leadingColor: p.operationalState.consoleColor,
                           trailing: AnyView(ConsoleTag(p.operationalState.consoleLabel, color: p.operationalState.consoleColor)))
            }
            ConsoleListSection(title: "角色指派紀錄", systemImage: "person.badge.plus", accent: CCTheme.command,
                               items: snapshot.roleAssignments.values.sorted { $0.startsAt > $1.startsAt }, maxRows: 12) { a in
                ConsoleRow(title: "\(a.position.consoleLabel) · \(a.personID.rawValue)",
                           subtitle: "範圍 \(a.scope.rawValue) · \(ConsoleFormat.stamp(a.startsAt))",
                           leadingSystemImage: "person.badge.plus", leadingColor: a.isActive ? CCTheme.accent : CCTheme.muted)
            }
        }
    }
}

// MARK: - SCC Phase 11 · 隊伍能力表

struct TeamCapabilityModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let reports = snapshot.teamCapabilityReports.values.sorted { $0.createdAt > $1.createdAt }
        VStack(alignment: .leading, spacing: 16) {
            ConsoleListSection(title: "隊伍能力表", systemImage: "list.bullet.clipboard.fill", accent: CCTheme.sectionTint(.logistics), items: reports) { r in
                var caps: [String] = []
                if r.team.hasTechnicalSearch { caps.append("技術搜索") }
                if r.team.hasDogSearch { caps.append("搜救犬") }
                if r.team.hasRescueCapability { caps.append("救援") }
                if r.team.hasMedicalCapability { caps.append("醫療") }
                if r.team.hasHazmatDetection { caps.append("毒化偵測") }
                return ConsoleRow(title: "\(r.team.teamCode) · \(r.team.teamName)",
                           subtitle: "\(r.team.country) · 人員 \(r.team.totalMembers) · 犬 \(r.team.searchDogCount) · " + (caps.isEmpty ? "—" : caps.joined(separator: "／")),
                           leadingSystemImage: "shield.lefthalf.filled", leadingColor: CCTheme.sectionTint(.logistics),
                           trailing: AnyView(HStack(spacing: 6) {
                               ConsoleTag(r.team.responseType.consoleLabel, color: CCTheme.command)
                               ConsoleTag(r.team.classificationStatus.consoleLabel, color: CCTheme.muted)
                           }))
            }
        }
    }
}

// MARK: - SCC Phase 12 · 傷患管理

struct PatientManagementModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TriageSummaryStrip(snapshot: snapshot)
            ConsoleListSection(title: "傷患統整", systemImage: "cross.case.fill", accent: CCTheme.danger, items: snapshot.sortedPatients, maxRows: 40) { p in
                ConsoleRow(title: "\(p.displayCode) · \(p.injurySummary)",
                           subtitle: "\(ConsoleFormat.coordinate(p.location)) · 更新 \(ConsoleFormat.stamp(p.updatedAt))",
                           leadingSystemImage: "cross.case.fill", leadingColor: p.triageCategory.consoleColor,
                           trailing: AnyView(ConsoleTag(p.triageCategory.consoleLabel, color: p.triageCategory.consoleColor)))
            }
        }
    }
}

// MARK: - SCC Phase 13 · START 檢傷

struct StartTriageModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TriageSummaryStrip(snapshot: snapshot)
            ConsoleListSection(title: "START 檢傷分類", systemImage: "staroflife.fill", accent: CCTheme.danger,
                               items: snapshot.sortedPatients, maxRows: 50) { p in
                ConsoleRow(title: "\(p.displayCode) · \(p.injurySummary)",
                           subtitle: p.latestVitals.map { v in "HR \(v.heartRate.map(String.init) ?? "—") · SpO₂ \(v.spo2.map { "\($0)%" } ?? "—")" } ?? "尚無生命徵象",
                           leadingSystemImage: "staroflife.fill", leadingColor: p.triageCategory.consoleColor,
                           trailing: AnyView(ConsoleTag(p.triageCategory.consoleLabel, color: p.triageCategory.consoleColor)))
            }
            ConsoleIntegrationNote(systemImage: "info.circle.fill", title: "SCC 對 START 為統計檢視",
                                   detail: "依權限矩陣，SCC 為部分權限（○）：可彙整與排序檢傷結果；實際檢傷分類與更新由 TL／EMT 端執行並同步。")
        }
    }
}

// MARK: - SCC Phase 14 · 照片牆

struct PhotoWallModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let photos = snapshot.photoReports.values.sorted { $0.capturedAt > $1.capturedAt }
        VStack(alignment: .leading, spacing: 16) {
            ConsoleListSection(title: "現場照片（GPS 整合）", systemImage: "photo.on.rectangle.angled", accent: CCTheme.info, items: photos, maxRows: 40) { photo in
                let ws = photo.worksiteID.flatMap { snapshot.worksites[$0]?.name }
                return ConsoleRow(title: photo.caption ?? "現場照片 \(photo.id.rawValue.suffix(6))",
                           subtitle: "\(ConsoleFormat.coordinate(photo.location)) · \(ConsoleFormat.stamp(photo.capturedAt))" + (ws.map { " · \($0)" } ?? ""),
                           leadingSystemImage: "photo.fill", leadingColor: CCTheme.info)
            }
        }
    }
}

// MARK: - SCC Phase 15 · 臨時據點

struct TemporaryBaseModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let bases = snapshot.mapFeatures.values
            .filter { [.assemblyPoint, .medicalStation, .casualtyCollectionPoint, .triageArea, .safetyZone].contains($0.featureType) }
            .sorted { $0.updatedAt > $1.updatedAt }
        VStack(alignment: .leading, spacing: 16) {
            if let incident = primaryIncident, let cp = incident.commandPostLocation {
                ConsolePanel("前進指揮所", systemImage: "tent.fill", accent: CCTheme.command) {
                    ConsoleRow(title: incident.displayName, subtitle: "指揮所座標 \(ConsoleFormat.coordinate(cp))",
                               leadingSystemImage: "flag.checkered", leadingColor: CCTheme.command)
                }
            }
            ConsoleListSection(title: "臨時據點與集結點", systemImage: "tent.fill", accent: CCTheme.sectionTint(.logistics), items: bases) { f in
                ConsoleRow(title: f.title, subtitle: "\(f.featureType.consoleLabel) · \(ConsoleFormat.stamp(f.updatedAt))",
                           leadingSystemImage: f.featureType.systemImage, leadingColor: CCTheme.sectionTint(.logistics))
            }
        }
    }
}

// MARK: - SCC Phase 16 · 安全管制 (進出紀錄)

struct AccessControlModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let logs = snapshot.safetyEntryLogs.values.sorted { $0.recordedAt > $1.recordedAt }
        let inside = snapshot.personnelStatusReports.values.filter { $0.operationalState == .inWorksite }.count
        VStack(alignment: .leading, spacing: 16) {
            ConsoleStatGrid(columns: 3, tiles: [
                ConsoleStatTile(title: "目前在區內", value: "\(inside)", systemImage: "figure.walk.motion", accent: CCTheme.info),
                ConsoleStatTile(title: "進出紀錄", value: "\(logs.count)", systemImage: "list.clipboard.fill", accent: CCTheme.accent),
                ConsoleStatTile(title: "危險區", value: "\(snapshot.safetyZones.values.filter { $0.isActive }.count)", systemImage: "exclamationmark.octagon.fill", accent: CCTheme.danger)
            ])
            ConsoleListSection(title: "人員進出紀錄", systemImage: "shield.lefthalf.filled", accent: CCTheme.command, items: logs, maxRows: 40) { log in
                let zone = snapshot.safetyZones[log.zoneID]?.title ?? log.zoneID.rawValue
                let actionLabel: String
                switch log.action {
                case .checkIn: actionLabel = "進入"
                case .checkOut: actionLabel = "離開"
                case .denied: actionLabel = "拒絕"
                case .emergencyExit: actionLabel = "緊急撤出"
                }
                let actionColor: Color = (log.action == .emergencyExit || log.action == .denied) ? CCTheme.danger : CCTheme.accent
                return ConsoleRow(title: "\(log.personID.rawValue) · \(actionLabel)",
                           subtitle: "\(zone) · \(ConsoleFormat.stamp(log.recordedAt))",
                           leadingSystemImage: "person.badge.shield.checkmark", leadingColor: actionColor,
                           trailing: AnyView(ConsoleTag(actionLabel, color: actionColor)))
            }
        }
    }
}

// MARK: - SCC Phase 18 · AI 決策輔助

struct AIDecisionSupportModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConsoleIntegrationNote(systemImage: "brain.head.profile", title: "現場 AI 決策輔助",
                                   detail: "AI 以現場即時輸入（SOS、危險區、工址狀態、人員配置與任務）產生派遣與安全建議，協助指揮官降低負荷。模型推論為待接整合。", tint: CCTheme.command)
            ConsoleStatGrid(columns: 3, tiles: [
                ConsoleStatTile(title: "待處理 SOS", value: "\(snapshot.activeSOSCount)", systemImage: "sos.circle.fill", accent: CCTheme.danger, caption: "AI 派遣輸入"),
                ConsoleStatTile(title: "受阻任務", value: "\(snapshot.tasks.values.filter { $0.status == .blocked }.count)", systemImage: "exclamationmark.circle.fill", accent: CCTheme.warning, caption: "瓶頸分析"),
                ConsoleStatTile(title: "啟用危險區", value: "\(snapshot.safetyZones.values.filter { $0.isActive }.count)", systemImage: "exclamationmark.octagon.fill", accent: CCTheme.danger, caption: "安全建議")
            ])
            ConsoleListSection(title: "決策紀錄", systemImage: "checkmark.seal.fill", accent: CCTheme.command,
                               items: snapshot.decisionRecords.values.sorted { $0.decidedAt > $1.decidedAt }) { d in
                ConsoleRow(title: d.title, subtitle: "\(d.reason) · \(ConsoleFormat.stamp(d.decidedAt))",
                           leadingSystemImage: "checkmark.seal.fill", leadingColor: CCTheme.command)
            }
        }
    }
}

// MARK: - SCC Phase 19 · LoRa 整合

struct LoRaIntegrationModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConsoleIntegrationNote(systemImage: "dot.radiowaves.up.forward", title: "LoRa 自主通訊備援",
                                   detail: "基地台失效時，LoRa 中繼維持 SOS、警報與群組訊息的弱頻寬傳遞。實際 LoRa/BLE gateway 與封包轉換為待硬體整合；以下為目前透過通訊鏈傳遞的資料量。", tint: CCTheme.warning)
            ConsoleStatGrid(columns: 3, tiles: [
                ConsoleStatTile(title: "群組訊息", value: "\(snapshot.groupChatMessages.count)", systemImage: "bubble.left.and.bubble.right.fill", accent: CCTheme.info),
                ConsoleStatTile(title: "語音回報", value: "\(snapshot.voiceReports.count)", systemImage: "waveform", accent: CCTheme.accent),
                ConsoleStatTile(title: "待送佇列", value: "\(state.runtime.pendingOutboundCount)", systemImage: "arrow.up.circle.fill", accent: CCTheme.warning)
            ])
        }
    }
}

// MARK: - SCC Phase 20 · 離線模式

struct OfflineModeModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let syncEvents = snapshot.auditEvents.filter { $0.action.isSyncEvent }.sorted { $0.createdAt > $1.createdAt }
        VStack(alignment: .leading, spacing: 16) {
            ConsoleStatGrid(columns: 3, tiles: [
                ConsoleStatTile(title: "待送佇列", value: "\(state.runtime.pendingOutboundCount)", systemImage: "tray.full.fill", accent: CCTheme.warning),
                ConsoleStatTile(title: "佇列總數", value: "\(state.runtime.outboundQueue.entries.count)", systemImage: "tray.2.fill", accent: CCTheme.info),
                ConsoleStatTile(title: "已處理同步", value: "\(snapshot.processedIdempotencyKeys.count)", systemImage: "checkmark.circle.fill", accent: CCTheme.accent)
            ])
            ConsoleIntegrationNote(systemImage: "wifi.slash", title: "離線指揮備援",
                                   detail: "斷網時所有現場操作本地暫存於離線佇列，恢復通訊後依優先序自動重送並追蹤收據。離線地圖圖磚下載為待接能力。")
            ConsoleListSection(title: "同步事件", systemImage: "arrow.triangle.2.circlepath", items: syncEvents, maxRows: 30) { e in
                ConsoleRow(title: "\(e.action.consoleLabel) · \(e.targetType)",
                           subtitle: ConsoleFormat.stamp(e.createdAt),
                           leadingSystemImage: e.action == .syncFailed ? "xmark.circle.fill" : "checkmark.circle.fill",
                           leadingColor: e.action == .syncFailed ? CCTheme.danger : CCTheme.accent)
            }
        }
    }
}

// MARK: - Shared triage strip

struct TriageSummaryStrip: View {
    let snapshot: OperationSnapshot
    var body: some View {
        ConsoleStatGrid(columns: 4, tiles: [
            ConsoleStatTile(title: "紅 (危急)", value: "\(snapshot.triageCount(.red))", systemImage: "cross.case.fill", accent: CCTheme.danger),
            ConsoleStatTile(title: "黃 (緊急)", value: "\(snapshot.triageCount(.yellow))", systemImage: "cross.case.fill", accent: CCTheme.warning),
            ConsoleStatTile(title: "綠 (輕傷)", value: "\(snapshot.triageCount(.green))", systemImage: "cross.case.fill", accent: CCTheme.accent),
            ConsoleStatTile(title: "黑 (死亡)", value: "\(snapshot.triageCount(.black))", systemImage: "cross.case.fill", accent: CCTheme.muted)
        ])
    }
}
