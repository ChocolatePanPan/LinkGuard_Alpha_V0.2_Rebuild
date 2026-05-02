//
//  HQSettingsView.swift
//  LinkGuardHQ
//
//  Consolidated settings panel — first one in the app.
//  Sections: General · Backend · AI · Voice · Storage.
//

import SwiftUI
#if os(macOS)
import AppKit

struct HQSettingsView: View {
    @ObservedObject var vm: HQViewModel
    @ObservedObject var supervisor: BackendSupervisor
    var onOpenBackendServices: (() -> Void)? = nil
    @EnvironmentObject var l10n: L10n

    @AppStorage("appColorScheme") private var appColorScheme: String = "dark"
    @AppStorage("hq.backendMode") private var backendModeRaw: String = BackendMode.embedded.rawValue
    @AppStorage("hq.remoteHost") private var remoteHost: String = ""
    @AppStorage("backendHost") private var legacyBackendHost: String = ""
    @AppStorage("ai.modeOverride.global") private var aiModeGlobal: String = "auto"
    @AppStorage("ai.modelProfile") private var aiModelProfileRaw: String = LocalAIModelProfile.singleE4B.rawValue
    @AppStorage("voice.engine") private var voiceEngine: String = "whisperkit"
    @AppStorage("voice.modelSize") private var voiceModelSize: String = "large-v3"

    @State private var setupAssistantPresented = false

    private var backendMode: BackendMode {
        BackendMode(rawValue: backendModeRaw) ?? .embedded
    }

    private var aiModelProfile: LocalAIModelProfile {
        LocalAIModelProfile(rawValue: aiModelProfileRaw) ?? .singleE4B
    }

    var body: some View {
        HQPage(maxWidth: NV.readablePageMaxWidth, spacing: NV.pageSpacing) {
            HQPageHeader(L("設定"), icon: "gearshape.fill", accent: NV.info)
            generalSection
            backendSection
            aiSection
            voiceSection
            storageSection
        }
        .sheet(isPresented: $setupAssistantPresented) {
            #if os(macOS)
            SetupAssistantView(supervisor: supervisor,
                               isPresented: $setupAssistantPresented)
                .frame(minWidth: 560, minHeight: 480)
            #else
            EmptyView()
            #endif
        }
    }

    // MARK: - Sections

    private var generalSection: some View {
        section(L("一般")) {
            Picker(L("外觀"), selection: $appColorScheme) {
                Text(L("跟隨系統")).tag("system")
                Text(L("淺色")).tag("light")
                Text(L("深色")).tag("dark")
            }
            .pickerStyle(.segmented)

            Picker(L("語言"), selection: Binding(
                get: { l10n.language },
                set: { l10n.language = $0 }
            )) {
                Text(L("繁體中文")).tag("zh-Hant")
                Text("English").tag("en")
            }
        }
    }

