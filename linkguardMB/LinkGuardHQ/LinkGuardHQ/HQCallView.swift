import SwiftUI

struct HQCallView: View {
    @ObservedObject var vm: HQViewModel

    var body: some View {
        HQCallContent(vm: vm, audio: vm.callAudioManager)
    }
}

private struct HQCallContent: View {
    @ObservedObject var vm: HQViewModel
    @ObservedObject var audio: HQCallAudioManager

    private var onlineUnits: [ConnectedFieldUnit] {
        vm.server.fieldUnits
            .filter(\.isOnline)
            .sorted { $0.deviceID < $1.deviceID }
    }

    var body: some View {
        HQPage {
            HQPageTitleBar(L("通話"), icon: "phone.fill", accent: NV.command) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(vm.server.isRunning ? NV.green : NV.danger)
                        .frame(width: NV.dotSize, height: NV.dotSize)
                    Text(vm.server.isRunning ? L("可撥打") : L("伺服器離線"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if vm.hqRole != .server {
                HQEmptyStateView(icon: "phone.slash", title: L("副指揮模式暫不支援通話"))
                    .hqPanelChrome(accent: NV.command)
            } else if let session = vm.activeCallSession {
                activeCallPanel(session)
            } else {
                targetGrid
            }

            recentCalls
        }
    }

    private var targetGrid: some View {
        VStack(alignment: .leading, spacing: NV.panelSpacing) {
            Text(L("線上前線裝置"))
                .font(.headline)

            if onlineUnits.isEmpty {
                HQEmptyStateView(icon: "iphone.slash", title: L("尚無線上前線裝置"))
                    .hqPanelChrome(accent: NV.command)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: NV.panelSpacing)], spacing: NV.panelSpacing) {
                    ForEach(onlineUnits) { unit in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "iphone.radiowaves.left.and.right")
                                    .font(.title3)
                                    .foregroundColor(NV.command)
                                    .frame(width: 36, height: 36)
                                    .background(NV.command.opacity(0.12))
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(unit.displayName)
                                        .font(.headline)
                                    Text(unit.nickname?.isEmpty == false
                                         ? "\(unit.deviceID) · \(unit.deptCode)"
                                         : unit.deptCode)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }

                            HStack(spacing: 10) {
                                Label("\(unit.battery)%", systemImage: "battery.75percent")
                                Label(L("%@ 前", unit.lastUpdate.formatted(date: .omitted, time: .shortened)), systemImage: "clock")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)

                            Button {
                                vm.startCall(to: unit)
                            } label: {
                                Label(L("撥打"), systemImage: "phone.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(NV.command)
                            .disabled(!vm.server.isRunning)
                        }
                        .padding(14)
                        .hqThemedSurfaceBackground()
                        .cornerRadius(12)
                    }
                }
            }
        }
    }

    private func activeCallPanel(_ session: CallSession) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: session.status == .active ? "phone.connection.fill" : "phone.arrow.up.right.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(session.status == .active ? NV.green : NV.command)
                    .frame(width: 64, height: 64)
                    .background((session.status == .active ? NV.green : NV.command).opacity(0.14))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(session.status.label)
                        .font(.title3.bold())
                    Text(session.participants.joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if session.status == .active {
                VStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(NV.green)
                            .frame(width: 10, height: 10)
                        Text(L("通話中"))
                            .font(.caption.bold())
                            .foregroundColor(NV.green)
                    }

                    Button {
                        audio.toggleMute()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(audio.isMuted ? NV.danger : NV.command.opacity(0.18))
                                .frame(width: 80, height: 80)
                            Image(systemName: audio.isMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundColor(audio.isMuted ? .white : .primary)
                        }
                    }
                    .buttonStyle(.plain)

                    Text(audio.isMuted ? L("已靜音") : L("麥克風開啟"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let error = audio.connectionError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(NV.danger)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L("等待對方接聽"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button(role: .destructive) {
                vm.endCall()
            } label: {
                Label(L("掛斷"), systemImage: "phone.down.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(NV.danger)
        }
        .padding(18)
        .hqThemedSurfaceBackground()
        .cornerRadius(14)
    }

    private var recentCalls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("最近通話"))
                .font(.headline)

            if vm.callInvites.isEmpty {
                Text(L("尚無通話紀錄"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .hqThemedSurfaceBackground(opacity: 0.7)
                    .cornerRadius(10)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(vm.callInvites.prefix(10)) { invite in
                        HStack(spacing: 10) {
                            Image(systemName: invite.status == .missed ? "phone.down.fill" : "phone.fill")
                                .foregroundColor(invite.status == .missed ? NV.danger : NV.command)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invite.initiatorName)
                                    .font(.subheadline.bold())
                                Text("\(invite.status.label) · \(invite.targetDeviceIDs.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .hqThemedSurfaceBackground(opacity: 0.7)
                        .cornerRadius(10)
                    }
                }
            }
        }
    }
}
