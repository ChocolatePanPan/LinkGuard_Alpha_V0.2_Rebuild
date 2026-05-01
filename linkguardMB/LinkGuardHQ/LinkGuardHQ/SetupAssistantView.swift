//
//  SetupAssistantView.swift
//  LinkGuardHQ
//
//  First-launch (or on-demand) wizard that gets the user to a working
//  embedded backend without ever opening Terminal.
//
//  Steps:
//    1. Detect Ollama (recommend `brew install ollama` if missing)
//    2. Pull / verify Gemma4 model(s) via ollama HTTP API
//    3. Create per-user Python venv + pip install requirements.txt
//    4. Smoke-test backend health endpoints
//
//  macOS only.
//

import SwiftUI

#if os(macOS)
import AppKit

struct SetupAssistantView: View {
    @ObservedObject var supervisor: BackendSupervisor
    @Binding var isPresented: Bool

    @State private var ollamaStatus: StepStatus = .pending
    @State private var ollamaDetail: String = ""
    @State private var modelStatus: StepStatus = .pending
    @State private var modelDetail: String = "gemma4:e4b"
    @State private var venvStatus: StepStatus = .pending
    @State private var venvDetail: String = ""
    @State private var smokeStatus: StepStatus = .pending
    @State private var smokeDetail: String = ""
    @State private var isRunning = false

    enum StepStatus { case pending, running, ok, failed }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("LinkGuardHQ 設定精靈"))
                .font(.title.bold())
            Text(L("一次性安裝內建後端 (Ollama + Gemma4 + Python 環境)。"))
                .foregroundColor(.secondary)

            Divider()

            step(idx: 1, title: L("偵測 Ollama"), status: ollamaStatus, detail: ollamaDetail)
            step(idx: 2, title: L("確認 / 下載模型 (gemma4:e4b)"), status: modelStatus, detail: modelDetail)
            step(idx: 3, title: L("建立 Python 虛擬環境 + pip install"), status: venvStatus, detail: venvDetail)
            step(idx: 4, title: L("啟動後端並通過健康檢查"), status: smokeStatus, detail: smokeDetail)

            Spacer()

            HStack {
                Button(L("跳過 (使用遠端後端)")) { isPresented = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button(L("開始")) { Task { await runAll() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)
                Button(L("完成")) { isPresented = false }
                    .disabled(smokeStatus != .ok)
            }
        }
        .padding(24)
    }

    // MARK: - Step row

    @ViewBuilder
    private func step(idx: Int, title: String, status: StepStatus, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon(status)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(idx). \(title)").font(.headline)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func statusIcon(_ s: StepStatus) -> some View {
        switch s {
        case .pending:
            Image(systemName: "circle.dashed").foregroundColor(.secondary)
        case .running:
            ProgressView().scaleEffect(0.6)
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundColor(NV.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundColor(NV.danger)
        }
    }

    // MARK: - Workflow

    private func runAll() async {
        isRunning = true
        defer { isRunning = false }

        await stepOllama()
        guard ollamaStatus == .ok else { return }

        await stepModel()
        guard modelStatus == .ok else { return }

        await stepVenv()
        guard venvStatus == .ok else { return }

        await stepSmoke()
    }

    // 1. Ollama
    private func stepOllama() async {
        ollamaStatus = .running
        ollamaDetail = L("呼叫 http://localhost:11434/api/tags ...")
        if let url = URL(string: "http://localhost:11434/api/tags") {
            do {
                var req = URLRequest(url: url)
                req.timeoutInterval = 3
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse,
                   (200..<300).contains(http.statusCode) {
                    ollamaStatus = .ok
                    ollamaDetail = L("Ollama 已執行於 :11434")
                    return
                }
            } catch { /* fall through to install hint */ }
        }
        ollamaStatus = .failed
        ollamaDetail = L("找不到 Ollama。請執行: brew install ollama && ollama serve")
        // Open download page so the user can act.
        if let url = URL(string: "https://ollama.com/download") {
            NSWorkspace.shared.open(url)
        }
    }

    // 2. Model presence
    private func stepModel() async {
        modelStatus = .running
        modelDetail = L("檢查模型 gemma4:e4b ...")
        guard let url = URL(string: "http://localhost:11434/api/tags") else {
            modelStatus = .failed; return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let tags = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["models"] as? [[String: Any]] ?? []
            let names = tags.compactMap { $0["name"] as? String }
            if names.contains(where: { $0.hasPrefix("gemma4:e4b") }) {
                modelStatus = .ok
                modelDetail = L("已存在: gemma4:e4b")
            } else {
                modelStatus = .failed
                modelDetail = L("缺少模型,請於 Terminal 執行: ollama pull gemma4:e4b")
            }
        } catch {
            modelStatus = .failed
            modelDetail = error.localizedDescription
        }
    }

    // 3. Python venv + pip
    private func stepVenv() async {
        venvStatus = .running
        venvDetail = L("建立 .venv 並安裝套件 (數分鐘) ...")
        let backendDir = supervisor.backendDir
        let venv = backendDir.deletingLastPathComponent().appendingPathComponent(".venv")
        let req = backendDir.appendingPathComponent("requirements.txt")
        let systemPython = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
                            .first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let py = systemPython else {
            venvStatus = .failed
            venvDetail = L("找不到系統 Python3,請先 brew install python@3.11")
            return
        }

        // Create venv if missing.
        if !FileManager.default.fileExists(atPath: venv.path) {
            let r = await runShell(URL(fileURLWithPath: py),
                                    args: ["-m", "venv", venv.path])
            if r.code != 0 {
                venvStatus = .failed
                venvDetail = L("venv 建立失敗: %@", r.output)
                return
            }
        }
        // Install requirements.
        let venvPython = venv.appendingPathComponent("bin/python3")
        let r = await runShell(venvPython,
                                args: ["-m", "pip", "install", "-r", req.path])
        if r.code == 0 {
            venvStatus = .ok
            venvDetail = L("已安裝至 %@", venv.path)
            // Force supervisor to re-resolve python.
            supervisor.pythonExecutable = venvPython
        } else {
            venvStatus = .failed
            venvDetail = L("pip install 失敗 (見終端機日誌)")
        }
    }

    // 4. Smoke test
    private func stepSmoke() async {
        smokeStatus = .running
        smokeDetail = L("啟動所有服務 ...")
        supervisor.startAll()
        // Wait up to 30 s for every service to report healthy.
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if supervisor.allHealthy {
                smokeStatus = .ok
                smokeDetail = L("9 個服務全部正常")
                return
            }
        }
        smokeStatus = .failed
        let bad = supervisor.services
            .filter { $0.status != .healthy }
            .map { $0.spec.displayName }
            .joined(separator: ", ")
        smokeDetail = L("超時,異常服務: %@", bad)
    }

    // MARK: - Shell helper

    private struct ShellResult { let code: Int32; let output: String }

    private func runShell(_ exec: URL, args: [String]) async -> ShellResult {
        await withCheckedContinuation { (cont: CheckedContinuation<ShellResult, Never>) in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = exec
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do {
                    try p.run()
                    p.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let out = String(data: data, encoding: .utf8) ?? ""
                    cont.resume(returning: .init(code: p.terminationStatus, output: out))
                } catch {
                    cont.resume(returning: .init(code: -1, output: error.localizedDescription))
                }
            }
        }
    }
}

#endif
