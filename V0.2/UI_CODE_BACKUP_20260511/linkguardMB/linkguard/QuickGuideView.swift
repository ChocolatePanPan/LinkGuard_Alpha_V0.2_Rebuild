import SwiftUI

// MARK: - 快速操作手冊

struct QuickGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    private let pages: [GuidePage] = [
        GuidePage(
            icon: "gauge.with.dots.needle.33percent",
            title: L("總覽儀表板"),
            color: .blue,
            steps: [
                L("開啟 App 後首頁即為總覽儀表板"),
                L("可即時查看連線人數、受困者數量、SOS 警報"),
                L("點擊各統計卡片可快速跳轉至對應頁面"),
                L("下方有災情摘要、最新事件日誌"),
            ]
        ),
        GuidePage(
            icon: "link",
            title: L("連線指揮中心"),
            color: .green,
            steps: [
                L("進入「連線」頁面"),
                L("確認 iPhone 與 Mac HQ 在同一區域網路"),
                L("系統會自動搜尋 Mac HQ (Bonjour)"),
                L("找到後點擊連線，綠色指示燈表示已連線"),
                L("連線後可使用電台、通訊、翻譯等功能"),
            ]
        ),
        GuidePage(
            icon: "heart.text.square",
            title: L("傷員回報"),
            color: .red,
            steps: [
                L("進入「傷員回報」頁面"),
                L("填寫身分證字號、姓名、出生日期（支援民國/西元）"),
                L("填入位置、呼吸速率、微血管充盈時間"),
                L("勾選「可遵從指令」表示意識狀態"),
                L("可使用語音輸入按鈕：長按錄音 → 放開自動轉錄"),
                L("GPS 座標會自動取得"),
                L("按「送出傷員回報」完成"),
            ]
        ),
        GuidePage(
            icon: "wave.3.right.circle.fill",
            title: L("NFC 檢傷標籤"),
            color: .teal,
            steps: [
                L("用途是讓傷患卡片離線保留最小可交接資料；這不是醫療處置教學，實際處置依消防、救護、醫療單位 SOP。"),
                L("正式顯示 ID：LG-260506-TAO-ZL-E01-S03-B02-F02-A-P023-K。"),
                L("NFC URL：https://linkguard.tw/p/LG260506TAOZLE01S03B02F02AP023K。"),
                L("資料庫 Key 與離線 payload 使用緊湊 ID：LG260506TAOZLE01S03B02F02AP023K。"),
                L("姓名、身分證、電話與完整病歷不寫入 NFC；傷患 ID 不可變動，檢傷、生命徵象、位置與處置可更新。"),
                L("同一名傷患只維護一張主要 NFC 卡；換卡時要先讀舊卡確認 ID，再覆寫或補登 HQ 紀錄。"),
            ]
        ),
        GuidePage(
            icon: "tag.fill",
            title: L("NFC 寫卡流程"),
            color: .teal,
            steps: [
                L("進入「傷員回報」頁面，先確認傷患 ID、分區、樓層、檢傷、生命徵象與處置欄位。"),
                L("NTAG215 選 LG1：LG1|ID|T|S|I|V|TX|TM，適合最低容量與快速交接。"),
                L("NTAG216 選 LG2：包含 LOC、ALG、NOTE、UPD，適合完整離線資料。"),
                L("按「寫入 NFC」後，只讓一張空白或可覆寫標籤靠近 iPhone 頂端。"),
                L("看到「NFC 寫入完成」後不要立刻離開頁面；App 會把 nfc_tag_written 同步到 HQ。"),
                L("回到 HQ 的「NFC 標籤管理」，用傷患 ID 搜尋，確認格式、容量、寫入裝置與 payload 都有紀錄。"),
            ]
        ),
        GuidePage(
            icon: "text.magnifyingglass",
            title: L("LG1 / LG2 速查"),
            color: .teal,
            steps: [
                L("LG1 範例：LG1|LG260506TAOZLE01S03B02F02AP023K|R|M45|LEG_BLEED|RR28/P120/G14|TQL|1430。"),
                L("LG2 範例：LG2|ID:LG260506TAOZLE01S03B02F02AP023K|T:R|S:M45|LOC:S03-B02-F02-A|I:LEFT_LEG_BLEED|V:RR28/P120/G14|TX:TQL+BAND|ALG:PCN|NOTE:CONSCIOUS|TM:20260506T1430|UPD:1455。"),
                L("T：R=紅/立即，Y=黃/延遲，G=綠/輕傷，B=黑/死亡或無生命跡象，U=未分類。"),
                L("S：M45=男性約45歲，F30=女性約30歲，C08=兒童約8歲，U=不明。"),
                L("常用 I：HEAD、CHEST、ABD、ARM_BLEED、LEG_BLEED、FX、BURN、CRUSH、UNCON、CPA。"),
                L("常用 TX：TQL、TQR、BAND、SPL、O2、CPR、AED、IV、NONE；多項處置用 + 連接。"),
            ]
        ),
        GuidePage(
            icon: "exclamationmark.magnifyingglass",
            title: L("NFC 讀不到排除"),
            color: .orange,
            steps: [
                L("iOS 必須使用 Apple 原生 NFC 掃描介面；本 App 會呼叫 NFCNDEFReaderSession，不會出現自製掃描畫面。"),
                L("Simulator 不能測 NFC；請使用支援 NFC 的 iPhone 實機，並把標籤靠近機身頂端。"),
                L("若掃描畫面完全沒有跳出，先檢查 Xcode Signing & Capabilities 是否有 Near Field Communication Tag Reading。"),
                L("免費 Apple Developer 帳號通常無法帶 NFC capability；真機測 CoreNFC 需付費 Developer Program 或已加入付費 Team。"),
                L("若 Apple 掃描畫面有跳出但讀不到，檢查標籤是否已 NDEF 格式化、容量是否足夠、一次是否靠近多張卡。"),
                L("備援流程：Android 或 HQ USB NFC 寫 URL，iPhone 背景 NFC 開網頁；同時印 QR Code 供相機掃描。"),
            ]
        ),
        GuidePage(
            icon: "mic.fill",
            title: L("語音輸入"),
            color: .orange,
            steps: [
                L("傷員回報頁面有語音輸入按鈕"),
                L("長按圓形麥克風按鈕開始錄音"),
                L("放開按鈕結束錄音，自動上傳轉錄"),
                L("轉錄結果自動填入位置欄位"),
                L("需確保已連線指揮中心（Mac HQ 提供轉錄服務）"),
            ]
        ),
        GuidePage(
            icon: "antenna.radiowaves.left.and.right",
            title: L("電台通訊"),
            color: .purple,
            steps: [
                L("「即時廣播」：按住 PTT 按鈕說話，放開結束"),
                L("音訊自動上傳至 HQ 轉錄歸檔"),
                L("「語音會報」：點擊錄音 → 再點停止 → 自動上傳"),
                L("HQ 會將轉錄結果廣播給所有前線裝置"),
                L("開啟「自動播放」可即時收聽其他人的廣播"),
            ]
        ),
        GuidePage(
            icon: "globe",
            title: L("即時翻譯"),
            color: .cyan,
            steps: [
                L("進入「翻譯」頁面"),
                L("選擇來源語言（或自動偵測）和目標語言"),
                L("支援：繁中、英、日、韓、越、泰、印尼、馬來語"),
                L("可使用快速醫療用語按鈕一鍵翻譯"),
                L("連線時使用 AI 翻譯，離線時使用內建翻譯庫"),
                L("翻譯結果可複製或朗讀"),
            ]
        ),
        GuidePage(
            icon: "bubble.left.and.bubble.right.fill",
            title: L("全域通訊"),
            color: .indigo,
            steps: [
                L("「通訊」頁面為全域文字聊天頻道"),
                L("所有連線的前線裝置和 HQ 共用頻道"),
                L("可使用預設訊息模板快速發送"),
                L("支援 @ 提及特定人員"),
                L("顯示已讀回條"),
            ]
        ),
        GuidePage(
            icon: "exclamationmark.triangle.fill",
            title: L("SOS 緊急求救"),
            color: .red,
            steps: [
                L("SOS 警報由受困者裝置（BLE 手環）觸發"),
                L("收到 SOS 會全螢幕警報 + 震動"),
                L("點擊「已確認」關閉彈窗，紀錄保留在列表"),
                L("SOS 紀錄頁面可查看所有歷史警報"),
            ]
        ),
        GuidePage(
            icon: "sparkles",
            title: L("AI 助理"),
            color: .mint,
            steps: [
                L("「AI 助理」頁面可直接向 AI 提問"),
                L("AI 知道現場所有資訊：受困者、傷患、天氣等"),
                L("可詢問檢傷建議、處置方式、資源調度"),
                L("需連線指揮中心以使用 AI 功能"),
            ]
        ),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 進度指示
                HStack(spacing: 6) {
                    ForEach(0..<pages.count, id: \.self) { idx in
                        Circle()
                            .fill(idx == currentPage ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 12)

                // 頁面內容
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { idx, page in
                        guidePageView(page)
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // 導航按鈕
                HStack {
                    if currentPage > 0 {
                        Button {
                            withAnimation { currentPage -= 1 }
                        } label: {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text(L("上一步"))
                            }
                            .font(.subheadline)
                        }
                    }

                    Spacer()

                    if currentPage < pages.count - 1 {
                        Button {
                            withAnimation { currentPage += 1 }
                        } label: {
                            HStack {
                                Text(L("下一步"))
                                Image(systemName: "chevron.right")
                            }
                            .font(.subheadline).bold()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NV.command)
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text(L("開始使用"))
                            }
                            .font(.subheadline).bold()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NV.green)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .navigationTitle(L("快速操作手冊"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("關閉")) { dismiss() }
                }
            }
        }
    }

    private func guidePageView(_ page: GuidePage) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // 圖示
                Image(systemName: page.icon)
                    .font(.system(size: 56))
                    .foregroundColor(page.color)
                    .padding(.top, 20)

                Text(page.title)
                    .font(.title2).bold()

                // 步驟列表
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(page.steps.enumerated()), id: \.offset) { idx, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(idx + 1)")
                                .font(.caption).bold()
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(page.color)
                                .clipShape(Circle())

                            Text(step)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 60)
            }
        }
    }
}

private struct GuidePage {
    let icon: String
    let title: String
    let color: Color
    let steps: [String]
}
