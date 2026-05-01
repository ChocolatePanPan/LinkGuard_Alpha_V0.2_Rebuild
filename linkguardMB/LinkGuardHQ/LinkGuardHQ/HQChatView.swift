import SwiftUI

struct HQChatView: View {
    @ObservedObject var vm: HQViewModel
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            // 訊息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(vm.chatMessages) { msg in
                            ChatBubble(
                                message: msg,
                                isFromHQ: msg.senderID == "HQ",
                                readCount: vm.chatReadCounts[msg.id] ?? 0
                            )
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: vm.chatMessages.count) { _ in
                    if let last = vm.chatMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // 輸入列
            HStack(spacing: 10) {
                TextField(L("輸入訊息…"), text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)

                // @ 提及選單
                Menu {
                    if vm.personnelAssignments.isEmpty {
                        Text(L("尚無人員"))
                    } else {
                        ForEach(vm.personnelAssignments) { p in
                            let tag = (p.nickname?.isEmpty == false) ? p.nickname! : p.name
                            Button("\(tag)  (\(String(p.id.suffix(6))))") {
                                if draft.hasSuffix(" ") || draft.isEmpty {
                                    draft += "@\(tag) "
                                } else {
                                    draft += " @\(tag) "
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "at")
                        .font(.title3)
                }
                .tint(NV.command)
                .disabled(vm.personnelAssignments.isEmpty)

                Button {
                    vm.sendChat(draft)
                    draft = ""
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !vm.server.isRunning)
                .tint(NV.command)
            }
            .padding()
        }
        .navigationTitle(L("通訊頻道"))
    }
}

// MARK: - 聊天氣泡

struct ChatBubble: View {
    let message: ChatMessage
    let isFromHQ: Bool
    var readCount: Int = 0

    var body: some View {
        HStack {
            if isFromHQ { Spacer(minLength: 60) }
            VStack(alignment: isFromHQ ? .trailing : .leading, spacing: 4) {
                Text(message.senderName)
                    .font(.caption2).foregroundColor(.secondary)
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isFromHQ ? NV.command.opacity(NV.tagOpacity) : Color.gray.opacity(NV.tagOpacity))
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
                    if isFromHQ && readCount > 0 {
                        Text(L("已讀 %lld", readCount))
                            .font(.caption2)
                            .foregroundColor(NV.info)
                    }
                }
            }
            if !isFromHQ { Spacer(minLength: 60) }
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private var timeText: String {
        Self.timeFmt.string(from: Date(timeIntervalSince1970: message.timestamp))
    }
}
