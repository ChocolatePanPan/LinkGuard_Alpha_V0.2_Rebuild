import SwiftUI

/// PADOS 多裝置目標選擇器
struct DeviceTargetSelector: View {
    @Binding var targetMode: HQViewModel.TargetMode
    @Binding var selectedIDs: Set<String>
    let fieldUnits: [ConnectedFieldUnit]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 模式切換
            Picker(L("目標模式"), selection: $targetMode) {
                ForEach(HQViewModel.TargetMode.allCases, id: \.self) { mode in
                    Text(mode == .broadcast ? L("全體廣播") : L("指定裝置")).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tint(NV.green)

            if targetMode == .selected {
                // 裝置清單
                if fieldUnits.isEmpty {
                    Text(L("目前無連線裝置"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    // 全選 / 取消全選
                    HStack {
                        Text(L("已選 %lld / %lld", selectedIDs.count, fieldUnits.count))
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Button(L("全選")) {
                            selectedIDs = Set(fieldUnits.map(\.deviceID))
                        }
                        .font(.caption)
                        Button(L("取消全選")) {
                            selectedIDs = []
                        }
                        .font(.caption)
                    }

                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(fieldUnits) { unit in
                                DeviceCheckRow(
                                    unit: unit,
                                    isSelected: selectedIDs.contains(unit.deviceID),
                                    onToggle: {
                                        if selectedIDs.contains(unit.deviceID) {
                                            selectedIDs.remove(unit.deviceID)
                                        } else {
                                            selectedIDs.insert(unit.deviceID)
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }
            }
        }
        .padding(NV.cardPadding)
        .background(NV.surface.opacity(0.6))
        .cornerRadius(NV.cardRadius)
    }
}

private struct DeviceCheckRow: View {
    let unit: ConnectedFieldUnit
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? NV.green : .gray)

                Circle()
                    .fill(unit.isOnline ? NV.green : .gray)
                    .frame(width: NV.dotSize, height: NV.dotSize)

                Text(unit.deviceID)
                    .font(.caption).bold()
                    .foregroundColor(.primary)

                Text(unit.deptCode)
                    .font(.caption2)
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(NV.team.opacity(NV.tagOpacity))
                    .cornerRadius(NV.tagRadius)

                Spacer()

                Image(systemName: "battery.\(min(unit.battery / 25 * 25, 100))")
                    .font(.caption2)
                    .foregroundColor(unit.battery < 20 ? NV.danger : .secondary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isSelected ? NV.green.opacity(0.08) : Color.clear)
            .cornerRadius(NV.tagRadius)
        }
        .buttonStyle(.plain)
    }
}
