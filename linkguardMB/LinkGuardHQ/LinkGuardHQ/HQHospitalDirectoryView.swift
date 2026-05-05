import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 全臺急救責任醫院目錄（HQ Mac 版）
struct HQHospitalDirectoryView: View {
    @ObservedObject var vm: HQViewModel
    @State private var query = ""
    @State private var selectedRegion: HQHospital.Region? = nil
    @State private var selectedLevel: HQHospital.Level? = nil

    private var filtered: [(region: HQHospital.Region, items: [HQHospital])] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return HQHospitalDirectory.grouped().compactMap { group in
            if let r = selectedRegion, r != group.region { return nil }
            let items = group.items.filter { h in
                if let lv = selectedLevel, lv != h.level { return false }
                guard !trimmed.isEmpty else { return true }
                return h.name.localizedCaseInsensitiveContains(trimmed)
                    || h.city.localizedCaseInsensitiveContains(trimmed)
                    || h.purpose.localizedCaseInsensitiveContains(trimmed)
            }
            return items.isEmpty ? nil : (group.region, items)
        }
    }

    private var totalCount: Int { filtered.reduce(0) { $0 + $1.items.count } }

    var body: some View {
        HQPage {
            HQPageTitleBar(L("後送醫院"),
                           subtitle: L("全臺急救責任醫院 84 家，依區域分組"),
                           icon: "cross.fill",
                           accent: NV.info) {
                Text(L("%lld 家", HQHospitalDirectory.all.count))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            // 搜尋 + 篩選
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField(L("搜尋縣市 / 醫院名稱 / 用途"), text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(NV.surface)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(NV.info.opacity(0.3), lineWidth: NV.strokeWidth))
                )

                // 區域篩選
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(nil as HQHospital.Region?, label: L("全部區域"), accent: NV.info,
                                   isSelected: selectedRegion == nil) { selectedRegion = nil }
                        ForEach(HQHospital.Region.allCases, id: \.self) { r in
                            filterChip(r, label: L(r.rawValue), accent: NV.info,
                                       isSelected: selectedRegion == r) { selectedRegion = r }
                        }
                    }
                }

                // 層級篩選
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(nil as HQHospital.Level?, label: L("全部層級"), accent: NV.green,
                                   isSelected: selectedLevel == nil) { selectedLevel = nil }
                        ForEach(HQHospital.Level.allCases, id: \.self) { lv in
                            filterChip(lv, label: L(lv.rawValue), accent: levelColor(lv),
                                       isSelected: selectedLevel == lv) { selectedLevel = lv }
                        }
                    }
                }
            }
            .hqPanelChrome(accent: NV.info)

            if filtered.isEmpty {
                HQEmptyStateView(icon: "magnifyingglass", title: L("沒有符合的醫院"))
                    .hqPanelChrome(accent: NV.info)
            } else {
                LazyVStack(alignment: .leading, spacing: NV.panelSpacing) {
                    ForEach(filtered, id: \.region) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "mappin.and.ellipse").foregroundColor(NV.info)
                                Text(L(group.region.rawValue)).font(.headline)
                                Text(L("%lld 家", group.items.count))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            VStack(spacing: 6) {
                                ForEach(group.items) { h in hospitalRow(h) }
                            }
                        }
                        .hqPanelChrome(accent: NV.info)
                    }
                }
            }
        }
    }

    // MARK: - Row

    private func hospitalRow(_ h: HQHospital) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Image(systemName: h.level.icon)
                    .foregroundColor(levelColor(h.level))
                    .font(.title3)
                Text(h.city)
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
            }
            .frame(width: 56)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(h.name).font(.subheadline.bold())
                    levelBadge(h.level)
                }
                if !h.address.isEmpty {
                    Text(h.address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                if !h.purpose.isEmpty {
                    Text(h.purpose)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if !h.phone.isEmpty {
                Button { callOrCopy(phone: h.phone) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                        Text(h.phone).monospacedDigit()
                    }
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(NV.info))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(NV.surface.opacity(0.6)))
    }

    // MARK: - Helpers

    private func levelColor(_ lv: HQHospital.Level) -> Color {
        switch lv {
        case .heavy:    return NV.danger
        case .moderate: return NV.warning
        case .children: return NV.command
        case .unknown:  return .secondary
        }
    }

    private func levelBadge(_ lv: HQHospital.Level) -> some View {
        Text(L(lv.rawValue))
            .font(.caption2.bold())
            .foregroundColor(levelColor(lv))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(levelColor(lv).opacity(0.12))
            .clipShape(Capsule())
    }

    private func filterChip<T>(_ value: T?,
                                label: String,
                                accent: Color,
                                isSelected: Bool,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(isSelected ? .white : accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(isSelected ? accent : accent.opacity(0.12)))
                .overlay(Capsule().stroke(accent.opacity(0.4), lineWidth: NV.strokeWidth))
        }
        .buttonStyle(.plain)
    }

    private func callOrCopy(phone: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(phone, forType: .string)
        #else
        if let url = URL(string: "tel://\(phone)") { UIApplication.shared.open(url) }
        #endif
    }
}
