import SwiftUI

// MARK: - View（資料模型定義於 FieldHospitalData.swift）

struct FieldHospitalView: View {
    @State private var query = ""
    @State private var selectedRegion: FieldHospital.Region? = nil
    @State private var selectedLevel: FieldHospital.Level? = nil

    private var filtered: [(region: FieldHospital.Region, items: [FieldHospital])] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return FieldHospitalDirectory.grouped().compactMap { group in
            if let r = selectedRegion, r != group.region { return nil }
            let items = group.items.filter { h in
                if let lv = selectedLevel, lv != h.level { return false }
                guard !trimmed.isEmpty else { return true }
                return h.name.localizedCaseInsensitiveContains(trimmed)
                    || h.city.localizedCaseInsensitiveContains(trimmed)
                    || h.address.localizedCaseInsensitiveContains(trimmed)
            }
            return items.isEmpty ? nil : (group.region, items)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("搜尋縣市 / 醫院名稱 / 地址", text: $query)
                    }
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            regionChip(nil, label: "全部")
                            ForEach(FieldHospital.Region.allCases, id: \.self) { r in
                                regionChip(r, label: r.rawValue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            levelChip(nil, label: "全部")
                            ForEach(FieldHospital.Level.allCases, id: \.self) { lv in
                                levelChip(lv, label: lv.rawValue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                ForEach(filtered, id: \.region) { group in
                    Section {
                        ForEach(group.items) { h in
                            hospitalRow(h)
                        }
                    } header: {
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                            Text("\(group.region.rawValue)（\(group.items.count) 家）")
                        }
                    }
                }

                if filtered.isEmpty {
                    Section {
                        Label("沒有符合的醫院", systemImage: "magnifyingglass")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("後送醫院（\(FieldHospitalDirectory.all.count) 家）")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func hospitalRow(_ h: FieldHospital) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: h.level.icon)
                    .foregroundColor(h.level.color)
                Text(h.name).font(.subheadline.bold())
                Spacer()
                Text(h.level.rawValue)
                    .font(.caption2.bold())
                    .foregroundColor(h.level.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(h.level.color.opacity(0.12))
                    .clipShape(Capsule())
            }
            if !h.address.isEmpty {
                Text(h.address)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            if !h.phone.isEmpty {
                Button {
                    let digits = h.phone.filter(\.isNumber)
                    if let url = URL(string: "tel://\(digits)") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label(h.phone, systemImage: "phone.fill")
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    private func regionChip(_ region: FieldHospital.Region?, label: String) -> some View {
        let sel = selectedRegion == region
        return Button { selectedRegion = region } label: {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(sel ? .white : .blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(sel ? Color.blue : Color.blue.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func levelChip(_ level: FieldHospital.Level?, label: String) -> some View {
        let sel = selectedLevel == level
        let accent = level?.color ?? Color.green
        return Button { selectedLevel = level } label: {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(sel ? .white : accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(sel ? accent : accent.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}
