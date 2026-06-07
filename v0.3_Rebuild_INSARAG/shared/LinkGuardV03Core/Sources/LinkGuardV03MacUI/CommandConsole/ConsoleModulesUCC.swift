import SwiftUI
import LinkGuardV03Core

// MARK: - Cross-region incident (≈ SCC node) rollup

struct IncidentNodeSummary: Identifiable {
    let incident: Incident
    let sectorCount: Int
    let worksiteCount: Int
    let activeSOS: Int
    let personnelOnline: Int
    let openTasks: Int
    let redPatients: Int
    var id: String { incident.id.rawValue }
}

private func incidentSummaries(_ snapshot: OperationSnapshot) -> [IncidentNodeSummary] {
    snapshot.incidents.values.map { incident in
        let id = incident.id
        return IncidentNodeSummary(
            incident: incident,
            sectorCount: snapshot.sectors.values.filter { $0.incidentID == id }.count,
            worksiteCount: snapshot.worksites.values.filter { $0.incidentID == id }.count,
            activeSOS: snapshot.sosReports.values.filter { $0.incidentID == id && $0.status == .active }.count,
            personnelOnline: snapshot.personnelStatusReports.values.filter { $0.incidentID == id && $0.connectivity == .online }.count,
            openTasks: snapshot.tasks.values.filter { $0.incidentID == id && $0.status != .completed && $0.status != .cancelled }.count,
            redPatients: snapshot.patients.values.filter { $0.incidentID == id && $0.triageCategory == .red }.count
        )
    }
    .sorted { $0.activeSOS > $1.activeSOS }
}

// MARK: - UCC Phase 1 · 基礎登入系統

struct IdentityAccessModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let profile = state.runtime.profile
        VStack(alignment: .leading, spacing: 16) {
            ConsolePanel("目前指揮身分", systemImage: "person.badge.key.fill", accent: CCTheme.accent) {
                VStack(alignment: .leading, spacing: 8) {
                    if let session = state.loginSession {
                        ConsoleRow(title: session.displayName, subtitle: "\(session.position.consoleLabel) · \(session.accountID.rawValue)",
                                   leadingSystemImage: "person.crop.circle.fill", leadingColor: CCTheme.accent)
                    } else {
                        ConsoleRow(title: profile.displayName, subtitle: state.runtime.device.displayName,
                                   leadingSystemImage: "person.crop.circle", leadingColor: CCTheme.muted)
                    }
                    HStack(spacing: 6) {
                        ConsoleTag("指揮權限 \(profile.commandAuthority.macDisplayName)", color: CCTheme.command)
                        ConsoleTag("\(profile.permissions.count) 項權限", color: CCTheme.accent)
                    }
                }
            }
            ConsoleListSection(title: "角色指派", systemImage: "person.2.badge.gearshape.fill", accent: CCTheme.command,
                               items: snapshot.roleAssignments.values.sorted { $0.startsAt > $1.startsAt }) { a in
                ConsoleRow(title: "\(a.position.consoleLabel) · \(a.personID.rawValue)",
                           subtitle: "範圍 \(a.scope.rawValue) · 由 \(a.assignedBy.rawValue) · \(ConsoleFormat.stamp(a.startsAt))",
                           leadingSystemImage: "person.badge.plus", leadingColor: a.isActive ? CCTheme.accent : CCTheme.muted,
                           trailing: AnyView(ConsoleTag(a.isActive ? "啟用" : "撤銷", color: a.isActive ? CCTheme.accent : CCTheme.muted)))
            }
            ConsolePanel("帳號權限清單", systemImage: "lock.shield.fill", accent: CCTheme.info) {
                let perms = profile.permissions.map { $0.rawValue }.sorted()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 6) {
                    ForEach(perms, id: \.self) { p in
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundColor(CCTheme.accent)
                            Text(p).font(.caption2).foregroundColor(.white.opacity(0.8)).lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - UCC Phase 2 · 全區戰情儀表板

struct GlobalDashboardModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConsoleStatGrid(columns: 4, tiles: [
                ConsoleStatTile(title: "災區/事故", value: "\(snapshot.incidents.count)", systemImage: "building.2.fill", accent: CCTheme.command),
                ConsoleStatTile(title: "分區", value: "\(snapshot.sectors.count)", systemImage: "square.split.2x2.fill", accent: CCTheme.accent),
                ConsoleStatTile(title: "工址", value: "\(snapshot.worksites.count)", systemImage: "mappin.and.ellipse", accent: CCTheme.info),
                ConsoleStatTile(title: "待處理 SOS", value: "\(snapshot.activeSOSCount)", systemImage: "sos.circle.fill", accent: CCTheme.danger),
                ConsoleStatTile(title: "在線人員", value: "\(snapshot.onlinePersonnelCount)", systemImage: "person.fill.checkmark", accent: CCTheme.accent),
                ConsoleStatTile(title: "進行任務", value: "\(snapshot.openTasks.count)", systemImage: "checklist", accent: CCTheme.command),
                ConsoleStatTile(title: "傷患", value: "\(snapshot.patients.count)", systemImage: "cross.case.fill", accent: CCTheme.danger),
                ConsoleStatTile(title: "啟用警報", value: "\(snapshot.alerts.count)", systemImage: "exclamationmark.triangle.fill", accent: CCTheme.warning)
            ])
            ConsoleListSection(title: "各災區概況", systemImage: "rectangle.3.group.fill", accent: CCTheme.command, items: incidentSummaries(snapshot)) { node in
                ConsoleRow(title: node.incident.displayName,
                           subtitle: "分區 \(node.sectorCount) · 工址 \(node.worksiteCount) · 在線 \(node.personnelOnline)",
                           leadingSystemImage: "building.2.fill", leadingColor: node.activeSOS > 0 ? CCTheme.danger : CCTheme.accent,
                           trailing: AnyView(HStack(spacing: 6) {
                               if node.activeSOS > 0 { ConsoleTag("SOS \(node.activeSOS)", color: CCTheme.danger) }
                               ConsoleTag(node.incident.status.rawValue, color: CCTheme.command)
                           }))
            }
            ConsoleListSection(title: "最新警報", systemImage: "bell.badge.fill", accent: CCTheme.warning, items: snapshot.sortedAlerts, maxRows: 8) { a in
                ConsoleRow(title: a.title, subtitle: "\(a.type.consoleLabel) · \(ConsoleFormat.stamp(a.issuedAt))",
                           leadingSystemImage: "exclamationmark.triangle.fill", leadingColor: CCTheme.priorityColor(a.priority),
                           trailing: AnyView(ConsoleTag(a.priority.consoleLabel, color: CCTheme.priorityColor(a.priority))))
            }
        }
    }
}

