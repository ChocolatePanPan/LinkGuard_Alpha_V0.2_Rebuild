//
//  HQBackendServicesView.swift
//  LinkGuardHQ
//
//  Sidebar entry that shows the embedded Python backend's per-service
//  status and lets the user start / stop / restart / inspect each.
//
//  macOS only (iOS HQ peer mode does not host the backend).
//

import SwiftUI

#if os(macOS)

struct HQBackendServicesView: View {
    @ObservedObject var vm: HQViewModel
    @ObservedObject var supervisor: BackendSupervisor
    @AppStorage("hq.backendMode") private var modeRaw: String = BackendMode.embedded.rawValue
    @AppStorage("hq.remoteHost") private var remoteHost: String = ""
    @State private var expandedLog: String? = nil

    private var mode: BackendMode {
        BackendMode(rawValue: modeRaw) ?? .embedded
    }

    var body: some View {
        HQPage {
            HQPageTitleBar(L("後端服務"), subtitle: mode.helpText, icon: mode.systemImage, accent: NV.green) {
                headerControls
            }

            if mode == .embedded {
                LazyVStack(spacing: NV.panelSpacing) {
                    ForEach(supervisor.services) { state in
                        serviceRow(state)
                    }
                }
            } else {
                modeNotice
            }
        }
    }

    // MARK: - Header

    private var headerControls: some View {
        HStack(spacing: 12) {
            if mode == .embedded {
                aggregateBadge
                Button {
                    supervisor.startAll()
                } label: {
                    Label(L("全部啟動"), systemImage: "play.fill")
                }
                .controlSize(.small)
                Button {
                    supervisor.stopAll()
                } label: {
                    Label(L("全部停止"), systemImage: "stop.fill")
                }
                .controlSize(.small)
                Button {
                    supervisor.restartCrashed()
                } label: {
                    Label(L("重啟異常"), systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(!supervisor.anyCrashed)
            }
        }
    }

    private var aggregateBadge: some View {
        Group {
            if supervisor.allHealthy {
                Label(L("全部正常"), systemImage: "checkmark.circle.fill")
                    .foregroundColor(NV.green)
            } else if supervisor.anyCrashed {
                Label(L("有服務異常"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(NV.danger)
            } else {
                Label(L("待啟動 / 檢查中"), systemImage: "circle.dashed")
                    .foregroundColor(.secondary)
            }
        }
        .font(.caption.bold())
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color.black.opacity(0.2))
        .cornerRadius(6)
    }

    private var modeNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HQEmptyStateView(
                icon: mode.systemImage,
                title: L("目前模式: %@", mode.displayName),
                subtitle: L("此頁面僅在「內建後端」模式下顯示服務狀態。請至設定切換模式。"),
                minHeight: 320
            )
        }
        .hqPanelChrome(accent: NV.green)
    }

    // MARK: - Service row

    @ViewBuilder
    private func serviceRow(_ state: BackendServiceState) -> some View {
        let metrics = supervisor.metrics(for: state.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                statusDot(for: state.status)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.spec.displayName).font(.headline)
                    Text("\(state.spec.scriptName) · :\(state.spec.port)")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let pid = state.pid {
                    Text("PID \(pid)").font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                if !metrics.cpu.isEmpty {
                    Text("CPU \(metrics.cpu)%").font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                if !metrics.memMB.isEmpty {
                    Text("\(metrics.memMB) MB").font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                if state.restartCount > 0 {
                    Text(L("重啟 ×%lld", state.restartCount))
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                Button {
                    if state.status == .stopped || state.status == .crashed {
                        supervisor.start(state.id)
                    } else {
                        supervisor.stop(state.id)
                    }
                } label: {
                    Image(systemName: (state.status == .stopped || state.status == .crashed)
                                       ? "play.fill" : "stop.fill")
                }
                .buttonStyle(.borderless)
                Button {
                    supervisor.restart(state.id)
                } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                Button {
                    expandedLog = (expandedLog == state.id) ? nil : state.id
                } label: { Image(systemName: "doc.plaintext") }
                .buttonStyle(.borderless)
                .help(L("檢視即時日誌"))
            }
            if let err = state.lastError, state.status == .crashed {
                Text(err)
                    .font(.caption)
                    .foregroundColor(NV.danger)
                    .padding(.top, 4)
            }
            if expandedLog == state.id {
                logView(for: state)
            }
        }
        .padding(12)
        .background(NV.surface.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(NV.green.opacity(0.22), lineWidth: 1)
        )
    }

    private func statusDot(for status: BackendServiceStatus) -> some View {
        let color: Color = {
            switch status {
            case .healthy:   return NV.green
            case .starting, .unhealthy: return .yellow
            case .crashed:   return NV.danger
            case .stopped:   return .gray
            }
        }()
        return Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .help(status.rawValue)
    }

    private func logView(for state: BackendServiceState) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(state.logTail.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(idx)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 240)
            .background(Color.black.opacity(0.6))
            .cornerRadius(6)
            .padding(.top, 8)
            .onChange(of: state.logTail.count) { newCount in
                proxy.scrollTo(newCount - 1, anchor: .bottom)
            }
        }
    }
}

#else  // iOS stub

struct HQBackendServicesView: View {
    @ObservedObject var vm: HQViewModel
    @ObservedObject var supervisor: BackendSupervisor
    var body: some View {
        Text(L("此頁面僅於 macOS 主機可用。"))
            .foregroundColor(.secondary)
            .padding()
    }
}

#endif
