import SwiftUI

/// HQ 電台收聽頁面 — 即時收聽前線 PTT 廣播 + 顯示 Whisper 轉錄紀錄
struct HQRadioView: View {
    @ObservedObject var vm: HQViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            HStack(spacing: 0) {
                // 左側：即時狀態 + 控制
                livePanel
                    .frame(width: 360)
                Divider()
                // 右側：轉錄紀錄
                transcriptionList
            }
        }
    }

    // MARK: - 頂部標題列

    private var headerBar: some View {
        HQSectionHeader(L("電台監聽"), icon: "antenna.radiowaves.left.and.right", accent: NV.green) {
            // TCP 即時串流狀態
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(vm.audioStreamServer.isRunning ? NV.green : NV.danger)
                        .frame(width: NV.dotSize, height: NV.dotSize)
                    Text(vm.audioStreamServer.isPlaying ? L("即時收聽中") :
                         vm.audioStreamServer.isRunning ? "串流伺服器待命" : "串流伺服器離線")
                        .font(.caption)
                        .foregroundColor(vm.audioStreamServer.isPlaying ? NV.green : .secondary)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(vm.udpAudioServer.isRunning ? NV.green : NV.danger)
                        .frame(width: NV.dotSize, height: NV.dotSize)
                    Text(vm.udpAudioServer.isRunning ? L("UDP 伺服器運行中") : L("UDP 伺服器離線"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.caption)
                    Text("\(vm.udpAudioServer.connectedClientCount)")
                        .font(.caption.monospacedDigit())
                }
                .foregroundColor(NV.info)
            }
        }
    }

    // MARK: - 左側即時面板

    private var livePanel: some View {
        VStack(spacing: 20) {
            // 廣播狀態指示
            broadcasterCard

            // 即時字幕（雙重辨識）
            liveTranscriptionCard

            // 播放控制
            playbackControls

            Spacer()
        }
        .padding(16)
    }

    private var broadcasterCard: some View {
        VStack(spacing: 12) {
            // HQ PTT 按鈕（按下廣播 / 放開結束）；同時顯示前線廣播狀態波紋
            ZStack {
                let isBroadcasting = vm.isHQPushToTalkActive || vm.currentBroadcaster != nil || vm.audioStreamServer.isPlaying
                if isBroadcasting {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(NV.green.opacity(0.3 - Double(i) * 0.1), lineWidth: 2)
                            .frame(width: CGFloat(60 + i * 20), height: CGFloat(60 + i * 20))
                    }
                }
                Circle()
                    .fill(vm.isHQPushToTalkActive ? Color.red : (isBroadcasting ? NV.green : NV.greenDim))
                    .frame(width: 56, height: 56)
                Image(systemName: isBroadcasting ? "mic.fill" : "mic.slash")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
            .frame(height: 100)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !vm.isHQPushToTalkActive { vm.startHQPushToTalk() }
                    }
                    .onEnded { _ in
                        if vm.isHQPushToTalkActive { vm.stopHQPushToTalk() }
                    }
            )
            .help(L("按住廣播（也可按住空白鍵）"))

            if vm.isHQPushToTalkActive {
                Text(L("HQ 廣播中…"))
                    .font(.headline)
                    .foregroundColor(.red)
                Text(L("放開結束並送出"))
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.8))
            } else if vm.audioStreamServer.isPlaying {
                Text(vm.audioStreamServer.currentSender ?? L("前線裝置"))
                    .font(.headline)
                    .foregroundColor(NV.green)
                Text(L("即時串流播放中…"))
                    .font(.caption)
                    .foregroundColor(NV.green.opacity(0.7))
            } else if let broadcaster = vm.currentBroadcaster {
                Text(broadcaster)
                    .font(.headline)
                    .foregroundColor(NV.green)
                Text(L("正在廣播中…"))
                    .font(.caption)
                    .foregroundColor(NV.green.opacity(0.7))
            } else {
                Text(L("待命中"))
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(L("等待前線 PTT 廣播"))
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: NV.cardRadius)
                .fill(NV.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: NV.cardRadius)
                        .stroke(vm.currentBroadcaster != nil ? NV.green.opacity(0.5) : NV.greenDim.opacity(0.3),
                                lineWidth: NV.strokeWidth)
                )
        )
    }

    // MARK: - 即時字幕卡片（雙重辨識）

    private var liveTranscriptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "captions.bubble")
                    .foregroundColor(NV.info)
                Text(L("即時字幕"))
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Spacer()
            }

            let transcriptions = vm.udpAudioServer.liveTranscriptions
            let states = vm.udpAudioServer.transcriptionStates

            if transcriptions.isEmpty {
                Text(L("等待語音輸入…"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(transcriptions.keys.sorted()), id: \.self) { deviceID in
                    let text = transcriptions[deviceID] ?? ""
                    let state = states[deviceID] ?? .idle

                    HStack(alignment: .top, spacing: 6) {
                        // 狀態指示圖示
                        Group {
                            switch state {
                            case .listening:
                                Image(systemName: "mic.fill")
                                    .foregroundColor(NV.green.opacity(0.7))
                            case .processing:
                                ProgressView()
                                    .controlSize(.small)
                            case .done:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(NV.green)
                            case .idle:
                                Image(systemName: "circle")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .font(.caption)
                        .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(deviceID)
                                .font(.caption2.bold())
                                .foregroundColor(NV.green.opacity(0.8))
                            Text(text.isEmpty ? "…" : text)
                                .font(.caption)
                                .foregroundColor(state == .done ? .primary : .secondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: NV.cardRadius)
                .fill(NV.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: NV.cardRadius)
                        .stroke(NV.greenDim.opacity(0.3), lineWidth: NV.strokeWidth)
                )
        )
    }

    private var playbackControls: some View {
        VStack(spacing: 12) {
            // 本地播放開關
            Toggle(isOn: $vm.udpAudioServer.isLocalPlaybackEnabled) {
                HStack(spacing: 8) {
                    Image(systemName: vm.udpAudioServer.isLocalPlaybackEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .foregroundColor(vm.udpAudioServer.isLocalPlaybackEnabled ? NV.green : .secondary)
                    Text(L("本地音訊播放"))
                        .foregroundColor(.primary)
                }
            }
            .toggleStyle(.switch)
            .tint(NV.green)

            // 音量控制
            if vm.udpAudioServer.isLocalPlaybackEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $vm.udpAudioServer.playbackVolume, in: 0...1)
                        .tint(NV.green)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(vm.udpAudioServer.playbackVolume * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: NV.cardRadius)
                .fill(NV.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: NV.cardRadius)
                        .stroke(NV.greenDim.opacity(0.3), lineWidth: NV.strokeWidth)
                )
        )
    }

    // MARK: - 右側轉錄列表

    private var transcriptionList: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "text.quote")
                    .foregroundColor(NV.info)
                Text(L("語音轉錄紀錄"))
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text(L("%lld 筆", vm.radioReports.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(NV.surface)

            Divider()

            if vm.radioReports.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "waveform.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(L("尚無轉錄紀錄"))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.radioReports) { report in
                            reportRow(report)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func reportRow(_ report: HQRadioReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: report.sourceType == .briefing ? "doc.text.fill" : "antenna.radiowaves.left.and.right")
                    .foregroundColor(report.sourceType == .briefing ? NV.info : NV.green)
                Text(report.senderName)
                    .font(.subheadline.bold())
                    .foregroundColor(NV.green)

                Text(report.sourceType == .briefing ? L("固定會報") : L("即時廣播"))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(report.sourceType == .briefing ? NV.info.opacity(0.2) : NV.green.opacity(0.2))
                    )
                    .foregroundColor(report.sourceType == .briefing ? NV.info : NV.green)

                Spacer()
                Text(report.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(report.transcription)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !report.locationDesc.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                    Text(report.locationDesc)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(NV.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(NV.greenDim.opacity(0.2), lineWidth: NV.strokeWidth)
                )
        )
    }
}
