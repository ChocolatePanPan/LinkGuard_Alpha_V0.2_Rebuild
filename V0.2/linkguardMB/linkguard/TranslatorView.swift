import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - 翻譯功能頁面

struct TranslatorView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @State private var inputText = ""
    @State private var sourceLang = "auto"
    @State private var targetLang = "en"
    @State private var errorMessage: String?
    @FocusState private var isTranslatorFocused: Bool

    private let languages: [(code: String, name: String)] = [
        ("auto", L("自動偵測")),
        ("zh-TW", L("繁體中文")),
        ("en", "English"),
        ("ja", L("日本語")),
        ("ko", "한국어"),
        ("vi", "Tiếng Việt"),
        ("th", "ภาษาไทย"),
        ("id", "Bahasa Indonesia"),
        ("ms", "Bahasa Melayu"),
    ]

    private let quickPhrases: [(text: String, label: String)] = [
        (L("你有哪裡不舒服？"), L("哪裡不舒服")),
        (L("你能呼吸嗎？"), L("能呼吸嗎")),
        (L("我要幫助你"), L("我要幫你")),
        (L("請不要移動"), L("不要移動")),
        (L("救護車來了"), L("救護車來了")),
        (L("你叫什麼名字？"), L("你的名字")),
        (L("你有沒有過敏？"), L("過敏史")),
        (L("請張開嘴巴"), L("張開嘴巴")),
    ]

    private var languageSelectorBackground: Color {
        #if canImport(UIKit)
        Color(.systemGray6)
        #else
        Color.secondary.opacity(0.08)
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if vm.isAIServicePaused {
                    AIServicePausedBanner(message: vm.aiServicePauseMessage)
                }

                if !vm.isWiFiCommandMode {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(NV.warning)
                        Text(L("未連線指揮中心，使用 iPhone 內建離線翻譯庫"))
                            .font(.caption)
                            .foregroundColor(NV.warning)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NV.warning.opacity(0.1))
                    .cornerRadius(8)
                }

                languageSelector
                inputSection

                if let err = errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(NV.danger)
                        Text(err)
                            .font(.caption)
                            .foregroundColor(NV.danger)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NV.danger.opacity(0.1))
                    .cornerRadius(8)
                }

                quickPhraseSection

                if let result = vm.latestTranslation {
                    resultSection(result)
                }
            }
            .padding()
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .outerNavigationTitle(L("翻譯"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .onChange(of: vm.translationErrorMessage) { _, msg in
            errorMessage = msg
        }
        .onChange(of: sourceLang) { _, _ in
            clearTranslationResult()
        }
        .onChange(of: targetLang) { _, _ in
            clearTranslationResult()
        }
    }

    // MARK: - 語言選擇器

    private var languageSelector: some View {
        HStack(alignment: .bottom, spacing: 10) {
            languagePickerColumn(title: L("來源語言"), label: L("來源"), selection: $sourceLang, options: languages)

            Button {
                guard sourceLang != "auto" else { return }
                let tmp = sourceLang
                sourceLang = targetLang
                targetLang = tmp
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(sourceLang == "auto" ? .secondary : NV.command)
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                    )
            }
            .disabled(sourceLang == "auto")
            .padding(.bottom, 1)

            languagePickerColumn(
                title: L("目標語言"),
                label: L("目標"),
                selection: $targetLang,
                options: languages.filter { $0.code != "auto" }
            )
        }
        .padding()
        .background(languageSelectorBackground)
        .cornerRadius(12)
    }

    private func languagePickerColumn(
        title: String,
        label: String,
        selection: Binding<String>,
        options: [(code: String, name: String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Picker(label, selection: selection) {
                ForEach(options, id: \.code) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 輸入區

    private var inputSection: some View {
        VStack(spacing: 8) {
            TextEditor(text: $inputText)
                .frame(height: 100)
                .focused($isTranslatorFocused)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )

            HStack(spacing: 8) {
                if isTranslatorFocused {
                    Button(L("完成")) {
                        isTranslatorFocused = false
                    }
                    .buttonStyle(.bordered)
                    .tint(NV.command)
                    .transition(.opacity.combined(with: .scale))
                }

                Button {
                    translate()
                } label: {
                    HStack {
                        if vm.isTranslating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "globe")
                        }
                        Text(vm.isTranslating ? L("翻譯中...") : L("翻譯"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(vm.isAIServicePaused ? .gray : NV.command)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isTranslating)
            }
        }
    }

    // MARK: - 快速醫療用語

    private var quickPhraseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("快速醫療用語"))
                .font(.caption)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 8) {
                ForEach(quickPhrases, id: \.text) { phrase in
                    Button {
                        inputText = phrase.text
                        translate(textOverride: phrase.text)
                    } label: {
                        Text(phrase.label)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(NV.command.opacity(0.1))
                            .foregroundColor(NV.command)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 翻譯結果

    private func resultSection(_ result: TranslationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("原文"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !result.detectedLang.isEmpty {
                        Text("(\(result.detectedLang))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Text(result.original)
                    .font(.body)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L("譯文 (%@)", result.targetLang))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(result.translated)
                    .font(.title2)
                    .fontWeight(.medium)
                    .textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NV.command.opacity(0.08))
            .cornerRadius(12)

            HStack(spacing: 16) {
                Button {
                    copyToPasteboard(result.translated)
                } label: {
                    Label(L("複製"), systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)

                Button {
                    speak(text: result.translated, lang: result.targetLang)
                } label: {
                    Label(L("朗讀"), systemImage: "speaker.wave.2.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Helpers

    private func copyToPasteboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func clearTranslationResult() {
        guard !vm.isTranslating else { return }
        errorMessage = nil
        vm.translationErrorMessage = nil
        vm.latestTranslation = nil
    }

    private func translate(textOverride: String? = nil) {
        let text = (textOverride ?? inputText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errorMessage = nil
        vm.translationErrorMessage = nil
        vm.isTranslating = true
        vm.latestTranslation = nil

        if let offline = OfflineTranslationLibrary.shared.translateExact(
            text: text,
            sourceLang: sourceLang,
            targetLang: targetLang
        ) {
            applyTranslation(
                original: text,
                translated: offline.translated,
                detectedLang: offline.detectedLang,
                targetLang: offline.targetLang
            )
            return
        }

        if vm.isAIServicePaused {
            if let offline = OfflineTranslationLibrary.shared.translate(
                text: text,
                sourceLang: sourceLang,
                targetLang: targetLang
            ) {
                applyTranslation(
                    original: text,
                    translated: offline.translated,
                    detectedLang: offline.detectedLang,
                    targetLang: offline.targetLang,
                    message: L("AI服務暫停，已切換離線翻譯庫")
                )
            } else {
                errorMessage = L("AI服務暫停，且離線翻譯庫無對應詞句")
                vm.translationErrorMessage = errorMessage
                vm.isTranslating = false
            }
            return
        }

        Task {
            let host = await MainActor.run { vm.transcriptionServerHost }
            if !host.isEmpty && host != "localhost",
               let directResult = await directTranslateHTTP(host: host, text: text, sourceLang: sourceLang, targetLang: targetLang) {
                await MainActor.run {
                    applyTranslation(
                        original: text,
                        translated: directResult,
                        detectedLang: sourceLang,
                        targetLang: targetLang
                    )
                }
                return
            }

            let canUseHQRelay = await MainActor.run { vm.commandClient.isConnected }
            if canUseHQRelay {
                await MainActor.run {
                    vm.requestTranslation(text: text, sourceLang: sourceLang, targetLang: targetLang)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak vm] in
                        guard vm?.isTranslating == true else { return }
                        if let offline = OfflineTranslationLibrary.shared.translate(
                            text: text,
                            sourceLang: sourceLang,
                            targetLang: targetLang
                        ) {
                            vm?.latestTranslation = TranslationResult(
                                original: text,
                                translated: offline.translated,
                                detectedLang: offline.detectedLang,
                                targetLang: offline.targetLang
                            )
                            vm?.translationErrorMessage = L("線上翻譯較慢，已切換離線翻譯庫")
                        } else {
                            vm?.translationErrorMessage = L("線上翻譯回應較慢，請確認 HQ 與 AI 服務狀態")
                        }
                        vm?.isTranslating = false
                    }
                }
                return
            }

            await MainActor.run {
                if let offline = OfflineTranslationLibrary.shared.translate(
                    text: text,
                    sourceLang: sourceLang,
                    targetLang: targetLang
                ) {
                    applyTranslation(
                        original: text,
                        translated: offline.translated,
                        detectedLang: offline.detectedLang,
                        targetLang: offline.targetLang
                    )
                } else {
                    errorMessage = L("離線翻譯庫無對應詞句，請改用常用救援/醫療短句")
                    vm.translationErrorMessage = errorMessage
                    vm.isTranslating = false
                }
            }
        }
    }

    private func applyTranslation(
        original: String,
        translated: String,
        detectedLang: String,
        targetLang: String,
        message: String? = nil
    ) {
        vm.latestTranslation = TranslationResult(
            original: original,
            translated: translated,
            detectedLang: detectedLang,
            targetLang: targetLang
        )
        errorMessage = message
        vm.translationErrorMessage = message
        vm.isTranslating = false
    }

    private func directTranslateHTTP(host: String, text: String, sourceLang: String, targetLang: String) async -> String? {
        guard let url = URL(string: "http://\(host):8001/translate") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5
        let body: [String: Any] = ["text": text, "source_lang": sourceLang, "target_lang": targetLang, "context": "rescue_medical"]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = bodyData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else { return nil }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let payload = json["data"] as? [String: Any] ?? json
                if let translated = payload["translated"] as? String, !translated.isEmpty {
                    return translated
                }
            }
        } catch {
            // 連線失敗 — silent fallback
        }
        return nil
    }

    private func speak(text: String, lang: String) {
        let utterance = AVSpeechUtterance(string: text)
        let langMap: [String: String] = [
            "zh-TW": "zh-TW", "en": "en-US", "ja": "ja-JP",
            "ko": "ko-KR", "vi": "vi-VN", "th": "th-TH",
            "id": "id-ID", "ms": "ms-MY",
        ]
        utterance.voice = AVSpeechSynthesisVoice(language: langMap[lang] ?? "en-US")
        utterance.rate = 0.56
        AVSpeechSynthesizer().speak(utterance)
    }
}