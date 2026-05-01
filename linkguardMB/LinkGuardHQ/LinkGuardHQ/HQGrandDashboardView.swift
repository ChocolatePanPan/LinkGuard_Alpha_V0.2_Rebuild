import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - HQ 大儀表板（Phase C）
// 整合 6 大面板：AI 主機健康度、受困者即時排序、AI 推送模式控制、
// 全節點清單、AI 對話時間軸、決策審計。
// 後端依賴 win11/gemma4_server.py port 8001：
//   /ai/health, /ai/models, /ai/command/list, /ai/command/cancel/{id},
//   /ai/command/auto_dispatch
// host 來源：vm.backendBridge.backendHost（Bonjour 或手動）
// 不使用 emoji。

struct HQGrandDashboardView: View {
    @ObservedObject var vm: HQViewModel
    @State private var aiHealth: AIHealthSnapshot? = nil
    @State private var pendingCommands: [AIProposal] = []
    @State private var lastFetchError: String? = nil
    @State private var pollTimer: Timer? = nil
    @State private var isLoading = false

    // 16 種指令的本地 mode 覆寫（HQ 緊急鎖定切全手動）
    @AppStorage("ai.modeOverride.global") private var globalModeOverride: String = "auto"  // auto | manual | locked
    @AppStorage("ai.modeOverride.perType") private var perTypeOverrideJSON: String = "{}"

