import SwiftUI

// MARK: - 指揮決策介面

struct HQDecisionView: View {
    @ObservedObject var vm: HQViewModel
    @State private var decisionText = ""
    @State private var selectedVictimIDs: Set<String> = []
    @State private var showSentAlert = false

    private var allVictims: [HQVictimRecord] { vm.allVictimRecords }

    var body: some View {
        HQPage {
            HQPageTitleBar(L("指揮決策"), icon: "brain.head.profile", accent: NV.command) {
                Text(vm.isBackendConnected ? L("AI 後端已連線") : L("AI 後端未連線"))
                    .font(.caption.monospaced())
                    .foregroundColor(vm.isBackendConnected ? NV.green : .secondary)
            }

            VStack(alignment: .leading, spacing: 20) {

                // 決策輸入
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("決策內容"))
                        .font(.headline)
                    TextEditor(text: $decisionText)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                }
                .padding(.horizontal)

                // 快速決策模板
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("快速決策"))
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
                        ForEach(quickDecisions, id: \.self) { template in
                            Button {
                                decisionText = template
                            } label: {
                                Text(L(template))
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(NV.command.opacity(0.15))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)

                // AI 建議決策
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("AI 決策建議"))
                        .font(.headline)
                    Button {
                        vm.requestAIDecision(context: decisionText)
                    } label: {
                        HStack {
                            if vm.backendBridge.isRequestingAI {
                                ProgressView()
                                    .controlSize(.small)
                                Text(vm.backendBridge.isConnected ? L("AI 生成中…") : L("連接本機後端…"))
                                    .bold()
                            } else {
                                Image(systemName: "brain")
                                Text(L("請求 AI 建議決策"))
                                    .bold()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!vm.isBackendConnected || vm.backendBridge.isRequestingAI)

                    if !vm.isBackendConnected {
                        Label(L("尚未連線後台伺服器"), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if vm.backendBridge.isRequestingAI && !vm.backendBridge.isConnected {
                        Label(L("正在連接本機 TCP 後端 127.0.0.1:9000"), systemImage: "hourglass")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let error = vm.backendBridge.lastError {
                        Label(error, systemImage: "xmark.octagon.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    if let ai = vm.backendBridge.latestAIDecision {
                        HStack(spacing: 8) {
                            if !ai.model.isEmpty {
                                Label(ai.model, systemImage: "cpu")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(ai.escalated ? Color.orange : Color.teal, in: Capsule())
                            }
                            if ai.escalated {
                                Label(L("已升級至大模型"), systemImage: "arrow.up.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // 關聯受困者
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("關聯受困者"))
                            .font(.headline)
                        Spacer()
                        Text(L("%lld 人已選", selectedVictimIDs.count))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button(selectedVictimIDs.count == allVictims.count ? L("取消全選") : L("全選")) {
                            if selectedVictimIDs.count == allVictims.count {
                                selectedVictimIDs.removeAll()
                            } else {
                                selectedVictimIDs = Set(allVictims.map(\.id))
                            }
                        }
                        .font(.caption)
                    }

                    if allVictims.isEmpty {
                        HStack {
                            Spacer()
                            Text(L("目前無受困者資料"))
                                .font(.subheadline)
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)], spacing: 8) {
                            ForEach(allVictims) { victim in
                                VictimSelectCard(
                                    victim: victim,
                                    isSelected: selectedVictimIDs.contains(victim.id)
                                ) {
                                    if selectedVictimIDs.contains(victim.id) {
                                        selectedVictimIDs.remove(victim.id)
                                    } else {
                                        selectedVictimIDs.insert(victim.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // 發送按鈕
                Button {
                    sendDecision()
                } label: {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text(L("發送指揮決策"))
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(NV.command)
                .disabled(decisionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .alert(L("決策已發送"), isPresented: $showSentAlert) {
            Button(L("確定")) { }
        } message: {
            Text(L("指揮決策已廣播至所有前線裝置"))
        }
        .onChange(of: vm.backendBridge.latestAIDecision?.id) { _, _ in
            if let ai = vm.backendBridge.latestAIDecision {
                decisionText = ai.decision
            }
        }
    }

    private func sendDecision() {
        let patients = allVictims
            .filter { selectedVictimIDs.contains($0.id) }
            .map { v in
                let location = vm.patientReports.first(where: { $0.patientId == v.id })?.location ?? ""
                return PatientDecisionEntry(
                    id: v.id,
                    location: location,
                    priority: v.priority.label,
                    reason: vm.victimTriageReasons[v.id] ?? vm.victimNotes[v.id] ?? ""
                )
            }

        vm.sendDecision(decision: decisionText, patients: patients)
        decisionText = ""
        selectedVictimIDs.removeAll()
        showSentAlert = true
    }

    private let quickDecisions = [
        "立即撤離所有人員至安全區域",
        "暫停搜救作業，等待結構評估",
        "優先救援 SOS 受困者",
        "轉移至備用指揮所",
        "啟動大量傷患機制（MCI）",
        "請求增派醫療支援",
        "變更搜救區域為 B 區",
        "全員休息 15 分鐘後繼續",
    ]
}

// MARK: - 受困者選擇卡片

private struct VictimSelectCard: View {
    let victim: HQVictimRecord
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? NV.green : .secondary)

                Image(systemName: victim.isSOS ? "sos" : "person.fill")
                    .foregroundColor(victim.isSOS ? NV.danger : (victim.isOnline ? NV.green : .gray))

                VStack(alignment: .leading, spacing: 2) {
                    Text(victim.id)
                        .font(.subheadline).bold()
                    HStack(spacing: 6) {
                        Text("\(victim.heartRate) bpm")
                        Text("·")
                        Text("\(victim.battery)%")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }

                Spacer()

                if victim.isSOS {
                    Text("SOS")
                        .font(.caption2).bold()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NV.danger)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
            }
            .padding(10)
            .background(isSelected ? NV.command.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? NV.command : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
