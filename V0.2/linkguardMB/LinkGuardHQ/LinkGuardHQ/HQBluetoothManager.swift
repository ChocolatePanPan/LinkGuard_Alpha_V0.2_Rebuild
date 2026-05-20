import Foundation
import CoreBluetooth
import Combine

// MARK: - HQ BLE 常數（對應 HQ LoRa 韌體 UUID，與 Field 端不同）

struct HQLoRaBLE {
    static let serviceUUID      = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331915B")
    static let statusUUID       = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26B8")
    static let commandUUID      = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26BB")
    static let loraCommandUUID  = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26BC")
}

// MARK: - HQ LoRa 韌體狀態

struct HQLoRaStatus: Decodable {
    let id: String
    let freq: Double
    let bat: Int
    let vbat: Double
    let lvl: Int
    let pair: String
    let uptime: Int
    let hqNodes: [HQLoRaNode]
    let cmdCount: Int
}

struct HQLoRaNode: Decodable, Identifiable {
    let id: String
    let bat: Int
    let rssi: Double
    let snr: Double
    let online: Bool
}

struct HQLoRaReceivedCommand: Decodable {
    let cmd_id: String
    let type: String
    let pri: Int
    let title: String
    let detail: String
    let sender: String
}

// MARK: - 已發現 BLE 裝置

struct HQDiscoveredDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral
}

// MARK: - HQ LoRa 藍牙管理器

class HQBluetoothManager: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var isPoweredOn = false
    @Published var discoveredDevices: [HQDiscoveredDevice] = []
    @Published var connectedDeviceName: String?
    @Published var loraStatus: HQLoRaStatus?

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var statusBuffer = Data()
    private var statusBufferTimestamp = Date()
    private var reconnectTimer: Timer?
    private var reconnectDelay: TimeInterval = 2

    var onStatusUpdate: ((HQLoRaStatus) -> Void)?
    var onLoRaCommand: ((HQLoRaReceivedCommand) -> Void)?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - 掃描

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        isScanning = true
        discoveredDevices.removeAll()
        centralManager.scanForPeripherals(
            withServices: [HQLoRaBLE.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }

    // MARK: - 連線

    func connect(to device: HQDiscoveredDevice) {
        stopScanning()
        if let old = connectedPeripheral {
            centralManager.cancelPeripheralConnection(old)
        }
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

    // MARK: - 發送指令

    func sendLevelChange(_ level: Int) {
        sendBLE("setlvl:\(level)")
    }

    func sendPairChange(_ pair: String) {
        sendBLE("setpair:\(pair)")
    }

    func sendCommand(cmdId: String, type: String, priority: Int, title: String, detail: String) {
        sendBLE("cmd:\(cmdId):\(type):\(priority):\(title):\(detail)")
    }

    func sendBroadcast(msgType: String, payload: String) {
        sendBLE("broadcast:\(msgType):\(payload)")
    }

    private func sendBLE(_ text: String) {
        guard let char = commandCharacteristic,
              let p = connectedPeripheral,
              let data = text.data(using: .utf8)
        else { return }
        p.writeValue(data, for: char, type: .withResponse)
    }
}

// MARK: - CBCentralManagerDelegate

extension HQBluetoothManager: CBCentralManagerDelegate {

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
        let name = peripheral.name ?? "HQ LoRa"
        discoveredDevices.append(
            HQDiscoveredDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue, peripheral: peripheral)
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        reconnectTimer?.invalidate()
        reconnectDelay = 2
        connectedDeviceName = peripheral.name ?? "HQ LoRa"
        peripheral.delegate = self
        peripheral.discoverServices([HQLoRaBLE.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                         didDisconnectPeripheral peripheral: CBPeripheral,
                         error: Error?) {
        isConnected = false
        commandCharacteristic = nil
        loraStatus = nil
        statusBuffer.removeAll()
        // 自動重連（指數退避：2s → 4s → 8s … 最多 60s）
        if connectedPeripheral != nil {
            print("[HQ-BLE] Disconnected, will retry in \(reconnectDelay)s...")
            reconnectTimer?.invalidate()
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectDelay, repeats: false) { [weak self] _ in
                guard let self, let p = self.connectedPeripheral, self.centralManager.state == .poweredOn else { return }
                print("[HQ-BLE] Attempting reconnect...")
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

extension HQBluetoothManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([
                HQLoRaBLE.statusUUID,
                HQLoRaBLE.commandUUID,
                HQLoRaBLE.loraCommandUUID
            ], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didDiscoverCharacteristicsFor service: CBService,
                     error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            switch char.uuid {
            case HQLoRaBLE.statusUUID:
                peripheral.setNotifyValue(true, for: char)
            case HQLoRaBLE.commandUUID:
                commandCharacteristic = char
            case HQLoRaBLE.loraCommandUUID:
                peripheral.setNotifyValue(true, for: char)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didUpdateValueFor characteristic: CBCharacteristic,
                     error: Error?) {
        guard error == nil, let data = characteristic.value, !data.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch characteristic.uuid {
            case HQLoRaBLE.statusUUID:
                if let firstByte = data.first, firstByte == UInt8(ascii: "{") {
                    self.statusBuffer = data
                    self.statusBufferTimestamp = Date()
                } else {
                    self.statusBuffer.append(data)
                }
                if let status = try? JSONDecoder().decode(HQLoRaStatus.self, from: self.statusBuffer) {
                    self.statusBuffer.removeAll()
                    self.loraStatus = status
                    self.onStatusUpdate?(status)
                } else if self.statusBuffer.count > 4096 ||
                          Date().timeIntervalSince(self.statusBufferTimestamp) > 3 {
                    self.statusBuffer.removeAll()
                }
            case HQLoRaBLE.loraCommandUUID:
                if let cmd = try? JSONDecoder().decode(HQLoRaReceivedCommand.self, from: data) {
                    self.onLoRaCommand?(cmd)
                }
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didUpdateNotificationStateFor characteristic: CBCharacteristic,
                     error: Error?) {
        if let error = error {
            print("[HQ-BLE] Notify subscribe failed: \(error)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        peripheral.discoverServices([HQLoRaBLE.serviceUUID])
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didWriteValueFor characteristic: CBCharacteristic,
                     error: Error?) {
        if let error = error {
            print("[HQ-BLE] Write failed: \(error)")
        }
    }
}
