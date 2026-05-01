import SwiftUI

#if os(macOS)
import AppKit

struct SetupAssistantView: View {
    @ObservedObject var supervisor: BackendSupervisor
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .font(.title)
                    .foregroundColor(NV.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("內建後端設定"))
                        .font(.title2.bold())
                    Text(L("所有 AI / Backend 服務都會在此 Mac 執行。"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            infoRow(title: L("Backend 資料夾"), value: supervisor.backendDir.path)
            infoRow(title: L("Python"), value: supervisor.pythonExecutable?.path ?? L("未偵測到"))

            VStack(alignment: .leading, spacing: 8) {
                Text(L("啟動狀態"))
                    .font(.headline)
                    .foregroundColor(NV.green)
                ForEach(supervisor.services) { service in
                    HStack {
                        Circle()
                            .fill(color(for: service.status))
                            .frame(width: 8, height: 8)
                        Text(service.spec.displayName)
                        Spacer()
                        Text(":\(service.spec.port)")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                        Text(service.status.rawValue)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding()
            .background(Color.black.opacity(0.18))
            .cornerRadius(8)

            Spacer()

            HStack {
                Button {
                    NSWorkspace.shared.open(supervisor.backendDir)
                } label: {
                    Label(L("開啟資料夾"), systemImage: "folder")
                }
                Button {
                    supervisor.startAll()
                } label: {
                    Label(L("啟動本機後端"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    supervisor.stopAll()
                } label: {
                    Label(L("停止"), systemImage: "stop.fill")
                }
                Spacer()
                Button(L("完成")) { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .background(NV.bg)
    }

    private func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(NV.green)
            Text(value)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.black.opacity(0.18))
        .cornerRadius(8)
    }

    private func color(for status: BackendServiceStatus) -> Color {
        switch status {
        case .healthy: return NV.green
        case .starting, .unhealthy: return .yellow
        case .crashed: return NV.danger
        case .stopped: return .gray
        }
    }
}

#endif