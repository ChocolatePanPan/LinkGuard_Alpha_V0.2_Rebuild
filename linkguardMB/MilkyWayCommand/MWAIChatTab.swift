import SwiftUI

// MARK: - AI 聊天訊息模型

struct MWAIMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String      // "user" | "assistant"
    let content: String
    let timestamp: Date
    let model: String?
    let elapsedMs: Int?
    let isError: Bool

    init(role: String, content: String, timestamp: Date = Date(),
         model: String? = nil, elapsedMs: Int? = nil, isError: Bool = false) {
        self.role = role; self.content = content; self.timestamp = timestamp
        self.model = model; self.elapsedMs = elapsedMs; self.isError = isError
    }
}

// MARK: - AI 助手 Tab

struct MWAIChatTab: View {
    @State private var messages: [MWAIMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var typingPulse = false
    @State private var serverHost = ""
    @FocusState private var inputFocused: Bool

    // iPad 泡泡最大寬度
    private let bubbleMaxW: CGFloat = 560

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                serverBar
                Divider()
                chatArea
                Divider()
                inputBar
            }
            .background(MWTheme.bg.ignoresSafeArea())
            .navigationTitle("AI 助手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        messages.removeAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(messages.isEmpty || isSending)
                    .foregroundStyle(messages.isEmpty ? .secondary : MWTheme.amber)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 伺服器設定列

    private var serverBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(serverHost.isEmpty ? MWTheme.amber : MWTheme.green)
                .frame(width: 8, height: 8)
            TextField("AI 伺服器 IP（例：192.168.1.100）", text: $serverHost)
                .font(.system(.caption, design: .monospaced))
                .autocorrectionDisabled()
                .autocapitalization(.none)
                .textContentType(.URL)
            Spacer()
            Text(serverHost.isEmpty ? "未連線" : "GEMMA4 AI")
                .font(.caption.bold())
                .foregroundStyle(serverHost.isEmpty ? MWTheme.amber : MWTheme.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MWTheme.surface.opacity(0.6))
    }

    // MARK: - 聊天區

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty && !isSending {
                        emptyHint.padding(.top, 80)
                    }
                    ForEach(messages) { msg in
                        bubble(for: msg).id(msg.id)
                    }
                    if isSending {
                        typingIndicator.id("typing")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: isSending) { _, sending in
                if sending { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
            }
        }
    }

    // MARK: - 氣泡

    @ViewBuilder
    private func bubble(for msg: MWAIMessage) -> some View {
        let isUser = msg.role == "user"
        let bg: Color = msg.isError ? MWTheme.red.opacity(0.15)
            : isUser ? MWTheme.violet.opacity(0.18) : MWTheme.green.opacity(0.12)
        let accent: Color = msg.isError ? MWTheme.red : isUser ? MWTheme.violet : MWTheme.green

        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: isUser ? "person.fill" : "sparkles")
                        .font(.caption).foregroundStyle(accent)
                    Text(isUser ? "指揮官" : (msg.model ?? "GEMMA4 AI"))
                        .font(.caption.bold()).foregroundStyle(accent)
                    Spacer()
                    Text(msg.timestamp, style: .time)
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                Text(msg.content)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !isUser, let ms = msg.elapsedMs {
                    Text("耗時 \(ms) ms")
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bg)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: bubbleMaxW, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 48) }
        }
    }

    // MARK: - 打字指示

    private var typingIndicator: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.caption2)
                Text("AI 思考中...")
                    .font(.caption.monospaced())
            }
            .foregroundStyle(MWTheme.green.opacity(typingPulse ? 1.0 : 0.4))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(MWTheme.green.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MWTheme.green.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    typingPulse.toggle()
                }
            }
            Spacer()
        }
    }

    // MARK: - 空白提示

    private var emptyHint: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(MWTheme.green.opacity(0.35))
            Text("GEMMA4 AI 助手")
                .font(.title2.bold())
                .foregroundStyle(MWTheme.green.opacity(0.7))
            Text("詢問救援建議 / 醫療判斷 / SOP / 翻譯")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(quickPrompts, id: \.self) { p in
                    Button {
                        draft = p
                        inputFocused = true
                    } label: {
                        Text("• \(p)")
                            .font(.subheadline)
                            .foregroundStyle(MWTheme.cyan)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: MWTouch.minH)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private let quickPrompts = [
        "呼吸 36 次/分鐘且意識模糊，要怎麼處置？",
        "這個傷患需要立刻後送嗎？",
        "瓦斯外洩疑慮，撤離半徑多少？",
        "CPR 按壓深度與頻率？",
    ]

    // MARK: - 輸入列

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("向 AI 提問現場狀況或醫療建議...", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(MWTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .focused($inputFocused)
                .disabled(isSending)

            Button { send() } label: {
                Image(systemName: "paperplane.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 52)
                    .background(canSend ? MWTheme.green : MWTheme.green.opacity(0.3), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MWTheme.bg)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && !serverHost.isEmpty
    }

    // MARK: - 發送

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        if serverHost.isEmpty {
            messages.append(MWAIMessage(role: "assistant",
                content: "尚未設定 AI 伺服器 IP，請在上方欄位填入 Win11 主機 IP（如 192.168.1.100）。",
                isError: true))
            return
        }

        messages.append(MWAIMessage(role: "user", content: text))
        draft = ""
        isSending = true
        let host = serverHost
        let history = messages.dropLast().suffix(12).map { ["role": $0.role, "content": $0.content] }

        Task {
            do {
                let result = try await postChat(host: host, message: text, history: Array(history))
                messages.append(result)
            } catch {
                messages.append(MWAIMessage(role: "assistant",
                    content: "AI 回覆失敗：\(error.localizedDescription)", isError: true))
            }
            isSending = false
        }
    }

    private func postChat(host: String, message: String, history: [[String: String]]) async throws -> MWAIMessage {
        guard let url = URL(string: "http://\(host):8001/chat") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120

        let systemPrompt = """
        你是 LinkGuard 災害救援 AI 助理，正在回答前線搜救人員的問題。
        回答原則：精準、條列、可立即執行；涉及醫療時提供 START 評估；使用正體中文。
        """
        let body: [String: Any] = [
            "system": systemPrompt,
            "message": message,
            "history": history
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let start = Date()
        let (data, resp) = try await URLSession.shared.data(for: req)
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

        guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reply = json["response"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        let model = json["model"] as? String
        return MWAIMessage(role: "assistant", content: reply, model: model, elapsedMs: elapsed)
    }
}
