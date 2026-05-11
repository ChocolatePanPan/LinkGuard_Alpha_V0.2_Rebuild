import SwiftUI

#if os(macOS)
/// macOS 控制中心視圖 — 透過 USB Serial 連接 Heltec 發送 LoRa 命令
struct CommandCenterView: View {
    @StateObject private var serial = SerialManager()
    @State private var selectedPort: String?
    @State private var commandTitle = ""
    @State private var commandDetail = ""
    @State private var commandType = "evacuation"
    @State private var commandPriority = 0
    @State private var sentCommands: [SentCommand] = []
    @State private var showConsole = false

    private let typeOptions = [
        ("search", L("搜索區域")), ("standby", L("原地待命")), ("support", L("支援請求")),
        ("report", L("狀態回報")), ("evacuation", L("撤離命令"))
    ]
    private let priorityOptions = [(0, L("一般")), (1, L("緊急")), (2, L("最高"))]

    var body: some View {
        NavigationSplitView {
            // 側邊欄：連線 + 命令歷史
            List {
                Section(L("Serial 連線")) {
                    connectionSection
                }
                Section(L("已發送命令")) {
                    if sentCommands.isEmpty {
                        Text(L("尚未發送任何命令"))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(sentCommands) { cmd in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    priorityBadge(cmd.priority)
                                    Text(cmd.title).bold()
                                }
                                Text(cmd.detail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(cmd.timeText)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } detail: {
            VStack(spacing: 0) {
                // 標題
                HStack {
                    VStack(alignment: .leading) {
                        Text(L("LinkGuard 指揮中心"))
                            .font(.largeTitle).bold()
                        Text("LoRa Command Center")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(serial.isConnected ? .green : .gray)
                        .frame(width: 10, height: 10)
                    Text(serial.isConnected ? L("已連線") : L("未連線"))
                        .font(.caption)
                        .foregroundColor(serial.isConnected ? .green : .gray)
                }
                .padding()

                Divider()

                // 發送命令表單
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        commandForm
                        Divider()
                        quickCommands
                        if showConsole {
                            Divider()
                            consoleView
                        }
                    }
                    .padding()
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showConsole.toggle()
                } label: {
                    Image(systemName: "terminal")
                }
                .help("Serial Console")
            }
            ToolbarItem {
                Button {
                    serial.scanPorts()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(L("重新掃描 Serial Ports"))
            }
        }
    }

    // MARK: - 連線區塊

    private var connectionSection: some View {
        Group {
            if serial.availablePorts.isEmpty {
                HStack {
                    Image(systemName: "usb")
                        .foregroundColor(.secondary)
                    Text(L("未偵測到裝置"))
                        .foregroundColor(.secondary)
                }
                Button(L("重新掃描")) { serial.scanPorts() }
                    .buttonStyle(.borderedProminent)
            } else {
                ForEach(serial.availablePorts, id: \.self) { port in
                    HStack {
                        Image(systemName: "cable.connector")
                        VStack(alignment: .leading) {
                            Text(port.components(separatedBy: "/").last ?? port)
                                .font(.caption).bold()
                            Text(port)
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        if serial.connectedPort == port {
                            Button(L("斷開")) { serial.disconnect() }
                                .buttonStyle(.bordered)
                                .tint(.red)
                        } else {
                            Button(L("連線")) { serial.connect(to: port) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 命令表單

    private var commandForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("發送指揮命令"))
                .font(.headline)

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text(L("類型")).font(.caption).foregroundColor(.secondary)
                    Picker("", selection: $commandType) {
                        ForEach(typeOptions, id: \.0) { key, label in
                            Text(label).tag(key)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                VStack(alignment: .leading) {
                    Text(L("優先等級")).font(.caption).foregroundColor(.secondary)
                    Picker("", selection: $commandPriority) {
                        ForEach(priorityOptions, id: \.0) { val, label in
                            Text(label).tag(val)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            }

            VStack(alignment: .leading) {
                Text(L("命令標題")).font(.caption).foregroundColor(.secondary)
                TextField(L("例：立即撤離 A 區"), text: $commandTitle)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading) {
                Text(L("命令詳情")).font(.caption).foregroundColor(.secondary)
                TextField(L("例：偵測到餘震風險，所有人員立即撤離至安全區"), text: $commandDetail)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button {
                    sendCustomCommand()
                } label: {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text(L("發送命令"))
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(commandPriority == 2 ? .red : (commandPriority == 1 ? .orange : .blue))
                .disabled(!serial.isConnected || commandTitle.isEmpty)

                if !serial.isConnected {
                    Text(L("請先連接 Serial"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 快速命令

    private var quickCommands: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("快速命令"))
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                QuickCmdButton(title: L("搜索 A 區"), icon: "map.fill", color: .blue) {
                    sendQuick("search", 0, L("搜索 A 區"), L("請前往 A 區進行生命跡象掃描"))
                }
                QuickCmdButton(title: L("原地待命"), icon: "pause.circle.fill", color: .gray) {
                    sendQuick("standby", 0, L("原地待命"), L("請暫停搜索等待下一步指示"))
                }
                QuickCmdButton(title: L("請求支援"), icon: "hand.raised.fill", color: .orange) {
                    sendQuick("support", 1, L("請求支援"), L("需要額外人力支援"))
                }
                QuickCmdButton(title: L("狀態回報"), icon: "doc.text.fill", color: .green) {
                    sendQuick("report", 0, L("回報狀態"), L("請各隊伍回報搜索進度與人員狀態"))
                }
                QuickCmdButton(title: L("緊急撤離"), icon: "arrow.uturn.backward.circle.fill", color: .red) {
                    sendQuick("evacuation", 2, L("立即撤離"), L("偵測到餘震風險，所有人員立即撤離至安全區"))
                }
                QuickCmdButton(title: L("緊急增援"), icon: "bolt.circle.fill", color: .red) {
                    sendQuick("support", 2, L("緊急增援"), L("發現多名受困者，人力不足請立即增援"))
                }
            }
            .disabled(!serial.isConnected)
        }
    }

    // MARK: - Serial Console

    private var consoleView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Serial Console")
                    .font(.headline)
                Spacer()
                Button(L("清除")) { serial.receivedLines.removeAll() }
                    .buttonStyle(.bordered)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(serial.receivedLines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(lineColor(line))
                                .id(idx)
                        }
                    }
                }
                .frame(height: 200)
                .padding(8)
                .background(Color.black.opacity(0.8))
                .cornerRadius(8)
                .onChange(of: serial.receivedLines.count) {
                    if let last = serial.receivedLines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - 邏輯

    private func sendCustomCommand() {
        let cmdId = UUID().uuidString.prefix(8).lowercased()
        serial.sendCommand(
            cmdId: String(cmdId), type: commandType,
            priority: commandPriority, title: commandTitle, detail: commandDetail
        )
        let cmd = SentCommand(
            id: UUID(), type: commandType, priority: commandPriority,
            title: commandTitle, detail: commandDetail, time: Date()
        )
        sentCommands.insert(cmd, at: 0)
        commandTitle = ""
        commandDetail = ""
    }

    private func sendQuick(_ type: String, _ pri: Int, _ title: String, _ detail: String) {
        let cmdId = UUID().uuidString.prefix(8).lowercased()
        serial.sendCommand(cmdId: String(cmdId), type: type, priority: pri, title: title, detail: detail)
        let cmd = SentCommand(id: UUID(), type: type, priority: pri, title: title, detail: detail, time: Date())
        sentCommands.insert(cmd, at: 0)
    }

    private func priorityBadge(_ pri: Int) -> some View {
        let (text, color): (String, Color) = switch pri {
        case 2: (L("最高"), .red)
        case 1: (L("緊急"), .orange)
        default: (L("一般"), .blue)
        }
        return Text(text)
            .font(.caption2).bold()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2))
            .cornerRadius(4)
            .foregroundColor(color)
    }

    private func lineColor(_ line: String) -> Color {
        if line.contains("CMD") || line.contains("TX-CMD") { return .cyan }
        if line.contains("ERR") || line.contains("FAIL") { return .red }
        if line.contains("OK") || line.contains("PONG") { return .green }
        if line.contains("RX") { return .yellow }
        return .white
    }
}

// MARK: - 快速命令按鈕

private struct QuickCmdButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption).bold()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }
}

// MARK: - 已發送命令記錄

private struct SentCommand: Identifiable {
    let id: UUID
    let type: String
    let priority: Int
    let title: String
    let detail: String
    let time: Date

    var timeText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: time)
    }
}

#Preview {
    CommandCenterView()
        .frame(width: 900, height: 600)
}
#endif
