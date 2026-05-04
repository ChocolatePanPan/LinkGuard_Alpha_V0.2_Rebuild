import Foundation
import SwiftUI
import Combine

@MainActor
final class MilkyWayCommandViewModel: ObservableObject {
    @Published var selectedRoute: MilkyWayRoute = .overview
    @Published var commandNetworkEnabled = true
    @Published var localNodeName = "MW-iPad-01"
    @Published var operationName = "Milky Way 指揮中心"
    @Published var activeCountdownEnd: Date?
    @Published var incidents: [MWIncident]
    @Published var teams: [MWTeamUnit]
    @Published var tasks: [MWTaskItem]
    @Published var logs: [MWLogEntry]
    @Published var resources: [MWResourceItem]

    private var timer: Timer?

    init() {
        incidents = [
            MWIncident(title: "北側樓梯煙霧回升", location: "A 棟 2F", severity: .urgent, note: "熱點持續，請避開北側梯間。", updatedAt: Date().addingTimeInterval(-180)),
            MWIncident(title: "傷患搬運完成 2 名", location: "臨時醫療區", severity: .watch, note: "需補充氧氣瓶與擔架。", updatedAt: Date().addingTimeInterval(-420)),
            MWIncident(title: "電力切斷確認", location: "地下機房", severity: .stable, note: "機電組完成掛牌。", updatedAt: Date().addingTimeInterval(-720))
        ]
        teams = [
            MWTeamUnit(name: "Alpha", role: "搜救", zone: "A 棟", status: "室內搜索", battery: 82, severity: .urgent),
            MWTeamUnit(name: "Bravo", role: "破壞", zone: "B 棟", status: "待命", battery: 64, severity: .watch),
            MWTeamUnit(name: "Medic", role: "醫療", zone: "集結點", status: "傷患處置", battery: 91, severity: .stable),
            MWTeamUnit(name: "Logistics", role: "補給", zone: "南側門", status: "裝備補位", battery: 58, severity: .watch)
        ]
        tasks = [
            MWTaskItem(title: "建立二次撤離路線", owner: "Bravo", due: "5 分鐘", progress: 0.45, severity: .urgent),
            MWTaskItem(title: "醫療區氧氣瓶補充", owner: "Logistics", due: "8 分鐘", progress: 0.3, severity: .watch),
            MWTaskItem(title: "Alpha 搜索區回報", owner: "Alpha", due: "3 分鐘", progress: 0.72, severity: .urgent)
        ]
        logs = [
            MWLogEntry(title: "獨立中樞啟動", detail: "本機 iPad 指揮中心已就緒。", time: Date().addingTimeInterval(-60), color: MWTheme.green),
            MWLogEntry(title: "任務同步", detail: "載入本機作戰資料，不連接 Mac HQ。", time: Date().addingTimeInterval(-50), color: MWTheme.cyan)
        ]
        resources = [
            MWResourceItem(name: "氧氣瓶", amount: "6 支", location: "醫療區", condition: .urgent),
            MWResourceItem(name: "擔架", amount: "4 組", location: "南側門", condition: .watch),
            MWResourceItem(name: "照明組", amount: "3 組", location: "補給車", condition: .stable),
            MWResourceItem(name: "破壞工具", amount: "2 箱", location: "B 棟入口", condition: .watch)
        ]
    }

    deinit {
        timer?.invalidate()
    }

    var metrics: [MWMetric] {
        [
            MWMetric(title: "危急事件", value: "\(incidents.filter { $0.severity == .critical || $0.severity == .urgent }.count)", icon: "exclamationmark.triangle.fill", color: MWTheme.red),
            MWMetric(title: "作戰隊伍", value: "\(teams.count)", icon: "person.3.fill", color: MWTheme.cyan),
            MWMetric(title: "待辦任務", value: "\(tasks.filter { $0.progress < 1 }.count)", icon: "checklist", color: MWTheme.amber),
            MWMetric(title: "資源品項", value: "\(resources.count)", icon: "shippingbox.fill", color: MWTheme.violet)
        ]
    }

    var countdownText: String {
        guard let activeCountdownEnd else { return "未啟動" }
        let remaining = max(0, Int(activeCountdownEnd.timeIntervalSinceNow))
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    func issue(_ preset: MWCommandPreset) {
        logs.insert(MWLogEntry(title: preset.title, detail: preset.detail, time: Date(), color: preset.color), at: 0)
        tasks.insert(MWTaskItem(title: preset.title, owner: "指揮官", due: "立即", progress: 0, severity: preset == .evacuate ? .critical : .urgent), at: 0)
    }

    func startCountdown(minutes: Int) {
        activeCountdownEnd = Date().addingTimeInterval(TimeInterval(minutes * 60))
        logs.insert(MWLogEntry(title: "倒數啟動", detail: "作戰倒數 \(minutes) 分鐘。", time: Date(), color: MWTheme.amber), at: 0)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let end = self.activeCountdownEnd, end.timeIntervalSinceNow <= 0 {
                    self.activeCountdownEnd = nil
                    self.logs.insert(MWLogEntry(title: "倒數結束", detail: "請重新評估現場節奏。", time: Date(), color: MWTheme.red), at: 0)
                    self.timer?.invalidate()
                    self.timer = nil
                } else {
                    self.objectWillChange.send()
                }
            }
        }
    }

    func cancelCountdown() {
        activeCountdownEnd = nil
        timer?.invalidate()
        timer = nil
        logs.insert(MWLogEntry(title: "倒數取消", detail: "指揮官已取消倒數管制。", time: Date(), color: MWTheme.cyan), at: 0)
    }

    func toggleNetwork() {
        commandNetworkEnabled.toggle()
        logs.insert(MWLogEntry(
            title: commandNetworkEnabled ? "指揮網開啟" : "指揮網關閉",
            detail: commandNetworkEnabled ? "本機中樞接受周邊節點連線。" : "本機中樞改為離線作戰。",
            time: Date(),
            color: commandNetworkEnabled ? MWTheme.green : MWTheme.amber
        ), at: 0)
    }
}
