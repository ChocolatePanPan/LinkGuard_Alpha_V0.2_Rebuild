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

    var onCommandReceived: ((String, String, Int, String, String, String) -> Void)?
    var onStatusReceived: ((String) -> Void)?

    private var fileDescriptor: Int32 = -1
    private var readThread: Thread?
    private var readBuffer = ""

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

        var options = termios()
        tcgetattr(fileDescriptor, &options)
        cfsetispeed(&options, baudRate)
        cfsetospeed(&options, baudRate)
        options.c_cflag |= UInt(CS8)
        options.c_cflag |= UInt(CLOCAL)
        options.c_cflag |= UInt(CREAD)
        options.c_cflag &= ~UInt(PARENB)
        options.c_cflag &= ~UInt(CSTOPB)
        options.c_lflag &= ~UInt(ICANON)
        options.c_lflag &= ~UInt(ECHO)
        options.c_cc.16 = 1
        options.c_cc.17 = 10
        tcsetattr(fileDescriptor, TCSANOW, &options)

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
        guard fileDescriptor >= 0 else { return }
        let data = (text + "\n").data(using: .utf8)!
        data.withUnsafeBytes { ptr in
            _ = write(fileDescriptor, ptr.baseAddress, data.count)
        }
    }

    func sendCommand(cmdId: String, type: String, priority: Int, title: String, detail: String) {
        let line = "CMD:\(cmdId):\(type):\(priority):\(title):\(detail)"
        send(line)
    }

    func requestStatus() { send("STATUS") }
    func ping() { send("PING") }

    // MARK: - 讀取

    private func startReading() {
        readThread = Thread {
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
            DispatchQueue.main.async {
                self.isConnected = false
                self.connectedPort = nil
            }
        }
        readThread?.start()
    }

    private func processIncoming(_ text: String) {
        readBuffer += text
        while let newlineRange = readBuffer.range(of: "\n") {
            let line = String(readBuffer[readBuffer.startIndex..<newlineRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            readBuffer = String(readBuffer[newlineRange.upperBound...])

            guard !line.isEmpty else { continue }

            DispatchQueue.main.async {
                self.lastResponse = line
                self.receivedLines.append(line)
                if self.receivedLines.count > 200 {
                    self.receivedLines.removeFirst(50)
                }
            }

            if line.starts(with: "CMD_RX:") {
                let parts = line.dropFirst(7).components(separatedBy: ":")
                if parts.count >= 6 {
                    DispatchQueue.main.async {
                        self.onCommandReceived?(parts[0], parts[1], Int(parts[2]) ?? 0, parts[3], parts[4], parts[5])
                    }
                }
            } else if line.starts(with: "{") {
                DispatchQueue.main.async {
                    self.onStatusReceived?(line)
                }
            }
        }
    }
}
#endif
