import SwiftUI

// MARK: - 替代伺服器 Tab（無 AI）

struct MWBackupServerTab: View {
    @ObservedObject var vm: MilkyWayCommandViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusCard
                    serviceCard
                    actionCard
                    policyCard
                }
                .padding(16)
            }
            .background(MWTheme.bg.ignoresSafeArea())
            .navigationTitle("替代伺服器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.recordHeartbeat()
                    } label: {
                        Label("更新心跳", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("二級指揮節點狀態", systemImage: "shield.lefthalf.filled")
                .font(.headline)
            HStack(spacing: 10) {
                Circle()
                    .fill(vm.failoverState.color)
                    .frame(width: 10, height: 10)
                Text(vm.failoverState.title)
                    .font(.title3.bold())
                    .foregroundStyle(vm.failoverState.color)
                Spacer()
                Text("主伺服器心跳：\(vm.heartbeatText)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(vm.failoverState.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider().overlay(MWTheme.elevated)

            statusRow(title: "上游主伺服器", value: vm.upstreamServer)
            statusRow(title: "本機備援端點", value: vm.standbyEndpoint)
            statusRow(title: "AI 功能", value: "停用（僅指揮與服務接管）")
        }
        .mwPanel()
    }

    private var serviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("可接手服務", systemImage: "server.rack")
                .font(.headline)
            ForEach(vm.managedServices, id: \.self) { service in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(vm.failoverState == .active ? MWTheme.green : MWTheme.cyan)
                    Text(service)
                        .font(.subheadline.monospaced())
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .mwPanel()
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("接管控制", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                .font(.headline)
            Text("當主伺服器異常時，啟用本機替代伺服器以維持通訊與任務派送。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    vm.activateBackupServer()
                } label: {
                    Label("立即接管", systemImage: "bolt.horizontal.circle.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: MWTouch.minH)
                }
                .buttonStyle(.borderedProminent)
                .tint(MWTheme.amber)
                .disabled(vm.failoverState == .active || vm.failoverState == .takingOver)

                Button {
                    vm.returnToStandby()
                } label: {
                    Label("回待命", systemImage: "pause.circle.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: MWTouch.minH)
                }
                .buttonStyle(.borderedProminent)
                .tint(MWTheme.cyan)
                .disabled(vm.failoverState == .standby)
            }
        }
        .mwPanel()
    }

    private var policyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("節點定位", systemImage: "info.circle")
                .font(.headline)
            Text("本節點為 HQ 下位的二級指揮中樞，可執行任務派送、電台通訊、醫療與照片資料轉發。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("設計原則：即時接管、不提供 AI 推論，避免備援模式下的運算負載與不確定性。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .mwPanel()
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}
