import SwiftUI

// =====================================================
//  HQ 端 AI 自由對話
// =====================================================

struct HQAIMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String          // "user" | "assistant"
    let content: String
    let timestamp: Date
    let model: String?
    let elapsedMs: Int?
    let isError: Bool
    let proposals: [AIProposal]

    init(role: String, content: String, timestamp: Date = Date(),
         model: String? = nil, elapsedMs: Int? = nil, isError: Bool = false,
         proposals: [AIProposal] = []) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.model = model
        self.elapsedMs = elapsedMs
        self.isError = isError
        self.proposals = proposals
    }
}

struct HQAIChatView: View {
    @ObservedObject var vm: HQViewModel
    @State private var messages: [HQAIMessage] = []
    @State private var draft: String = ""
    @State private var isSending: Bool = false
    @State private var typingPulse: Bool = false
    @State private var autoBroadcast: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            pageFrame {
                HQPageTitleBar(L("AI 指揮對話"), subtitle: L("查詢部署建議 / 行動規劃 / 資源評估 / 風險研判"), icon: "sparkles", accent: NV.command) {
                    headerControls
                }
            }
            .padding(.top, NV.pagePadding)
            .padding(.bottom, NV.panelSpacing)

            Divider().background(NV.command.opacity(0.25))
            escalationTriggerBanner

