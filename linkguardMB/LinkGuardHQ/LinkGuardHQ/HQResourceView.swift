import SwiftUI

// MARK: - HQ 資源管理

struct HQResourceView: View {
    @ObservedObject var vm: HQViewModel

    private var resourceData: [String: Any] { vm.latestResourceUpdate ?? [:] }
    private var summary: [String: Any] { resourceData["summary"] as? [String: Any] ?? [:] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("資源管理"))
                    .font(.title).bold()
                    .padding(.horizontal)

                if summary.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(L("等待資源狀態資料…"))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(Array(summary.keys.sorted()), id: \.self) { key in
                            if let info = summary[key] as? [String: Any] {
                                ResourceCard(
                                    name: key,
                                    total: info["total"] as? Int ?? 0,
                                    available: info["available"] as? Int ?? 0
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // 個別資源列表
                if let resources = resourceData["resources"] as? [[String: Any]] {
                    Text(L("資源清單"))
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(0..<resources.count, id: \.self) { idx in
                        let r = resources[idx]
                        ResourceRow(resource: r)
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
        }
    }
}

struct ResourceCard: View {
    let name: String
    let total: Int
    let available: Int

    private var ratio: Double {
        guard total > 0 else { return 0 }
        return Double(available) / Double(total)
    }

    private var color: Color {
        if ratio > 0.5 { return NV.green }
        if ratio > 0.2 { return .orange }
        return NV.danger
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(name)
                .font(.headline)
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(ratio))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(available)")
                        .font(.title2.bold())
                        .foregroundColor(color)
                    Text("/ \(total)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 80, height: 80)
            Text(L("%lld 可用", available))
                .font(.caption)
                .foregroundColor(color)
        }
        .padding()
        .background(NV.surface.opacity(0.5))
        .cornerRadius(12)
    }
}

struct ResourceRow: View {
    let resource: [String: Any]

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(resource["name"] as? String ?? "")
                    .font(.subheadline).bold()
                Text(resource["type"] as? String ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            let status = resource["status"] as? String ?? ""
            Text(status)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(status == "available" ? NV.green.opacity(0.2) : NV.warning.opacity(0.2))
                .cornerRadius(6)
            Text("\(resource["available"] as? Int ?? 0)/\(resource["total"] as? Int ?? 0)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(NV.surface.opacity(0.3))
        .cornerRadius(8)
    }
}