// MARK: - UCC Phase 3 · 多災區地圖 (多 SCC 顯示)

struct MultiDisasterMapModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConsoleIntegrationNote(systemImage: "map.fill", title: "多災區地圖總覽",
                                   detail: "跨災區整合：每個事故對應一個 SCC 節點，UCC 在同一張戰略地圖上掌握所有災區位置、規模與緊急度。實體圖磚/底圖 SDK 為待接整合。", tint: CCTheme.info)
            ConsoleListSection(title: "災區節點", systemImage: "mappin.and.ellipse", accent: CCTheme.command, items: incidentSummaries(snapshot)) { node in
                ConsoleRow(title: node.incident.displayName,
                           subtitle: "指揮所 \(ConsoleFormat.coordinate(node.incident.commandPostLocation)) · 工址 \(node.worksiteCount) · 任務 \(node.openTasks)",
                           leadingSystemImage: "mappin.circle.fill", leadingColor: node.redPatients > 0 || node.activeSOS > 0 ? CCTheme.danger : CCTheme.accent,
                           trailing: AnyView(HStack(spacing: 6) {
                               if node.activeSOS > 0 { ConsoleTag("SOS \(node.activeSOS)", color: CCTheme.danger) }
                               if node.redPatients > 0 { ConsoleTag("紅 \(node.redPatients)", color: CCTheme.danger) }
                           }))
            }
        }
    }
}

// MARK: - UCC Phase 4 · ICS 指揮架構

