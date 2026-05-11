import Foundation
import CoreBluetooth
import Combine

// MARK: - BLE 常數（對應 Heltec WiFi LoRa 32 V3 韌體預留 BLE UUID）

struct LinkGuardBLE {
    // 主服務
    static let serviceUUID      = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
    // 狀態特徵：韌體端送出與 /up 相同的 JSON（bat, lvl, victims[]）
    static let statusUUID       = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8")
    // 指令特徵：App 端寫入控制指令（setdept, setlvl）
    static let commandUUID      = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26AB")
    // LoRa 命令特徵：韌體端轉發來自指揮中心的 LoRa 命令（Notify）
    static let loraCommandUUID  = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26AC")
}

// MARK: - 已發現裝置

struct DiscoveredDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral
}

// MARK: - BLE 資料解析

struct BLEDataParser {

    /// 解析韌體 JSON（同 /up 端點格式）
    static func parseStatusJSON(_ data: Data) -> FirmwareStatusResponse? {
        do {
            return try JSONDecoder().decode(FirmwareStatusResponse.self, from: data)
        } catch {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
            print("[BLE] JSON parse FAIL (\(data.count) bytes): \(error)")
            print("[BLE] Raw data: \(preview)")
            return nil
        }
    }

    /// 編碼 setdept 指令
    static func encodeDeptCommand(_ dept: String) -> Data? {
        "setdept:\(dept)".data(using: .utf8)
    }

    /// 編碼 setlvl 指令
    static func encodeLevelCommand(_ level: Int) -> Data? {
        "setlvl:\(level)".data(using: .utf8)
    }

    /// 編碼 setpair 指令
    static func encodePairCommand(_ pair: String) -> Data? {
        "setpair:\(pair)".data(using: .utf8)
    }

    /// 編碼命令回執（通知韌體 App 已收到命令）
    static func encodeCommandAck(_ commandID: String) -> Data? {
        "cmd_ack:\(commandID)".data(using: .utf8)
    }

    /// 解析韌體轉發的 LoRa 命令 JSON
    /// 格式：{"cmd_id":"xxx","type":"evacuation","pri":2,"title":"立即撤離","detail":"...","sender":"HQ-Alpha"}
    static func parseLoRaCommand(_ data: Data) -> FirmwareLoRaCommand? {
        do {
            return try JSONDecoder().decode(FirmwareLoRaCommand.self, from: data)
        } catch {
            print("[BLE] LoRa command decode failed: \(error.localizedDescription)")
            return nil
        }
    }
}

/// 韌體轉發的 LoRa 指揮命令格式
struct FirmwareLoRaCommand: Decodable {
    let cmd_id: String          // 命令唯一 ID
    let type: String            // 命令類型 key（對應 CommandType.rawValue 或英文 key）
    let pri: Int                // 優先等級 0=routine, 1=urgent, 2=critical
    let title: String           // 命令標題
    let detail: String          // 命令詳情
    let sender: String          // 發送者代號

    /// 轉換為 App 內部的 CommandOrder
    func toCommandOrder() -> CommandOrder {
        let priority = CommandPriority(rawValue: pri) ?? .routine
        let commandType = CommandType.fromKey(type) ?? .statusReport

        return CommandOrder(
            id: UUID(uuidString: cmd_id) ?? UUID(),
            type: commandType,
            priority: priority,
            title: title,
            detail: detail,
            sender: sender,
            time: Date(),
            isRead: false
        )
    }
}

// MARK: - 藍牙管理器

