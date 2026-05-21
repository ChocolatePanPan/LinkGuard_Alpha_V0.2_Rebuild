import SwiftUI
import LinkGuardV03Core

public struct MacSystemLoginOverlayView: View {
    @Binding var macState: MacSystemUIState
    @State private var directory = AccountDirectory.demo
    @State private var identifier = ""
    @State private var password = ""
    @State private var errorMessage: String? = nil

    private let demoAccounts = [
        ("IC-01", "事故指揮官 (Incident Commander)", "事故指揮"),
        ("CS-01", "指揮幕僚 (Command Staff)", "指揮幕僚"),
        ("PLAN-01", "計畫組長 (Planning Chief)", "計畫組"),
        ("LOG-01", "後勤組長 (Logistics Chief)", "後勤組"),
        ("FIN-01", "財務行政組長 (Finance Chief)", "財務組")
    ]

    public init(macState: Binding<MacSystemUIState>) {
        self._macState = macState
    }

    public var body: some View {
        ZStack {
            // Dark night vision dimmed background
            Color.black.opacity(0.85)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 24) {
                // HUD styling window
                VStack(spacing: 20) {
                    // Header
                    HStack(spacing: 12) {
                        Image(systemName: "shield.and.key.fill")
                            .font(.title)
                            .foregroundColor(NV.green)
                        VStack(alignment: .leading) {
                            Text("LinkGuard-E 登錄系統")
                                .font(.title3.weight(.bold))
                                .foregroundColor(.white)
                            Text("ICS 權責與指揮鏈驗證")
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

                    // Input Form
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("帳號識別碼 (帳號 ID / 人員 ID / 呼號)")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                            TextField("例如 IC-01", text: $identifier)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color.black.opacity(0.4))
                                .cornerRadius(6)
                                .foregroundColor(.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(NV.green.opacity(0.3), lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("密鑰")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                            SecureField("請輸入安全憑證密碼", text: $password)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color.black.opacity(0.4))
                                .cornerRadius(6)
                                .foregroundColor(.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(NV.green.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }

                    // Log In Button
                    Button(action: performLogin) {
                        HStack {
                            Spacer()
                            Text("驗證並登錄系統")
                                .font(.body.weight(.bold))
                            Spacer()
                        }
                        .foregroundColor(.black)
                        .padding(.vertical, 12)
                        .background(NV.green)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    // Quick Demo Accounts to Click & Auto-fill
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ICS 推薦測試帳號 (密碼：password):")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                            ForEach(demoAccounts, id: \.0) { account in
                                GridRow {
                                    Button(action: {
                                        self.identifier = account.0
                                        self.password = "password"
                                    }) {
                                        Text(account.0)
                                            .font(.caption.monospaced().weight(.bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(NV.nightVisionSurface)
                                            .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)

                                    Text(account.1)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
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

    private func performLogin() {
        errorMessage = nil
        do {
            let (_, newState) = try MacSystemUIFactory.loginAndMakeState(
                directory: &directory,
                identifier: identifier,
                credentialDigest: password,
                appID: macState.runtime.device.appID,
                deviceID: macState.runtime.device.id,
                displayName: macState.runtime.device.displayName,
                issuedAt: Date(),
                snapshot: macState.runtime.snapshot,
                versionInfo: macState.settingsInfo.versionInfo
            )
            macState = newState
        } catch AccountAccessError.accountNotFound {
            errorMessage = "找不到此帳號或呼號"
        } catch AccountAccessError.invalidCredential {
            errorMessage = "憑證密碼錯誤"
        } catch AccountAccessError.appNotAllowed {
            errorMessage = "此帳號無權登入本端應用"
        } catch {
            errorMessage = "登入驗證失敗: \(error.localizedDescription)"
        }
    }
}

public struct MacSystemSessionStatusPanel: View {
    let session: LoginSession
    let onLogout: () -> Void

    public var body: some View {
        HQPanel(title: "登錄狀態", icon: "person.badge.shield.checkmark.fill", accent: NV.green) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundColor(NV.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.displayName)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                        Text("呼號: \(session.profile.appID.rawValue.uppercased())-\(session.position.rawValue)")
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
                        Text("Session")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(session.id.rawValue)
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                }

                Button(action: onLogout) {
                    HStack {
                        Spacer()
                        Text("登出系統 (Logout)")
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