struct ICSArchitectureModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let arch = state.uccICSArchitecture {
                ConsolePanel(arch.title, systemImage: "point.3.connected.trianglepath.dotted", accent: CCTheme.command) {
                    Text(arch.coordinationRole).font(.caption).foregroundColor(CCTheme.muted)
                }
                ForEach(arch.lanes) { lane in
                    ConsolePanel("\(CCTheme.sectionName(lane.section))", systemImage: lane.systemImageName, accent: CCTheme.sectionTint(lane.section)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(lane.roleInUCC).font(.caption).foregroundColor(.white.opacity(0.85))
                            Text("權限邊界：\(lane.authorityBoundary)").font(.caption2).foregroundColor(CCTheme.muted)
                            if !lane.primaryPositions.isEmpty {
                                HStack(spacing: 5) {
                                    ForEach(lane.primaryPositions, id: \.self) { pos in
                                        ConsoleTag(pos.consoleLabel, color: CCTheme.sectionTint(lane.section))
                                    }
                                }
                            }
                        }
                    }
                }
                ConsolePanel("指揮邊界規則", systemImage: "checkmark.shield.fill", accent: CCTheme.warning) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(arch.boundaryRules) { rule in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.title).font(.caption.weight(.bold)).foregroundColor(CCTheme.warning)
                                Text(rule.detail).font(.caption2).foregroundColor(CCTheme.muted).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            } else {
                ConsoleEmptyState(systemImage: "point.3.connected.trianglepath.dotted", title: "ICS 架構未載入")
            }
        }
    }
}

// MARK: - UCC Phase 5 · 全區 SOS 總覽

struct GlobalSOSModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConsoleStatGrid(columns: 4, tiles: [
                ConsoleStatTile(title: "待處理", value: "\(snapshot.activeSOSCount)", systemImage: "sos.circle.fill", accent: CCTheme.danger),
                ConsoleStatTile(title: "處理中", value: "\(snapshot.sosReports.values.filter { $0.status == .responding }.count)", systemImage: "figure.run.circle.fill", accent: CCTheme.info),
                ConsoleStatTile(title: "已確認", value: "\(snapshot.sosReports.values.filter { $0.status == .acknowledged }.count)", systemImage: "checkmark.seal.fill", accent: CCTheme.warning),
                ConsoleStatTile(title: "已解除", value: "\(snapshot.sosReports.values.filter { $0.status == .resolved }.count)", systemImage: "checkmark.circle.fill", accent: CCTheme.accent)
            ])
            ConsoleListSection(title: "全區 SOS 事件", systemImage: "sos.circle.fill", accent: CCTheme.danger, items: snapshot.sortedSOS, maxRows: 60) { sos in
                let area = snapshot.incidents[sos.incidentID]?.displayName ?? sos.incidentID.rawValue
                return ConsoleRow(title: "\(sos.dangerType.consoleLabel) · \(area)",
                           subtitle: "\(sos.reporterAppID.rawValue) · \(ConsoleFormat.coordinate(sos.location)) · \(ConsoleFormat.stamp(sos.createdAt))",
                           leadingSystemImage: "sos.circle.fill", leadingColor: sos.status.consoleColor,
                           trailing: AnyView(HStack(spacing: 6) {
                               ConsoleTag(sos.severity.consoleLabel, color: CCTheme.priorityColor(sos.severity))
                               ConsoleTag(sos.status.consoleLabel, color: sos.status.consoleColor)
                           }))
            }
        }
    }
}

// MARK: - UCC Phase 6 · 全區傷患統計

struct CasualtyStatisticsModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let pendingEvac = snapshot.evacuationRequests.values.filter { $0.status != .handedOff && $0.status != .cancelled }.count
        VStack(alignment: .leading, spacing: 16) {
            TriageSummaryStrip(snapshot: snapshot)
            ConsoleStatGrid(columns: 3, tiles: [
                ConsoleStatTile(title: "傷患總數", value: "\(snapshot.patients.count + snapshot.patientOperationalSummaries.count)", systemImage: "cross.case.fill", accent: CCTheme.danger),
                ConsoleStatTile(title: "待後送", value: "\(pendingEvac)", systemImage: "cross.circle.fill", accent: CCTheme.warning),
                ConsoleStatTile(title: "收治醫院", value: "\(snapshot.hospitalCapacities.count)", systemImage: "building.2.fill", accent: CCTheme.info)
            ])
            ConsoleListSection(title: "各災區傷患分布", systemImage: "chart.bar.fill", accent: CCTheme.command, items: incidentSummaries(snapshot)) { node in
                let total = snapshot.patients.values.filter { $0.incidentID == node.incident.id }.count
                return ConsoleRow(title: node.incident.displayName,
                           subtitle: "傷患 \(total) · 紅 \(node.redPatients)",
                           leadingSystemImage: "cross.case.fill", leadingColor: node.redPatients > 0 ? CCTheme.danger : CCTheme.accent,
                           trailing: AnyView(ConsoleTag("紅 \(node.redPatients)", color: CCTheme.danger)))
            }
        }
    }
}

