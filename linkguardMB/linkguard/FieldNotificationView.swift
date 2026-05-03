import SwiftUI

// MARK: - 前線通知 & PWS & 會報整合檢視

struct FieldNotificationView: View {
    @ObservedObject var vm: LinkGuardViewModel

    var body: some View {
        NavigationStack {
            List {
                // PWS 警報
                if !vm.pwsAlerts.isEmpty {
                    Section(header: Label(L("PWS 警報"), systemImage: "exclamationmark.triangle.fill")) {
                        ForEach(vm.pwsAlerts) { alert in
                            HStack(spacing: 10) {
                                Image(systemName: alert.alertType.icon)
                                    .foregroundColor(alert.severity.color)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(alert.title).font(.headline)
                                        if alert.isActive {
                                            Text(L("活躍")).font(.caption2).bold()
                                                .padding(.horizontal, 4).padding(.vertical, 2)
                                                .background(NV.danger)
                                                .foregroundColor(.white)
                                                .cornerRadius(4)
                                        }
                                    }
                                    Text(alert.content)
                                        .font(.caption).foregroundColor(.secondary)
                                    HStack {
                                        Text(alert.severity.label)
                                            .font(.caption2).bold()
                                            .foregroundColor(alert.severity.color)
                                        Text("· \(alert.publisher)")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                // 會報
                if !vm.briefings.isEmpty {
                    Section(header: Label(L("會報"), systemImage: "doc.text.fill")) {
                        ForEach(vm.briefings) { report in
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
                                ForEach(report.sections.indices, id: \.self) { i in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(report.sections[i].title)
                                            .font(.caption).bold()
                                        Text(report.sections[i].content)
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                Text("by \(report.author)")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // HQ 廣播記錄
                if !vm.textBroadcasts.isEmpty {
                    Section(header: Label(L("HQ 廣播"), systemImage: "megaphone.fill")) {
                        ForEach(vm.textBroadcasts) { broadcast in
                            HStack(spacing: 10) {
                                Image(systemName: broadcast.priority == "urgent" ? "exclamationmark.bubble.fill" : "megaphone.fill")
                                    .foregroundColor(broadcast.priority == "urgent" ? NV.danger : NV.command)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(broadcast.message)
                                        .font(.subheadline)
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
                    }
                }

                // 個人通知
                Section(header: Label(L("個人通知"), systemImage: "bell.fill")) {
                    if vm.personalNotifications.isEmpty {
                        Text(L("無通知"))
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(vm.personalNotifications) { notif in
                            HStack(spacing: 10) {
                                Image(systemName: notif.isRead ? "bell" : "bell.badge.fill")
                                    .foregroundColor(notif.isRead ? .secondary : NV.info)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(notif.title).font(.headline)
                                        .foregroundColor(notif.isRead ? .secondary : .primary)
                                    Text(notif.content)
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if !notif.isRead {
                                    Button {
                                        vm.markNotificationAsRead(notif.id)
                                    } label: {
                                        Text(L("已讀")).font(.caption2)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(NV.info)
                                }
                            }
                        }
                    }
                }

                // 人員配置
                if !vm.personnelAssignments.isEmpty {
                    Section(header: Label(L("人員配置"), systemImage: "person.3.fill")) {
                        ForEach(vm.personnelAssignments) { assign in
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
                    }
                }
            }
            .navigationTitle(L("前線動態通知"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .contentMargins(.top, 0, for: .scrollContent)
        }
    }

    private func broadcastTimeText(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d HH:mm"
        return fmt.string(from: date)
    }
}
