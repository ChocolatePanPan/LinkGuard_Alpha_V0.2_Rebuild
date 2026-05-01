import SwiftUI

// =====================================================
//  AI 副駕駛指令提案卡片
//  顯示在 HQAIChatView 的 AI 回覆下方，由指揮官點「執行」
//  才會經 HQViewModel.executeAIProposal → HQCommandServer.sendCommand 廣播
// =====================================================

struct HQAIProposalCard: View {
    let proposal: AIProposal
    let isExecuted: Bool
    let isIgnored: Bool
    let onExecute: () -> Void
    let onIgnore: () -> Void

    // Phase E 安全閘狀態
    @State private var showDoubleConfirm: Bool = false
    @State private var confirmText: String = ""
    @State private var autoDispatchCancelled: Bool = false
    @State private var autoCountdownRemain: Int = 0
    @State private var autoTimer: Timer? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // 左側 priority 彩色條
            Rectangle()
                .fill(proposal.priorityColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                // 頂部：類型 icon + 標籤 + priority
                HStack(spacing: 6) {
                    Image(systemName: proposal.iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(proposal.priorityColor)
                    Text(L("AI 提案 · %@", proposal.typeLabel))
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundColor(proposal.priorityColor)
                        .tracking(1)
                    Spacer()
                    Text(proposal.priorityLabel)
                        .font(.system(.caption2, design: .monospaced).bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(proposal.priorityColor.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                // Phase E：安全閘 badges
                if proposal.isAutoMode || proposal.requiresDoubleConfirm {
                    HStack(spacing: 6) {
                        if proposal.isAutoMode {
                            badgePill(text: autoCountdownRemain > 0
                                       ? "AUTO \(autoCountdownRemain)s"
                                       : "AUTO \(proposal.countdown_sec)s",
                                       color: NV.warning,
                                       icon: "timer")
                        }
                        if proposal.requiresDoubleConfirm {
                            badgePill(text: "DOUBLE-CONFIRM",
                                       color: NV.danger,
                                       icon: "exclamationmark.shield.fill")
                        }
                        Spacer()
                    }
                }

                // 標題
                Text(proposal.title)
                    .font(.system(.subheadline, design: .default).bold())
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                // 詳情
                if !proposal.detail.isEmpty {
                    Text(proposal.detail)
                        .font(.caption)
                        .foregroundColor(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 目標
                HStack(spacing: 4) {
                    Image(systemName: "scope")
                        .font(.system(size: 9))
                    Text(targetText)
                        .font(.system(.caption2, design: .monospaced))
                }
                .foregroundColor(.secondary)

                // Rationale
                if !proposal.rationale.isEmpty {
                    Text(L("理由：%@", proposal.rationale))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 按鈕列
                HStack(spacing: 8) {
                    if isExecuted {
                        statusPill(text: L("已執行"), color: NV.green, icon: "checkmark.circle.fill")
                        Spacer()
                    } else if isIgnored {
                        statusPill(text: L("已忽略"), color: .gray, icon: "xmark.circle.fill")
                        Spacer()
                    } else {
                        Button(action: handleExecuteTap) {
                            HStack(spacing: 4) {
                                Image(systemName: autoCountdownRemain > 0
                                                  ? "stop.circle.fill"
                                                  : "paperplane.fill")
                                Text(executeButtonLabel)
                            }
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(autoCountdownRemain > 0 ? NV.warning : NV.green)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(action: onIgnore) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark")
                                Text(L("忽略"))
                            }
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(NV.warning)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .overlay(Capsule().stroke(NV.warning.opacity(0.6), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                }
                .padding(.top, 2)

                // Phase E：DOUBLE-CONFIRM 確認區
                if showDoubleConfirm {
                    doubleConfirmBlock
                }
            }
            .padding(10)
        }
        .background(NV.command.opacity(isExecuted || isIgnored ? 0.05 : 0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(proposal.priorityColor.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(isIgnored ? 0.55 : 1.0)
        .onAppear { startAutoCountdownIfNeeded() }
        .onDisappear { autoTimer?.invalidate() }
    }

    // MARK: - Phase E 安全閘行為

    private var executeButtonLabel: String {
        if autoCountdownRemain > 0 { return L("取消 \(autoCountdownRemain)s") }
        return L("執行")
    }

    private func handleExecuteTap() {
        // 倒數中按下＝取消自動派遣
        if autoCountdownRemain > 0 {
            autoTimer?.invalidate()
            autoTimer = nil
            autoCountdownRemain = 0
            autoDispatchCancelled = true
            return
        }
        // 雙重確認：第一次按 → 顯示確認區
        if proposal.requiresDoubleConfirm && !showDoubleConfirm {
            showDoubleConfirm = true
            confirmText = ""
            return
        }
        onExecute()
    }

    private func startAutoCountdownIfNeeded() {
        guard proposal.isAutoMode,
              proposal.countdown_sec > 0,
              !proposal.requiresDoubleConfirm,   // 雙確認不走自動倒數
              !isExecuted, !isIgnored,
              !autoDispatchCancelled else { return }
        autoCountdownRemain = proposal.countdown_sec
        autoTimer?.invalidate()
        autoTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
            Task { @MainActor in
                autoCountdownRemain -= 1
                if autoCountdownRemain <= 0 {
                    t.invalidate()
                    autoTimer = nil
                    if !autoDispatchCancelled && !isExecuted && !isIgnored {
                        onExecute()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var doubleConfirmBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().background(NV.danger.opacity(0.6))
            Text(L("高風險指令：請輸入「確認」兩字以執行"))
                .font(.caption.bold())
                .foregroundColor(NV.danger)
            HStack(spacing: 6) {
                TextField("", text: $confirmText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
                Button(action: {
                    if confirmText.trimmingCharacters(in: .whitespacesAndNewlines) == "確認" {
                        showDoubleConfirm = false
                        onExecute()
                    }
                }) {
                    Text(L("確認執行"))
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(confirmText.trimmingCharacters(in: .whitespacesAndNewlines) == "確認"
                                    ? NV.danger : Color.gray.opacity(0.4))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(confirmText.trimmingCharacters(in: .whitespacesAndNewlines) != "確認")
                Button(action: { showDoubleConfirm = false; confirmText = "" }) {
                    Text(L("取消"))
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay(Capsule().stroke(Color.gray.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(NV.danger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func badgePill(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(.caption2, design: .monospaced).bold())
        .foregroundColor(color)
        .padding(.horizontal, 5).padding(.vertical, 1)
        .background(color.opacity(0.18))
        .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
        .clipShape(Capsule())
    }

    private var targetText: String {
        if proposal.targets.isEmpty {
            return L("目標：全部前線（廣播）")
        }
        return L("目標：%lld 台 (%@)",
                 proposal.targets.count,
                 proposal.targets.prefix(3).joined(separator: ", "))
    }

    @ViewBuilder
    private func statusPill(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(.caption, design: .monospaced).bold())
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }
}