// MARK: - UCC Phase 7 · AI 戰略分析

struct AIStrategyModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConsoleIntegrationNote(systemImage: "brain.head.profile", title: "AI 戰略資源調度分析",
                                   detail: "AI 以全區災情、資源缺口與 SCC 狀態，產生跨區資源調度與優先序建議，降低高階指揮負荷。戰略推論模型為待接整合；以下為 AI 的即時輸入指標。", tint: CCTheme.command)
            ConsoleStatGrid(columns: 4, tiles: [
                ConsoleStatTile(title: "災區數", value: "\(snapshot.incidents.count)", systemImage: "building.2.fill", accent: CCTheme.command, caption: "跨區協調"),
                ConsoleStatTile(title: "待處理 SOS", value: "\(snapshot.activeSOSCount)", systemImage: "sos.circle.fill", accent: CCTheme.danger, caption: "緊急加權"),
                ConsoleStatTile(title: "受阻任務", value: "\(snapshot.tasks.values.filter { $0.status == .blocked }.count)", systemImage: "exclamationmark.circle.fill", accent: CCTheme.warning, caption: "瓶頸"),
                ConsoleStatTile(title: "資源請求", value: "\(snapshot.purchaseRequests.count)", systemImage: "shippingbox.fill", accent: CCTheme.info, caption: "後勤缺口")
            ])
            ConsoleListSection(title: "AI 戰略決策紀錄", systemImage: "checkmark.seal.fill", accent: CCTheme.command,
                               items: snapshot.decisionRecords.values.sorted { $0.decidedAt > $1.decidedAt }) { d in
                ConsoleRow(title: d.title, subtitle: "\(d.reason) · \(ConsoleFormat.stamp(d.decidedAt))",
                           leadingSystemImage: "brain.head.profile", leadingColor: CCTheme.command)
            }
        }
    }
}

// MARK: - UCC Phase 8 · 熱區分析

struct HeatmapModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        // Per-sector intensity from worksite load + hazard zones.
        struct SectorHeat: Identifiable { let name: String; let worksites: Int; let blocked: Int; let intensity: Int; var id: String { name } }
        let heats: [SectorHeat] = snapshot.sectors.values.map { sector in
            let ws = snapshot.worksites.values.filter { $0.sectorID == sector.id }
            let blocked = ws.filter { $0.status == .blocked || $0.status == .inProgress }.count
            return SectorHeat(name: sector.name, worksites: ws.count, blocked: blocked, intensity: ws.count + blocked * 2)
        }.sorted { $0.intensity > $1.intensity }
        return VStack(alignment: .leading, spacing: 16) {
            ConsoleIntegrationNote(systemImage: "flame.fill", title: "災情熱區分析",
                                   detail: "彙整 SOS、傷患、危險區與工址負載，標示災情高密度熱區供戰略判斷。空間核密度視覺化為待接整合；以下為依分區聚合的熱度指標。", tint: CCTheme.danger)
            ConsoleStatGrid(columns: 4, tiles: [
                ConsoleStatTile(title: "SOS 熱點", value: "\(snapshot.activeSOSCount)", systemImage: "sos.circle.fill", accent: CCTheme.danger),
                ConsoleStatTile(title: "危險區", value: "\(snapshot.safetyZones.values.filter { $0.isActive }.count)", systemImage: "exclamationmark.octagon.fill", accent: CCTheme.warning),
                ConsoleStatTile(title: "紅標傷患", value: "\(snapshot.triageCount(.red))", systemImage: "cross.case.fill", accent: CCTheme.danger),
                ConsoleStatTile(title: "搜救中工址", value: "\(snapshot.worksites.values.filter { $0.status == .inProgress }.count)", systemImage: "magnifyingglass.circle.fill", accent: CCTheme.info)
            ])
            ConsoleListSection(title: "分區熱度排序", systemImage: "flame.fill", accent: CCTheme.danger, items: heats) { h in
                ConsoleRow(title: h.name, subtitle: "工址 \(h.worksites) · 活躍 \(h.blocked)",
                           leadingSystemImage: "flame.fill",
                           leadingColor: h.intensity >= 6 ? CCTheme.danger : (h.intensity >= 3 ? CCTheme.warning : CCTheme.accent),
                           trailing: AnyView(ConsoleTag("熱度 \(h.intensity)", color: h.intensity >= 6 ? CCTheme.danger : CCTheme.warning)))
            }
        }
    }
}

