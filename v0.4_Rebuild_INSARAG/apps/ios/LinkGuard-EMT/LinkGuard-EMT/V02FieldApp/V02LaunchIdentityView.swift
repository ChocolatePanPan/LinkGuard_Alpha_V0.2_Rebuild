import SwiftUI

struct V02LaunchIdentity: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let detail: String
    let deptCode: String
    let nodeID: String
    let nickname: String
    let systemImage: String
    let accent: Color

    static let selectedIDKey = "linkguard_v04_selected_identity"
    static let shouldShowPickerKey = "linkguard_v04_should_show_identity_picker"

    static let all: [V02LaunchIdentity] = [
        V02LaunchIdentity(
            id: "TL-01",
            title: "TL-01 分隊長",
            subtitle: "Team Leader",
            detail: "小隊指揮、任務派遣、USAR 協調",
            deptCode: "TL",
            nodeID: "TL-01",
            nickname: "分隊長",
            systemImage: "person.2.badge.gearshape.fill",
            accent: NV.command
        ),
        V02LaunchIdentity(
            id: "TL-02",
            title: "TL-02 副分隊長",
            subtitle: "Deputy Team Leader",
            detail: "協助指揮、安全回報、資源協調",
            deptCode: "TL",
            nodeID: "TL-02",
            nickname: "副分隊長",
            systemImage: "person.badge.shield.checkmark.fill",
            accent: NV.info
        ),
        V02LaunchIdentity(
            id: "TE-01",
            title: "TE-01 搜救員",
            subtitle: "Technical Search / Rescue",
            detail: "現場任務、GPS、照片、SOS 與狀態回報",
            deptCode: "TE",
            nodeID: "TE-01",
            nickname: "搜救員",
            systemImage: "figure.run.circle.fill",
            accent: NV.green
        ),
        V02LaunchIdentity(
            id: "EMT-01",
            title: "EMT-01 救護組長",
            subtitle: "Medical Lead",
            detail: "傷患回報、START 檢傷、後送協調",
            deptCode: "EMT",
            nodeID: "EMT-01",
            nickname: "救護組長",
            systemImage: "cross.case.fill",
            accent: NV.danger
        ),
        V02LaunchIdentity(
            id: "EMT-02",
            title: "EMT-02 救護員",
            subtitle: "Emergency Medical Technician",
            detail: "生命徵象、傷患照片、NFC 標籤與交接",
            deptCode: "EMT",
            nodeID: "EMT-02",
            nickname: "救護員",
            systemImage: "heart.text.square.fill",
            accent: NV.warning
        ),
        V02LaunchIdentity(
            id: "VO-01",
            title: "VO-01 志工",
            subtitle: "Volunteer",
            detail: "支援任務、災情、照片與位置回報",
            deptCode: "VO",
            nodeID: "VO-01",
            nickname: "志工",
            systemImage: "hands.sparkles.fill",
            accent: NV.simulation
        ),
        V02LaunchIdentity(
            id: "SCC-01",
            title: "SCC-01 現場指揮",
            subtitle: "Sector Command",
            detail: "現場指揮、分區協調、作業監控",
            deptCode: "SCC",
            nodeID: "SCC-01",
            nickname: "現場指揮",
            systemImage: "building.2.crop.circle.fill",
            accent: NV.command
        ),
        V02LaunchIdentity(
            id: "UCC-01",
            title: "UCC-01 總指揮",
            subtitle: "UCC Command",
            detail: "跨區協調、資源調度、HQ 指揮通訊",
            deptCode: "UCC",
            nodeID: "UCC-01",
            nickname: "總指揮",
            systemImage: "network",
            accent: NV.info
        )
    ]

    static func find(_ id: String) -> V02LaunchIdentity? {
        all.first { $0.id == id }
    }

    func apply() {
        UserDefaults.standard.set(id, forKey: Self.selectedIDKey)
        UserDefaults.standard.set(nodeID, forKey: "linkguard_custom_node_id")
        UserDefaults.standard.set(deptCode, forKey: "linkguard_dept_code")
        UserDefaults.standard.set(nickname, forKey: "linkguard_user_nickname")
    }
}

struct V02LaunchIdentityGate<Content: View>: View {
    @AppStorage(V02LaunchIdentity.selectedIDKey) private var selectedIdentityID = ""
    @AppStorage(V02LaunchIdentity.shouldShowPickerKey) private var shouldShowPicker = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            if shouldShowPicker {
                V02LaunchIdentityView { identity in
                    identity.apply()
                    selectedIdentityID = identity.id
                    shouldShowPicker = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                content()
                    .transition(.opacity)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            shouldShowPicker = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                Text(selectedIdentityID.isEmpty ? L("身份") : selectedIdentityID)
                                    .font(.caption.bold())
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .glassEffect(.regular.tint(NV.green), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                        .padding(.trailing, 12)
                        .accessibilityLabel(L("切換身份"))
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: shouldShowPicker)
        .onAppear {
            shouldShowPicker = true
        }
    }
}

struct V02LaunchIdentityView: View {
    @EnvironmentObject private var l10n: L10n
    let onSelect: (V02LaunchIdentity) -> Void

    private var isEnglish: Bool {
        l10n.language.hasPrefix("en")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                        ForEach(V02LaunchIdentity.all) { identity in
                            Button {
                                onSelect(identity)
                            } label: {
                                V02LaunchIdentityCard(identity: identity, isEnglish: isEnglish)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
            }
            .background(NV.bg.ignoresSafeArea())
            .navigationTitle(isEnglish ? "Choose identity" : "選擇身份")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("", selection: $l10n.language) {
                        Text("中文").tag("zh-Hant")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(NV.green)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image("Logo", bundle: .main)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .padding(8)
                    .background(NV.surface, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("LinkGuard v0.4")
                        .font(.title2.bold())
                    Text(isEnglish ? "Open one app as multiple field identities." : "同一個 App，先選身份再進入 v0.2 現場系統。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Text(isEnglish ? "Your choice sets the node ID, department code, and display name used by reports, SOS, chat, and HQ sync." : "選擇後會套用節點 ID、部門碼與顯示名稱，回報、SOS、通訊與 HQ 同步都會使用該身份。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(NV.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(NV.green.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct V02LaunchIdentityCard: View {
    let identity: V02LaunchIdentity
    let isEnglish: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: identity.systemImage)
                    .font(.title2)
                    .foregroundColor(identity.accent)
                    .frame(width: 38, height: 38)
                    .background(identity.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(identity.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(identity.subtitle)
                        .font(.caption.bold())
                        .foregroundColor(identity.accent)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right.circle.fill")
                    .foregroundColor(identity.accent.opacity(0.85))
            }

            Text(identity.detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                identityPill(title: identity.deptCode, icon: "tag.fill")
                identityPill(title: identity.nodeID, icon: "antenna.radiowaves.left.and.right")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
        .background(NV.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(identity.accent.opacity(0.26), lineWidth: 1)
        )
    }

    private func identityPill(title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(title)
                .font(.caption2.bold().monospaced())
        }
        .foregroundColor(identity.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(identity.accent.opacity(0.14), in: Capsule())
    }
}
