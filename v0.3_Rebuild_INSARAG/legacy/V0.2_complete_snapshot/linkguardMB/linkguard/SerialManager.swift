import Foundation

#if os(macOS)
import Combine
import IOKit
import IOKit.serial

/// macOS USB Serial 通訊管理器（連接 Heltec WiFi LoRa 32 V3）
class SerialManager: ObservableObject {

    @Published var isConnected = false
    @Published var availablePorts: [String] = []
    @Published var connectedPort: String?
    @Published var lastResponse: String = ""
    @Published var receivedLines: [String] = []

    /// LoRa 命令收到回呼（從其他節點轉發的命令）
    var onCommandReceived: ((String, String, Int, String, String, String) -> Void)?
    /// 狀態 JSON 回呼
    var onStatusReceived: ((String) -> Void)?

    private var fileDescriptor: Int32 = -1
    private var readThread: Thread?
    private var readBuffer = ""
    private let serialQueue = DispatchQueue(label: "com.linkguard.serial.read")

    init() {
        scanPorts()
    }

    // MARK: - 掃描 Serial Ports

    func scanPorts() {
        availablePorts = Self.listSerialPorts()
    }

    static func listSerialPorts() -> [String] {
        var ports: [String] = []
        let matchingDict = IOServiceMatching(kIOSerialBSDServiceValue)
        var iterator: io_iterator_t = 0

        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard result == KERN_SUCCESS else { return ports }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let pathAsCFString = IORegistryEntryCreateCFProperty(
                service, "IOCalloutDevice" as CFString, kCFAllocatorDefault, 0
            )?.takeUnretainedValue() as? String {
                // 過濾只顯示 USB serial（排除 Bluetooth 等）
                if pathAsCFString.contains("usbserial") ||
                   pathAsCFString.contains("usbmodem") ||
                   pathAsCFString.contains("SLAB") ||
                   pathAsCFString.contains("wchusbserial") ||
                   pathAsCFString.contains("cu.") {
                    ports.append(pathAsCFString)
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
        return ports.sorted()
    }

    // MARK: - 連線 / 斷線

    func connect(to port: String, baudRate: speed_t = 115200) {
        disconnect()

        fileDescriptor = open(port, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fileDescriptor >= 0 else {
            print("[Serial] 無法開啟 \(port)")
            return
        }

        // 設定 serial port 參數
        var options = termios()
        tcgetattr(fileDescriptor, &options)
        cfsetispeed(&options, baudRate)
        cfsetospeed(&options, baudRate)
        options.c_cflag |= UInt(CS8)           // 8 bits
        options.c_cflag |= UInt(CLOCAL)        // 不使用 modem 控制
        options.c_cflag |= UInt(CREAD)         // 允許讀取
        options.c_cflag &= ~UInt(PARENB)       // 無 parity
        options.c_cflag &= ~UInt(CSTOPB)       // 1 stop bit
        options.c_lflag &= ~UInt(ICANON)       // raw mode
        options.c_lflag &= ~UInt(ECHO)
        options.c_cc.16 = 1  // VMIN
        options.c_cc.17 = 10 // VTIME (1 second timeout)
        tcsetattr(fileDescriptor, TCSANOW, &options)

        // 清除 non-blocking flag
        var flags = fcntl(fileDescriptor, F_GETFL)
        flags &= ~O_NONBLOCK
        fcntl(fileDescriptor, F_SETFL, flags)

        connectedPort = port
        isConnected = true
        startReading()
        print("[Serial] 已連接 \(port)")
    }

    func disconnect() {
        readThread?.cancel()
        readThread = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectedPort = nil
        }
    }

    // MARK: - 發送

    func send(_ text: String) {
        guard fileDescriptor >= 0,
              let data = (text + "\n").data(using: .utf8) else { return }
        data.withUnsafeBytes { ptr in
            _ = write(fileDescriptor, ptr.baseAddress, data.count)
        }
    }

    /// 發送指揮命令
    func sendCommand(cmdId: String, type: String, priority: Int, title: String, detail: String) {
        let line = "CMD:\(cmdId):\(type):\(priority):\(title):\(detail)"
        send(line)
    }

    /// 請求狀態
    func requestStatus() {
        send("STATUS")
    }

    /// Ping 測試
    func ping() {
        send("PING")
    }

    // MARK: - 讀取

    private func startReading() {
        readThread = Thread { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while !Thread.current.isCancelled && self.fileDescriptor >= 0 {
                let bytesRead = read(self.fileDescriptor, &buffer, buffer.count)
                if bytesRead > 0 {
                    if let str = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
                        self.processIncoming(str)
                    }
                } else if bytesRead < 0 && errno != EAGAIN {
                    break
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.isConnected = false
                self?.connectedPort = nil
            }
        }
        readThread?.start()
    }

    private func processIncoming(_ text: String) {
        serialQueue.sync {
            readBuffer += text
        }
        var lines: [String] = []
        serialQueue.sync {
            while let newlineRange = readBuffer.range(of: "\n") {
                let line = String(readBuffer[readBuffer.startIndex..<newlineRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                readBuffer = String(readBuffer[newlineRange.upperBound...])
                if !line.isEmpty { lines.append(line) }
            }
        }
        for line in lines {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lastResponse = line
                self.receivedLines.append(line)
                // 限制最大行數
                if self.receivedLines.count > 200 {
                    self.receivedLines.removeFirst(50)
                }
            }

            // 解析特殊回應
            if line.starts(with: "CMD_RX:") {
                // CMD_RX:cmdId:type:pri:title:detail:sender
                let parts = line.dropFirst(7).components(separatedBy: ":")
                if parts.count >= 6, let cmdId = parts.first {
                    let type = parts[1]
                    let pri = Int(parts[2]) ?? 0
                    let title = parts[3]
                    let detail = parts[4]
                    let sender = parts[5]
                    DispatchQueue.main.async { [weak self] in
                        self?.onCommandReceived?(cmdId, type, pri, title, detail, sender)
                    }
                }
            } else if line.starts(with: "{") {
                // JSON 狀態回應
                DispatchQueue.main.async { [weak self] in
                    self?.onStatusReceived?(line)
                }
            }
        }
    }
}
#endif