// MARK: - UCC Phase 9 · 資源管理

struct ResourceManagementModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConsoleStatGrid(columns: 3, tiles: [
                ConsoleStatTile(title: "採購請求", value: "\(snapshot.purchaseRequests.count)", systemImage: "shippingbox.fill", accent: CCTheme.info),
                ConsoleStatTile(title: "工時紀錄", value: "\(snapshot.personnelHours.count)", systemImage: "clock.fill", accent: CCTheme.accent),
                ConsoleStatTile(title: "隊伍", value: "\(snapshot.teamCapabilityReports.count)", systemImage: "person.3.fill", accent: CCTheme.command)
            ])
            ConsoleListSection(title: "物資/採購請求", systemImage: "shippingbox.fill", accent: CCTheme.info,
                               items: snapshot.purchaseRequests.values.sorted { $0.itemName < $1.itemName }) { r in
                ConsoleRow(title: "\(r.itemName) ×\(String(format: "%g", r.quantity))",
                           subtitle: r.reason + (r.estimatedCost.map { " · 估價 \(Int($0))" } ?? ""),
                           leadingSystemImage: "shippingbox.fill", leadingColor: CCTheme.info,
                           trailing: AnyView(ConsoleTag(r.status.rawValue, color: CCTheme.muted)))
            }
            ConsoleListSection(title: "人力與隊伍", systemImage: "person.3.fill", accent: CCTheme.command,
                               items: snapshot.teamCapabilityReports.values.sorted { $0.createdAt > $1.createdAt }, maxRows: 12) { r in
                ConsoleRow(title: "\(r.team.teamCode) · \(r.team.teamName)",
                           subtitle: "\(r.team.responseType.consoleLabel) · 人員 \(r.team.totalMembers)",
                           leadingSystemImage: "person.3.fill", leadingColor: CCTheme.command)
            }
        }
    }
}

// MARK: - UCC Phase 10 · EMT 跨區派遣

struct EMTDispatchModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConsoleStatGrid(columns: 3, tiles: [
                ConsoleStatTile(title: "後送請求", value: "\(snapshot.evacuationRequests.count)", systemImage: "cross.circle.fill", accent: CCTheme.danger),
                ConsoleStatTile(title: "待派後送", value: "\(snapshot.evacuationRequests.values.filter { $0.status == .pending }.count)", systemImage: "clock.badge.exclamationmark.fill", accent: CCTheme.warning),
                ConsoleStatTile(title: "收治醫院", value: "\(snapshot.hospitalCapacities.count)", systemImage: "building.2.fill", accent: CCTheme.info)
            ])
            ConsoleListSection(title: "醫療後送派遣", systemImage: "cross.circle.fill", accent: CCTheme.danger,
                               items: snapshot.evacuationRequests.values.sorted { $0.priority > $1.priority }) { e in
                let hospital = e.destinationHospitalID.flatMap { snapshot.hospitalCapacities[$0]?.name }
                return ConsoleRow(title: "後送 \(e.patientID.rawValue)",
                           subtitle: "目的地 \(hospital ?? "未指定") · \(ConsoleFormat.stamp(e.requestedAt))",
                           leadingSystemImage: "cross.circle.fill", leadingColor: e.status.consoleColor,
                           trailing: AnyView(HStack(spacing: 6) {
                               ConsoleTag(e.priority.consoleLabel, color: CCTheme.priorityColor(e.priority))
                               ConsoleTag(e.status.consoleLabel, color: e.status.consoleColor)
                           }))
            }
            ConsoleListSection(title: "醫院容量", systemImage: "building.2.fill", accent: CCTheme.info,
                               items: snapshot.hospitalCapacities.values.sorted { $0.name < $1.name }) { h in
                ConsoleRow(title: h.name,
                           subtitle: "急診 \(h.emergencyCapacity) · 外傷 \(h.traumaCapacity) · 燒燙傷 \(h.burnCapacity) · 兒科 \(h.pediatricCapacity)",
                           leadingSystemImage: "cross.fill", leadingColor: CCTheme.info)
            }
        }
    }
}

