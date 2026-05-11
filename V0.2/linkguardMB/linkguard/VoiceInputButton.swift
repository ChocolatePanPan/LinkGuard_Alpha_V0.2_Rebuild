import SwiftUI

/// 語音輸入按鈕 — 長按錄音，放開上傳轉錄
struct VoiceInputButton: View {
    @ObservedObject var voiceManager: VoiceInputManager
    let serverHost: String
    let onTranscribed: (String) -> Void

    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 8) {
            switch voiceManager.state {
            case .idle:
                micButton
            case .recording:
                recordingIndicator
            case .uploading(let progress):
                uploadingIndicator(progress: progress)
            case .done(let text):
                doneIndicator(text: text)
            case .error(let msg):
                errorIndicator(msg: msg)
            }
        }
    }

    // MARK: - 麥克風按鈕

    private var micButton: some View {
        Button {
            // tap to start, tap again to stop
        } label: {
            Image(systemName: "mic.fill")
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(NV.command)
                .clipShape(Circle())
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.2)
                .onEnded { _ in
                    isPressed = true
                    voiceManager.startRecording()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    if isPressed {
                        isPressed = false
                        voiceManager.stopAndTranscribe(serverHost: serverHost)
                    }
                }
        )
        .accessibilityLabel(L("語音輸入"))
        .accessibilityHint(L("長按開始錄音，放開結束並轉錄"))
    }

    // MARK: - 錄音中

    private var recordingIndicator: some View {
        Button {
            voiceManager.stopAndTranscribe(serverHost: serverHost)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(NV.danger)
                    .frame(width: 10, height: 10)
                    .modifier(PulseEffect())
                Text(L("錄音中⋯ 點擊停止"))
                    .font(.caption)
                    .foregroundColor(NV.danger)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(NV.danger.opacity(0.15))
            .clipShape(Capsule())
        }
    }

    // MARK: - 上傳中

    private func uploadingIndicator(progress: Double) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(L("轉錄中⋯"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 完成

    private func doneIndicator(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(NV.green)
            Text(L("已轉錄"))
                .font(.caption)
                .foregroundColor(NV.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onAppear {
            onTranscribed(text)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                voiceManager.reset()
            }
        }
    }

    // MARK: - 錯誤

    private func errorIndicator(msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(NV.danger)
            Text(msg)
                .font(.caption)
                .foregroundColor(NV.danger)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onTapGesture {
            voiceManager.reset()
        }
    }
}

// MARK: - 脈搏動畫

private struct PulseEffect: ViewModifier {
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: scale)
            .onAppear { scale = 1.4 }
    }
}
