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

    private var callStatusText: String {
        if let session = vm.activeCallSession {
            return session.status.label
        }
        return vm.commandClient.isConnected ? L("待命中") : L("未連線")
    }

    private var callStatusColor: Color {
        guard vm.commandClient.isConnected else { return NV.danger }
        if let session = vm.activeCallSession {
            return statusColor(session.status)
        }
        return NV.green
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    callOverviewCard

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
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .contentMargins(.top, 0, for: .scrollContent)
        }
    }

    private var callOverviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(callStatusColor.opacity(0.16))
                    Image(systemName: vm.activeCallSession == nil ? "phone.badge.waveform" : "phone.connection.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(callStatusColor)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(L("救援 PTT 通話"))
                        .font(.title3.bold())
                    Text(vm.commandClient.isConnected ? L("Mac HQ 語音中繼可用") : L("未連線 Mac HQ，無法撥打通話"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                Text(callStatusText)
                    .font(.caption.bold())
                    .foregroundColor(callStatusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular.tint(callStatusColor.opacity(0.18)), in: .capsule)
            }

            HStack(spacing: 8) {
                CallInfoChip(icon: "person.2.fill", title: L("線上隊員"), value: "\(onlineMembers.count)", color: NV.team)
                CallInfoChip(icon: "waveform", title: L("語音"), value: audio.isSessionActive ? L("已啟動") : L("待命"), color: audio.isSessionActive ? NV.green : NV.command)
                CallInfoChip(icon: vm.commandClient.isConnected ? "wifi" : "wifi.slash", title: L("中繼"), value: vm.commandClient.isConnected ? L("正常") : L("中斷"), color: vm.commandClient.isConnected ? NV.green : NV.danger)
            }
        }
        .padding(14)
        .background(NV.surface)
        .cornerRadius(16)
    }

    private var callTargetList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L("可撥打隊員"), systemImage: "person.crop.circle.badge.checkmark")
                    .font(.headline)
                Spacer()
                Text(L("%lld 人在線", onlineMembers.count))
                    .font(.caption.bold())
                    .foregroundColor(NV.team)
            }

            if onlineMembers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: vm.commandClient.isConnected ? "person.3.sequence" : "wifi.slash")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundColor(vm.commandClient.isConnected ? .secondary : NV.danger)
                    VStack(spacing: 4) {
                        Text(vm.commandClient.isConnected ? L("尚無其他線上搜救節點") : L("等待 HQ 連線"))
                            .font(.headline)
                        Text(vm.commandClient.isConnected ? L("隊員上線後會出現在這裡") : L("連線後即可撥打 PTT 通話"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(30)
                .background(NV.surface)
                .cornerRadius(16)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(onlineMembers) { member in
                        CallTargetRow(member: member, canCall: vm.commandClient.isConnected) {
                            vm.startCall(to: member)
                        }
                    }
                }
            }
        }
    }

    private func activeCallPanel(_ session: CallSession) -> some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(statusColor(session.status).opacity(0.16))
                    Image(systemName: statusIcon(session.status))
                        .font(.title.weight(.semibold))
                        .foregroundColor(statusColor(session.status))
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 6) {
                    Text(session.status.label)
                        .font(.title2.bold())
                    Text(participantText(session.participants))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Label(session.mode.uppercased(), systemImage: "waveform")
                        Text("·")
                        Text(timeText(session.startedAt))
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                if audio.isReceiving {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3)
                        .foregroundColor(NV.green)
                        .frame(width: 36, height: 36)
                        .glassEffect(.regular.tint(NV.green.opacity(0.2)), in: .circle)
                }
            }

            if session.status == .active {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(audio.isTransmitting ? NV.danger.opacity(0.35) : NV.command.opacity(0.2), lineWidth: 12)
                            .frame(width: 154, height: 154)
                        Circle()
                            .fill(audio.isTransmitting ? NV.danger : NV.command.opacity(0.18))
                            .frame(width: 126, height: 126)
                            .shadow(color: audio.isTransmitting ? NV.danger.opacity(0.35) : .clear, radius: 18)
                        VStack(spacing: 8) {
                            Image(systemName: audio.isTransmitting ? "mic.fill" : "mic")
                                .font(.system(size: 42, weight: .semibold))
                            Text(audio.isTransmitting ? L("放開結束") : L("按住說話"))
                                .font(.caption.bold())
                        }
                        .foregroundColor(audio.isTransmitting ? .white : .primary)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !audio.isTransmitting { audio.startTransmitting() }
                            }
                            .onEnded { _ in audio.stopTransmitting() }
                    )

                    audioStatusLine
                }
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.large)
                    Text(session.status == .ringing ? L("等待對方接聽") : session.status.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L("最近通話"), systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                if !vm.callInvites.isEmpty {
                    Text("\(min(vm.callInvites.count, 8))")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
            }

            if vm.callInvites.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "phone.badge.clock")
                        .foregroundColor(.secondary)
                    Text(L("尚無通話紀錄"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(14)
                .background(NV.surface.opacity(0.72))
                .cornerRadius(12)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(vm.callInvites.prefix(8)) { invite in
                        RecentCallRow(invite: invite, timeText: timeText(invite.createdAt))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var audioStatusLine: some View {
        if let error = audio.connectionError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(NV.danger)
        } else if audio.isReceiving {
            Label(L("正在接收語音"), systemImage: "speaker.wave.2.fill")
                .font(.caption)
                .foregroundColor(NV.green)
        } else if audio.isSessionActive {
            Label(L("語音通道已就緒"), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(NV.green)
        } else {
            Label(L("語音通道準備中"), systemImage: "waveform")
                .font(.caption)
                .foregroundColor(.secondary)
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

    private func statusIcon(_ status: CallStatus) -> String {
        switch status {
        case .ringing: return "phone.arrow.up.right.fill"
        case .active: return "phone.connection.fill"
        case .declined: return "phone.down.circle.fill"
        case .ended: return "phone.down.fill"
        case .missed: return "phone.badge.exclamationmark"
        }
    }

    private func statusColor(_ status: CallStatus) -> Color {
        switch status {
        case .ringing: return NV.command
        case .active: return NV.green
        case .declined, .missed: return NV.danger
        case .ended: return .secondary
        }
    }
}

private struct CallInfoChip: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(color.opacity(0.08))
        .cornerRadius(12)
    }
}

private struct CallTargetRow: View {
    let member: TeamMember
    let canCall: Bool
    let onCall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(member.signalColor.opacity(0.14))
                    .frame(width: 46, height: 46)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(member.signalColor)
                Circle()
                    .fill(member.isOnline ? NV.green : .gray)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(NV.surface, lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(member.nickname?.isEmpty == false ? member.nickname! : member.id)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(member.deptCode)
                        .font(.caption2.bold())
                        .foregroundColor(NV.team)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NV.team.opacity(0.12))
                        .cornerRadius(6)
                    Label("\(member.battery)%", systemImage: "battery.50")
                    Label(member.lastSeenText, systemImage: "clock")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: onCall) {
                Image(systemName: "phone.fill")
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(NV.command)
            .disabled(!canCall)
        }
        .padding(12)
        .background(NV.surface)
        .cornerRadius(14)
    }
}

private struct RecentCallRow: View {
    let invite: CallInvite
    let timeText: String

    private var color: Color {
        switch invite.status {
        case .active: return NV.green
        case .ringing: return NV.command
        case .missed, .declined: return NV.danger
        case .ended: return .secondary
        }
    }

    private var icon: String {
        switch invite.status {
        case .active: return "phone.connection.fill"
        case .ringing: return "phone.arrow.up.right.fill"
        case .missed: return "phone.badge.exclamationmark"
        case .declined: return "phone.down.circle.fill"
        case .ended: return "phone.down.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundColor(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(invite.initiatorName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text("\(invite.status.label) · \(timeText)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !invite.targetDeviceIDs.isEmpty {
                Text(invite.targetDeviceIDs.prefix(2).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(NV.surface.opacity(0.7))
        .cornerRadius(12)
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
                    Text(L("邀請你進入 PTT 通話"))
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
