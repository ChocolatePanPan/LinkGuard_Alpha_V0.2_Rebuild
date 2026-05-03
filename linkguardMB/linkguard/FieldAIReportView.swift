import SwiftUI

// =====================================================
//  Field AI Report — 前線 AI 助理回報頁
//  輸入口語化現場觀察 → 後端 /report/formalize (gemma4:e2b)
//  自動改寫成正式戰情報告，按下確認後送出 (走既有 chatMessages / hazard 通道)
//
//  Plan v2 Phase B
// =====================================================

struct FieldAIReportView: View {
    @ObservedObject var vm: LinkGuardViewModel

    enum IncidentType: String, CaseIterable, Identifiable {
        case general, patient, resource, hazard
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general:  return L("一般")
            case .patient:  return L("傷患")
            case .resource: return L("資源")
            case .hazard:   return L("危險")
            }
        }
    }

    @State private var rawText: String = ""
    @State private var incidentType: IncidentType = .general
    @State private var formalText: String = ""
    @State private var isFormalizing: Bool = false
    @State private var lastModel: String = ""
    @State private var lastElapsedMs: Int = 0
    @State private var errorMessage: String = ""
    @State private var dispatched: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            statusBar
            Divider().background(NV.command.opacity(0.25))
            if vm.isAIServicePaused {
                AIServicePausedBanner(message: vm.aiServicePauseMessage)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    typePicker
                    rawInputCard
                    actionRow
                    if !errorMessage.isEmpty {
                        errorBanner
                    }
                    if !formalText.isEmpty {
                        formalCard
                        sendCard
                    }
                }
                .padding(14)
            }
            .aiPausedAppearance(vm.isAIServicePaused)
        }
        .navigationTitle(L("AI 回報"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
    }

    // MARK: 狀態列

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(vm.isAIServicePaused ? Color.gray : canSend ? NV.green : NV.command.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(vm.isAIServicePaused
                 ? L("AI服務暫停")
                 : canSend
                 ? L("HQ 連線中：%@", vm.transcriptionServerHost)
                 : L("尚未連線到 HQ"))
                .font(.caption)
                .foregroundStyle(vm.isAIServicePaused ? .secondary : NV.command.opacity(0.85))
            Spacer()
            if !lastModel.isEmpty {
                Text(L("模型：%@ · %lldms", lastModel, lastElapsedMs))
                    .font(.caption2)
                    .foregroundStyle(NV.command.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: 類型挑選

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("回報類型")).font(.caption.bold()).foregroundStyle(NV.command)
            Picker("", selection: $incidentType) {
                ForEach(IncidentType.allCases) { t in
                    Text(L(t.label)).tag(t)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: 原始輸入

    private var rawInputCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("口語化觀察（隨意打、AI 會整型化）"))
                .font(.caption.bold())
                .foregroundStyle(NV.command)
            TextEditor(text: $rawText)
                .frame(minHeight: 120, maxHeight: 200)
                .padding(8)
                .background(NV.command.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(NV.command.opacity(0.25), lineWidth: 1)
                )
        }
    }

    // MARK: 動作列

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                rawText = ""
                formalText = ""
                errorMessage = ""
                dispatched = false
            } label: {
                Label(L("清除"), systemImage: "trash")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .disabled(rawText.isEmpty && formalText.isEmpty)

            Spacer()

            Button {
                Task { await formalize() }
            } label: {
                if isFormalizing {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text(L("整型化中…")).font(.caption.bold())
                    }
                } else {
                    Label(L("整型化"), systemImage: "sparkles")
                        .font(.caption.bold())
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || isFormalizing
                      || !canSend)
        }
    }

    private var errorBanner: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(errorMessage).font(.caption).foregroundStyle(.orange)
            Spacer()
        }
        .padding(8)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: 整型化結果

    private var formalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("AI 整型化結果"))
                    .font(.caption.bold())
                    .foregroundStyle(NV.command)
                Spacer()
                Button {
                    UIPasteboard.general.string = formalText
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
            ScrollView {
                Text(formalText)
                    .font(.callout)
                    .foregroundStyle(NV.command)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 240)
            .background(NV.green.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: 送出

    private var sendCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("送出選項")).font(.caption.bold()).foregroundStyle(NV.command)
                Spacer()
                if dispatched {
                    Label(L("已送出"), systemImage: "checkmark.seal.fill")
                        .font(.caption.bold())
                        .foregroundStyle(NV.green)
                }
            }
            HStack(spacing: 10) {
                Button {
                    sendAsChat()
                } label: {
                    Label(L("傳給 HQ 通訊"), systemImage: "paperplane.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .disabled(formalText.isEmpty || dispatched)

                if incidentType == .hazard {
                    Button {
                        sendAsHazard()
                    } label: {
                        Label(L("登錄為危險回報"), systemImage: "exclamationmark.octagon.fill")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .disabled(formalText.isEmpty || dispatched)
                }
            }
        }
    }

    // MARK: - 邏輯

    private var canSend: Bool {
        vm.isFieldAIAvailable
    }

    @MainActor
    private func formalize() async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, canSend else {
            if vm.isAIServicePaused { errorMessage = L("AI服務暫停") }
            return
        }
        errorMessage = ""
        formalText = ""
        dispatched = false
        isFormalizing = true
        defer { isFormalizing = false }

        let host = vm.transcriptionServerHost
        guard let url = URL(string: "http://\(host):8001/report/formalize") else {
            errorMessage = L("URL 錯誤")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 90

        let body: [String: Any] = [
            "raw_text": text,
            "reporter": vm.nodeStatus.nodeID,
            "incident_type": incidentType.rawValue,
            "session_id": "field_\(vm.nodeStatus.nodeID)",
        ]
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let raw = String(data: data, encoding: .utf8) ?? ""
                errorMessage = L("HTTP %lld：%@", http.statusCode, String(raw.prefix(160)))
                return
            }
            let env = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            // backend 用 api_ok：欄位平鋪在頂層
            let payload = (env["data"] as? [String: Any]) ?? env
            formalText = (payload["formal"] as? String) ?? ""
            lastModel = (payload["model"] as? String) ?? ""
            lastElapsedMs = (payload["elapsed_ms"] as? Int) ?? 0
            if formalText.isEmpty {
                errorMessage = L("AI 回覆為空，請再描述清楚一些。")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func sendAsChat() {
        guard !formalText.isEmpty else { return }
        let prefix = "[AI整型化:\(incidentType.label)]\n"
        vm.sendChat(prefix + formalText)
        dispatched = true
    }

    @MainActor
    private func sendAsHazard() {
        guard !formalText.isEmpty else { return }
        // 預設使用 structural（其他）類別；description 帶整型化後的全文
        vm.reportHazard(type: .structural, description: formalText, zone: "", severity: .medium)
        dispatched = true
    }
}
