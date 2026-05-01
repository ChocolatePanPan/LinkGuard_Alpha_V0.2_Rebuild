import SwiftUI
import AVFoundation

// MARK: - 翻譯功能頁面

struct TranslatorView: View {
    @ObservedObject var vm: LinkGuardViewModel
    @State private var inputText = ""
    @State private var sourceLang = "auto"
    @State private var targetLang = "en"
    @State private var isTranslating = false
    @State private var errorMessage: String?

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 連線狀態提示
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

                    // 語言選擇
                    languageSelector

                    // 輸入區
                    inputSection

                    // 錯誤提示
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

                    // 快速醫療用語
                    quickPhraseSection

                    // 翻譯結果
                    if let result = vm.latestTranslation {
                        resultSection(result)
                    }
                }
                .padding()
            }
            .navigationTitle(L("翻譯"))
            #if os(iOS)
            .toolbarVisibility(.hidden, for: .navigationBar)
            #endif
            .contentMargins(.top, 0, for: .scrollContent)
            .safeAreaInset(edge: .top) {
                HStack {
                    Text(L("翻譯"))
                        .font(.title2).bold()
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .onChange(of: vm.latestTranslation?.translated) { _, _ in
            isTranslating = false
        }
    }

    // MARK: - 語言選擇器

    private var languageSelector: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("來源語言"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker(L("來源"), selection: $sourceLang) {
                    ForEach(languages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
            }

            Button {
                guard sourceLang != "auto" else { return }
                let tmp = sourceLang
                sourceLang = targetLang
                targetLang = tmp
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title3)
                    .foregroundColor(NV.command)
            }
            .disabled(sourceLang == "auto")

            VStack(alignment: .leading, spacing: 4) {
                Text(L("目標語言"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker(L("目標"), selection: $targetLang) {
                    ForEach(languages.filter { $0.code != "auto" }, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - 輸入區

    private var inputSection: some View {
        VStack(spacing: 8) {
            TextEditor(text: $inputText)
                .frame(height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )

            Button {
                translate()
            } label: {
                HStack {
                    if isTranslating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "globe")
                    }
                    Text(isTranslating ? L("翻譯中...") : L("翻譯"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(NV.command)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating)
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
                        translate()
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

            // 原文
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

            // 譯文
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

            // 操作按鈕
            HStack(spacing: 16) {
                Button {
                    UIPasteboard.general.string = result.translated
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

    private func translate() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errorMessage = nil
        isTranslating = true
        // 清除舊結果，避免 .onChange 因相同字串而不觸發
        vm.latestTranslation = nil

        if vm.commandClient.isConnected {
            // 線上翻譯（透過 HQ → 後台 gemma4）
            vm.requestTranslation(text: text, sourceLang: sourceLang, targetLang: targetLang)
            // 超時保護（12 秒，因 GEMMA4 翻譯可能需 5-10 秒）
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak vm] in
                guard self.isTranslating else { return }
                // HQ 未回應 → 嘗試 HTTP 直連 gemma4 備援
                Task {
                    let host = vm?.transcriptionServerHost ?? ""
                    if !host.isEmpty && host != "localhost",
                       let directResult = await self.directTranslateHTTP(host: host, text: text, sourceLang: sourceLang, targetLang: targetLang) {
                        await MainActor.run {
                            vm?.latestTranslation = TranslationResult(
                                original: text,
                                translated: directResult,
                                detectedLang: sourceLang,
                                targetLang: targetLang
                            )
                            self.isTranslating = false
                            self.errorMessage = L("已透過備援路由完成翻譯")
                        }
                        return
                    }
                    // HTTP 也失敗 → 離線 fallback
                    await MainActor.run {
                        self.isTranslating = false
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
                            self.errorMessage = L("線上翻譯逾時，已切換離線翻譯庫")
                        } else {
                            self.errorMessage = L("翻譯逾時，且離線翻譯庫無對應詞句")
                        }
                    }
                }
            }
        } else {
            // 離線模式：先嘗試直連 gemma4，再 fallback 離線翻譯庫
            Task {
                let host = vm.transcriptionServerHost
                if !host.isEmpty && host != "localhost",
                   let directResult = await directTranslateHTTP(host: host, text: text, sourceLang: sourceLang, targetLang: targetLang) {
                    await MainActor.run {
                        vm.latestTranslation = TranslationResult(
                            original: text,
                            translated: directResult,
                            detectedLang: sourceLang,
                            targetLang: targetLang
                        )
                        isTranslating = false
                    }
                    return
                }
                await MainActor.run {
                    if let offline = OfflineTranslationLibrary.shared.translate(
                        text: text,
                        sourceLang: sourceLang,
                        targetLang: targetLang
                    ) {
                        vm.latestTranslation = TranslationResult(
                            original: text,
                            translated: offline.translated,
                            detectedLang: offline.detectedLang,
                            targetLang: offline.targetLang
                        )
                    } else {
                        errorMessage = L("離線翻譯庫無對應詞句，請改用常用救援/醫療短句")
                    }
                    isTranslating = false
                }
            }
        }
    }

    /// 直連 gemma4 /translate HTTP 備援
    private func directTranslateHTTP(host: String, text: String, sourceLang: String, targetLang: String) async -> String? {
        guard let url = URL(string: "http://\(host):8001/translate") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        let body: [String: Any] = ["text": text, "source_lang": sourceLang, "target_lang": targetLang, "context": "rescue_medical"]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = bodyData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else { return nil }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let translated = json["translated"] as? String, !translated.isEmpty {
                return translated
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
        utterance.rate = 0.45
        AVSpeechSynthesizer().speak(utterance)
    }
}
