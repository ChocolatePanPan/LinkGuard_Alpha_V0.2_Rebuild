import SwiftUI

struct FieldCallView: View {
    @ObservedObject var vm: LinkGuardViewModel

    var body: some View {
        FieldCallContent(vm: vm, audio: vm.callAudioManager)
    }
}

private struct FieldCallContent: View {
    @ObservedObject var vm: LinkGuardViewModel
    @ObservedObject var audio: CallAudioManager

    private var onlineMembers: [TeamMember] {
        vm.teamMembers
            .filter { $0.isOnline && $0.id != vm.nodeStatus.nodeID }
            .sorted { $0.id < $1.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    connectionBanner

                    if let session = vm.activeCallSession {
                        activeCallPanel(session)
                    } else {
                        callTargetList
                    }

                    recentCalls
                }
                .padding(16)
            }
            .background(NV.bg.ignoresSafeArea())
            .navigationTitle(L("通話"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.fill")
                .font(.title2)
                .foregroundColor(NV.command)
                .frame(width: 44, height: 44)
                .background(NV.command.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(L("通話"))
                    .font(.title2.bold())
                Text(L("與隊員語音通話"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var connectionBanner: some View {
        if !vm.commandClient.isConnected {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                Text(L("未連線 Mac HQ，無法撥打通話"))
                    .font(.caption)
            }
            .foregroundColor(.white)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NV.danger)
            .cornerRadius(10)
        }
    }

    private var callTargetList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("可撥打隊員"))
                .font(.headline)

            if onlineMembers.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.3.sequence")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(L("尚無其他線上搜救節點"))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(NV.surface)
                .cornerRadius(12)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(onlineMembers) { member in
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .foregroundColor(NV.team)
                                .font(.title2)
                                .frame(width: 38, height: 38)
                                .background(NV.team.opacity(0.12))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(member.id)
                                    .font(.headline)
                                Text("\(member.deptCode) · \(L("電量")) \(member.battery)%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button {
                                vm.startCall(to: member)
                            } label: {
                                Image(systemName: "phone.fill")
                                    .font(.title3)
                                    .frame(width: 38, height: 38)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(NV.command)
                            .disabled(!vm.commandClient.isConnected)
                        }
                        .padding(12)
                        .background(NV.surface)
                        .cornerRadius(12)
                    }
                }
            }
        }
    }

    private func activeCallPanel(_ session: CallSession) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Image(systemName: session.status == .active ? "phone.connection.fill" : "phone.arrow.up.right.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(session.status == .active ? NV.green : NV.command)
                Text(session.status.label)
                    .font(.title3.bold())
                Text(participantText(session.participants))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            if session.status == .active {
                VStack(spacing: 12) {
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

                    if audio.isReceiving {
                        Label(L("正在接收語音"), systemImage: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundColor(NV.green)
                    }
                    if let error = audio.connectionError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(NV.danger)
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                Text(L("等待對方接聽"))
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        .background(NV.surface)
        .cornerRadius(16)
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
                    .background(NV.surface.opacity(0.72))
                    .cornerRadius(10)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(vm.callInvites.prefix(8)) { invite in
                        HStack(spacing: 10) {
                            Image(systemName: invite.status == .active ? "phone.connection.fill" : "phone.fill")
                                .foregroundColor(invite.status == .missed ? NV.danger : NV.command)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invite.initiatorName)
                                    .font(.subheadline.bold())
                                Text("\(invite.status.label) · \(timeText(invite.createdAt))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(NV.surface.opacity(0.7))
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    private func participantText(_ participants: [String]) -> String {
        participants.joined(separator: " · ")
    }

    private func timeText(_ timestamp: Double) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}

struct IncomingCallOverlay: View {
    let invite: CallInvite
    let onAccept: () -> Void
    let onDecline: () -> Void
    @State private var pulse = false

    var body: some View {
        ZStack {
            NV.bg.opacity(0.96)
                .ignoresSafeArea()

            VStack(spacing: 26) {
                ZStack {
                    Circle()
                        .stroke(NV.command.opacity(pulse ? 0.08 : 0.34), lineWidth: 4)
                        .frame(width: pulse ? 210 : 150, height: pulse ? 210 : 150)
                    Circle()
                        .fill(NV.command.opacity(0.18))
                        .frame(width: 116, height: 116)
                    Image(systemName: "phone.fill")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundColor(NV.command)
                }
                .frame(height: 220)

                VStack(spacing: 8) {
                    Text(L("來電"))
                        .font(.largeTitle.bold())
                    Text(invite.initiatorName)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(NV.command)
                    Text(L("邀請你進入語音通話"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 24) {
                    Button(role: .destructive) {
                        onDecline()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "phone.down.fill")
                                .font(.title2)
                            Text(L("拒絕"))
                                .font(.caption.bold())
                        }
                        .foregroundColor(.white)
                        .frame(width: 88, height: 72)
                        .background(NV.danger)
                        .cornerRadius(18)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onAccept()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "phone.fill")
                                .font(.title2)
                            Text(L("接聽"))
                                .font(.caption.bold())
                        }
                        .foregroundColor(.white)
                        .frame(width: 88, height: 72)
                        .background(NV.green)
                        .cornerRadius(18)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(28)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