// MARK: - UCC Phase 11 · 重型隊調度

struct HeavyTeamDispatchModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let heavy = snapshot.teamCapabilityReports.values.filter { $0.team.responseType == .heavy || $0.team.responseType == .medium }
            .sorted { $0.createdAt > $1.createdAt }
        let rescueTasks = snapshot.tasks.values.filter { $0.type == .rescue && $0.status != .completed && $0.status != .cancelled }
            .sorted { $0.priority > $1.priority }
        return VStack(alignment: .leading, spacing: 16) {
            ConsoleIntegrationNote(systemImage: "figure.2.and.child.holdinghands", title: "USAR 重型隊調度",
                                   detail: "依 INSARAG 分級調派中／重型 USAR 隊伍至大型倒塌現場。下方為已回報能力的隊伍與待派的救援任務。", tint: CCTheme.command)
            ConsoleListSection(title: "可調派重型/中型隊", systemImage: "shield.lefthalf.filled", accent: CCTheme.command, items: heavy) { r in
                ConsoleRow(title: "\(r.team.teamCode) · \(r.team.teamName)",
                           subtitle: "\(r.team.country) · 人員 \(r.team.totalMembers) · \(r.team.classificationStatus.consoleLabel)",
                           leadingSystemImage: "shield.lefthalf.filled", leadingColor: CCTheme.command,
                           trailing: AnyView(ConsoleTag(r.team.responseType.consoleLabel, color: CCTheme.danger)))
            }
            ConsoleListSection(title: "待派救援任務", systemImage: "arrow.triangle.branch", accent: CCTheme.danger, items: rescueTasks) { t in
                ConsoleRow(title: t.summary, subtitle: "隊伍 \(t.assignedTeamID?.rawValue ?? "未指派")",
                           leadingSystemImage: "arrow.triangle.branch", leadingColor: t.status.consoleColor,
                           trailing: AnyView(ConsoleTag(t.priority.consoleLabel, color: CCTheme.priorityColor(t.priority))))
            }
        }
    }
}

// MARK: - UCC Phase 12 · 空拍機管理

struct UAVManagementModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let aerial = snapshot.photoReports.values.sorted { $0.capturedAt > $1.capturedAt }
        return VStack(alignment: .leading, spacing: 16) {
            ConsoleIntegrationNote(systemImage: "airplane.circle.fill", title: "UAV 空拍機資訊整合",
                                   detail: "整合空拍機即時影像、航線與災區俯視圖供空中支援判斷。UAV 遙測/串流閘道為待接整合；以下為現場 GPS 影像回報（可作為空中偵察素材）。", tint: CCTheme.info)
            ConsoleStatGrid(columns: 2, tiles: [
                ConsoleStatTile(title: "影像回報", value: "\(aerial.count)", systemImage: "photo.on.rectangle.angled", accent: CCTheme.info),
                ConsoleStatTile(title: "災區數", value: "\(snapshot.incidents.count)", systemImage: "map.fill", accent: CCTheme.command)
            ])
            ConsoleListSection(title: "空中偵察影像", systemImage: "photo.fill.on.rectangle.fill", accent: CCTheme.info, items: aerial, maxRows: 30) { p in
                ConsoleRow(title: p.caption ?? "影像 \(p.id.rawValue.suffix(6))",
                           subtitle: "\(ConsoleFormat.coordinate(p.location)) · \(ConsoleFormat.stamp(p.capturedAt))",
                           leadingSystemImage: "airplane", leadingColor: CCTheme.info)
            }
        }
    }
}

// MARK: - UCC Phase 13 · PWS 整合

