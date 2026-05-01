import Foundation

// MARK: - iPhone 內建離線翻譯庫

struct OfflineTranslationLibrary {
    static let shared = OfflineTranslationLibrary()

    struct OfflineHit {
        let translated: String
        let detectedLang: String
        let targetLang: String
    }

    private struct PhraseEntry {
        let translations: [String: String]
        let aliases: [String: [String]]
    }

    private let supportedLangs: Set<String> = [
        "zh-TW", "en", "ja", "ko", "vi", "th", "id", "ms",
    ]

    // 內建救援/醫療常用句庫（可離線使用）
    private let entries: [PhraseEntry] = [
        PhraseEntry(
            translations: [
                "zh-TW": "你有哪裡不舒服？", "en": "Where do you feel discomfort?", "ja": "どこがつらいですか？", "ko": "어디가 불편하세요?", "vi": "Bạn thấy khó chịu ở đâu?", "th": "คุณรู้สึกไม่สบายตรงไหน?", "id": "Bagian mana yang terasa tidak nyaman?", "ms": "Di bahagian mana anda rasa tidak selesa?",
            ],
            aliases: ["zh-TW": ["你哪裡不舒服", "哪裡不舒服"], "en": ["where does it hurt"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "你能呼吸嗎？", "en": "Can you breathe?", "ja": "呼吸できますか？", "ko": "숨을 쉴 수 있나요?", "vi": "Bạn có thở được không?", "th": "คุณหายใจได้ไหม?", "id": "Apakah kamu bisa bernapas?", "ms": "Bolehkah anda bernafas?",
            ],
            aliases: ["zh-TW": ["能呼吸嗎"], "en": ["can you breath", "can you breathe"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "我要幫助你", "en": "I am here to help you.", "ja": "あなたを助けます。", "ko": "제가 도와드릴게요.", "vi": "Tôi ở đây để giúp bạn.", "th": "ฉันอยู่ที่นี่เพื่อช่วยคุณ", "id": "Saya di sini untuk membantu Anda.", "ms": "Saya di sini untuk membantu anda.",
            ],
            aliases: ["zh-TW": ["我要幫你"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "請不要移動", "en": "Please do not move.", "ja": "動かないでください。", "ko": "움직이지 마세요.", "vi": "Vui lòng đừng di chuyển.", "th": "กรุณาอย่าขยับ", "id": "Tolong jangan bergerak.", "ms": "Tolong jangan bergerak.",
            ],
            aliases: ["zh-TW": ["不要移動"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "救護車來了", "en": "The ambulance is here.", "ja": "救急車が来ました。", "ko": "구급차가 도착했습니다.", "vi": "Xe cứu thương đã đến.", "th": "รถพยาบาลมาถึงแล้ว", "id": "Ambulans sudah tiba.", "ms": "Ambulans sudah tiba.",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "你叫什麼名字？", "en": "What is your name?", "ja": "お名前は何ですか？", "ko": "이름이 무엇인가요?", "vi": "Bạn tên là gì?", "th": "คุณชื่ออะไร?", "id": "Siapa nama Anda?", "ms": "Siapa nama anda?",
            ],
            aliases: ["zh-TW": ["你的名字"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "你有沒有過敏？", "en": "Do you have any allergies?", "ja": "アレルギーはありますか？", "ko": "알레르기가 있나요?", "vi": "Bạn có bị dị ứng gì không?", "th": "คุณมีอาการแพ้อะไรไหม?", "id": "Apakah Anda punya alergi?", "ms": "Adakah anda mempunyai alahan?",
            ],
            aliases: ["zh-TW": ["過敏史"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "請張開嘴巴", "en": "Please open your mouth.", "ja": "口を開けてください。", "ko": "입을 벌려 주세요.", "vi": "Vui lòng mở miệng.", "th": "กรุณาอ้าปาก", "id": "Tolong buka mulut Anda.", "ms": "Sila buka mulut anda.",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "頭痛", "en": "Headache", "ja": "頭痛", "ko": "두통", "vi": "Đau đầu", "th": "ปวดศีรษะ", "id": "Sakit kepala", "ms": "Sakit kepala",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "胸痛", "en": "Chest pain", "ja": "胸の痛み", "ko": "흉통", "vi": "Đau ngực", "th": "เจ็บหน้าอก", "id": "Nyeri dada", "ms": "Sakit dada",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "呼吸困難", "en": "Difficulty breathing", "ja": "呼吸困難", "ko": "호흡곤란", "vi": "Khó thở", "th": "หายใจลำบาก", "id": "Sulit bernapas", "ms": "Sesak nafas",
            ],
            aliases: ["zh-TW": ["喘不過氣"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "出血", "en": "Bleeding", "ja": "出血", "ko": "출혈", "vi": "Chảy máu", "th": "มีเลือดออก", "id": "Perdarahan", "ms": "Pendarahan",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "骨折", "en": "Fracture", "ja": "骨折", "ko": "골절", "vi": "Gãy xương", "th": "กระดูกหัก", "id": "Patah tulang", "ms": "Patah tulang",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "意識不清", "en": "Unconscious", "ja": "意識不明", "ko": "의식 없음", "vi": "Bất tỉnh", "th": "หมดสติ", "id": "Tidak sadar", "ms": "Tidak sedarkan diri",
            ],
            aliases: ["zh-TW": ["昏迷", "失去意識"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "過敏反應", "en": "Allergic reaction", "ja": "アレルギー反応", "ko": "알레르기 반응", "vi": "Phản ứng dị ứng", "th": "ปฏิกิริยาแพ้", "id": "Reaksi alergi", "ms": "Reaksi alahan",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "需要立即送醫", "en": "Need immediate transport to hospital.", "ja": "直ちに病院へ搬送が必要です。", "ko": "즉시 병원 이송이 필요합니다.", "vi": "Cần chuyển viện ngay lập tức.", "th": "ต้องนำส่งโรงพยาบาลทันที", "id": "Perlu segera dibawa ke rumah sakit.", "ms": "Perlu dihantar ke hospital dengan segera.",
            ],
            aliases: ["zh-TW": ["要馬上送醫"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "請保持清醒", "en": "Please stay awake.", "ja": "意識を保ってください。", "ko": "의식을 유지해 주세요.", "vi": "Vui lòng giữ tỉnh táo.", "th": "กรุณาพยายามอย่าหลับ", "id": "Tolong tetap sadar.", "ms": "Sila kekal sedar.",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "痛在哪裡？", "en": "Where is the pain?", "ja": "どこが痛いですか？", "ko": "어디가 아픈가요?", "vi": "Bạn đau ở đâu?", "th": "เจ็บตรงไหน?", "id": "Sakitnya di mana?", "ms": "Sakit di mana?",
            ],
            aliases: ["zh-TW": ["哪裡痛"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "請壓住傷口", "en": "Please apply pressure to the wound.", "ja": "傷口を圧迫してください。", "ko": "상처 부위를 압박해 주세요.", "vi": "Vui lòng đè ép lên vết thương.", "th": "กรุณากดแผลไว้", "id": "Tolong tekan bagian luka.", "ms": "Sila tekan pada luka.",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "請慢慢呼吸", "en": "Please breathe slowly.", "ja": "ゆっくり呼吸してください。", "ko": "천천히 숨 쉬세요.", "vi": "Vui lòng thở chậm lại.", "th": "กรุณาหายใจช้า ๆ", "id": "Tolong bernapas perlahan.", "ms": "Sila bernafas perlahan-lahan.",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "我們正在撤離", "en": "We are evacuating now.", "ja": "現在避難しています。", "ko": "지금 대피 중입니다.", "vi": "Chúng tôi đang sơ tán.", "th": "เรากำลังอพยพ", "id": "Kami sedang evakuasi sekarang.", "ms": "Kami sedang berpindah keluar sekarang.",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "請跟著我走", "en": "Please follow me.", "ja": "私についてきてください。", "ko": "저를 따라오세요.", "vi": "Vui lòng đi theo tôi.", "th": "กรุณาตามฉันมา", "id": "Tolong ikuti saya.", "ms": "Sila ikut saya.",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "危險，請後退", "en": "Danger, please step back.", "ja": "危険です、下がってください。", "ko": "위험합니다. 뒤로 물러나세요.", "vi": "Nguy hiểm, vui lòng lùi lại.", "th": "อันตราย กรุณาถอยหลัง", "id": "Bahaya, mohon mundur.", "ms": "Bahaya, sila berundur.",
            ],
            aliases: ["zh-TW": ["危險請後退"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "請等待指示", "en": "Please wait for instructions.", "ja": "指示を待ってください。", "ko": "지시를 기다려 주세요.", "vi": "Vui lòng chờ chỉ thị.", "th": "กรุณารอคำสั่ง", "id": "Tolong tunggu instruksi.", "ms": "Sila tunggu arahan.",
            ],
            aliases: [:]
        ),
        // 新增醫療與救援擴充句庫
        PhraseEntry(
            translations: [
                "zh-TW": "你有糖尿病嗎？", "en": "Do you have diabetes?", "ja": "糖尿病はありますか？", "ko": "당뇨병이 있나요?", "vi": "Bạn có bị tiểu đường không?", "th": "คุณเป็นเบาหวานไหม?", "id": "Apakah Anda menderita diabetes?", "ms": "Adakah anda menghidap kencing manis?",
            ],
            aliases: ["zh-TW": ["糖尿病"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "你有高血壓嗎？", "en": "Do you have high blood pressure?", "ja": "高血圧はありますか？", "ko": "고혈압이 있나요?", "vi": "Bạn có bị huyết áp cao không?", "th": "คุณมีความดันโลหิตสูงไหม?", "id": "Apakah Anda memiliki tekanan darah tinggi?", "ms": "Adakah anda mempunyai darah tinggi?",
            ],
            aliases: ["zh-TW": ["高血壓"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "你正在服用什麼藥？", "en": "What medications are you taking?", "ja": "何の薬を飲んでいますか？", "ko": "어떤 약을 복용하고 있나요?", "vi": "Bạn đang uống thuốc gì?", "th": "คุณกำลังทานยาอะไรอยู่?", "id": "Obat apa yang sedang Anda konsumsi?", "ms": "Apakah ubat yang anda sedang ambil?",
            ],
            aliases: ["zh-TW": ["吃什麼藥", "服用藥物"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "你最後一次吃東西是什麼時候？", "en": "When was the last time you ate?", "ja": "最後にいつ食事をしましたか？", "ko": "마지막으로 언제 식사하셨나요?", "vi": "Lần cuối bạn ăn là khi nào?", "th": "คุณกินอาหารครั้งสุดท้ายเมื่อไหร่?", "id": "Kapan terakhir kali Anda makan?", "ms": "Bilakah kali terakhir anda makan?",
            ],
            aliases: ["zh-TW": ["最後吃東西"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "你懷孕了嗎？", "en": "Are you pregnant?", "ja": "妊娠していますか？", "ko": "임신 중이신가요?", "vi": "Bạn có đang mang thai không?", "th": "คุณตั้งครรภ์อยู่ไหม?", "id": "Apakah Anda sedang hamil?", "ms": "Adakah anda sedang mengandung?",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "腹痛", "en": "Abdominal pain", "ja": "腹痛", "ko": "복통", "vi": "Đau bụng", "th": "ปวดท้อง", "id": "Sakit perut", "ms": "Sakit perut",
            ],
            aliases: ["zh-TW": ["肚子痛"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "噁心", "en": "Nausea", "ja": "吐き気", "ko": "메스꺼움", "vi": "Buồn nôn", "th": "คลื่นไส้", "id": "Mual", "ms": "Loya",
            ],
            aliases: ["zh-TW": ["想吐"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "頭暈", "en": "Dizziness", "ja": "めまい", "ko": "어지러움", "vi": "Chóng mặt", "th": "เวียนศีรษะ", "id": "Pusing", "ms": "Pening",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "燒傷", "en": "Burn injury", "ja": "やけど", "ko": "화상", "vi": "Bỏng", "th": "แผลไฟไหม้", "id": "Luka bakar", "ms": "Kecederaan melecur",
            ],
            aliases: ["zh-TW": ["燙傷"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "脫水", "en": "Dehydration", "ja": "脱水", "ko": "탈수", "vi": "Mất nước", "th": "ขาดน้ำ", "id": "Dehidrasi", "ms": "Dehidrasi",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "休克", "en": "Shock", "ja": "ショック", "ko": "쇼크", "vi": "Sốc", "th": "ช็อก", "id": "Syok", "ms": "Kejutan",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "請問你有幾歲？", "en": "How old are you?", "ja": "おいくつですか？", "ko": "몇 살이세요?", "vi": "Bạn bao nhiêu tuổi?", "th": "คุณอายุเท่าไหร่?", "id": "Berapa umur Anda?", "ms": "Berapakah umur anda?",
            ],
            aliases: ["zh-TW": ["幾歲", "年齡"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "這裡很安全", "en": "It is safe here.", "ja": "ここは安全です。", "ko": "여기는 안전합니다.", "vi": "Ở đây an toàn.", "th": "ที่นี่ปลอดภัย", "id": "Di sini aman.", "ms": "Di sini selamat.",
            ],
            aliases: ["zh-TW": ["安全"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "結構不穩定，請撤離", "en": "Structure unstable, please evacuate.", "ja": "構造が不安定です、避難してください。", "ko": "구조물이 불안정합니다. 대피하세요.", "vi": "Cấu trúc không ổn định, vui lòng sơ tán.", "th": "โครงสร้างไม่มั่นคง กรุณาอพยพ", "id": "Struktur tidak stabil, harap evakuasi.", "ms": "Struktur tidak stabil, sila berpindah.",
            ],
            aliases: ["zh-TW": ["結構不穩"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "我們需要更多人手", "en": "We need more personnel.", "ja": "もっと人手が必要です。", "ko": "더 많은 인력이 필요합니다.", "vi": "Chúng tôi cần thêm nhân lực.", "th": "เราต้องการคนเพิ่ม", "id": "Kami butuh lebih banyak personel.", "ms": "Kami perlukan lebih ramai kakitangan.",
            ],
            aliases: ["zh-TW": ["需要人手", "增援"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "已找到生還者", "en": "Survivor found.", "ja": "生存者を発見しました。", "ko": "생존자를 발견했습니다.", "vi": "Đã tìm thấy người sống sót.", "th": "พบผู้รอดชีวิต", "id": "Korban selamat ditemukan.", "ms": "Mangsa selamat ditemui.",
            ],
            aliases: ["zh-TW": ["發現生還者"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "需要擔架", "en": "Need a stretcher.", "ja": "担架が必要です。", "ko": "들것이 필요합니다.", "vi": "Cần cáng.", "th": "ต้องการเปลหาม", "id": "Butuh tandu.", "ms": "Perlukan tandu.",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "需要氧氣", "en": "Need oxygen.", "ja": "酸素が必要です。", "ko": "산소가 필요합니다.", "vi": "Cần ôxy.", "th": "ต้องการออกซิเจน", "id": "Butuh oksigen.", "ms": "Perlukan oksigen.",
            ],
            aliases: [:]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "有瓦斯外洩", "en": "Gas leak detected.", "ja": "ガス漏れがあります。", "ko": "가스 누출이 감지되었습니다.", "vi": "Phát hiện rò rỉ khí gas.", "th": "พบแก๊สรั่ว", "id": "Terdeteksi kebocoran gas.", "ms": "Kebocoran gas dikesan.",
            ],
            aliases: ["zh-TW": ["瓦斯洩漏", "瓦斯"]]
        ),
        PhraseEntry(
            translations: [
                "zh-TW": "水源在這裡", "en": "Water source is here.", "ja": "水源はここにあります。", "ko": "수원지가 여기 있습니다.", "vi": "Nguồn nước ở đây.", "th": "แหล่งน้ำอยู่ที่นี่", "id": "Sumber air ada di sini.", "ms": "Sumber air di sini.",
            ],
            aliases: [:]
        ),
    ]

    private init() {}

    func translate(text: String, sourceLang: String = "auto", targetLang: String) -> OfflineHit? {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return nil }
        guard supportedLangs.contains(targetLang) else { return nil }

        var detected = sourceLang
        if sourceLang == "auto" {
            detected = detectLanguage(for: original)
        }

        if detected == targetLang {
            return OfflineHit(translated: original, detectedLang: detected, targetLang: targetLang)
        }

        if let translated = exactTranslate(text: original, detected: detected, target: targetLang) {
            return OfflineHit(translated: translated, detectedLang: detected, targetLang: targetLang)
        }

        if let translated = fuzzyTranslate(text: original, detected: detected, target: targetLang) {
            return OfflineHit(translated: translated, detectedLang: detected, targetLang: targetLang)
        }

        return nil
    }

    private func detectLanguage(for text: String) -> String {
        let normalized = normalize(text)

        // 先走句庫精準匹配，可偵測到非字元語系
        for lang in supportedLangs {
            if exactTranslate(text: normalized, detected: lang, target: "en") != nil {
                return lang
            }
        }

        if text.range(of: "[\\u3040-\\u30ff]", options: .regularExpression) != nil { return "ja" }
        if text.range(of: "[\\uac00-\\ud7af]", options: .regularExpression) != nil { return "ko" }
        if text.range(of: "[A-Za-z]", options: .regularExpression) != nil { return "en" }
        if text.range(of: "[\\u4e00-\\u9fff]", options: .regularExpression) != nil { return "zh-TW" }
        return "zh-TW"
    }

    private func exactTranslate(text: String, detected: String, target: String) -> String? {
        let key = normalize(text)
        for entry in entries {
            if let sourceText = entry.translations[detected], normalize(sourceText) == key {
                return entry.translations[target]
            }
            if let aliasList = entry.aliases[detected], aliasList.contains(where: { normalize($0) == key }) {
                return entry.translations[target]
            }
            // 自動偵測不準時，允許跨語系匹配
            if detected == "auto" {
                for (lang, sourceText) in entry.translations where supportedLangs.contains(lang) {
                    if normalize(sourceText) == key {
                        return entry.translations[target]
                    }
                }
            }
        }
        return nil
    }

    private func fuzzyTranslate(text: String, detected: String, target: String) -> String? {
        let key = normalize(text)
        for entry in entries {
            if let sourceText = entry.translations[detected], key.contains(normalize(sourceText)) {
                return entry.translations[target]
            }
            if let aliasList = entry.aliases[detected], aliasList.contains(where: { key.contains(normalize($0)) }) {
                return entry.translations[target]
            }
        }
        return nil
    }

    private func normalize(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let punctuations = ["？", "?", "！", "!", "。", ".", "，", ",", "、", "；", ";", "：", ":", "\n", "\r", "\t"]
        for p in punctuations {
            result = result.replacingOccurrences(of: p, with: "")
        }
        result = result.replacingOccurrences(of: "  ", with: " ")
        return result
    }
}
