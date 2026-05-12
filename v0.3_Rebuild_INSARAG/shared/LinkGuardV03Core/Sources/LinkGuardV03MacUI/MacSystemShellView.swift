import LinkGuardV03Core
import SwiftUI

public struct MacSystemShellView: View {
    private let state: MacSystemUIState
    @State private var selectedSection: ICSSection?

    public init(state: MacSystemUIState) {
        self.state = state
        self._selectedSection = State(initialValue: state.navigationItems.first?.section)
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section {
                    ForEach(state.navigationItems) { item in
                        NavigationLink(value: item.section) {
                            Label(item.title, systemImage: item.systemImageName)
                        }
                    }
                } header: {
                    Text(state.runtime.profile.displayName)
                }
            }
            .navigationTitle(state.title)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MacHeaderView(state: state)
                    MacMetricGrid(metrics: state.metrics)
                    MacQuickActionBar(actions: state.quickActions)
                    MacSectionDetailView(
                        module: selectedModule,
                        routes: state.transportRoutes.filter { route in route.canSend || route.receives }
                    )
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var selectedModule: MacInheritedModule? {
        let selected = selectedSection ?? state.navigationItems.first?.section
        return state.inheritedModules.first { $0.section == selected }
    }
}

private struct MacHeaderView: View {
    let state: MacSystemUIState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title)
                        .font(.title2.weight(.semibold))
                    Text(state.subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 16)
                Text(state.versionInfo.displayVersion)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Text(state.runtime.device.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MacMetricGrid: View {
    let metrics: [MacMetricTile]
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: metric.systemImageName)
                            .imageScale(.medium)
                        Spacer()
                        Text(metric.value)
                            .font(.title3.monospacedDigit().weight(.semibold))
                    }
                    Text(metric.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(minHeight: 88, alignment: .topLeading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct MacQuickActionBar: View {
    let actions: [MacQuickAction]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(actions) { action in
                Button {
                } label: {
                    Label(action.title, systemImage: action.systemImageName)
                }
                .buttonStyle(.bordered)
                .disabled(action.isEnabled == false)
                .help(action.title)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct MacSectionDetailView: View {
    let module: MacInheritedModule?
    let routes: [MacTransportRouteSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let module {
                HStack(alignment: .firstTextBaseline) {
                    Label(module.title, systemImage: module.systemImageName)
                        .font(.headline)
                    Spacer()
                    Text("\(module.recordCount)")
                        .font(.headline.monospacedDigit())
                }
                FlowRow(items: module.enabledPermissions.map(\.rawValue))
                FlowRow(items: module.inheritedFrom)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Transport")
                    .font(.headline)
                ForEach(routes) { route in
                    HStack(spacing: 12) {
                        Image(systemName: route.canSend ? "arrow.up.circle" : "arrow.down.circle")
                            .foregroundStyle(route.canSend ? .primary : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.messageType.rawValue)
                                .font(.subheadline.weight(.medium))
                            Text(route.policy.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(route.receives ? "Receive" : "Relay")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct FlowRow: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }
}
