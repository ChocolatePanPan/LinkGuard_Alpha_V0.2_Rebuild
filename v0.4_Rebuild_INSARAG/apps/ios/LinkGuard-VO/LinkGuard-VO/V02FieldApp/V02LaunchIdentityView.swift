import SwiftUI

enum V02PermissionLevel {
    case none
    case partial
    case full

    var isVisible: Bool { self != .none }
}

enum V02RoleCapability: Hashable {
    case overallDisaster
    case fieldMap
    case hazardReport
    case teamOverview
    case taskManagement
    case taskReceive
    case patientCreate
    case startTriage
    case patientMonitoring
    case evacuationManagement
    case hospitalInfo
    case sosCreate
    case sosHandle
    case radioMonitor
    case voiceReport
    case translation
    case photoReport
    case notification
    case briefing
    case eventLog
    case aiStrategic
    case aiField
    case aiPatient
    case loraSync
    case offlineSync
    case highPressure
}

enum V02FieldRole: String, CaseIterable, Identifiable {
    case ucc = "UCC"
    case scc = "SCC"
    case tl = "TL"
    case te = "TE"
    case emt = "EMT"
    case vo = "VO"

    var id: String { rawValue }

    init(deptCode: String) {
        switch deptCode.uppercased() {
        case "UCC":
            self = .ucc
        case "SCC":
            self = .scc
        case "TL":
            self = .tl
        case "EMT":
            self = .emt
        case "VO":
            self = .vo
        default:
            self = .te
        }
    }

    static var current: V02FieldRole {
        if let identity = V02LaunchIdentity.current {
            return identity.role
        }
        let savedDept = UserDefaults.standard.string(forKey: "linkguard_dept_code") ?? "TE"
        return V02FieldRole(deptCode: savedDept)
    }

    func title(isEnglish: Bool) -> String {
        switch self {
        case .ucc: return isEnglish ? "Unified Command Center" : "聯合指揮中心"
        case .scc: return isEnglish ? "Site Command Center" : "現場指揮中心"
        case .tl: return isEnglish ? "Team Leader" : "小隊長"
        case .te: return isEnglish ? "Team Explorer" : "搜救隊員"
        case .emt: return isEnglish ? "Emergency Medical Team" : "醫療救護"
        case .vo: return isEnglish ? "Volunteer" : "志工支援"
        }
    }

    func summary(isEnglish: Bool) -> String {
        switch self {
        case .ucc:
            return isEnglish ? "Cross-area strategy, SCC monitoring, resources, AI analysis, and event logs." : "跨區戰略、SCC 監控、資源調度、AI 分析與事件紀錄。"
        case .scc:
            return isEnglish ? "On-site tactical command, zones, tasks, safety, SOS, and team coordination." : "現場戰術指揮、分區任務、安全管制、SOS 與隊伍協同。"
        case .tl:
            return isEnglish ? "Squad task execution, TE coordination, local marking, patients, and safety reports." : "小隊任務執行、TE 管理、局部標記、傷患建立與安全回報。"
        case .te:
            return isEnglish ? "Frontline search, GPS, SOS, hazard, photo, voice, and task completion reports." : "第一線搜救、GPS、SOS、危險、照片、語音與任務完成回報。"
        case .emt:
            return isEnglish ? "Patient creation, START triage, monitoring, evacuation, hospitals, and translation." : "傷患建立、START 檢傷、生理監測、後送、醫院資訊與翻譯。"
        case .vo:
            return isEnglish ? "Simplified support: location, SOS, disaster/photo reports, voice, and translation." : "簡化支援：定位、SOS、災情/照片回報、語音輸入與多語翻譯。"
        }
    }

    func coreFocus(isEnglish: Bool) -> [String] {
        switch self {
        case .ucc:
            return isEnglish ? ["SCC monitoring", "Resource dispatch", "AI strategy", "Event logs"] : ["SCC 監控", "資源調度", "AI 戰略", "事件日誌"]
        case .scc:
            return isEnglish ? ["Site map", "Task dispatch", "SOS priority", "Safety control"] : ["現場地圖", "任務派遣", "SOS 優先", "安全管制"]
        case .tl:
            return isEnglish ? ["Squad tasks", "TE overview", "Patient creation", "Voice reports"] : ["小隊任務", "TE 總覽", "傷患建立", "語音回報"]
        case .te:
            return isEnglish ? ["Task receive", "SOS", "Hazard report", "Photo report"] : ["任務接收", "SOS", "危險回報", "照片回報"]
        case .emt:
            return isEnglish ? ["START triage", "Patient updates", "Evacuation", "Hospitals"] : ["START 檢傷", "傷患更新", "後送管理", "醫院資訊"]
        case .vo:
            return isEnglish ? ["SOS", "Disaster report", "Photo report", "Translation"] : ["SOS", "災情回報", "照片回報", "多語翻譯"]
        }
    }