    private var backendSection: some View {
        section(L("後端")) {
            Picker(L("後端模式"), selection: Binding(
                get: { backendModeRaw },
                set: { newValue in
                    backendModeRaw = newValue
                    applyBackendMode()
                }
            )) {
                ForEach(BackendMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.systemImage)
                        .tag(mode.rawValue)
                }
            }
            .pickerStyle(.inline)

            Text(backendMode.helpText)
                .font(.caption)
                .foregroundColor(.secondary)

            #if os(macOS)
            if backendMode == .embedded {
                HStack {
                    Button {
                        setupAssistantPresented = true
                    } label: {
                        Label(L("執行設定精靈"), systemImage: "wand.and.stars")
                    }
                    Spacer()
                    Text(L("Python: %@",
                          supervisor.pythonExecutable?.path ?? L("未偵測到")))
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            #endif

            Divider()
            serverRuntimeStatus
        }
    }

    private var serverRuntimeStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusSubsectionHeader(L("語音辨識 (Apple Speech)"), icon: "waveform")
            speechServerStatus
            Divider()
            statusSubsectionHeader(L("照片伺服器 (HTTP)"), icon: "photo")
            photoServerStatus
            Divider()
            statusSubsectionHeader(L("後台伺服器"), icon: "server.rack")
            backendConnectionStatus
        }
    }

    @ViewBuilder
    private var speechServerStatus: some View {
        if vm.hqRole == .peer {
            if let status = vm.peerClient.serverStatus {
                statusRow(isRunning: status.speechServerRunning,
                          runningText: L("運行中 (port 8003)"),
                          stoppedText: L("已停止"),
                          trailingText: L("已處理 %lld 筆", status.speechProcessedCount))
            } else {
                statusRow(isRunning: false,
                          runningText: L("已同步"),
                          stoppedText: L("尚未收到主 HQ 狀態"))
            }
        } else {
            statusRow(isRunning: vm.speechServer.isRunning,
                      runningText: L("運行中 (port 8003)"),
                      stoppedText: L("已停止"),
                      trailingText: L("已處理 %lld 筆", vm.speechServer.processedCount))
            if !vm.speechServer.lastTranscription.isEmpty {
                Text(vm.speechServer.lastTranscription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            if let error = vm.speechServer.lastError {
                errorText(error)
            }
            HStack {
                if vm.speechServer.isRunning {
                    Button(L("停止辨識伺服器")) { vm.speechServer.stop() }
                        .font(.caption)
                        .foregroundColor(NV.danger)
                } else {
                    Button(L("啟動辨識伺服器")) { vm.speechServer.start() }
                        .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private var photoServerStatus: some View {
        if vm.hqRole == .peer {
            if let status = vm.peerClient.serverStatus {
                statusRow(isRunning: status.photoServerRunning,
                          runningText: L("運行中 (port 8014)"),
                          stoppedText: L("已停止"),
                          trailingText: L("已收 %lld 張", status.photoReceivedCount))
            } else {
                statusRow(isRunning: false,
                          runningText: L("已同步"),
                          stoppedText: L("尚未收到主 HQ 狀態"))
            }
        } else {
            statusRow(isRunning: vm.photoServer.isRunning,
                      runningText: L("運行中 (port 8014)"),
                      stoppedText: L("已停止"),
                      trailingText: L("已收 %lld 張", vm.photoServer.receivedCount))
            if let error = vm.photoServer.lastError {
                errorText(error)
            }
            HStack {
                if vm.photoServer.isRunning {
                    Button(L("停止照片伺服器")) { vm.photoServer.stop() }
                        .font(.caption)
                        .foregroundColor(NV.danger)
                } else {
                    Button(L("啟動照片伺服器")) { vm.photoServer.start() }
                        .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private var backendConnectionStatus: some View {
        if vm.hqRole == .peer {
            if let status = vm.peerClient.serverStatus {
                statusRow(isRunning: status.backendConnected,
                          runningText: L("已連線 %@", status.backendHost),
                          stoppedText: L("未連線"))
            } else {
                statusRow(isRunning: false,
                          runningText: L("已同步"),
                          stoppedText: L("尚未收到主 HQ 狀態"))
            }
        } else if backendMode == .embedded {
            embeddedBackendStatus
        } else if backendMode == .remote {
            remoteBackendStatus
        } else {
            bonjourBackendStatus
        }
    }

    private var embeddedBackendStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow(isRunning: vm.isBackendConnected,
                      runningText: L("此 Mac 內建後端 127.0.0.1"),
                      stoppedText: L("此 Mac 後端啟動中"))
            HStack(spacing: 8) {
                Button(L("啟動本機後端")) {
                    vm.ensureMacLocalBackend()
                }
                .font(.caption)
                if let onOpenBackendServices {
                    Button(L("查看服務")) {
                        onOpenBackendServices()
                    }
                    .font(.caption)
                }
            }
            if let error = vm.backendBridge.lastError {
                errorText(error)
            }
        }
    }

    private var remoteBackendStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            backendBridgeStatusRow
            HStack {
                Text(L("遠端主機:"))
                TextField("192.168.1.10", text: $remoteHost)
                    .textFieldStyle(.roundedBorder)
                if vm.backendBridge.isConnected {
                    Button(L("斷開連線")) {
                        vm.backendBridge.disconnect()
                    }
                    .font(.caption)
                    .foregroundColor(NV.danger)
                } else {
                    Button(L("連接")) { applyBackendMode() }
                        .buttonStyle(.borderedProminent)
                        .disabled(remoteHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if let error = vm.backendBridge.lastError {
                errorText(error)
            }
        }
    }

    private var bonjourBackendStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            backendBridgeStatusRow
            if !vm.backendBridge.isDiscovering {
                TextField(L("後台 IP（手動）"), text: $legacyBackendHost)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
            HStack(spacing: 8) {
                if vm.backendBridge.isConnected {
                    Button(L("斷開連線")) {
                        vm.backendBridge.disconnect()
                    }
                    .font(.caption)
                    .foregroundColor(NV.danger)
                } else {
                    Button(L("自動搜尋")) {
                        vm.backendBridge.startAutoDiscovery()
                    }
                    .font(.caption)
                    .disabled(vm.backendBridge.isDiscovering)
                    if !legacyBackendHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(L("手動連線")) {
                            let host = legacyBackendHost.trimmingCharacters(in: .whitespacesAndNewlines)
                            vm.backendBridge.connect(host: host)
                        }
                        .font(.caption)
                    }
                }
            }
            if let error = vm.backendBridge.lastError {
                errorText(error)
            }
        }
    }

    private var backendBridgeStatusRow: some View {
        HStack(spacing: 6) {
            if vm.backendBridge.isDiscovering {
                ProgressView().scaleEffect(0.7)
            } else {
                Circle()
                    .fill(vm.backendBridge.isConnected ? NV.green : Color.gray)
                    .frame(width: 8, height: 8)
            }
            Text(vm.backendBridge.isDiscovering ? L("Bonjour 搜尋中...") :
                 vm.backendBridge.isConnected ? L("已連線 %@", vm.backendBridge.backendHost) : L("未連線"))
                .font(.caption)
                .foregroundColor(vm.backendBridge.isDiscovering ? .orange :
                                 vm.backendBridge.isConnected ? NV.green : .secondary)
            Spacer()
        }
    }

    private var aiSection: some View {
        section(L("AI 決策")) {
            Picker(L("全域決策模式"), selection: $aiModeGlobal) {
                Text(L("自動 (Auto)")).tag("auto")
                Text(L("手動 (Manual)")).tag("manual")
                Text(L("鎖定 (Locked)")).tag("locked")
            }
            .pickerStyle(.segmented)

            Picker(L("模型大小"), selection: $aiModelProfileRaw) {
                ForEach(LocalAIModelProfile.allCases) { profile in
                    Text(profile.displayName).tag(profile.rawValue)
                }
            }
            .pickerStyle(.menu)

            Text(aiModelProfile.summary)
                .font(.caption)
                .foregroundColor(.secondary)

            #if os(macOS)
            HStack {
                Button {
                    supervisor.applyStoredAIModelProfile(restartIfRunning: true)
                } label: {
                    Label(L("套用並重啟 AI"), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(backendMode != .embedded)

                Spacer()

                Text("\(aiModelProfile.runtimeModel) · \(aiModelProfile.parallelWorkers) worker")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
            #endif

            Text(L("Auto = AI 直接派發 / Manual = AI 提案、需人員核可 / Locked = 不允許 AI 介入。"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var voiceSection: some View {
        section(L("語音轉錄")) {
            Picker(L("辨識引擎"), selection: $voiceEngine) {
                Text(L("WhisperKit (此 Mac)")).tag("whisperkit")
                Text(L("Python whisper_server")).tag("python")
            }
            .pickerStyle(.segmented)
            Picker(L("模型大小"), selection: $voiceModelSize) {
                Text("large-v3").tag("large-v3")
                Text("medium").tag("medium")
                Text("base").tag("base")
            }
            Text(L("WhisperKit 在 Apple Silicon 上有 Metal 加速;Python 引擎使用 CPU + int8。"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var storageSection: some View {
        section(L("儲存")) {
            #if os(macOS)
            HStack {
                Text(L("資料夾:"))
                Text(supervisor.backendDir.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(L("在 Finder 開啟")) {
                    NSWorkspace.shared.open(supervisor.backendDir)
                }
            }
            #else
            Text(L("此區塊僅於 macOS 主機可用。"))
                .foregroundColor(.secondary)
            #endif
        }
    }

    // MARK: - Helpers

    private func section<Content: View>(_ title: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(NV.green)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hqPanelChrome(accent: NV.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusSubsectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(NV.green)
                .frame(width: 18)
            Text(title)
                .font(.subheadline.bold())
            Spacer()
        }
    }

    private func statusRow(isRunning: Bool,
                           runningText: String,
                           stoppedText: String,
                           trailingText: String? = nil) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRunning ? NV.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(isRunning ? runningText : stoppedText)
                .font(.caption)
                .foregroundColor(isRunning ? NV.green : .secondary)
            Spacer()
            if let trailingText {
                Text(trailingText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func errorText(_ message: String) -> some View {
        Text(message)
            .font(.caption2)
            .foregroundColor(NV.danger)
            .lineLimit(2)
    }

    /// React to backend-mode change: tell HQBackendBridge where to connect.
    private func applyBackendMode() {
        switch backendMode {
        case .embedded:
            #if os(macOS)
            vm.ensureMacLocalBackend()
            legacyBackendHost = "127.0.0.1"
            #endif
        case .remote:
            let host = remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else { return }
            #if os(macOS)
            supervisor.stopAll()
            #endif
            vm.backendBridge.connect(host: host, port: 9000)
            legacyBackendHost = host
        case .bonjour:
            #if os(macOS)
            supervisor.stopAll()
            #endif
            // Existing NWBrowser logic in HQBackendBridge will be triggered by
            // HQViewModel during `startServer()`. Nothing else to do here.
            legacyBackendHost = ""
        }
    }
}

#else

struct HQSettingsView: View {
    @ObservedObject var vm: HQViewModel
    var body: some View {
        Text(L("設定僅 macOS 支援")).foregroundColor(.secondary)
    }
}

#endif

