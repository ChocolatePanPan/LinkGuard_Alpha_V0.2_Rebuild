import LinkGuardV03Core
import SwiftUI

struct MacUCCICSArchitecturePanel: View {
    let architecture: MacUCCICSArchitecture

    var body: some View {
        HQPanel(title: architecture.title, icon: "building.columns.fill", accent: NV.command) {
            VStack(alignment: .leading, spacing: 10) {
                header
                Divider()
                laneList
                Divider()
                boundaryList
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(architecture.commandAuthority.macDisplayName)
                .font(.caption.weight(.semibold))
                .foregroundColor(NV.command)
            Text(architecture.coordinationRole)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var laneList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(architecture.lanes) { lane in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: lane.systemImageName)
                        .foregroundColor(NV.green)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lane.title)
                            .font(.caption.weight(.semibold))
                        Text(lane.roleInUCC)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(lane.authorityBoundary)
                            .font(.caption2)
                            .foregroundColor(NV.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var boundaryList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(architecture.boundaryRules) { rule in
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.title)
                        .font(.caption.weight(.semibold))
                    Text(rule.detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
