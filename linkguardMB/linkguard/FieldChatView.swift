import SwiftUI

// MARK: - 前線通訊介面

struct FieldChatView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 標題列
                HStack {
                    Text(L("全域通訊頻道"))
                        .font(.title2).bold()
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // 連線狀態 banner
                if !vm.commandClient.isConnected {
                    HStack {
                        Image(systemName: "wifi.slash")
                        Text(L("未連線 Mac HQ，訊息無法發送"))
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(NV.danger)
                }

                // 訊息列表
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(vm.chatMessages.enumerated()), id: \.element.id) { idx, msg in
                                // 時間分隔（首則或間隔 >5 分鐘）
                                if idx == 0 || msg.timestamp - vm.chatMessages[idx - 1].timestamp > 300 {
                                    Text(chatTimeSeparator(msg.timestamp))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }

                                FieldChatBubble(
                                    message: msg,
                                    isSelf: msg.senderID == vm.nodeStatus.nodeID,
                                    showSender: idx == 0
                                        || vm.chatMessages[idx - 1].senderID != msg.senderID
                                        || msg.timestamp - vm.chatMessages[idx - 1].timestamp > 300,
                                    readCount: vm.chatReadCounts[msg.id] ?? 0
                                )
                                .id(msg.id)
                            }
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: vm.chatMessages.count) { _, _ in
                        if let last = vm.chatMessages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                Divider()

                // 預設訊息模板
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presetMessages) { preset in
                            Button {
                                vm.sendChat(preset.text)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: preset.icon)
                                        .font(.caption2)
                                    Text(preset.text)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .tint(NV.command)
                            .disabled(!vm.commandClient.isConnected)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }

                // 輸入列
                HStack(spacing: 10) {
                    TextField(L("輸入訊息…"), text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        .submitLabel(.send)
                        .onSubmit {
                            guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                  vm.commandClient.isConnected else { return }
                            vm.sendChat(draft)
                            draft = ""
                        }

                    // @ 提及選單
                    Menu {
                        let members = mentionCandidates()
                        if members.isEmpty {
                            Text(L("尚無人員"))
                        } else {
                            ForEach(Array(members.enumerated()), id: \.offset) { _, m in
                                Button("\(m.tag)  (\(String(m.id.suffix(6))))") {
                                    if draft.hasSuffix(" ") || draft.isEmpty {
                                        draft += "@\(m.tag) "
                                    } else {
                                        draft += " @\(m.tag) "
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "at")
                            .font(.title3)
                    }
                    .tint(NV.command)

                    Button {
                        vm.sendChat(draft)
                        draft = ""
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.title3)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !vm.commandClient.isConnected)
                    .tint(NV.command)
                }
                .padding()
            }
            .navigationTitle(L("全域通訊頻道"))
            #if os(iOS)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("完成")) {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            #endif
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f
    }()

    private func chatTimeSeparator(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts)
        return Calendar.current.isDateInToday(date)
            ? Self.timeFmt.string(from: date)
            : Self.dateFmt.string(from: date)
    }

    private struct MentionCandidate {
        let id: String
        let tag: String
    }

    private func mentionCandidates() -> [MentionCandidate] {
        var out: [MentionCandidate] = []
        for p in vm.personnelAssignments {
            let nick = p.nickname ?? ""
            let tag = nick.isEmpty ? p.name : nick
            out.append(MentionCandidate(id: p.id, tag: tag))
        }
        for t in vm.teamMembers {
            let nick = t.nickname ?? ""
            let tag = nick.isEmpty ? t.id : nick
            out.append(MentionCandidate(id: t.id, tag: tag))
        }
        return out
    }
}

struct FieldChatBubble: View {
    let message: ChatMessage
    let isSelf: Bool
    var showSender: Bool = true
    var readCount: Int = 0

    var body: some View {
        HStack {
            if isSelf { Spacer(minLength: 60) }
            VStack(alignment: isSelf ? .trailing : .leading, spacing: 4) {
                if showSender {
                    HStack(spacing: 4) {
                        Text(message.senderName)
                            .font(.caption2).foregroundColor(.secondary)
                        if message.senderID == "HQ" || message.senderName.contains("HQ") {
                            Text("HQ")
                                .font(.caption2).bold()
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(NV.command.opacity(0.3))
                                .cornerRadius(4)
                        }
                    }
                }
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isSelf ? NV.green.opacity(0.2) :
                                (message.senderID == "HQ") ? NV.command.opacity(0.15) : Color.gray.opacity(0.15))
                    .cornerRadius(16)
                if !message.mentions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(message.mentions.prefix(5), id: \.self) { mid in
                            Text("@\(String(mid.suffix(6)))")
                                .font(.caption2)
                                .foregroundColor(NV.command)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(NV.command.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                }
                HStack(spacing: 6) {
                    Text(timeText)
                        .font(.caption2).foregroundColor(.secondary)
                    if isSelf && readCount > 0 {
                        Text(L("已讀 %lld", readCount))
                            .font(.caption2)
                            .foregroundColor(NV.info)
                    }
                }
            }
            if !isSelf { Spacer(minLength: 60) }
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private var timeText: String {
        Self.timeFmt.string(from: Date(timeIntervalSince1970: message.timestamp))
    }
}
