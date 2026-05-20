import SwiftUI

// MARK: - HQ 傷患惡化預警儀表板

struct HQPatientWarningView: View {
    @ObservedObject var vm: HQViewModel

    var body: some View {
        HQPage {
            HQPageTitleBar(L("傷患惡化預警"), icon: "heart.text.square", accent: NV.danger) {
                let urgentCount = vm.patientWarnings.filter { $0.triageLevel == "RED" }.count
                HStack(spacing: 10) {
                    if urgentCount > 0 {
                        Label(L("%lld 危急", urgentCount), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .foregroundColor(NV.danger)
                    }
                    Text(L("%lld 則預警", vm.patientWarnings.count))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            if vm.patientWarnings.isEmpty {
                HQEmptyStateView(icon: "heart.text.square", title: L("目前無傷患惡化預警"))
                    .hqPanelChrome(accent: NV.danger)
            } else {
                LazyVStack(spacing: NV.panelSpacing) {
                    ForEach(vm.patientWarnings) { warning in
                        HQPatientWarningRow(
                            warning: warning,
                            onDismiss: { vm.dismissPatientWarning(warning.id) }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - 預警列

struct HQPatientWarningRow: View {
    let warning: HQPatientWarning
    var onDismiss: () -> Void

    private var levelColor: Color {
        switch warning.triageLevel.uppercased() {
        case "RED": return NV.danger
        case "YELLOW": return NV.warning
        case "GREEN": return NV.green
        default: return .secondary
        }
    }

    private var levelText: String {
        switch warning.triageLevel.uppercased() {
        case "RED": return L("危急")
        case "YELLOW": return L("中度")
        case "GREEN": return L("輕度")
        default: return warning.triageLevel
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 嚴重度指示條
            RoundedRectangle(cornerRadius: 3)
                .fill(levelColor)
                .frame(width: 6)

            VStack(alignment: .leading, spacing: 6) {
                // 頂部：患者名 + 等級 + 時間
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(levelColor)
                    Text(warning.patientName)
                        .font(.headline)
                    Text(levelText)
                        .font(.caption).bold()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(levelColor.opacity(0.2))
                        .cornerRadius(4)

                    Spacer()

                    Text(L("%lld 分鐘前檢傷", warning.minutesSinceTriage))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // 預警訊息
                Text(warning.warningMessage)
                    .font(.body)
                    .foregroundColor(levelColor)

                // 底部：患者 ID + 操作
                HStack {
                    Text("ID: \(warning.patientId)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        onDismiss()
                    } label: {
                        Label(L("確認"), systemImage: "checkmark")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(NV.green)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(levelColor.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(levelColor.opacity(0.3))
        )
    }
}