struct PWSIntegrationModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let pwsAlerts = snapshot.alerts.values.filter { [.weather, .collapseRisk, .hazardousMaterial, .evacuation].contains($0.type) }
            .sorted { $0.issuedAt > $1.issuedAt }
        return VStack(alignment: .leading, spacing: 16) {
            ConsoleIntegrationNote(systemImage: "antenna.radiowaves.left.and.right.circle.fill", title: "PWS 地震/災防告警整合",
                                   detail: "接收強震即時警報 (PWS/EEW) 與災防告警細胞廣播，提前推播至全區裝置以爭取應變時間。電信 CBS/PWS 來源為待接整合。", tint: CCTheme.warning)
            ConsoleStatGrid(columns: 2, tiles: [
                ConsoleStatTile(title: "告警事件", value: "\(pwsAlerts.count)", systemImage: "exclamationmark.triangle.fill", accent: CCTheme.warning),
                ConsoleStatTile(title: "已確認回條", value: "\(snapshot.alertAcknowledgements.count)", systemImage: "checkmark.seal.fill", accent: CCTheme.accent)
            ])
            ConsoleListSection(title: "告警與推播", systemImage: "exclamationmark.triangle.fill", accent: CCTheme.warning, items: pwsAlerts) { a in
                ConsoleRow(title: a.title, subtitle: "\(a.type.consoleLabel) · \(ConsoleFormat.stamp(a.issuedAt))",
                           leadingSystemImage: "antenna.radiowaves.left.and.right", leadingColor: CCTheme.priorityColor(a.priority),
                           trailing: AnyView(ConsoleTag(a.priority.consoleLabel, color: CCTheme.priorityColor(a.priority))))
            }
        }
    }
}

// MARK: - UCC Phase 14 · EMIC 整合

struct EMICIntegrationModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        return VStack(alignment: .leading, spacing: 16) {
            ConsoleIntegrationNote(systemImage: "building.2.crop.circle.fill", title: "EMIC 政府災情平台同步",
                                   detail: "與消防署 EMIC／CEOC 同步災情報告、機關訊息與任務派遣，達成跨機關協同。正式 EMIC endpoint、簽章與查證 API 為待接整合；以下為已進入快照的相容資料契約。", tint: CCTheme.command)
            ConsoleStatGrid(columns: 3, tiles: [
                ConsoleStatTile(title: "災情報告", value: "\(snapshot.disasterReports.count)", systemImage: "doc.text.fill", accent: CCTheme.info),
                ConsoleStatTile(title: "機關訊息", value: "\(snapshot.agencyMessages.count)", systemImage: "envelope.fill", accent: CCTheme.accent),
                ConsoleStatTile(title: "CEOC 任務", value: "\(snapshot.ceocMissions.count)", systemImage: "list.bullet.rectangle.fill", accent: CCTheme.command)
            ])
            ConsoleListSection(title: "災情報告 (DisasterReport)", systemImage: "doc.text.fill", accent: CCTheme.info,
                               items: snapshot.disasterReports.values.sorted { $0.createdAt > $1.createdAt }, maxRows: 15) { r in
                ConsoleRow(title: "\(r.kind.consoleLabel)" + (r.summary.map { " · \($0)" } ?? ""),
                           subtitle: "\(ConsoleFormat.coordinate(r.location)) · \(ConsoleFormat.stamp(r.createdAt))" + (r.emicReferenceID.map { " · EMIC \($0)" } ?? ""),
                           leadingSystemImage: "doc.text.fill", leadingColor: CCTheme.priorityColor(r.severity),
                           trailing: AnyView(ConsoleTag(r.verificationStatus.map(verificationLabel) ?? "未查證", color: CCTheme.muted)))
            }
            ConsoleListSection(title: "CEOC 任務派遣", systemImage: "list.bullet.rectangle.fill", accent: CCTheme.command,
                               items: snapshot.ceocMissions.values.sorted { $0.issuedAt > $1.issuedAt }, maxRows: 15) { m in
                ConsoleRow(title: "\(m.missionNumber) · \(m.taskDescription)",
                           subtitle: "\(m.issuingAgency.displayName) → \(m.receivingAgency.displayName) · \(ConsoleFormat.stamp(m.issuedAt))",
                           leadingSystemImage: "arrow.left.arrow.right.circle.fill", leadingColor: CCTheme.command,
                           trailing: AnyView(ConsoleTag(m.priority.consoleLabel, color: CCTheme.priorityColor(m.priority))))
            }
        }
    }

    private func verificationLabel(_ v: VerificationStatus) -> String {
        switch v {
        case .unverified: return "未查證"
        case .pending: return "查證中"
        case .verified: return "已查證"
        case .disputed: return "有爭議"
        }
    }
}

// MARK: - UCC Phase 18 · 多 SCC 監控

