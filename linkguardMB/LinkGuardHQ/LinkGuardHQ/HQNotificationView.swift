import SwiftUI

struct HQNotificationView: View {
    @ObservedObject var vm: HQViewModel
    @State private var showSendSheet = false

    var body: some View {
        HQPage {
            HQPageTitleBar(L("個人通知"), icon: "bell.fill", accent: NV.reinforce) {
                Text(L("%lld 則通知", vm.personalNotifications.count))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            if vm.personalNotifications.isEmpty {
                HQEmptyStateView(icon: "bell", title: L("尚未發送個人通知"))
                    .hqPanelChrome(accent: NV.reinforce)
            } else {
                LazyVStack(spacing: NV.panelSpacing) {
                    ForEach(vm.personalNotifications) { notif in
                        NotificationCard(notification: notif)
                    }
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            Button {
                showSendSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(vm.server.isRunning ? NV.reinforce : Color.gray)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .padding(24)
            .disabled(!vm.server.isRunning)
            .help(L("發送個人通知"))
        }
        .sheet(isPresented: $showSendSheet) {
            SendNotificationSheet(vm: vm)
        }
    }
}

struct NotificationCard: View {
    let notification: PersonalNotification

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.fill")
                .foregroundColor(NV.info)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(notification.title)
                        .font(.headline)
                    Spacer()
                    Text(timeText)
                        .font(.caption2).foregroundColor(.secondary)
                }
                Text(notification.content)
                    .font(.subheadline).foregroundColor(.secondary)
                Text("→ \(notification.targetDeviceID)")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    private var timeText: String {
        let date = Date(timeIntervalSince1970: notification.timestamp)
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }
}

// MARK: - 發送通知

struct SendNotificationSheet: View {
    @ObservedObject var vm: HQViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var targetDeviceID = ""
    @State private var title = ""
    @State private var content = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(L("目標")) {
                    if vm.server.fieldUnits.isEmpty {
                        Text(L("無連線裝置")).foregroundColor(.secondary)
                    } else {
                        Picker(L("裝置"), selection: $targetDeviceID) {
                            Text(L("選擇裝置")).tag("")
                            ForEach(vm.server.fieldUnits) { unit in
                                Text("\(unit.deviceID) (\(unit.deptCode))").tag(unit.deviceID)
                            }
                        }
                    }
                }
                Section(L("內容")) {
                    TextField(L("標題"), text: $title)
                    TextField(L("訊息"), text: $content, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L("發送個人通知"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("發送")) {
                        let notif = PersonalNotification(
                            targetDeviceID: targetDeviceID,
                            title: title,
                            content: content
                        )
                        vm.sendNotification(notif)
                        dismiss()
                    }
                    .disabled(title.isEmpty || targetDeviceID.isEmpty)
                }
            }
        }
    }
}
