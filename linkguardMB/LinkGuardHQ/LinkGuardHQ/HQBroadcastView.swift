import SwiftUI

// MARK: - HQ 文字廣播管理

struct HQBroadcastView: View {
    @ObservedObject var vm: HQViewModel
    @State private var broadcastMessage = ""
    @State private var selectedPriority = "normal"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 標題列
            HStack {
                Text(L("文字廣播"))
                    .font(.title).bold()
                Spacer()
                Text(L("%lld 則廣播", vm.textBroadcasts.count))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            // 發送區域
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("發送新廣播"))
                        .font(.headline)

                    // 優先級
                    HStack(spacing: 12) {
                        Text(L("優先級："))
                            .foregroundColor(.secondary)
                        Picker("", selection: $selectedPriority) {
                            Text(L("一般")).tag("normal")
                            Text(L("緊急")).tag("urgent")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }

                    // 訊息輸入
                    TextEditor(text: $broadcastMessage)
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3))
                        )

                    // 發送按鈕
                    HStack {
                        Spacer()
                        Button {
                            guard !broadcastMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            vm.sendTextBroadcast(message: broadcastMessage, priority: selectedPriority)
                            broadcastMessage = ""
                        } label: {
                            Label(L("發送廣播"), systemImage: "megaphone.fill")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(selectedPriority == "urgent" ? NV.danger : NV.command)
                        .disabled(broadcastMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(8)
            }
            .padding(.horizontal)

            Divider()

            // 廣播歷史
            if vm.textBroadcasts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "megaphone")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(L("尚未發送任何廣播"))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.textBroadcasts) { broadcast in
                            HQBroadcastRow(
                                broadcast: broadcast,
                                readStatus: vm.readStatuses[broadcast.broadcastId]
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical)
    }
}

// MARK: - 廣播列

struct HQBroadcastRow: View {
    let broadcast: HQTextBroadcast
    var readStatus: (total: Int, readCount: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 頂部：優先級 + 發送者 + 時間
            HStack {
                if broadcast.priority == "urgent" {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(NV.danger)
                    Text(L("緊急"))
                        .font(.caption).bold()
                        .foregroundColor(NV.danger)
                }

                Text(broadcast.senderName)
                    .font(.subheadline).bold()

                Spacer()

                Text(broadcast.timeText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 訊息內容
            Text(broadcast.message)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            // 已讀回條
            if let status = readStatus {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(NV.green)
                        .font(.caption)
                    Text(L("已讀 %lld/%lld", status.readCount, status.total))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if status.total > 0 {
                        ProgressView(
                            value: Double(status.readCount),
                            total: Double(status.total)
                        )
                        .tint(NV.green)
                        .frame(width: 80)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(broadcast.priority == "urgent"
                      ? NV.danger.opacity(0.1)
                      : Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(broadcast.priority == "urgent"
                        ? NV.danger.opacity(0.3)
                        : Color.secondary.opacity(0.1))
        )
    }
}