struct MultiSCCMonitorModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let nodes = incidentSummaries(snapshot)
        return VStack(alignment: .leading, spacing: 16) {
            ConsoleIntegrationNote(systemImage: "rectangle.3.group.fill", title: "多 SCC 狀態監控",
                                   detail: "監控所有現場指揮中心 (SCC) 節點的連線、人員、SOS 與任務狀態，掌握全區運作健康度。每個事故節點代表一個 SCC 戰術指揮範圍。", tint: CCTheme.command)
            ConsoleStatGrid(columns: 3, tiles: [
                ConsoleStatTile(title: "SCC 節點", value: "\(nodes.count)", systemImage: "rectangle.3.group.fill", accent: CCTheme.command),
                ConsoleStatTile(title: "有 SOS 節點", value: "\(nodes.filter { $0.activeSOS > 0 }.count)", systemImage: "sos.circle.fill", accent: CCTheme.danger),
                ConsoleStatTile(title: "在線人員合計", value: "\(snapshot.onlinePersonnelCount)", systemImage: "person.fill.checkmark", accent: CCTheme.accent)
            ])
            ConsoleListSection(title: "SCC 節點狀態", systemImage: "rectangle.3.group.fill", accent: CCTheme.command, items: nodes) { node in
                let health: Color = node.activeSOS > 0 ? CCTheme.danger : (node.personnelOnline == 0 ? CCTheme.warning : CCTheme.accent)
                let healthLabel = node.activeSOS > 0 ? "緊急" : (node.personnelOnline == 0 ? "無在線" : "正常")
                return ConsoleRow(title: node.incident.displayName,
                           subtitle: "分區 \(node.sectorCount) · 工址 \(node.worksiteCount) · 任務 \(node.openTasks) · 在線 \(node.personnelOnline)",
                           leadingSystemImage: "dot.radiowaves.left.and.right", leadingColor: health,
                           trailing: AnyView(HStack(spacing: 6) {
                               if node.activeSOS > 0 { ConsoleTag("SOS \(node.activeSOS)", color: CCTheme.danger) }
                               ConsoleTag(healthLabel, color: health)
                           }))
            }
        }
    }
}

// MARK: - UCC Phase 19 · AI 風險預測 (二次災害)

struct AIRiskPredictionModule: ConsoleModule {
    let state: MacSystemUIState
    var body: some View {
        let collapseZones = snapshot.safetyZones.values.filter { $0.zoneType == .collapseRisk || $0.zoneType == .hotZone }
            .sorted { $0.severity > $1.severity }
        return VStack(alignment: .leading, spacing: 16) {
            ConsoleIntegrationNote(systemImage: "exclamationmark.triangle.fill", title: "AI 二次災害風險預測",
                                   detail: "以結構危險區、餘震/天氣告警與工址狀態，預測二次倒塌與連鎖風險，提前發布安全管制。風險推論模型與感測來源為待接整合。", tint: CCTheme.danger)
            ConsoleStatGrid(columns: 3, tiles: [
                ConsoleStatTile(title: "倒塌風險區", value: "\(collapseZones.count)", systemImage: "square.stack.3d.down.forward.fill", accent: CCTheme.danger),
                ConsoleStatTile(title: "結構告警", value: "\(snapshot.alerts.values.filter { $0.type == .collapseRisk }.count)", systemImage: "exclamationmark.triangle.fill", accent: CCTheme.warning),
                ConsoleStatTile(title: "受阻工址", value: "\(snapshot.worksites.values.filter { $0.status == .blocked }.count)", systemImage: "xmark.octagon.fill", accent: CCTheme.danger)
            ])
            ConsoleListSection(title: "高風險區域", systemImage: "exclamationmark.octagon.fill", accent: CCTheme.danger, items: collapseZones) { z in
                ConsoleRow(title: z.title, subtitle: "\(z.zoneType.consoleLabel) · 嚴重度 \(z.severity.consoleLabel) · \(ConsoleFormat.stamp(z.updatedAt))",
                           leadingSystemImage: "exclamationmark.octagon.fill", leadingColor: z.zoneType.consoleColor,
                           trailing: AnyView(ConsoleTag(z.isActive ? "監控中" : "解除", color: z.isActive ? CCTheme.danger : CCTheme.muted)))
            }
        }
    }
}