            ScrollViewReader { proxy in
                ScrollView {
                    pageFrame {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if messages.isEmpty && !isSending {
                                emptyHint
                            }
                            ForEach(messages) { msg in
                                bubble(for: msg)
                                    .id(msg.id)
                            }
                            if isSending {
                                typingIndicator.id("typing")
                            }
                        }
                        .padding(.vertical, 10)
                    }
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
            pageFrame { inputBar }
                .padding(.vertical, 12)
        }
        .background(NV.bg.ignoresSafeArea())
    }

    // MARK: - 子視圖

    private var headerControls: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(vm.isBackendConnected ? NV.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(vm.effectiveBackendHost.isEmpty
                 ? L("未連線")
                 : "BACKEND ▸ \(vm.effectiveBackendHost)")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
            Button {
                autoBroadcast.toggle()
            } label: {
                Label(autoBroadcast ? L("自動廣播") : L("廣播關閉"), systemImage: "megaphone.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
                messages.removeAll()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(messages.isEmpty || isSending)
            .foregroundColor(messages.isEmpty ? .secondary : NV.warning)
        }
    }

    private func pageFrame<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, NV.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var escalationTriggerBanner: some View {
        if let data = vm.backendBridge.latestEscalationTrigger {
            let reqId = (data["request_id"] as? String) ?? "?"
            let status = (data["status"] as? String) ?? "processing"
            pageFrame {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.title2)
                        .foregroundColor(NV.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("雙 AI 共識達成：已升級至主模型"))
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(NV.warning)
                        Text("request_id: \(reqId)  ·  \(status)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        vm.backendBridge.latestEscalationTrigger = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .hqPanelChrome(accent: NV.warning)
            }
                .padding(.bottom, NV.panelSpacing)
        }
    }

    private var emptyHint: some View {
            HQEmptyStateView(
                icon: "sparkles",
                title: L("AI 指揮對話"),
                subtitle: L("查詢部署建議 / 行動規劃 / 資源評估 / 風險研判"),
                minHeight: 360
            )
    }

    @ViewBuilder
    private func bubble(for msg: HQAIMessage) -> some View {
        let isUser = msg.role == "user"
        let bg: Color = msg.isError ? NV.danger.opacity(0.18)
            : isUser ? NV.command.opacity(0.20) : NV.green.opacity(0.12)
        let border: Color = msg.isError ? NV.danger.opacity(0.5)
            : isUser ? NV.command.opacity(0.5) : NV.green.opacity(0.5)
        let accent: Color = msg.isError ? NV.danger
            : isUser ? NV.command : NV.green

        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: isUser ? "person.fill" : "sparkles")
                        .font(.caption2)
                        .foregroundColor(accent)
                    Text(isUser ? L("HQ 指揮官") : (msg.model ?? "GEMMA4 AI"))
                        .font(.system(.caption2, design: .monospaced).bold())
                        .foregroundColor(accent)
                        .tracking(1)
                    Spacer()
                    Text(timeFormatter.string(from: msg.timestamp))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                if !msg.content.isEmpty {
                    Text(msg.content)
                        .font(.body)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // AI 副駕駛指令提案卡（HITL 審批）
                if !isUser && !msg.proposals.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(msg.proposals) { proposal in
                            HQAIProposalCard(
                                proposal: proposal,
                                isExecuted: vm.executedProposalIDs.contains(proposal.id),
                                isIgnored: vm.ignoredProposalIDs.contains(proposal.id),
                                onExecute: { vm.executeAIProposal(proposal) },
                                onIgnore: { vm.ignoreAIProposal(proposal) }
                            )
                        }
                    }
                    .padding(.top, 4)
                }
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
            if !isUser { Spacer(minLength: 48) }
        }
    }

    private var typingIndicator: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                Text(L("AI 思考中…"))
                    .font(.system(.caption, design: .monospaced))
                    .tracking(2)
            }
            .foregroundColor(NV.green.opacity(typingPulse ? 1.0 : 0.4))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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
            TextField(L("向 AI 提問或下達指令…"), text: $draft, axis: .vertical)
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
    }

    // MARK: - 行為

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isSending && !vm.effectiveBackendHost.isEmpty
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        let host = vm.effectiveBackendHost
        guard !host.isEmpty else {
            messages.append(HQAIMessage(
                role: "assistant",
                content: L("尚未設定後端 AI 伺服器，請於設定畫面配置"),
                isError: true
            ))
            return
        }
        let userMsg = HQAIMessage(role: "user", content: text)
        messages.append(userMsg)
        draft = ""
        isSending = true

        let history = messages.dropLast().suffix(12).map { ["role": $0.role, "content": $0.content] }
        Task {
            do {
                #if os(macOS)
                try await vm.prepareAIChatBackendIfNeeded()
                #endif
                let result = try await postChat(host: host, message: text, history: Array(history))
                await MainActor.run {
                    messages.append(result)
                    isSending = false
                    // 自動廣播 AI 回覆給所有前線 / HQ 裝置（提案不自動廣播，需指揮官審批）
                    if autoBroadcast && !result.isError && result.proposals.isEmpty {
                        let body = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !body.isEmpty {
                            vm.sendTextBroadcast(message: "[AI] " + body, priority: "normal")
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    messages.append(HQAIMessage(
                        role: "assistant",
                        content: L("AI 連線失敗:%@", error.localizedDescription),
                        isError: true
                    ))
                    isSending = false
                }
            }
        }
    }

    private func postChat(host: String, message: String,
                          history: [[String: String]]) async throws -> HQAIMessage {
        guard let url = makeBackendURL(host: host, port: 8001, path: "/chat/with_tools") else {
            throw NSError(domain: "HQAIChat", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "URL 無效（host=\(host)）"])
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        let body: [String: Any] = [
            "message": message,
            "history": history,
            "session_id": "hq_commander",
            "use_server_session": true,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "HQAIChat", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(raw.prefix(200))"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "HQAIChat", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "無法解析 JSON"])
        }
        let payload = (json["data"] as? [String: Any]) ?? json
        let reply = (payload["reply"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let model = payload["model"] as? String
        let elapsed = payload["elapsed_ms"] as? Int
        // 解析 proposals
        var proposals: [AIProposal] = []
        if let raw = payload["proposals"] as? [[String: Any]] {
            let decoder = JSONDecoder()
            for dict in raw {
                if let data = try? JSONSerialization.data(withJSONObject: dict),
                   let p = try? decoder.decode(AIProposal.self, from: data) {
                    proposals.append(p)
                }
            }
        }
        let isEmpty = reply.isEmpty && proposals.isEmpty
        return HQAIMessage(
            role: "assistant",
            content: reply,
            model: model,
            elapsedMs: elapsed,
            isError: isEmpty,
            proposals: proposals
        )
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }
}
