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
                L("「固定會報」：點擊錄音 → 再點停止 → 自動上傳"),
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
            .toolbarBackground(.hidden, for: .navigationBar)
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
