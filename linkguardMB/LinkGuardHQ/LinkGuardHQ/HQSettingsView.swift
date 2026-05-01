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
    @EnvironmentObject var l10n: L10n

    @AppStorage("appColorScheme") private var appColorScheme: String = "dark"
    @AppStorage("hq.backendMode") private var backendModeRaw: String = BackendMode.embedded.rawValue
    @AppStorage("hq.remoteHost") private var remoteHost: String = ""
    @AppStorage("backendHost") private var legacyBackendHost: String = ""
    @AppStorage("ai.modeOverride.global") private var aiModeGlobal: String = "auto"
    @AppStorage("voice.engine") private var voiceEngine: String = "whisperkit"
    @AppStorage("voice.modelSize") private var voiceModelSize: String = "large-v3"

    @State private var setupAssistantPresented = false

    private var backendMode: BackendMode {
        BackendMode(rawValue: backendModeRaw) ?? .embedded
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(L("設定"))
                    .font(.largeTitle.bold())
                    .padding(.top, 8)

                generalSection
                backendSection
                aiSection
                voiceSection
                storageSection
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 24)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NV.bg)
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
                Text("繁體中文").tag("zh-Hant")
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

            if backendMode == .remote {
                HStack {
                    Text(L("遠端主機:"))
                    TextField("192.168.1.10", text: $remoteHost)
                        .textFieldStyle(.roundedBorder)
                    Button(L("連接")) { applyBackendMode() }
                        .buttonStyle(.borderedProminent)
                        .disabled(remoteHost.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

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
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