class BluetoothManager: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var isPoweredOn = false
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var connectedDeviceName: String?

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?

    /// BLE JSON 累積緩衝區（處理 MTU 截斷）
    private var statusBuffer = Data()
    private var statusBufferTimestamp = Date()
    private var reconnectTimer: Timer?
    private var reconnectDelay: TimeInterval = 2

    /// 韌體狀態更新回呼
    var onStatusUpdate: ((FirmwareStatusResponse) -> Void)?
    /// LoRa 指揮命令回呼
    var onLoRaCommand: ((FirmwareLoRaCommand) -> Void)?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    deinit {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    // MARK: 掃描

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        isScanning = true
        discoveredDevices.removeAll()
        centralManager.scanForPeripherals(
            withServices: [LinkGuardBLE.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }

    // MARK: 連線

    func connect(to device: DiscoveredDevice) {
        stopScanning()
        connectedPeripheral = device.peripheral
        centralManager.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        reconnectTimer?.invalidate()
        reconnectDelay = 2
        guard let p = connectedPeripheral else { return }
        connectedPeripheral = nil
        connectedDeviceName = nil
        centralManager.cancelPeripheralConnection(p)
    }

    // MARK: 發送指令

    func sendDeptChange(_ dept: String) {
        guard let char = commandCharacteristic,
              let p = connectedPeripheral,
              let data = BLEDataParser.encodeDeptCommand(dept)
        else { return }
        p.writeValue(data, for: char, type: .withResponse)
    }

    func sendLevelChange(_ level: Int) {
        guard let char = commandCharacteristic,
              let p = connectedPeripheral,
              let data = BLEDataParser.encodeLevelCommand(level)
        else { return }
        p.writeValue(data, for: char, type: .withResponse)
    }

    func sendPairChange(_ pair: String) {
        guard let char = commandCharacteristic,
              let p = connectedPeripheral,
              let data = BLEDataParser.encodePairCommand(pair)
        else { return }
        p.writeValue(data, for: char, type: .withResponse)
    }

    func sendReinforcement(message: String, location: String) {
        guard let char = commandCharacteristic,
              let p = connectedPeripheral,
              let data = "reinforce:\(message)|\(location)".data(using: .utf8)
        else { return }
        p.writeValue(data, for: char, type: .withResponse)
    }

    func sendReinforcementReply(to team: String, accept: Bool) {
        guard let char = commandCharacteristic,
              let p = connectedPeripheral,
              let data = "rf_reply:\(team)|\(accept ? "JOIN" : "NAK")".data(using: .utf8)
        else { return }
        p.writeValue(data, for: char, type: .withResponse)
    }

    func sendTeamPing() {
        guard let char = commandCharacteristic,
              let p = connectedPeripheral,
              let data = "team_ping".data(using: .utf8)
        else { return }
        p.writeValue(data, for: char, type: .withResponse)
    }

    /// 發送命令回執（通知韌體 App 已收到 LoRa 命令）
    func sendCommandAck(_ commandID: String) {
        guard let char = commandCharacteristic,
              let p = connectedPeripheral,
              let data = BLEDataParser.encodeCommandAck(commandID)
        else { return }
        p.writeValue(data, for: char, type: .withResponse)
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isPoweredOn = central.state == .poweredOn
        if central.state != .poweredOn {
            isConnected = false
            isScanning = false
        }
    }

    func centralManager(_ central: CBCentralManager,
                         didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any],
                         rssi RSSI: NSNumber) {
        guard !discoveredDevices.contains(where: { $0.id == peripheral.identifier }) else { return }
        let name = peripheral.name ?? L("未知裝置")
        discoveredDevices.append(
            DiscoveredDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue, peripheral: peripheral)
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        reconnectTimer?.invalidate()
        reconnectDelay = 2  // 重連成功，重設退避計時
        connectedDeviceName = peripheral.name ?? "LinkGuard"
        peripheral.delegate = self
        print("[BLE] Connected to \(peripheral.name ?? "?"), discovering services...")
        peripheral.discoverServices([LinkGuardBLE.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                         didDisconnectPeripheral peripheral: CBPeripheral,
                         error: Error?) {
        isConnected = false
        commandCharacteristic = nil
        statusCharacteristic = nil
        statusBuffer.removeAll()
        // 自動重連（指數退避：2s → 4s → 8s … 最多 60s）
        if connectedPeripheral != nil {
            print("[BLE] Disconnected, will retry in \(reconnectDelay)s...")
            reconnectTimer?.invalidate()
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectDelay, repeats: false) { [weak self] _ in
                guard let self, let p = self.connectedPeripheral, self.centralManager.state == .poweredOn else { return }
                print("[BLE] Attempting reconnect...")
                self.centralManager.connect(p, options: nil)
            }
            reconnectDelay = min(reconnectDelay * 2, 60)
        }
    }

    func centralManager(_ central: CBCentralManager,
                         didFailToConnect peripheral: CBPeripheral,
                         error: Error?) {
        isConnected = false
        connectedPeripheral = nil
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("[BLE] Service discovery error: \(error)")
            return
        }
        guard let services = peripheral.services else {
            print("[BLE] No services found")
            return
        }
        print("[BLE] Found \(services.count) services")
        for service in services {
            peripheral.discoverCharacteristics([
                LinkGuardBLE.statusUUID,
                LinkGuardBLE.commandUUID,
                LinkGuardBLE.loraCommandUUID
            ], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didDiscoverCharacteristicsFor service: CBService,
                     error: Error?) {
        guard let chars = service.characteristics else {
            print("[BLE] No characteristics found")
            return
        }
        print("[BLE] Found \(chars.count) characteristics")
        for char in chars {
            switch char.uuid {
            case LinkGuardBLE.statusUUID:
                statusCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                print("[BLE] Subscribed to status notifications")
            case LinkGuardBLE.commandUUID:
                commandCharacteristic = char
                print("[BLE] Found command characteristic")
            case LinkGuardBLE.loraCommandUUID:
                peripheral.setNotifyValue(true, for: char)
                print("[BLE] Subscribed to LoRa command notifications")
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didUpdateValueFor characteristic: CBCharacteristic,
                     error: Error?) {
        if let error = error {
            print("[BLE] Read error: \(error)")
            return
        }
        guard let data = characteristic.value, !data.isEmpty else {
            print("[BLE] Empty data for \(characteristic.uuid)")
            return
        }

        print("[BLE] Received \(data.count) bytes from \(characteristic.uuid.uuidString.prefix(8))")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch characteristic.uuid {
            case LinkGuardBLE.statusUUID:
                // 累積 BLE 資料（處理 MTU 截斷導致 JSON 不完整的情況）
                // 韌體每次 notify 都是完整 JSON，但可能被 BLE 截斷
                // 檢測策略：如果 data 以 '{' 開頭，清空舊緩衝重新累積
                if let firstByte = data.first, firstByte == UInt8(ascii: "{") {
                    self.statusBuffer = data
                    self.statusBufferTimestamp = Date()
                } else {
                    self.statusBuffer.append(data)
                }

                // 嘗試解析完整 JSON
                if let status = BLEDataParser.parseStatusJSON(self.statusBuffer) {
                    self.statusBuffer.removeAll()
                    self.onStatusUpdate?(status)
                } else if self.statusBuffer.count > 4096 ||
                          Date().timeIntervalSince(self.statusBufferTimestamp) > 3 {
                    // 緩衝區過大或超時，放棄
                    print("[BLE] Status buffer overflow/timeout (\(self.statusBuffer.count) bytes), clearing")
                    self.statusBuffer.removeAll()
                }
            case LinkGuardBLE.loraCommandUUID:
                if let command = BLEDataParser.parseLoRaCommand(data) {
                    self.onLoRaCommand?(command)
                }
            default:
                break
            }
        }
    }

    // MARK: Notify 訂閱結果

    func peripheral(_ peripheral: CBPeripheral,
                     didUpdateNotificationStateFor characteristic: CBCharacteristic,
                     error: Error?) {
        if let error = error {
            print("[BLE] ❌ Notify subscribe FAILED for \(characteristic.uuid.uuidString.prefix(8)): \(error)")
        } else {
            print("[BLE] ✅ Notify \(characteristic.isNotifying ? "ON" : "OFF") for \(characteristic.uuid.uuidString.prefix(8))")
        }
    }

    // MARK: 服務變更

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        print("[BLE] Services invalidated: \(invalidatedServices.map { $0.uuid.uuidString })")
        // 重新探索服務
        peripheral.discoverServices([LinkGuardBLE.serviceUUID])
    }

    // MARK: Write 結果

    func peripheral(_ peripheral: CBPeripheral,
                     didWriteValueFor characteristic: CBCharacteristic,
                     error: Error?) {
        if let error = error {
            print("[BLE] ❌ Write FAILED: \(error)")
        } else {
            print("[BLE] ✅ Write OK to \(characteristic.uuid.uuidString.prefix(8))")
        }
    }
}