    func permission(_ capability: V02RoleCapability) -> V02PermissionLevel {
        switch capability {
        case .overallDisaster:
            switch self {
            case .ucc, .scc: return .full
            case .tl, .emt: return .partial
            case .te, .vo: return .none
            }
        case .fieldMap:
            switch self {
            case .scc, .tl: return .full
            case .ucc, .te: return .partial
            case .emt, .vo: return .none
            }
        case .hazardReport:
            switch self {
            case .scc, .tl: return .full
            case .ucc, .te, .vo: return .partial
            case .emt: return .none
            }
        case .teamOverview:
            switch self {
            case .ucc, .scc: return .full
            case .tl, .emt: return .partial
            case .te, .vo: return .none
            }
        case .taskManagement:
            switch self {
            case .scc, .tl: return .full
            case .ucc: return .partial
            case .te, .emt, .vo: return .none
            }
        case .taskReceive:
            switch self {
            case .te: return .full
            case .tl, .emt: return .partial
            case .scc, .ucc, .vo: return .none
            }
        case .patientCreate:
            switch self {
            case .tl, .emt: return .full
            case .scc, .te: return .partial
            case .ucc, .vo: return .none
            }
        case .startTriage:
            switch self {
            case .tl, .emt: return .full
            case .scc: return .partial
            case .ucc, .te, .vo: return .none
            }
        case .patientMonitoring:
            switch self {
            case .emt: return .full
            case .scc, .tl, .ucc: return .partial
            case .te, .vo: return .none
            }
        case .evacuationManagement:
            switch self {
            case .emt: return .full
            case .scc: return .partial
            case .ucc, .tl, .te, .vo: return .none
            }
        case .hospitalInfo:
            switch self {
            case .emt: return .full
            case .ucc, .scc, .tl: return .partial
            case .te, .vo: return .none
            }
        case .sosCreate:
            switch self {
            case .te, .emt: return .full
            case .scc, .tl, .vo: return .partial
            case .ucc: return .none
            }
        case .sosHandle:
            switch self {
            case .scc, .tl, .te, .emt: return .full
            case .ucc, .vo: return .partial
            }
        case .radioMonitor:
            switch self {
            case .ucc, .scc: return .full
            case .tl: return .partial
            case .te, .emt, .vo: return .none
            }
        case .voiceReport:
            switch self {
            case .scc, .tl, .te, .emt: return .full
            case .ucc, .vo: return .partial
            }
        case .translation:
            switch self {
            case .emt, .vo: return .full
            case .scc, .tl, .te: return .partial
            case .ucc: return .none
            }
        case .photoReport:
            switch self {
            case .scc, .tl, .te, .emt, .vo: return .full
            case .ucc: return .partial
            }
        case .notification:
            switch self {
            case .scc, .tl, .te, .emt: return .full
            case .ucc, .vo: return .partial
            }
        case .briefing:
            switch self {
            case .scc, .tl: return .full
            case .ucc: return .partial
            case .te, .emt, .vo: return .none
            }
        case .eventLog:
            switch self {
            case .ucc, .scc: return .full
            case .tl, .emt: return .partial
            case .te, .vo: return .none
            }
        case .aiStrategic:
            switch self {
            case .ucc: return .full
            case .scc: return .partial
            case .tl, .te, .emt, .vo: return .none
            }
        case .aiField:
            switch self {
            case .scc: return .full
            case .ucc, .tl: return .partial
            case .te, .emt, .vo: return .none
            }
        case .aiPatient:
            switch self {
            case .emt: return .full
            case .ucc, .scc, .tl: return .partial
            case .te, .vo: return .none
            }
        case .loraSync:
            switch self {
            case .scc, .tl, .te, .emt: return .full
            case .ucc, .vo: return .partial
            }
        case .offlineSync:
            return .full
        case .highPressure:
            switch self {
            case .scc, .tl, .te, .emt: return .full
            case .vo: return .partial
            case .ucc: return .none
            }
        }
    }

    func can(_ capability: V02RoleCapability) -> Bool {
        permission(capability).isVisible
    }

