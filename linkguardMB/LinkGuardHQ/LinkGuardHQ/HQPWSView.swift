import SwiftUI

struct HQPWSView: View {
    @ObservedObject var vm: HQViewModel
    @State private var showAddSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 活躍警報
                let active = vm.pwsAlerts.filter(\.isActive)
                if !active.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L("活躍警報"), systemImage: "exclamationmark.triangle.fill")
                            .font(.headline).foregroundColor(NV.danger)
                        ForEach(active) { alert in
                            PWSAlertCard(alert: alert, isActive: true) {
                                vm.deactivatePWSAlert(alert.id)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // 歷史警報
                let inactive = vm.pwsAlerts.filter { !$0.isActive }
                if !inactive.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L("歷史警報"), systemImage: "clock")
                            .font(.headline).foregroundColor(.secondary)
                        ForEach(inactive) { alert in
                            PWSAlertCard(alert: alert, isActive: false, onDeactivate: nil)
                        }
                    }
                    .padding(.horizontal)
                }

                if vm.pwsAlerts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 40)).foregroundColor(.secondary)
                        Text(L("目前無 PWS 警報"))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(L("PWS 警報"))
        .overlay(alignment: .bottomLeading) {
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(vm.server.isRunning ? NV.danger : Color.gray)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .padding(24)
            .disabled(!vm.server.isRunning)
            .help(L("新增 PWS 警報"))
        }
        .sheet(isPresented: $showAddSheet) {
            AddPWSAlertSheet(vm: vm)
        }
    }
}

struct PWSAlertCard: View {
    let alert: PWSAlert
    let isActive: Bool
    let onDeactivate: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: alert.alertType.icon)
                    .foregroundColor(alert.severity.color)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(.headline)
                    Text(alert.alertType.label)
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text(alert.severity.label)
                    .font(.caption).bold()
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(alert.severity.color.opacity(NV.tagOpacity))
                    .foregroundColor(alert.severity.color)
                    .cornerRadius(NV.tagRadius)
            }

            Text(alert.content)
                .font(.subheadline).foregroundColor(.secondary)

            HStack {
                Text(L("來源: %@", alert.publisher))
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text(timeText)
                    .font(.caption2).foregroundColor(.secondary)
                if isActive, let onDeactivate {
                    Button(L("解除")) { onDeactivate() }
                        .font(.caption).tint(NV.warning)
                }
            }
        }
        .padding()
        .background(isActive ? alert.severity.color.opacity(0.05) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: NV.cardRadius)
                .stroke(isActive ? alert.severity.color.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: NV.strokeWidth)
        )
        .cornerRadius(NV.cardRadius)
    }

    private var timeText: String {
        let date = Date(timeIntervalSince1970: alert.publishTime)
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }
}

// MARK: - 新增 PWS 警報

struct AddPWSAlertSheet: View {
    @ObservedObject var vm: HQViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var alertType: PWSAlertType = .earthquake
    @State private var severity: PWSSeverity = .moderate
    @State private var title = ""
    @State private var detail = ""
    @State private var source = "手動輸入"

    var body: some View {
        NavigationStack {
            Form {
                Section(L("警報類型")) {
                    Picker(L("類型"), selection: $alertType) {
                        ForEach(PWSAlertType.allCases, id: \.self) { t in
                            Label(t.label, systemImage: t.icon).tag(t)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("嚴重程度"))
                            .font(.subheadline).foregroundColor(.secondary)
                        Picker(L("嚴重程度"), selection: $severity) {
                            ForEach(PWSSeverity.allCases, id: \.self) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }
                Section(L("警報內容")) {
                    TextField(L("標題"), text: $title)
                    TextField(L("詳情"), text: $detail, axis: .vertical)
                        .lineLimit(2...5)
                    TextField(L("來源"), text: $source)
                }
                Section(L("傳送目標")) {
                    HStack {
                        Image(systemName: vm.targetMode == .broadcast ? "antenna.radiowaves.left.and.right" : "person.2.circle")
                            .foregroundColor(NV.command)
                        Text(vm.targetMode == .broadcast ? L("全體廣播") : L("指定 %lld 台裝置", vm.selectedTargetDeviceIDs.count))
                            .font(.subheadline)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L("新增 PWS 警報"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("發送")) {
                        let alert = PWSAlert(
                            alertType: alertType,
                            title: title,
                            content: detail,
                            severity: severity,
                            publisher: source
                        )
                        vm.addPWSAlert(alert)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}
