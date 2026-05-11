import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 全臺消防局聯絡簿
/// - 依區域分組顯示 22 個縣市消防局
/// - 點選地址 → 開啟 Apple Maps 導航
/// - 點選 119 → macOS 複製到剪貼簿；iOS/iPadOS 直接撥號
struct HQFireDepartmentDirectoryView: View {
    @ObservedObject var vm: HQViewModel
    @State private var query = ""
    @State private var selectedRegion: HQFireDepartment.Region? = nil

    private var filtered: [(region: HQFireDepartment.Region, items: [HQFireDepartment])] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return HQFireDepartmentDirectory.grouped().compactMap { group in
            if let r = selectedRegion, r != group.region { return nil }
            let items = group.items.filter { dept in
                guard !trimmed.isEmpty else { return true }
                return dept.name.localizedCaseInsensitiveContains(trimmed)
                    || dept.city.localizedCaseInsensitiveContains(trimmed)
                    || dept.address.localizedCaseInsensitiveContains(trimmed)
            }
            return items.isEmpty ? nil : (group.region, items)
        }
    }

    var body: some View {
        HQPage {
            HQPageTitleBar(L("消防局聯絡簿"),
                           subtitle: L("全臺 22 縣市消防局總局聯絡資訊"),
                           icon: "flame.fill",
                           accent: NV.danger) {
                Text(L("%lld 局", HQFireDepartmentDirectory.all.count))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            // 搜尋 + 區域過濾
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(L("搜尋縣市 / 消防局 / 地址"), text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(NV.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(NV.greenDim.opacity(0.3), lineWidth: NV.strokeWidth)
                        )
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        regionChip(nil, label: L("全部"))
                        ForEach(HQFireDepartment.Region.allCases, id: \.self) { region in
                            regionChip(region, label: L(region.rawValue))
                        }
                    }
                }
            }
            .hqPanelChrome(accent: NV.danger)

            if filtered.isEmpty {
                HQEmptyStateView(icon: "magnifyingglass", title: L("沒有符合的消防局"))
                    .hqPanelChrome(accent: NV.danger)
            } else {
                LazyVStack(alignment: .leading, spacing: NV.panelSpacing) {
                    ForEach(filtered, id: \.region) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundColor(NV.danger)
                                Text(L(group.region.rawValue))
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(L("%lld 局", group.items.count))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            VStack(spacing: 6) {
                                ForEach(group.items) { dept in
                                    fireDepartmentRow(dept)
                                }
                            }
                        }
                        .hqPanelChrome(accent: NV.danger)
                    }
                }
            }
        }
    }

    private func regionChip(_ region: HQFireDepartment.Region?, label: String) -> some View {
        let isSelected = (selectedRegion == region)
        return Button {
            selectedRegion = region
        } label: {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(isSelected ? .white : NV.danger)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? NV.danger : NV.danger.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(NV.danger.opacity(0.4), lineWidth: NV.strokeWidth)
                )
        }
        .buttonStyle(.plain)
    }

    private func fireDepartmentRow(_ dept: HQFireDepartment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .foregroundColor(NV.danger)
                    .font(.title3)
                Text(dept.city)
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
            }
            .frame(width: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(dept.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Button {
                    openInMaps(address: dept.address, name: dept.name)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "map")
                            .font(.caption2)
                        Text(dept.address)
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundColor(NV.info)
                }
                .buttonStyle(.plain)
                .help(L("在地圖中開啟"))
            }

            Spacer(minLength: 0)

            Button {
                callOrCopy(phone: dept.phone)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "phone.fill")
                    Text(dept.phone)
                        .monospacedDigit()
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(NV.danger))
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .help(L("複製電話到剪貼簿"))
            #else
            .help(L("撥打 119"))
            #endif
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(NV.surface.opacity(0.6))
        )
    }

    // MARK: - 平台行為

    private func openInMaps(address: String, name: String) {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        #if os(macOS)
        if let url = URL(string: "https://maps.apple.com/?q=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let url = URL(string: "https://maps.apple.com/?q=\(encoded)") {
            UIApplication.shared.open(url)
        }
        #endif
    }

    private func callOrCopy(phone: String) {
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(phone, forType: .string)
        #else
        if let url = URL(string: "tel://\(phone)") {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