    func canAccessTab(_ tab: AppTab) -> Bool {
        switch tab {
        case .dashboard, .connection:
            return true
        case .ai:
            return can(.aiStrategic) || can(.aiField) || can(.aiPatient)
        case .notifications:
            return can(.notification)
        case .chat, .communication:
            return can(.voiceReport) || can(.radioMonitor)
        case .disaster:
            return can(.overallDisaster) || can(.fieldMap) || can(.hazardReport)
        case .sos:
            return can(.sosCreate) || can(.sosHandle)
        case .decision, .commands:
            switch self {
            case .ucc, .scc, .tl, .te, .emt:
                return true
            case .vo:
                return false
            }
        case .squadLeader:
            return self == .ucc || self == .scc || self == .tl
        case .victims:
            return can(.patientCreate) || can(.patientMonitoring) || self == .ucc
        case .reinforcement:
            return can(.taskManagement) || self == .emt
        case .team:
            return can(.teamOverview)
        case .personnelAssignment:
            return can(.taskManagement)
        case .patientForm, .nfcReader:
            return can(.patientCreate) || can(.startTriage) || can(.patientMonitoring)
        case .capabilityReport:
            return self == .ucc || self == .scc || self == .tl
        case .translator:
            return can(.translation)
        case .hospitals:
            return can(.hospitalInfo)
        case .photo:
            return can(.photoReport)
        case .radio:
            return can(.radioMonitor) || can(.voiceReport)
        }
    }
}

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

extension V02LaunchIdentity {
    var role: V02FieldRole {
        V02FieldRole(deptCode: deptCode)
    }

    static var current: V02LaunchIdentity? {
        let id = UserDefaults.standard.string(forKey: selectedIDKey) ?? ""
        return find(id)
    }
}

struct V02LaunchIdentityView: View {
    @EnvironmentObject private var l10n: L10n
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("appColorScheme") private var appColorScheme = "dark"
    let onSelect: (V02LaunchIdentity) -> Void

    private var isEnglish: Bool {
        l10n.language.hasPrefix("en")
    }

    private var launchPreferredColorScheme: ColorScheme? {
        switch appColorScheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var isLightAppearance: Bool {
        switch appColorScheme {
        case "light": return true
        case "dark": return false
        default: return systemColorScheme == .light
        }
    }

    private var pageBackground: Color {
        isLightAppearance ? Color(red: 0.955, green: 0.975, blue: 0.962) : NV.bg
    }

    private var panelBackground: Color {
        isLightAppearance ? Color.white : NV.surface
    }

    private var logoBackground: Color {
        isLightAppearance ? Color(red: 0.900, green: 0.945, blue: 0.915) : NV.surface
    }

    private var panelStroke: Color {
        isLightAppearance ? NV.green.opacity(0.18) : NV.green.opacity(0.25)
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
                                V02LaunchIdentityCard(
                                    identity: identity,
                                    isEnglish: isEnglish,
                                    isLightAppearance: isLightAppearance
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
            }
            .background(pageBackground.ignoresSafeArea())
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
        .preferredColorScheme(launchPreferredColorScheme)
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
                    .background(logoBackground, in: RoundedRectangle(cornerRadius: 12))

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

            themeControl
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(panelStroke, lineWidth: 1)
        )
        .shadow(color: isLightAppearance ? Color.black.opacity(0.06) : .clear, radius: 14, x: 0, y: 8)
    }

    private var themeControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(isEnglish ? "Appearance" : "外觀", systemImage: isLightAppearance ? "sun.max.fill" : "moon.fill")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            Picker("", selection: $appColorScheme) {
                Label(isEnglish ? "Night" : "夜視", systemImage: "moon.fill").tag("dark")
                Label(isEnglish ? "Light" : "淺色", systemImage: "sun.max.fill").tag("light")
                Label(isEnglish ? "System" : "系統", systemImage: "circle.lefthalf.filled").tag("system")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
        }
        .padding(.top, 2)
    }
}

private struct V02LaunchIdentityCard: View {
    let identity: V02LaunchIdentity
    let isEnglish: Bool
    let isLightAppearance: Bool

    private var cardBackground: Color {
        isLightAppearance ? Color.white : NV.surface
    }

    private var cardStroke: Color {
        identity.accent.opacity(isLightAppearance ? 0.20 : 0.26)
    }

    private var iconBackground: Color {
        identity.accent.opacity(isLightAppearance ? 0.11 : 0.16)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: identity.systemImage)
                    .font(.title2)
                    .foregroundColor(identity.accent)
                    .frame(width: 38, height: 38)
                    .background(iconBackground, in: RoundedRectangle(cornerRadius: 10))

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
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(cardStroke, lineWidth: 1)
        )
        .shadow(color: isLightAppearance ? identity.accent.opacity(0.08) : .clear, radius: 10, x: 0, y: 6)
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
