import SwiftUI
import Combine

// MARK: - 電台通訊 Tab（骨架 UI，觸控優化，支援橫豎屏）

struct MWRadioTab: View {
    @ObservedObject var vm: MilkyWayCommandViewModel
    @State private var selectedChannel: MWRadioChannel = .cmd
    @State private var pttActive = false
    @State private var messages: [MWRadioMessage] = MWRadioMessage.samples
    @State private var draft = ""
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        NavigationStack {
            Group {
                if hSizeClass == .regular {
                    // iPad 橫屏：左右分欄
                    HStack(spacing: 0) {
                        sidePanel.frame(width: 280)
                        Divider()
                        mainPanel
                    }
                } else {
                    // 豎屏或 compact：上下
                    VStack(spacing: 0) {
                        channelPicker
                        Divider()
                        mainPanel
                    }
                }
            }
            .background(MWTheme.bg.ignoresSafeArea())
            .navigationTitle("電台通訊")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 左欄（regular 模式）

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("頻道")
                .font(.headline)
                .padding(16)
            Divider()
            ForEach(MWRadioChannel.allCases) { ch in
                Button {
                    selectedChannel = ch
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: ch.icon)
                            .foregroundStyle(selectedChannel == ch ? MWTheme.green : .secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ch.name)
                                .font(.subheadline.bold())
                                .foregroundStyle(selectedChannel == ch ? .primary : .secondary)
                            Text(ch.frequency)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedChannel == ch {
                            Image(systemName: "checkmark")
                                .foregroundStyle(MWTheme.green)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: MWTouch.minH)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(selectedChannel == ch ? MWTheme.green.opacity(0.08) : .clear)
            }
            Spacer()
            statusIndicator.padding(16)
        }
        .background(MWTheme.surface.opacity(0.5))
    }

    // MARK: - 頻道 Picker（compact 模式）

    private var channelPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MWRadioChannel.allCases) { ch in
                    Button {
                        selectedChannel = ch
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: ch.icon)
                            Text(ch.name)
                                .font(.subheadline.bold())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selectedChannel == ch ? MWTheme.green : MWTheme.surface)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(MWTheme.bg)
    }

    // MARK: - 主面板（訊息 + PTT）

    private var mainPanel: some View {
        VStack(spacing: 0) {
            // 頻道標頭
            HStack(spacing: 10) {
                Image(systemName: selectedChannel.icon)
                    .foregroundStyle(MWTheme.green)
                Text(selectedChannel.name)
                    .font(.title3.bold())
                Text(selectedChannel.frequency)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                statusIndicator
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(MWTheme.surface.opacity(0.6))

            Divider()

            // 訊息紀錄
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages.filter { $0.channel == selectedChannel.rawValue || $0.channel == "all" }) { msg in
                        MWRadioMessageRow(msg: msg)
                    }
                }
                .padding(16)
            }

            Divider()

            // 輸入列 + PTT
            HStack(alignment: .bottom, spacing: 12) {
                TextField("發送文字訊息...", text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(MWTheme.surface, in: RoundedRectangle(cornerRadius: 10))

                if !draft.isEmpty {
                    Button {
                        sendText()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.title3)
                            .foregroundStyle(.black)
                            .frame(width: 48, height: 48)
                            .background(MWTheme.green, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                // PTT 大按鈕
                Button {
                    pttActive.toggle()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: pttActive ? "mic.fill" : "mic")
                            .font(.system(size: 32, weight: .bold))
                        Text(pttActive ? "放開" : "PTT")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(pttActive ? .black : MWTheme.green)
                    .frame(width: 80, height: 80)
                    .background(pttActive ? MWTheme.green : MWTheme.green.opacity(0.14),
                                in: Circle())
                    .contentShape(Circle())
                    .scaleEffect(pttActive ? 1.08 : 1.0)
                    .animation(.spring(response: 0.2), value: pttActive)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(MWTheme.bg)
        }
    }

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(vm.commandNetworkEnabled ? MWTheme.green : MWTheme.amber)
                .frame(width: 8, height: 8)
            Text(vm.commandNetworkEnabled ? "聯網" : "離線")
                .font(.caption.bold())
                .foregroundStyle(vm.commandNetworkEnabled ? MWTheme.green : MWTheme.amber)
        }
    }

    private func sendText() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        messages.insert(MWRadioMessage(channel: selectedChannel.rawValue, sender: "指揮官", content: text, time: Date()), at: 0)
        draft = ""
        vm.logs.insert(MWLogEntry(title: "電台發送", detail: "[\(selectedChannel.name)] \(text)", time: Date(), color: MWTheme.cyan), at: 0)
    }
}

// MARK: - 模型

enum MWRadioChannel: String, CaseIterable, Identifiable {
    case cmd   = "CMD"
    case alpha = "ALPHA"
    case bravo = "BRAVO"
    case med   = "MED"
    case log   = "LOG"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .cmd:   return "指揮頻道"
        case .alpha: return "Alpha 組"
        case .bravo: return "Bravo 組"
        case .med:   return "醫療組"
        case .log:   return "後勤"
        }
    }

    var frequency: String {
        switch self {
        case .cmd:   return "155.000 MHz"
        case .alpha: return "155.050 MHz"
        case .bravo: return "155.100 MHz"
        case .med:   return "155.150 MHz"
        case .log:   return "155.200 MHz"
        }
    }

    var icon: String {
        switch self {
        case .cmd:   return "antenna.radiowaves.left.and.right"
        case .alpha: return "person.fill.badge.plus"
        case .bravo: return "shield.fill"
        case .med:   return "cross.case.fill"
        case .log:   return "shippingbox.fill"
        }
    }
}

struct MWRadioMessage: Identifiable {
    let id = UUID()
    let channel: String
    let sender: String
    let content: String
    let time: Date

    static let samples: [MWRadioMessage] = [
        MWRadioMessage(channel: "CMD", sender: "Alpha 組", content: "A棟2樓已清空，移往3樓搜救。", time: Date().addingTimeInterval(-180)),
        MWRadioMessage(channel: "MED", sender: "醫療組", content: "需要額外擔架，臨時醫療區。", time: Date().addingTimeInterval(-320)),
        MWRadioMessage(channel: "CMD", sender: "指揮官", content: "Bravo 組待命，等待工程評估。", time: Date().addingTimeInterval(-480)),
        MWRadioMessage(channel: "all", sender: "後勤", content: "氧氣瓶補充完成，南側門待領。", time: Date().addingTimeInterval(-600)),
    ]
}

private struct MWRadioMessageRow: View {
    let msg: MWRadioMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(MWTheme.cyan)
                Text(msg.sender)
                    .font(.subheadline.bold())
                Spacer()
                Text(msg.time, style: .time)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(msg.content)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MWTheme.elevated.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
    }
}
