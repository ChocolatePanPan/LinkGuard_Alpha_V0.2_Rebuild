import SwiftUI

// MARK: - 前線通知 & PWS & 會報整合檢視

struct FieldNotificationView: View {
    @ObservedObject var vm: LinkGuardViewModel

    var body: some View {
        NavigationStack {
            List {
                // ── 統一活動記錄（主要）──
                Section(header: Label(L("所有通知"), systemImage: "list.bullet.rectangle.fill")) {
                    if vm.activityLog.isEmpty {
                        Text(L("暫無記錄"))
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(vm.activityLog) { entry in
                            NavigationLink {
                                activityDetail(entry)
                            } label: {
                                activityRow(entry)
                            }
                        }
                    }
                }

                // 個人通知（詳細）
                if !vm.personalNotifications.isEmpty {
                    Section(header: Label(L("個人通知"), systemImage: "bell.fill")) {
                        ForEach(vm.personalNotifications) { notif in
                            NavigationLink {
                                personalNotificationDetail(notif)
                                    .onAppear {
                                        if !notif.isRead { vm.markNotificationAsRead(notif.id) }
                                    }
                            } label: {
                                personalNotificationRow(notif)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if !notif.isRead {
                                    Button(L("已讀")) {
                                        vm.markNotificationAsRead(notif.id)
                                    }
                                    .tint(NV.info)
                                }
                            }
                        }
                    }
                }

                // HQ 廣播記錄
                if !vm.textBroadcasts.isEmpty {
                    Section(header: Label(L("HQ 廣播"), systemImage: "megaphone.fill")) {
                        ForEach(vm.textBroadcasts) { broadcast in
                            NavigationLink {
                                textBroadcastDetail(broadcast)
                            } label: {
                                textBroadcastRow(broadcast)
                            }
                        }
                    }
                }

                // HQ 決策
                if !vm.decisions.isEmpty {
                    Section(header: Label(L("HQ 決策"), systemImage: "checkmark.seal.fill")) {
                        ForEach(vm.decisions) { decision in
                            NavigationLink {
                                decisionDetail(decision)
                            } label: {
                                decisionRow(decision)
                            }
                        }
                    }
                }

                // PWS 警報
                if !vm.pwsAlerts.isEmpty {
                    Section(header: Label(L("PWS 警報"), systemImage: "exclamationmark.triangle.fill")) {
                        ForEach(vm.pwsAlerts) { alert in
                            NavigationLink {
                                pwsAlertDetail(alert)
                            } label: {
                                pwsAlertRow(alert)
                            }
                        }
                    }
                }

                // 會報
                if !vm.briefings.isEmpty {
                    Section(header: Label(L("會報"), systemImage: "doc.text.fill")) {
                        ForEach(vm.briefings) { report in
                            NavigationLink {
                                briefingDetail(report)
                            } label: {
                                briefingRow(report)
                            }
                        }
                    }
                }

                // 人員配置
                if !vm.personnelAssignments.isEmpty {
                    Section(header: Label(L("人員配置"), systemImage: "person.3.fill")) {
                        ForEach(vm.personnelAssignments) { assign in
                            NavigationLink {
                                personnelAssignmentDetail(assign)
                            } label: {
                                personnelAssignmentRow(assign)
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("前線動態通知"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .contentMargins(.top, 0, for: .scrollContent)
        }
    }

    @ViewBuilder
    private func activityRow(_ entry: ActivityLogEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.kind.icon)
                .foregroundColor(kindColor(entry.kind))
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.title)
                        .font(.subheadline).bold()
                        .lineLimit(1)
                    Spacer()
                    Text(entry.timeText)
                        .font(.caption2).foregroundColor(.secondary)
                }
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private func personalNotificationRow(_ notif: PersonalNotification) -> some View {
        HStack(spacing: 10) {
            Image(systemName: notif.isRead ? "bell" : "bell.badge.fill")
                .foregroundColor(notif.isRead ? .secondary : NV.info)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(notif.title).font(.headline)
                        .foregroundColor(notif.isRead ? .secondary : .primary)
                    Spacer()
                    Text(notif.timeText)
                        .font(.caption2).foregroundColor(.secondary)
                }
                Text(notif.content)
                    .font(.caption).foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func textBroadcastRow(_ broadcast: TextBroadcast) -> some View {
        HStack(spacing: 10) {
            Image(systemName: broadcast.priority == "urgent" ? "exclamationmark.bubble.fill" : "megaphone.fill")
                .foregroundColor(broadcast.priority == "urgent" ? NV.danger : NV.command)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(broadcast.message)
                    .font(.subheadline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(broadcast.senderName)
                        .font(.caption2).foregroundColor(.secondary)
                    Text("·")
                        .font(.caption2).foregroundColor(.secondary)
                    Text(broadcastTimeText(broadcast.timestamp))
                        .font(.caption2).foregroundColor(.secondary)
                }
                if broadcast.priority == "urgent" {
                    Text(L("緊急"))
                        .font(.caption2).bold()
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(NV.danger.opacity(0.3))
                        .foregroundColor(NV.danger)
                        .cornerRadius(4)
                }
            }
        }
    }

    @ViewBuilder
    private func decisionRow(_ decision: HQDecision) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(NV.command)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(decision.model.isEmpty ? L("HQ 決策") : decision.model)
                        .font(.caption).bold()
                        .foregroundColor(NV.command)
                    Spacer()
                    Text(broadcastTimeText(decision.receivedAt))
                        .font(.caption2).foregroundColor(.secondary)
                }
                Text(decision.decision)
                    .font(.subheadline)
                    .lineLimit(3)
            }
        }
    }

