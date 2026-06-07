import SwiftUI
import LinkGuardV03Core

/// v0.3 role-aware command console shell for LinkGuard-UCC / LinkGuard-SCC.
///
/// Replaces the generic copied v0.2 HQ dashboard with a phase-organized,
/// permission-gated console driven by `CommandConsoleCatalog`. Each module is a
/// genuine v0.3 surface backed by the live `OperationSnapshot`.
public struct MacCommandConsoleView: View {
    @State private var macState: MacSystemUIState
    @State private var selectedModuleID: String?
    #if os(macOS)
    @StateObject private var syncReceiver = MacSyncReceiver()
    #endif

    public init(state: MacSystemUIState) {
        _macState = State(initialValue: state)
    }

    private var state: MacSystemUIState { macState }
    private var appID: LinkGuardAppID { state.runtime.device.appID }
    private var modules: [CommandConsoleModule] { CommandConsoleCatalog.modules(for: appID) }
    private var snapshot: OperationSnapshot { state.runtime.snapshot }

    private var selectedModule: CommandConsoleModule? {
        if let id = selectedModuleID, let module = modules.first(where: { $0.id == id }) {
            return module
        }
        return modules.first
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 256, ideal: 280, max: 320)
        } detail: {
            if let module = selectedModule {
                ConsoleModuleScaffold(module: module, state: state)
                    .id(module.id)
            } else {
                ConsoleEmptyState(systemImage: "square.dashed", title: "無可用模組",
                                  message: "此主控台沒有依權限啟用的模組。")
                    .padding(40)
            }
        }
        .background(CCTheme.background)
        .preferredColorScheme(.dark)
        .tint(CCTheme.accent)
        .onAppear {
            if selectedModuleID == nil { selectedModuleID = modules.first?.id }
            #if os(macOS)
            startSyncReceiverIfNeeded()
            #endif
        }
        #if os(macOS)
        .onDisappear { syncReceiver.stop() }
        #endif
    }

    #if os(macOS)
    private func startSyncReceiverIfNeeded() {
        // A command console ingests the live incident state from field/iPad devices.
        guard syncReceiver.isRunning == false else { return }
        syncReceiver.start { batch, receivedAt in
            macState.receive(batch, receivedAt: receivedAt)
        }
    }
    #endif

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            Divider().overlay(CCTheme.stroke)
            List(selection: $selectedModuleID) {
                ForEach(modules) { module in
                    moduleRow(module)
                        .tag(module.id)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            sidebarFooter
        }
        .background(CCTheme.sidebar)
    }

    private var sidebarHeader: some View {
        let info = CommandConsoleCatalog.positioning(for: appID)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: appID == .ucc ? "globe.asia.australia.fill" : "mappin.and.ellipse")
                    .foregroundColor(CCTheme.accent)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(info?.title ?? appID.rawValue)
                        .font(.headline).foregroundColor(.white)
                    Text(info?.role ?? "")
                        .font(.caption2.weight(.semibold)).foregroundColor(CCTheme.accent)
                }
                Spacer(minLength: 0)
            }
            if let summary = info?.summary {
                Text(summary)
                    .font(.caption2).foregroundColor(CCTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                ConsoleTag("\(modules.count) 模組", color: CCTheme.accent)
                ConsoleTag(state.runtime.profile.commandAuthority.macDisplayName, color: CCTheme.command)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func moduleRow(_ module: CommandConsoleModule) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(CCTheme.sectionTint(module.section).opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: module.systemImageName)
                    .font(.caption)
                    .foregroundColor(CCTheme.sectionTint(module.section))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(module.title).font(.callout.weight(.semibold)).foregroundColor(.white.opacity(0.95)).lineLimit(1)
                Text("\(module.phaseLabel) · \(module.capability)")
                    .font(.caption2).foregroundColor(CCTheme.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            AccessBadge(level: module.accessLevel, compact: true)
        }
        .padding(.vertical, 2)
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().overlay(CCTheme.stroke)
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled").font(.caption2).foregroundColor(CCTheme.muted)
                if let session = state.loginSession {
                    Text(session.displayName).font(.caption2.weight(.semibold)).foregroundColor(.white.opacity(0.8))
                    Text("· \(session.position.rawValue)").font(.caption2).foregroundColor(CCTheme.muted).lineLimit(1)
                } else {
                    Text(state.runtime.device.displayName).font(.caption2).foregroundColor(CCTheme.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Text(state.settingsInfo.versionInfo.displayVersion)
                .font(.caption2.monospaced()).foregroundColor(CCTheme.muted.opacity(0.7))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// Wraps a module's routed body with a consistent v0.3 header (phase label, title,
/// capability/purpose, ICS section and access level).
struct ConsoleModuleScaffold: View {
    let module: CommandConsoleModule
    let state: MacSystemUIState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(CCTheme.stroke)
            ScrollView {
                ConsoleModuleRouter(module: module, state: state)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CCTheme.background)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(CCTheme.sectionTint(module.section).opacity(0.18))
                    .frame(width: 46, height: 46)
                Image(systemName: module.systemImageName)
                    .font(.title3)
                    .foregroundColor(CCTheme.sectionTint(module.section))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(module.title).font(.title2.weight(.bold)).foregroundColor(.white)
                    ConsoleTag(module.phaseLabel, color: CCTheme.muted)
                }
                Text("\(module.capability) · \(module.purpose)")
                    .font(.callout).foregroundColor(CCTheme.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                AccessBadge(level: module.accessLevel)
                ConsoleTag(CCTheme.sectionName(module.section), color: CCTheme.sectionTint(module.section))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CCTheme.surface)
    }
}
