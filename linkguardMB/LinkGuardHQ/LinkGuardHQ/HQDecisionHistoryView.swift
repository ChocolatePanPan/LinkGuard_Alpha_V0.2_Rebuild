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
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .background(NV.bg)
        .onAppear { reload() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .foregroundColor(NV.green)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("AI 決策歷史"))
                    .font(.title2.bold())
                Text(L("來源: %@:8001/decisions", hostDisplay))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
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
            .disabled(isLoading)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if let err = lastError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(NV.danger)
                    .font(.largeTitle)
                Text(err).foregroundColor(.secondary)
                Button(L("重試")) { reload() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty && !isLoading {
            Text(L("沒有資料"))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredRows) { r in row(r) }
                }
                .padding()
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
        .background(Color.black.opacity(0.2))
        .cornerRadius(6)
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