    @ViewBuilder
    private func pwsAlertRow(_ alert: PWSAlert) -> some View {
        HStack(spacing: 10) {
            Image(systemName: alert.alertType.icon)
                .foregroundColor(NV.danger)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(alert.title).font(.headline)
                    Spacer()
                    Text(tsText(alert.publishTime))
                        .font(.caption2).foregroundColor(.secondary)
                }
                if alert.isActive {
                    Text(L("活躍")).font(.caption2).bold()
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(NV.danger)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
                Text(alert.content)
                    .font(.caption).foregroundColor(.secondary)
                    .lineLimit(2)
                HStack {
                    Text(alert.severity.label)
                        .font(.caption2).bold()
                        .foregroundColor(NV.danger)
                    Text("· \(alert.publisher)")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func briefingRow(_ report: BriefingReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(NV.info)
                Text(report.title).font(.headline)
                Spacer()
                Text(report.type.label)
                    .font(.caption2).bold()
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(NV.info.opacity(0.2))
                    .cornerRadius(4)
            }
            ForEach(report.sections.prefix(2).indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.sections[i].title)
                        .font(.caption).bold()
                    Text(report.sections[i].content)
                        .font(.caption2).foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Text("by \(report.author) · \(report.timeText)")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func personnelAssignmentRow(_ assign: PersonnelAssignment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: assign.role.icon)
                .foregroundColor(NV.info)
            VStack(alignment: .leading, spacing: 2) {
                Text(assign.name).font(.subheadline).bold()
                HStack(spacing: 6) {
                    Text(assign.role.label)
                        .font(.caption2).bold()
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(NV.info.opacity(0.2))
                        .cornerRadius(4)
                    if !assign.assignedZone.isEmpty { Text(assign.assignedZone).font(.caption2).foregroundColor(.secondary) }
                    if !assign.assignedFloor.isEmpty { Text(assign.assignedFloor).font(.caption2).foregroundColor(.secondary) }
                }
            }
        }
    }

    @ViewBuilder
    private func activityDetail(_ entry: ActivityLogEntry) -> some View {
        if entry.title.contains(L("災情")), let site = vm.disasterSite {
            DisasterNotificationDetailView(site: site, receivedAt: entry.timestamp)
        } else {
            NotificationDetailView(
                title: entry.title,
                subtitle: entry.timeText,
                icon: entry.kind.icon,
                color: kindColor(entry.kind),
                sections: [
                    NotificationDetailSection(
                        title: L("通知資料"),
                        rows: detailRows([
                            (L("類型"), entry.kind.rawValue),
                            (L("時間"), detailTimeText(entry.timestamp)),
                            (L("標題"), entry.title)
                        ]),
                        body: entry.detail
                    )
                ]
            )
        }
    }

    private func personalNotificationDetail(_ notif: PersonalNotification) -> some View {
        NotificationDetailView(
            title: notif.title,
            subtitle: notif.timeText,
            icon: notif.isRead ? "bell" : "bell.badge.fill",
            color: notif.isRead ? .secondary : NV.info,
            sections: [
                NotificationDetailSection(
                    title: L("通知資料"),
                    rows: detailRows([
                        (L("狀態"), notif.isRead ? L("已讀") : L("未讀")),
                        (L("時間"), detailTimestampText(notif.timestamp)),
                        (L("目標裝置"), notif.targetDeviceID),
                        (L("通知 ID"), notif.id)
                    ]),
                    body: notif.content
                )
            ]
        )
    }

    private func textBroadcastDetail(_ broadcast: TextBroadcast) -> some View {
        NotificationDetailView(
            title: L("HQ 廣播"),
            subtitle: broadcastTimeText(broadcast.timestamp),
            icon: broadcast.priority == "urgent" ? "exclamationmark.bubble.fill" : "megaphone.fill",
            color: broadcast.priority == "urgent" ? NV.danger : NV.command,
            sections: [
                NotificationDetailSection(
                    title: L("廣播資料"),
                    rows: detailRows([
                        (L("發送者"), broadcast.senderName),
                        (L("優先級"), broadcast.priority == "urgent" ? L("緊急") : L("一般")),
                        (L("時間"), detailTimeText(broadcast.timestamp)),
                        (L("廣播 ID"), broadcast.broadcastId)
                    ]),
                    body: broadcast.message
                )
            ]
        )
    }

    private func decisionDetail(_ decision: HQDecision) -> some View {
        var sections = [
            NotificationDetailSection(
                title: L("決策資料"),
                rows: detailRows([
                    (L("模型"), decision.model),
                    (L("觸發來源"), decision.trigger),
                    (L("收到時間"), detailTimeText(decision.receivedAt)),
                    (L("決策時間"), decision.timestamp),
                    (L("決策 ID"), decision.decisionId),
                    (L("請求 ID"), decision.requestId),
                    (L("升級狀態"), decision.escalationStatus),
                    (L("佇列位置"), decision.queuePosition.map(String.init))
                ]),
                body: decision.decision
            )
        ]
        if !decision.patients.isEmpty {
            let patientText = decision.patients.map { patient in
                [patient.id, patient.priority, patient.location, patient.reason]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
            }.joined(separator: "\n")
            sections.append(NotificationDetailSection(title: L("相關傷員"), rows: [], body: patientText))
        }
        return NotificationDetailView(
            title: L("HQ 決策"),
            subtitle: broadcastTimeText(decision.receivedAt),
            icon: "checkmark.seal.fill",
            color: NV.command,
            sections: sections
        )
    }

    private func pwsAlertDetail(_ alert: PWSAlert) -> some View {
        NotificationDetailView(
            title: alert.title,
            subtitle: alert.severity.label,
            icon: alert.alertType.icon,
            color: NV.danger,
            sections: [
                NotificationDetailSection(
                    title: L("警報資料"),
                    rows: detailRows([
                        (L("類型"), alert.alertType.label),
                        (L("嚴重度"), alert.severity.label),
                        (L("狀態"), alert.isActive ? L("活躍") : L("已解除")),
                        (L("發布者"), alert.publisher),
                        (L("發布時間"), detailTimestampText(alert.publishTime)),
                        (L("到期時間"), alert.expireTime.map(detailTimestampText)),
                        (L("警報 ID"), alert.id)
                    ]),
                    body: alert.content
                )
            ]
        )
    }

    private func briefingDetail(_ report: BriefingReport) -> some View {
        var sections = [
            NotificationDetailSection(
                title: L("會報資料"),
                rows: detailRows([
                    (L("類型"), report.type.label),
                    (L("作者"), report.author),
                    (L("時間"), detailTimestampText(report.timestamp)),
                    (L("會報 ID"), report.id)
                ]),
                body: nil
            )
        ]
        sections.append(contentsOf: report.sections.map { section in
            NotificationDetailSection(
                title: section.title.isEmpty ? L("內容") : section.title,
                rows: [],
                body: section.content
            )
        })
        return NotificationDetailView(
            title: report.title,
            subtitle: report.type.label,
            icon: "doc.text.fill",
            color: NV.info,
            sections: sections
        )
    }

    private func personnelAssignmentDetail(_ assign: PersonnelAssignment) -> some View {
        NotificationDetailView(
            title: assign.name,
            subtitle: assign.role.label,
            icon: assign.role.icon,
            color: NV.info,
            sections: [
                NotificationDetailSection(
                    title: L("人員資料"),
                    rows: detailRows([
                        (L("姓名"), assign.name),
                        (L("暱稱"), assign.nickname),
                        (L("角色"), assign.role.label),
                        (L("負責區域"), assign.assignedZone),
                        (L("樓層"), assign.assignedFloor),
                        (L("時間"), detailTimestampText(assign.timestamp)),
                        (L("人員 ID"), assign.id)
                    ]),
                    body: nil
                )
            ]
        )
    }

    private func kindColor(_ kind: ActivityKind) -> Color {
        switch kind {
        case .sentMessage:          return NV.command
        case .receivedMessage:      return NV.info
        case .personalNotification: return NV.info
        case .command:              return NV.command
        case .hqDecision:           return NV.command
        case .pwsAlert:             return NV.danger
        case .briefing:             return NV.info
        case .broadcast:            return NV.command
        case .sos:                  return NV.danger
        case .reinforcement:        return NV.danger
        case .hazard:               return NV.danger
        case .patientWarning:       return NV.danger
        case .deviceAlert:          return NV.danger
        case .task:                 return NV.command
        case .timer:                return NV.danger
        case .patientReport:        return NV.info
        case .quickStatus:          return NV.command
        }
    }

    private func broadcastTimeText(_ date: Date) -> String {
        let fmt = Calendar.current.isDateInToday(date) ? LGDateFormat.hm : LGDateFormat.mdHmShort
        return fmt.string(from: date)
    }

    private func detailTimeText(_ date: Date) -> String {
        LGDateFormat.mdHm.string(from: date)
    }

    private func tsText(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let fmt = Calendar.current.isDateInToday(date) ? LGDateFormat.hm : LGDateFormat.mdHmShort
        return fmt.string(from: date)
    }

    private func detailTimestampText(_ timestamp: Double) -> String {
        guard timestamp > 0 else { return "" }
        return detailTimeText(Date(timeIntervalSince1970: timestamp))
    }

    private func detailRows(_ rows: [(String, String?)]) -> [NotificationDetailRow] {
        rows.compactMap { label, value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return NotificationDetailRow(label: label, value: value)
        }
    }

    // MARK: - 全部通知彙總

    @ViewBuilder
    func allNotificationsView() -> some View {
        List {
            // 個人通知
            if !vm.personalNotifications.isEmpty {
                Section(header: Label(L("個人通知"), systemImage: "bell.fill")) {
                    ForEach(vm.personalNotifications) { notif in
                        NavigationLink {
                            personalNotificationDetail(notif)
                                .onAppear { if !notif.isRead { vm.markNotificationAsRead(notif.id) } }
                        } label: {
                            personalNotificationRow(notif)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !notif.isRead {
                                Button(L("已讀")) { vm.markNotificationAsRead(notif.id) }
                                    .tint(NV.info)
                            }
                        }
                    }
                }
            }

            // HQ 廣播
            if !vm.textBroadcasts.isEmpty {
                Section(header: Label(L("HQ 廣播"), systemImage: "megaphone.fill")) {
                    ForEach(vm.textBroadcasts) { broadcast in
                        NavigationLink {
                            textBroadcastDetail(broadcast)
                        } label: {
                            textBroadcastRow(broadcast)
                        }
                    }
                }
            }

            // HQ 決策
            if !vm.decisions.isEmpty {
                Section(header: Label(L("HQ 決策"), systemImage: "checkmark.seal.fill")) {
                    ForEach(vm.decisions) { decision in
                        NavigationLink {
                            decisionDetail(decision)
                        } label: {
                            decisionRow(decision)
                        }
                    }
                }
            }

            // PWS 警報
            if !vm.pwsAlerts.isEmpty {
                Section(header: Label(L("PWS 警報"), systemImage: "exclamationmark.triangle.fill")) {
                    ForEach(vm.pwsAlerts) { alert in
                        NavigationLink {
                            pwsAlertDetail(alert)
                        } label: {
                            pwsAlertRow(alert)
                        }
                    }
                }
            }

            // 會報
            if !vm.briefings.isEmpty {
                Section(header: Label(L("會報"), systemImage: "doc.text.fill")) {
                    ForEach(vm.briefings) { report in
                        NavigationLink {
                            briefingDetail(report)
                        } label: {
                            briefingRow(report)
                        }
                    }
                }
            }

            // 人員配置
            if !vm.personnelAssignments.isEmpty {
                Section(header: Label(L("人員配置"), systemImage: "person.3.fill")) {
                    ForEach(vm.personnelAssignments) { assign in
                        NavigationLink {
                            personnelAssignmentDetail(assign)
                        } label: {
                            personnelAssignmentRow(assign)
                        }
                    }
                }
            }

            // 活動記錄
            if !vm.activityLog.isEmpty {
                Section(header: Label(L("活動記錄"), systemImage: "list.bullet.rectangle")) {
                    ForEach(vm.activityLog) { entry in
                        NavigationLink {
                            activityDetail(entry)
                        } label: {
                            activityRow(entry)
                        }
                    }
                }
            }

            if vm.personalNotifications.isEmpty && vm.textBroadcasts.isEmpty &&
               vm.decisions.isEmpty && vm.pwsAlerts.isEmpty &&
               vm.briefings.isEmpty && vm.personnelAssignments.isEmpty && vm.activityLog.isEmpty {
                Section {
                    Text(L("暫無任何通知"))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(L("所有通知"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NotificationDetailRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

private struct NotificationDetailSection: Identifiable {
    let id = UUID()
    let title: String
    let rows: [NotificationDetailRow]
    let body: String?
}

private struct NotificationDetailView: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let sections: [NotificationDetailSection]

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(color)
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            ForEach(sections) { section in
                Section(header: Text(section.title)) {
                    ForEach(section.rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.label)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(row.value)
                                .font(.body)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                    if let body = section.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
                        Text(body)
                            .font(.body)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(L("通知詳情"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 災情通知詳情

private struct DisasterNotificationDetailView: View {
    let site: DisasterSite
    let receivedAt: Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // 收到時間
                GroupBox(label: Label(L("通知資訊"), systemImage: "bell.badge.fill")) {
                    HStack {
                        Text(L("收到時間")).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(LGDateFormat.mdHm.string(from: receivedAt)).bold()
                    }
                    if site.lastUpdated > 0 {
                        HStack {
                            Text(L("資料更新")).font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(LGDateFormat.mdHm.string(from: Date(timeIntervalSince1970: site.lastUpdated))).bold()
                        }
                    }
                }

                // 建物資訊
                GroupBox(label: Label(L("建物資訊"), systemImage: "building.2")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !site.buildingName.isEmpty {
                            HStack {
                                Text(L("名稱")).font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Text(site.buildingName).bold()
                            }
                        }
                        if !site.address.isEmpty {
                            HStack {
                                Text(L("地址")).font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Text(site.address)
                            }
                        }
                        HStack {
                            Text(L("倒塌類型")).font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(site.collapseType.label).bold().foregroundColor(NV.warning)
                        }
                        HStack {
                            Text(L("影響樓層")).font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(L("地上 %lldF / 地下 %lldF", site.aboveGroundFloors, site.undergroundFloors)).bold()
                        }
                    }
                }

                // 樓層狀態
                if !site.floors.isEmpty {
                    GroupBox(label: Label(L("樓層狀態"), systemImage: "square.stack.3d.up")) {
                        VStack(spacing: 6) {
                            ForEach(site.floors) { floor in
                                HStack {
                                    Text(floor.id).font(.headline).frame(width: 40)
                                    Text(floor.condition.label)
                                        .font(.caption).bold()
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(floor.condition.color.opacity(0.2))
                                        .foregroundColor(floor.condition.color)
                                        .cornerRadius(4)
                                    Spacer()
                                    if !floor.note.isEmpty {
                                        Text(floor.note).font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                // 救援分區
                if !site.zones.isEmpty {
                    GroupBox(label: Label(L("救援分區"), systemImage: "map")) {
                        VStack(spacing: 6) {
                            ForEach(site.zones) { zone in
                                HStack {
                                    Text(zone.name).font(.subheadline).bold()
                                    Spacer()
                                    Text(zone.status.label)
                                        .font(.caption).bold()
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(zone.status.color.opacity(0.2))
                                        .foregroundColor(zone.status.color)
                                        .cornerRadius(4)
                                    if !zone.assignedPersonnel.isEmpty {
                                        Text(zone.assignedPersonnel.joined(separator: ", "))
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                // 已知危害
                if !site.hazards.isEmpty {
                    GroupBox(label: Label(L("已知危害"), systemImage: "exclamationmark.shield")) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 6) {
                            ForEach(site.hazards, id: \.self) { hazard in
                                HStack(spacing: 4) {
                                    Image(systemName: hazard.icon)
                                    Text(hazard.label).font(.caption)
                                }
                                .padding(6)
                                .background(hazard.color.opacity(0.15))
                                .foregroundColor(hazard.color)
                                .cornerRadius(6)
                            }
                        }
                    }
                }

                // 出入口
                if !site.entryPoints.isEmpty {
                    GroupBox(label: Label(L("出入口"), systemImage: "door.left.hand.open")) {
                        VStack(spacing: 6) {
                            ForEach(site.entryPoints) { entry in
                                HStack {
                                    Image(systemName: entry.isAccessible ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(entry.isAccessible ? NV.green : NV.danger)
                                    Text(entry.name)
                                    Spacer()
                                    Text(entry.isAccessible ? L("可通行") : L("封閉"))
                                        .font(.caption)
                                        .foregroundColor(entry.isAccessible ? NV.green : NV.danger)
                                }
                            }
                        }
                    }
                }

                // 集結點
                if !site.rallyPoint.isEmpty {
                    GroupBox(label: Label(L("集結點"), systemImage: "flag.fill")) {
                        Text(site.rallyPoint).font(.headline)
                    }
                }

                // 備註
                if !site.note.isEmpty {
                    GroupBox(label: Label(L("備註"), systemImage: "note.text")) {
                        Text(site.note).textSelection(.enabled)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(L("災情詳情"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
