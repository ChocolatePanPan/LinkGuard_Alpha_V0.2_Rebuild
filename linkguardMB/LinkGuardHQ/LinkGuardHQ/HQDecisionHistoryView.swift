//
//  HQDecisionHistoryView.swift
//  LinkGuardHQ
//
//  Browse the SQLite-backed AI decision history exposed by
//  gemma4_server `GET /decisions?limit=N` (added on the Python side).
//
//  Read-only — pulls JSON from whichever backend is currently active
//  (embedded localhost, remote, or Bonjour-discovered).
//

import SwiftUI

private struct DecisionRow: Identifiable, Decodable {
    let id: Int
    let timestamp: String
    let msg_type: String?
    let summary: String?
    let confidence: Double?
    let device_id: String?
    let raw_json: String?

    enum CodingKeys: String, CodingKey {
        case id, timestamp, msg_type, summary, confidence, device_id, raw_json
    }
}

private struct DecisionsResponse: Decodable {
    let decisions: [DecisionRow]
    let total: Int
}

private struct ApiEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
}

struct HQDecisionHistoryView: View {
    @ObservedObject var vm: HQViewModel
    @State private var rows: [DecisionRow] = []
    @State private var isLoading = false
    @State private var lastError: String?
    @State private var search = ""
    @State private var limit = 50

    var body: some View {
        HQPage {
            HQPageTitleBar(L("AI 決策歷史"), subtitle: L("來源: %@:8001/decisions", hostDisplay), icon: "clock.arrow.circlepath", accent: NV.command) {
                headerControls
            }
            content
        }
        .onAppear { reload() }
    }

    private var headerControls: some View {
        HStack(spacing: 12) {
            TextField(L("搜尋..."), text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            Picker("", selection: $limit) {
                Text("50").tag(50)
                Text("100").tag(100)
                Text("200").tag(200)
                Text("500").tag(500)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .onChange(of: limit) { _ in reload() }
            Button { reload() } label: {
                Label(L("重新載入"), systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(isLoading)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let err = lastError {
            VStack(spacing: 12) {
                HQEmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: L("讀取 AI 決策失敗"),
                    subtitle: err,
                    minHeight: 320
                )
                Button(L("重試")) { reload() }
                    .buttonStyle(.borderedProminent)
            }
            .hqPanelChrome(accent: NV.danger)
        } else if rows.isEmpty && isLoading {
            VStack(spacing: 12) {
                ProgressView()
                HQEmptyStateView(icon: "clock.arrow.circlepath", title: L("載入 AI 決策歷史"), minHeight: 260)
            }
            .hqPanelChrome(accent: NV.command)
        } else if rows.isEmpty && !isLoading {
            HQEmptyStateView(
                icon: "clock.arrow.circlepath",
                title: L("沒有 AI 決策資料"),
                subtitle: L("後端尚未回傳任何決策紀錄。"),
                minHeight: 360
            )
            .hqPanelChrome(accent: NV.command)
        } else {
            LazyVStack(alignment: .leading, spacing: NV.panelSpacing) {
                ForEach(filteredRows) { r in row(r) }
            }
        }
    }

    private func row(_ r: DecisionRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(r.timestamp)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                if let t = r.msg_type, !t.isEmpty {
                    Text(t)
                        .font(.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(NV.green.opacity(0.2))
                        .cornerRadius(4)
                }
                if let d = r.device_id, !d.isEmpty {
                    Text(d).font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let c = r.confidence {
                    Text(String(format: "%.0f%%", c * 100))
                        .font(.caption.bold())
                        .foregroundColor(c >= 0.8 ? NV.green : (c >= 0.5 ? .yellow : NV.danger))
                }
            }
            Text(r.summary ?? "—")
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(NV.surface.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(NV.command.opacity(0.22), lineWidth: 1)
        )
    }

    // MARK: - Filtering

    private var filteredRows: [DecisionRow] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter { r in
            (r.summary?.lowercased().contains(q) ?? false)
                || (r.msg_type?.lowercased().contains(q) ?? false)
                || (r.device_id?.lowercased().contains(q) ?? false)
        }
    }

    // MARK: - Networking

    private var hostDisplay: String {
        let h = vm.effectiveBackendHost
        return h.isEmpty ? "127.0.0.1" : h
    }

    private func reload() {
        let host = hostDisplay
        guard let url = makeBackendURL(host: host, port: 8001,
                                        path: "/decisions?limit=\(limit)") else {
            lastError = "Invalid host: \(host)"
            return
        }
        isLoading = true
        lastError = nil
        Task {
            do {
                var req = URLRequest(url: url)
                req.timeoutInterval = 5
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let env = try JSONDecoder().decode(ApiEnvelope<DecisionsResponse>.self, from: data)
                await MainActor.run {
                    rows = env.data?.decisions ?? []
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    lastError = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
