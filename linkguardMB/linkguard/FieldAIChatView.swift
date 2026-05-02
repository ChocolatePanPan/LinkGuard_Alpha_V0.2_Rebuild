import SwiftUI

// =====================================================
//  Field AI Chat — 前線搜救人員與 Gemma4 AI 自由對話
//  呼叫 Win11 backend gemma4_server :8001/chat
//  Host 取自 vm.transcriptionServerHost（HQ 連線解析的真正 IP）
// =====================================================

struct FieldAIMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String          // "user" | "assistant"
    let content: String
    let timestamp: Date
    let model: String?
    let elapsedMs: Int?
    let isError: Bool

    init(role: String, content: String, timestamp: Date = Date(),
         model: String? = nil, elapsedMs: Int? = nil, isError: Bool = false) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.model = model
        self.elapsedMs = elapsedMs
        self.isError = isError
    }
}

struct FieldAIChatView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @State private var messages: [FieldAIMessage] = []
    @State private var draft: String = ""
    @State private var isSending: Bool = false
    @State private var typingPulse: Bool = false
    @State private var includeContext: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider().background(NV.command.opacity(0.25))
            if vm.isAIServicePaused {
                AIServicePausedBanner(message: vm.aiServicePauseMessage)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if messages.isEmpty && !isSending {
                                emptyHint.padding(.top, 60)
                            }
                            ForEach(messages) { msg in
                                bubble(for: msg).id(msg.id)
                            }
                            if isSending {
                                typingIndicator.id("typing")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: isSending) { _, sending in
                        if sending {
                            withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                        }
                    }
                }

                Divider().background(NV.command.opacity(0.25))
                inputBar
            }
            .aiPausedAppearance(vm.isAIServicePaused)
        }
        .navigationTitle(L("AI 助理"))
    }

    // MARK: - 子元件

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(vm.isAIServicePaused ? Color.gray : vm.commandClient.isConnected ? NV.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(vm.isAIServicePaused ? L("AI服務暫停") : "FIELD AI ASSISTANT")
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundColor(vm.isAIServicePaused ? .secondary : NV.command)
                .tracking(2)
            Spacer()
            Toggle(isOn: $includeContext) {
                Text(L("附帶現場資訊"))
                    .font(.caption2)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(NV.info)
            Button {
                messages.removeAll()
            } label: {
                Image(systemName: "trash").font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(messages.isEmpty || isSending)
            .foregroundColor(messages.isEmpty ? .secondary : NV.warning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.25))
    }

    private var emptyHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundColor(NV.command.opacity(0.3))
            Text(L("AI 助理"))
                .font(.system(.headline, design: .monospaced).bold())
                .foregroundColor(NV.command.opacity(0.7))
                .tracking(4)
            Text(L("詢問處置建議 / 醫療判斷 / SOP / 翻譯 / 災情評估"))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("試試問："))
                    .font(.caption2).foregroundColor(.secondary)
                ForEach(quickPrompts, id: \.self) { p in
                    Button {
                        draft = p
                    } label: {
                        Text("• \(p)")
                            .font(.caption)
                            .foregroundColor(NV.info)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private let quickPrompts: [String] = [
        L("呼吸 36 次/分鐘且意識模糊，要怎麼處置？"),
        L("這個傷患需要立刻後送嗎？"),
        L("瓦斯外洩疑慮，撤離半徑多少？"),
        L("CPR 按壓深度與頻率？"),
    ]

    @ViewBuilder
    private func bubble(for msg: FieldAIMessage) -> some View {
        let isUser = msg.role == "user"
        let bg: Color = msg.isError ? NV.danger.opacity(0.18)
            : isUser ? NV.command.opacity(0.20) : NV.green.opacity(0.12)
        let border: Color = msg.isError ? NV.danger.opacity(0.5)
            : isUser ? NV.command.opacity(0.5) : NV.green.opacity(0.5)
        let accent: Color = msg.isError ? NV.danger
            : isUser ? NV.command : NV.green

        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 32) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: isUser ? "person.fill" : "sparkles")
                        .font(.caption2).foregroundColor(accent)
                    Text(isUser ? L("搜救人員") : (msg.model ?? "GEMMA4 AI"))
                        .font(.system(.caption2, design: .monospaced).bold())
                        .foregroundColor(accent)
                        .tracking(1)
                    Spacer()
                    Text(timeFormatter.string(from: msg.timestamp))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Text(msg.content)
                    .font(.body)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !isUser, let ms = msg.elapsedMs {
                    Text(L("耗時 %lld ms", ms))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bg)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            if !isUser { Spacer(minLength: 32) }
        }
    }

    private var typingIndicator: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.caption2)
                Text(L("AI 思考中..."))
                    .font(.system(.caption, design: .monospaced))
                    .tracking(2)
            }
            .foregroundColor(NV.green.opacity(typingPulse ? 1.0 : 0.4))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(NV.green.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(NV.green.opacity(0.4), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    typingPulse.toggle()
                }
            }
            Spacer()
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(L("向 AI 提問現場狀況或醫療建議"), text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(isSending)
                .onSubmit { send() }

            Button {
                send()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.title3)
                    .foregroundColor(.black)
                    .padding(12)
                    .background(canSend ? NV.green : NV.green.opacity(0.3))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(12)
    }

    // MARK: - 行為

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isSending && vm.isFieldAIAvailable
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        guard !vm.isAIServicePaused else {
            messages.append(FieldAIMessage(
                role: "assistant",
                content: L("AI服務暫停"),
                isError: true
            ))
            return
        }
        let host = vm.transcriptionServerHost
        guard !host.isEmpty, host != "localhost" else {
            messages.append(FieldAIMessage(
                role: "assistant",
                content: L("尚未連接到 AI 伺服器，請先連線 HQ。"),
                isError: true
            ))
            return
        }
        let userMsg = FieldAIMessage(role: "user", content: text)
        messages.append(userMsg)
        draft = ""
        isSending = true

        // 收集現場上下文（受困者數量、傷患摘要、災情）作為提示，
        // 讓 AI 回答時能對齊當下情境
        let composedMessage = includeContext ? composeWithContext(text) : text
        let history = messages.dropLast().suffix(12).map {
            ["role": $0.role, "content": $0.content]
        }

        Task {
            do {
                let result = try await postChat(host: host,
                                                message: composedMessage,
                                                history: Array(history))
                await MainActor.run {
                    messages.append(result)
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    messages.append(FieldAIMessage(
                        role: "assistant",
                        content: L("AI 回覆失敗：%@", error.localizedDescription),
                        isError: true
                    ))
                    isSending = false
                }
            }
        }
    }

    /// 把當前現場資訊（傷患/受困者/災情）附加到 user message，
    /// 讓 AI 不需另外詢問即可掌握上下文
    private func composeWithContext(_ question: String) -> String {
        var ctx: [String] = []

        if !vm.victims.isEmpty {
            ctx.append(L("裝置受困者數：%lld（線上 %lld）",
                         vm.victims.count, vm.onlineVictimCount))
        }
        if !vm.localPatients.isEmpty {
            ctx.append(L("已回報傷患：%lld 名", vm.localPatients.count))
            for p in vm.localPatients.suffix(5) {
                var line = "  - "
                if !p.name.isEmpty { line += "\(p.name) " }
                line += "(\(p.location.isEmpty ? "?" : p.location)) "
                line += "呼吸:\(p.breathingRate == -1 ? "無" : "\(p.breathingRate)")/min "
                line += p.canFollowCommands ? "可聽令" : "無法聽令"
                if !p.notes.isEmpty { line += "備註:\(p.notes)" }
                ctx.append(line)
            }
        }
        if let site = vm.disasterSite {
            let name = site.buildingName.isEmpty ? site.address : site.buildingName
            if !name.isEmpty {
                ctx.append(L("災情現場：%@", name))
            }
        }
        if !vm.hazardReports.isEmpty {
            ctx.append(L("危險回報：%lld 筆", vm.hazardReports.count))
        }

        guard !ctx.isEmpty else { return question }
        return "【現場狀況】\n" + ctx.joined(separator: "\n") + "\n\n【提問】\n" + question
    }

    private func postChat(host: String, message: String,
                          history: [[String: String]]) async throws -> FieldAIMessage {
        guard let url = URL(string: "http://\(host):8001/chat") else {
            throw NSError(domain: "FieldAIChat", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L("URL 錯誤")])
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120

        let systemPrompt = """
        你是 LinkGuard 災害救援 AI 助理，正在回答前線搜救人員的問題。
        回答原則：
        - 精準、條列、可立即執行
        - 涉及醫療時提供 START 評估或基礎急救要點
        - 涉及危險時優先提示安全撤離距離與防護
        - 若資訊不足請主動指出需補充哪些觀察
        - 使用正體中文，避免冗長空泛內容
        """
        let body: [String: Any] = [
            "message": message,
            "history": history,
            "system_prompt": systemPrompt,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "FieldAIChat", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey:
                                     "HTTP \(http.statusCode): \(raw.prefix(200))"])
        }

        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let payload = (envelope["data"] as? [String: Any]) ?? envelope
        let reply = (payload["reply"] as? String) ?? ""
        let model = payload["model"] as? String
        let elapsed = payload["elapsed_ms"] as? Int

        return FieldAIMessage(role: "assistant",
                              content: reply.isEmpty ? L("(空回覆)") : reply,
                              model: model, elapsedMs: elapsed)
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }
}
