import SwiftUI
import LinkGuardV03Core

public struct MacSystemIdentityPickerOverlayView: View {
    @Binding var macState: MacSystemUIState
    @State private var errorMessage: String? = nil
    private let directory = AccountDirectory.demo

    private let identityOptions = [
        IdentityOption(identifier: "IC-01", title: "事故指揮官", section: "Incident Commander"),
        IdentityOption(identifier: "CS-01", title: "指揮幕僚", section: "Command Staff"),
        IdentityOption(identifier: "OPS-01", title: "作業組長", section: "Operations Section"),
        IdentityOption(identifier: "PLAN-01", title: "計畫組長", section: "Planning Section"),
        IdentityOption(identifier: "LOG-01", title: "後勤組長", section: "Logistics Section"),
        IdentityOption(identifier: "FIN-01", title: "財務行政組長", section: "Finance/Admin Section")
    ]

    public init(macState: Binding<MacSystemUIState>) {
        self._macState = macState
    }

    private var availableIdentityOptions: [IdentityOption] {
        identityOptions.filter { option in
            guard let account = try? directory.account(for: option.identifier) else { return false }
            return account.status == .active && account.canUse(appID: macState.runtime.device.appID)
        }
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 24) {
                VStack(spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.title)
                            .foregroundColor(NV.green)
                        VStack(alignment: .leading) {
                            Text("選擇啟動身分")
                                .font(.title3.weight(.bold))
                                .foregroundColor(.white)
                            Text("LinkGuard-E Operator Identity")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 10)

                    Divider()

                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundColor(NV.danger)
                            Text(error)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(NV.danger)
                        }
                        .padding(8)
                        .background(NV.danger.opacity(0.15))
                        .cornerRadius(6)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("目前身分")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        ForEach(availableIdentityOptions) { option in
                            Button(action: { selectIdentity(option) }) {
                                HStack(spacing: 12) {
                                    Text(option.identifier)
                                        .font(.caption.monospaced().weight(.bold))
                                        .foregroundColor(.black)
                                        .frame(width: 78, alignment: .center)
                                        .padding(.vertical, 6)
                                        .background(NV.green)
                                        .cornerRadius(4)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.title)
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(.white)
                                        Text(option.section)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(NV.green.opacity(0.8))
                                }
                                .padding(10)
                                .background(Color.black.opacity(0.4))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(NV.green.opacity(0.22), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if availableIdentityOptions.isEmpty {
                            Text("此主控台尚無可選身分")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .padding(24)
                .frame(width: 450)
                .background(NV.nightVisionChrome)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(NV.green, lineWidth: 1.5)
                )
            }
        }
    }

    private func selectIdentity(_ option: IdentityOption) {
        errorMessage = nil
        do {
            let (_, newState) = try MacSystemUIFactory.selectIdentityAndMakeState(
                directory: directory,
                identifier: option.identifier,
                appID: macState.runtime.device.appID,
                deviceID: macState.runtime.device.id,
                displayName: macState.runtime.device.displayName,
                selectedAt: Date(),
                snapshot: macState.runtime.snapshot,
                versionInfo: macState.settingsInfo.versionInfo
            )
            macState = newState
        } catch AccountAccessError.accountNotFound {
            errorMessage = "找不到此身分"
        } catch AccountAccessError.appNotAllowed {
            errorMessage = "此身分不屬於本端主控台"
        } catch {
            errorMessage = "身分選擇失敗: \(error.localizedDescription)"
        }
    }

    private struct IdentityOption: Identifiable {
        let identifier: String
        let title: String
        let section: String

        var id: String { identifier }
    }
}

public typealias MacSystemLoginOverlayView = MacSystemIdentityPickerOverlayView

public struct MacSystemSessionStatusPanel: View {
    let session: LoginSession
    let onLogout: () -> Void
    private var activation: ModuleActivationSnapshot { session.moduleActivationSnapshot }

    public var body: some View {
        HQPanel(title: "目前身分", icon: "person.crop.circle.badge.checkmark", accent: NV.green) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundColor(NV.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.displayName)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                        Text(session.accountID.rawValue)
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("部門定位")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(session.position.rawValue)
                            .font(.caption2.bold())
                            .foregroundColor(NV.command)
                    }

                    HStack {
                        Text("功能模式")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(activation.shell.macDisplayName)
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("已啟用模組")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                    if activation.enabledModules.isEmpty {
                        Text("無可用模組")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(activation.enabledModules.prefix(5))) { module in
                            HStack(spacing: 6) {
                                Image(systemName: module.id.macSystemImageName)
                                    .font(.caption2)
                                    .foregroundColor(NV.green)
                                Text(module.displayName)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.white.opacity(0.92))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                Button(action: onLogout) {
                    HStack {
                        Spacer()
                        Text("重新選擇身分")
                            .font(.caption.weight(.bold))
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .background(NV.danger.opacity(0.8))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 250)
    }
}

private extension LinkGuardProductShell {
    var macDisplayName: String {
        switch self {
        case .mobile:
            return "Mobile"
        case .command:
            return "Command"
        case .adminProvisioning:
            return "Admin"
        }
    }
}

private extension LinkGuardModuleID {
    var macSystemImageName: String {
        switch self {
        case .volunteerReporting:
            return "person.wave.2.fill"
        case .teamMemberOperations:
            return "figure.walk"
        case .teamLeaderOperations:
            return "person.2.badge.gearshape.fill"
        case .emtMedical:
            return "cross.case.fill"
        case .sccMobileCommand, .sccCommand:
            return "map.fill"
        case .fieldAIAssistant:
            return "sparkles"
        case .photoEvidence:
            return "camera.fill"
        case .voicePTT:
            return "waveform.circle.fill"
        case .fieldTranslation:
            return "character.bubble.fill"
        case .patientTriage:
            return "cross.vial.fill"
        case .nfcPatientTagging:
            return "wave.3.right.circle.fill"
        case .hospitalDirectory:
            return "building.2.fill"
        case .personalNotifications:
            return "bell.badge.fill"
        case .ceocDashboard:
            return "rectangle.3.group.fill"
        case .mapOperations:
            return "map.circle.fill"
        case .agencyMessaging:
            return "building.2.crop.circle.fill"
        case .resourceCoordination:
            return "shippingbox.fill"
        case .aarReplay:
            return "clock.arrow.circlepath"
        case .backupReplay:
            return "externaldrive.fill"
        case .adminProvisioning:
            return "person.badge.key.fill"
        }
    }
}