    private var port: Int { 8001 }
    private var host: String { vm.backendBridge.backendHost }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerBar
                if let err = lastFetchError {
                    Text("[ERROR] \(err)")
                        .font(.caption.monospaced())
                        .foregroundColor(NV.danger)
                }
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    aiHealthPanel
                    rankedPatientsPanel
                    pushModeControlPanel
                    nodeListPanel
                }
                conversationTimelinePanel
                decisionAuditPanel
            }
            .padding(20)
        }
        .background(NV.bg.ignoresSafeArea())
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.title)
                .foregroundColor(NV.green)
            Text(L("HQ 大儀表板"))
                .font(.title.bold())
                .foregroundColor(.primary)
            Spacer()
            statusChip("BACKEND", host.isEmpty ? "未連線" : host,
                       ok: !host.isEmpty)
            statusChip("MODE", globalModeOverride.uppercased(),
                       ok: globalModeOverride != "locked")
            Button {
                Task { await refreshAll() }
            } label: {
                Label(L("重新整理"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isLoading || host.isEmpty)
        }
    }

    private func statusChip(_ label: String, _ value: String, ok: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(ok ? NV.green : NV.danger).frame(width: 8, height: 8)
            Text("\(label) ▸ \(value)")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(NV.surface).cornerRadius(6)
    }

    // MARK: - Panel 1: AI 主機健康度

    private var aiHealthPanel: some View {
        panelCard(title: "AI 主機健康度", icon: "cpu") {
            if let h = aiHealth {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(h.hosts, id: \.name) { host in
                        hostRow(host)
                    }
                    Divider().background(NV.greenDim)
                    HStack {
                        Text(L("Tier 路由："))
                            .font(.caption).foregroundColor(.secondary)
                        Text(h.tierRoutingSummary)
                            .font(.caption.monospaced())
                            .foregroundColor(.primary)
                    }
                }
            } else {
                Text(host.isEmpty ? L("請先連接 backend") : L("載入中…"))
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func hostRow(_ host: AIHostStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: host.ollama_ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundColor(host.ollama_ok ? NV.green : NV.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Text(host.models.joined(separator: " / "))
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("queue \(host.queue)")
                    .font(.caption.monospaced())
                Text("err \(host.errors_5min)")
                    .font(.caption.monospaced())
                    .foregroundColor(host.errors_5min > 0 ? NV.warning : .secondary)
            }
        }
        .padding(8)
        .background(NV.bg.opacity(0.4))
        .cornerRadius(6)
    }

    // MARK: - Panel 2: 受困者即時排序

    private var rankedPatientsPanel: some View {
        panelCard(title: "受困者即時排序（Top 10）", icon: "person.fill.questionmark") {
            let top = Array(vm.backendBridge.rankedPatients.prefix(10))
            if top.isEmpty {
                Text(L("無資料"))
                    .font(.caption).foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(top.enumerated()), id: \.offset) { idx, p in
                        HStack(spacing: 8) {
                            Text("#\(idx + 1)")
                                .font(.caption.monospaced().bold())
                                .foregroundColor(NV.green)
                                .frame(width: 28, alignment: .leading)
                            Circle()
                                .fill(triageColor(p.priority))
                                .frame(width: 8, height: 8)
                            Text(p.location.isEmpty ? p.id : p.location)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%.0f", p.totalScore))
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func triageColor(_ level: String) -> Color {
        switch level.uppercased() {
        case "RED", "P1", "重傷": return NV.danger
        case "YELLOW", "P2", "中傷": return Color.orange
        case "GREEN", "P3", "輕傷": return NV.green
        case "BLACK", "P5", "死亡": return Color.black
        default: return Color.gray
        }
    }

    // MARK: - Panel 3: AI 推送模式控制

    private var pushModeControlPanel: some View {
        panelCard(title: "AI 推送模式控制（16 類）", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Picker(L("全域"), selection: $globalModeOverride) {
                        Text(L("全自動")).tag("auto")
                        Text(L("全手動")).tag("manual")
                        Text(L("緊急鎖定")).tag("locked")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                    Spacer()
                    if globalModeOverride == "locked" {
                        Label(L("鎖定中"), systemImage: "lock.shield.fill")
                            .font(.caption.bold())
                            .foregroundColor(NV.danger)
                    }
                }
                Divider().background(NV.greenDim)
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 6) {
                    ForEach(allCommandTypes, id: \.self) { t in
                        cmdTypeRow(t)
                    }
                }
            }
        }
    }

    private let allCommandTypes: [String] = [
        // 7 auto-capable
        "dispatch", "status_check", "escalate_to_main",
        "medical_priority_change", "resource_relocate", "recall", "checkpoint",
        // 9 manual
        "alert", "medical", "resource", "personnel", "evacuate",
        "emergency_evacuation", "force_broadcast", "task_order", "zone_lockdown"
    ]

    private func cmdTypeRow(_ t: String) -> some View {
        let proposal = AIProposal(id: "x", type: t, priority: 3, title: "", detail: "",
                                   targets: [], rationale: "", timestamp: "")
        let perType = decodePerTypeOverride()
        let current = perType[t] ?? "default"
        let locked = (globalModeOverride == "locked") || perType[t] == "manual"
        return HStack(spacing: 6) {
            Image(systemName: proposal.iconName)
                .font(.caption)
                .foregroundColor(locked ? NV.warning : NV.green)
                .frame(width: 16)
            Text(proposal.typeLabel)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            Menu {
                Button(L("跟隨全域")) { setPerType(t, "default") }
                Button(L("強制自動")) { setPerType(t, "auto") }
                Button(L("強制手動")) { setPerType(t, "manual") }
            } label: {
                Text(current)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(NV.bg.opacity(0.5))
                    .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 80)
        }
        .padding(.vertical, 2)
    }

    private func decodePerTypeOverride() -> [String: String] {
        guard let data = perTypeOverrideJSON.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    private func setPerType(_ key: String, _ value: String) {
        var dict = decodePerTypeOverride()
        if value == "default" { dict.removeValue(forKey: key) } else { dict[key] = value }
        if let d = try? JSONEncoder().encode(dict),
           let s = String(data: d, encoding: .utf8) {
            perTypeOverrideJSON = s
        }
    }

    // MARK: - Panel 4: 全節點清單

    private var nodeListPanel: some View {
        panelCard(title: "全節點清單", icon: "antenna.radiowaves.left.and.right") {
            let nodes = vm.backendBridge.loraNodes
            if nodes.isEmpty {
                Text(L("無 LoRa 節點資料"))
                    .font(.caption).foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(nodes) { n in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(n.rssi > -120 ? NV.green : NV.danger)
                                .frame(width: 8, height: 8)
                            Text(n.nodeId)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            Text("RSSI \(n.rssi)")
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                            Text("BAT \(n.battery)%")
                                .font(.caption2.monospaced())
                                .foregroundColor(n.battery < 20 ? NV.danger : .secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Panel 5: AI 對話時間軸

    private var conversationTimelinePanel: some View {
        panelCard(title: "AI 對話時間軸（最近）", icon: "bubble.left.and.bubble.right") {
            if pendingCommands.isEmpty {
                Text(L("尚無待審/進行中提案"))
                    .font(.caption).foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pendingCommands) { p in
                        proposalTimelineRow(p)
                    }
                }
            }
        }
    }

    private func proposalTimelineRow(_ p: AIProposal) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack {
                Image(systemName: p.iconName)
                    .foregroundColor(p.priorityColor)
                Text(p.priorityLabel.prefix(2))
                    .font(.caption2.monospaced())
                    .foregroundColor(p.priorityColor)
            }
            .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(p.typeLabel)
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                    Text(p.id)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                    if p.isAutoMode {
                        Text("AUTO \(p.countdown_sec)s")
                            .font(.caption2.monospaced().bold())
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(NV.warning.opacity(0.3))
                            .foregroundColor(NV.warning)
                            .cornerRadius(3)
                    }
                    if p.requiresDoubleConfirm {
                        Text("DOUBLE-CONFIRM")
                            .font(.caption2.monospaced().bold())
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(NV.danger.opacity(0.3))
                            .foregroundColor(NV.danger)
                            .cornerRadius(3)
                    }
                }
                Text(p.title)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
            Spacer()
            HStack(spacing: 4) {
                Button(L("執行")) {
                    Task { await dispatchCommand(p.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(globalModeOverride == "locked")
                Button(L("取消")) {
                    Task { await cancelCommand(p.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(NV.bg.opacity(0.3))
        .cornerRadius(6)
    }

    // MARK: - Panel 6: 決策審計（簡版：用 backendDecisions）

    private var decisionAuditPanel: some View {
        panelCard(title: "決策審計（最近 20 筆）", icon: "list.bullet.clipboard") {
            let entries = Array(vm.backendBridge.backendDecisions.prefix(20))
            if entries.isEmpty {
                Text(L("無決策紀錄"))
                    .font(.caption).foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entries) { d in
                        HStack(spacing: 8) {
                            Image(systemName: "brain.head.profile")
                                .foregroundColor(NV.green)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.decision)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                Text("\(d.model) · \(d.timestamp)")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if d.escalated {
                                Text("ESC")
                                    .font(.caption2.bold())
                                    .foregroundColor(NV.warning)
                            }
                        }
                        .padding(6)
                        .background(NV.bg.opacity(0.3))
                        .cornerRadius(4)
                    }
                }
            }
        }
    }

    // MARK: - Card wrapper

    private func panelCard<Content: View>(title: String, icon: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(NV.green)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NV.surface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(NV.greenDim, lineWidth: 1)
        )
    }

    // MARK: - Polling & API

    private func startPolling() {
        Task { await refreshAll() }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            Task { await refreshAll() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func refreshAll() async {
        guard !host.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        await fetchAIHealth()
        await fetchPendingCommands()
    }

    private func fetchAIHealth() async {
        guard let url = makeBackendURL(host: host, port: port, path: "/ai/health") else { return }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.aiHealth = AIHealthSnapshot(json: json)
                self.lastFetchError = nil
            }
        } catch {
            self.lastFetchError = "ai/health: \(error.localizedDescription)"
        }
    }

    private func fetchPendingCommands() async {
        guard let url = makeBackendURL(host: host, port: port, path: "/ai/command/list") else { return }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = json["commands"] as? [[String: Any]] else { return }
            let decoder = JSONDecoder()
            var out: [AIProposal] = []
            for item in arr {
                if let d = try? JSONSerialization.data(withJSONObject: item),
                   let p = try? decoder.decode(AIProposal.self, from: d) {
                    out.append(p)
                }
            }
            self.pendingCommands = out
        } catch {
            self.lastFetchError = "ai/command/list: \(error.localizedDescription)"
        }
    }

    private func dispatchCommand(_ id: String) async {
        guard let url = makeBackendURL(host: host, port: port,
                                        path: "/ai/command/auto_dispatch") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id])
        _ = try? await URLSession.shared.data(for: req)
        await fetchPendingCommands()
    }

    private func cancelCommand(_ id: String) async {
        guard let url = makeBackendURL(host: host, port: port,
                                        path: "/ai/command/cancel/\(id)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        _ = try? await URLSession.shared.data(for: req)
        await fetchPendingCommands()
    }
}

// MARK: - AI Health 結構

struct AIHealthSnapshot {
    let hosts: [AIHostStatus]
    let tierRouting: [String: String]

    init(json: [String: Any]) {
        var arr: [AIHostStatus] = []
        if let hosts = json["hosts"] as? [[String: Any]] {
            for h in hosts {
                arr.append(AIHostStatus(
                    name: (h["name"] as? String) ?? "host?",
                    models: (h["models"] as? [String]) ?? [],
                    ollama_ok: (h["ollama_ok"] as? Bool) ?? false,
                    queue: (h["queue"] as? Int) ?? 0,
                    errors_5min: (h["errors_5min"] as? Int) ?? 0
                ))
            }
        }
        self.hosts = arr
        if let tr = json["tier_routing"] as? [String: String] {
            self.tierRouting = tr
        } else if let tr = json["tier_routing"] as? [String: Any] {
            var dict: [String: String] = [:]
            for (k, v) in tr { dict[k] = "\(v)" }
            self.tierRouting = dict
        } else {
            self.tierRouting = [:]
        }
    }

    var tierRoutingSummary: String {
        let order = ["field", "hq_local", "hq_main"]
        return order.compactMap { k in
            tierRouting[k].map { "\(k)=\($0)" }
        }.joined(separator: " ")
    }
}

struct AIHostStatus {
    let name: String
    let models: [String]
    let ollama_ok: Bool
    let queue: Int
    let errors_5min: Int
}
