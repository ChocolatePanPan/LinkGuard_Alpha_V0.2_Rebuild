import Foundation

/// 模擬引擎：模擬韌體 rescue.ino 的行為，產生擬真受困者資料
/// 用於 Demo 展示（沒有硬體時可模擬 BLE 資料）
class SimulationEngine {

    private let victimIDs = ["VT-A3F", "VT-B72", "VT-C1E", "VT-D9A", "VT-E45"]

    // MARK: - 初始資料

    func createInitialNodeStatus() -> RescueNodeStatus {
        RescueNodeStatus(
            nodeID: "RT-7F2-EMT",
            deptCode: "EMT",
            battery: 85,
            loraLevel: 4,
            isConnected: false,
            pairCode: "0000"
        )
    }

    func createInitialVictims() -> [VictimNode] {
        [
            VictimNode(id: "VT-A3F", heartRate: 78, battery: 65, rssi: -62, snr: 8.5,
                       isSOS: true, lastSeen: Date(), isOnline: true),
            VictimNode(id: "VT-B72", heartRate: 92, battery: 43, rssi: -78, snr: 5.2,
                       isSOS: false, lastSeen: Date().addingTimeInterval(-10), isOnline: true),
            VictimNode(id: "VT-C1E", heartRate: 0, battery: 12, rssi: -91, snr: 1.3,
                       isSOS: true, lastSeen: Date().addingTimeInterval(-45), isOnline: false),
        ]
    }

    func createInitialSOSRecords() -> [SOSRecord] {
        let now = Date()
        return [
            SOSRecord(id: UUID(), victimID: "VT-A3F", heartRate: 78, rssi: -62,
                      distance: "1.2m", battery: 65, time: now.addingTimeInterval(-30), isAcknowledged: false),
            SOSRecord(id: UUID(), victimID: "VT-C1E", heartRate: 0, rssi: -91,
                      distance: "48m", battery: 12, time: now.addingTimeInterval(-120), isAcknowledged: true),
        ]
    }

    // MARK: - 模擬更新（每 2 秒 tick，對應韌體 PING_INTERVAL=3000）

    /// 模擬 RSSI 訊號波動與心率微變
    func updateVictimSignals(_ victims: inout [VictimNode]) {
        for i in victims.indices where victims[i].isOnline {
            // RSSI 微幅波動
            let rssiDrift = Double.random(in: -3...3)
            victims[i].rssi = max(-99, min(-30, victims[i].rssi + rssiDrift))
            // SNR 微幅波動
            let snrDrift = Double.random(in: -0.5...0.5)
            victims[i].snr = max(-5, min(15, victims[i].snr + snrDrift))
            // 心率微變
            if victims[i].heartRate > 0 {
                let hrDrift = Int.random(in: -3...3)
                victims[i].heartRate = max(40, min(180, victims[i].heartRate + hrDrift))
            }
            victims[i].lastSeen = Date()
            // 偶爾消耗電量
            if Int.random(in: 0...15) == 0 {
                victims[i].battery = max(0, victims[i].battery - 1)
            }
        }
    }

    /// 模擬受困者上線/離線（韌體：30s 無更新 = 離線）
    func updateVictimOnlineStatus(_ victims: inout [VictimNode]) {
        for i in victims.indices {
            let interval = Date().timeIntervalSince(victims[i].lastSeen)
            victims[i].isOnline = interval < 30
            // 偶爾讓離線的重新上線
            if !victims[i].isOnline && Int.random(in: 0...10) == 0 {
                victims[i].isOnline = true
                victims[i].rssi = Double.random(in: -85 ... -50)
                victims[i].lastSeen = Date()
            }
        }
    }

    /// 模擬節點電量與 LoRa 檔位
    func updateNodeStatus(_ status: inout RescueNodeStatus) {
        if Int.random(in: 0...30) == 0 {
            status.battery = max(0, status.battery - 1)
        }
    }

    /// 隨機產生新受困者 SOS（低機率，模擬 LoRa 收到新封包）
    func maybeDiscoverNewVictim(existing: [VictimNode]) -> VictimNode? {
        guard Int.random(in: 0...30) == 0 else { return nil }
        // 從 pool 中找一個尚未存在的 ID
        let existingIDs = Set(existing.map(\.id))
        let available = victimIDs.filter { !existingIDs.contains($0) }
        guard let newID = available.randomElement() else { return nil }
        return VictimNode(
            id: newID,
            heartRate: Int.random(in: 0...1) == 0 ? Int.random(in: 50...120) : 0,
            battery: Int.random(in: 10...90),
            rssi: Double.random(in: -90 ... -50),
            snr: Double.random(in: 0...10),
            isSOS: Int.random(in: 0...2) == 0,
            lastSeen: Date(),
            isOnline: true
        )
    }

    /// 隨機觸發 SOS 狀態變化
    func maybeToggleSOS(_ victims: inout [VictimNode]) -> SOSRecord? {
        guard let i = victims.indices.randomElement(),
              victims[i].isOnline,
              Int.random(in: 0...20) == 0
        else { return nil }

        victims[i].isSOS.toggle()

        guard victims[i].isSOS else { return nil }
        return SOSRecord(
            id: UUID(),
            victimID: victims[i].id,
            heartRate: victims[i].heartRate,
            rssi: victims[i].rssi,
            distance: victims[i].distanceText,
            battery: victims[i].battery,
            time: Date(),
            isAcknowledged: false
        )
    }
}
