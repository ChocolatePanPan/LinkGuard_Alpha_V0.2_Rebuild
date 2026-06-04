import SwiftUI

// MARK: - 受困者總覽

struct HQVictimOverviewView: View {
    @ObservedObject var vm: HQViewModel

    @State private var searchText = ""
    @State private var filterOnlineOnly = false
    @State private var filterSOSOnly = false
    @State private var filterPriority: VictimPriority? = nil
    @State private var filterStatus: VictimStatus? = nil
    @State private var sortBy: VictimSort = .priority
    @State private var selectedVictimID: String? = nil

    enum VictimSort: String, CaseIterable {
        case priority = "優先級"
        case heartRate = "心率"
        case signal = "訊號"
        case battery = "電量"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                victimList
                    .frame(minWidth: 400)
                Divider()
                detailPanel
                    .frame(minWidth: 300, idealWidth: 360)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HQSectionHeader(L("受困者總覽"), icon: "person.fill.questionmark", accent: NV.warning) {
                victimStats
            }

            HStack(spacing: 12) {
                // 搜尋
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField(L("搜尋受困者 ID / 裝置…"), text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .hqThemedSurfaceBackground()
                .cornerRadius(8)
                .frame(maxWidth: 260)

                Toggle(L("僅上線"), isOn: $filterOnlineOnly)
                    .toggleStyle(.switch).controlSize(.small)
                Toggle(L("僅 SOS"), isOn: $filterSOSOnly)
                    .toggleStyle(.switch).controlSize(.small)

                Picker(L("優先級"), selection: $filterPriority) {
                    Text(L("全部")).tag(VictimPriority?.none)
                    ForEach(VictimPriority.allCases, id: \.self) { p in
                        Label(p.label, systemImage: p.icon).tag(VictimPriority?.some(p))
                    }
                }
                .frame(width: 110)

                Picker(L("處置狀態"), selection: $filterStatus) {
                    Text(L("全部")).tag(VictimStatus?.none)
                    ForEach(VictimStatus.allCases, id: \.self) { s in
                        Label(s.label, systemImage: s.icon).tag(VictimStatus?.some(s))
                    }
                }
                .frame(width: 130)

                Picker(L("排序"), selection: $sortBy) {
                    ForEach(VictimSort.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .frame(width: 90)
            }
            .padding(.horizontal, NV.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.bottom, 14)
    }

    private var victimStats: some View {
        HStack(spacing: 16) {
            VStatBadge(label: "總計", value: "\(vm.allVictimRecords.count)", color: NV.warning)
            VStatBadge(label: "上線", value: "\(vm.allVictimRecords.filter(\.isOnline).count)", color: NV.green)
            VStatBadge(label: "SOS", value: "\(vm.allVictimRecords.filter(\.isSOS).count)", color: NV.danger)
            VStatBadge(label: "緊急", value: "\(vm.allVictimRecords.filter { $0.priority == .critical }.count)", color: .red)
        }
    }

    // MARK: - 受困者清單

    private var victimList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                let records = sortedAndFiltered
                if records.isEmpty {
                    Text(L("目前無受困者資料"))
                        .font(.callout).foregroundColor(.secondary)
                        .padding(.top, 40)
                } else {
                    ForEach(records) { record in
                        VictimRowCard(
                            record: record,
                            isSelected: selectedVictimID == record.id,
                            onTap: { selectedVictimID = record.id },
                            onSetPriority: { vm.setVictimPriority(record.id, $0) }
                        )
                    }
                }
            }
            .padding()
        }
    }

    private var sortedAndFiltered: [HQVictimRecord] {
        var result = vm.allVictimRecords
        if filterOnlineOnly { result = result.filter(\.isOnline) }
        if filterSOSOnly { result = result.filter(\.isSOS) }
        if let p = filterPriority { result = result.filter { $0.priority == p } }
        if let s = filterStatus { result = result.filter { $0.status == s } }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.id.lowercased().contains(q) ||
                $0.sourceDeviceID.lowercased().contains(q) ||
                $0.sourceDeptCode.lowercased().contains(q) ||
                $0.patientName.lowercased().contains(q) ||
                $0.location.lowercased().contains(q)
            }
        }
        switch sortBy {
        case .priority:
            result.sort { $0.priority > $1.priority }
        case .heartRate:
            result.sort { ($0.heartRate == 0 ? -1 : $0.heartRate) > ($1.heartRate == 0 ? -1 : $1.heartRate) }
        case .signal:
            result.sort { $0.rssi > $1.rssi }
        case .battery:
            result.sort { $0.battery < $1.battery }
        }
        return result
    }

    // MARK: - 詳情面板

    private var detailPanel: some View {
        Group {
            if let vid = selectedVictimID,
               let record = vm.allVictimRecords.first(where: { $0.id == vid }) {
                VictimDetailPanel(record: record, vm: vm)
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "person.fill.questionmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text(L("選擇受困者查看詳情"))
                        .font(.callout).foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - 受困者列表行

private struct VictimRowCard: View {
    let record: HQVictimRecord
    let isSelected: Bool
    let onTap: () -> Void
    let onSetPriority: (VictimPriority) -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // 優先級指示
                Circle()
                    .fill(record.priority.color)
                    .frame(width: NV.dotSize, height: NV.dotSize)

                // 上線 / SOS
                VStack(spacing: 2) {
                    Circle()
                        .fill(record.isOnline ? NV.green : .gray)
                        .frame(width: NV.dotSize, height: NV.dotSize)
                    if record.isSOS {
                        Text("SOS")
                            .font(.system(size: 7, weight: .black))
                            .foregroundColor(NV.danger)
                    }
                }
                .frame(width: 24)

                // 主要資訊
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(record.id).font(.headline)
                        if !record.patientName.isEmpty {
                            Text(record.patientName)
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(record.sourceDeptCode)
                            .font(.caption2).bold()
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(NV.team.opacity(NV.tagOpacity))
                            .cornerRadius(NV.tagRadius)
                        Text("← \(record.sourceDeviceID)")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    // 處置狀態標籤
                    HStack(spacing: 4) {
                        Image(systemName: record.status.icon)
                            .font(.system(size: 9))
                        Text(record.status.label)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(record.status.color)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(record.status.color.opacity(NV.tagOpacity))
                    .cornerRadius(NV.tagRadius)
                }

                Spacer()

                // 生命跡象
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundColor(heartColor)
                        Text(record.heartRate > 0 ? "\(record.heartRate) bpm" : "-- bpm")
                            .font(.caption).monospacedDigit()
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "battery.50")
                            .font(.caption2)
                        Text("\(record.battery)%")
                            .font(.caption).monospacedDigit()
                            .foregroundColor(record.battery < 20 ? NV.danger : .secondary)
                    }
                    Text(String(format: "%.0f dBm", record.rssi))
                        .font(.caption2).foregroundColor(.secondary)
                }

                // 快速優先級選擇
                Menu {
                    ForEach(VictimPriority.allCases, id: \.self) { p in
                        Button {
                            onSetPriority(p)
                        } label: {
                            Label(p.label, systemImage: p.icon)
                        }
                    }
                } label: {
                    Image(systemName: record.priority.icon)
                        .foregroundColor(record.priority.color)
                        .frame(width: 24, height: 24)
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #endif
                .frame(width: 30)
            }
            .padding(NV.cardPadding)
            .background(isSelected ? NV.command.opacity(NV.tagOpacity) : Color.clear)
            .hqThemedSurfaceBackground()
            .cornerRadius(NV.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: NV.cardRadius)
                    .stroke(isSelected ? NV.command.opacity(0.5) : Color.clear, lineWidth: NV.strokeWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private var heartColor: Color {
        guard record.heartRate > 0 else { return .gray }
        if record.heartRate < 50 || record.heartRate > 120 { return NV.danger }
        if record.heartRate < 60 || record.heartRate > 100 { return NV.warning }
        return NV.green
    }
}

// MARK: - 受困者詳情面板

private struct VictimDetailPanel: View {
    let record: HQVictimRecord
    @ObservedObject var vm: HQViewModel
    @State private var editingNote: String = ""
    @State private var editingDescription: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 標題
                HStack {
                    Image(systemName: "person.fill.questionmark")
                        .font(.title2).foregroundColor(NV.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.id)
                            .font(.title2).bold()
                        if !record.patientName.isEmpty {
                            Text(record.patientName)
                                .font(.callout).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if record.hasPatientReport {
                        Label(L("傷患回報"), systemImage: "doc.text")
                            .font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(NV.info.opacity(NV.tagOpacity))
                            .foregroundColor(NV.info)
                            .cornerRadius(NV.tagRadius)
                    }
                    if record.isSOS {
                        Label("SOS", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).bold()
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(NV.danger.opacity(NV.tagOpacity))
                            .foregroundColor(NV.danger)
                            .cornerRadius(NV.tagRadius)
                    }
                }

                // 上線狀態
                HStack(spacing: 4) {
                    Circle()
                        .fill(record.isOnline ? NV.green : .gray)
                        .frame(width: 8, height: 8)
                    Text(record.isOnline ? L("上線中") : L("離線"))
                        .font(.caption).foregroundColor(record.isOnline ? NV.green : .secondary)
                }

                Divider()

                if record.hasPatientReport {
                    HQInlinePhotoStrip(
                        vm: vm,
                        reportType: "傷員回報",
                        keywords: patientPhotoKeywords(record),
                        title: L("現場照片"),
                        limit: 2,
                        cardWidth: 180
                    )
                }

                Divider()

                // 處置狀態
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("處置狀態")).font(.headline)
                    LazyVGrid(columns: [
                        GridItem(.flexible()), GridItem(.flexible()),
                        GridItem(.flexible()), GridItem(.flexible())
                    ], spacing: 6) {
                        ForEach(VictimStatus.allCases, id: \.self) { s in
                            Button {
                                vm.setVictimStatus(record.id, s)
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: s.icon)
                                        .font(.callout)
                                    Text(s.label)
                                        .font(.system(size: 9))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(record.status == s ? s.color.opacity(NV.tagOpacity) : Color.clear)
                                .cornerRadius(NV.tagRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: NV.tagRadius)
                                        .stroke(record.status == s ? s.color : Color.gray.opacity(0.3), lineWidth: NV.strokeWidth)
                                )
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(record.status == s ? s.color : .secondary)
                        }
                    }
                }

                Divider()

                // 生命跡象卡
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("生命跡象")).font(.headline)

                    HStack(spacing: 20) {
                        DetailMetric(icon: "heart.fill", label: "心率",
                                     value: record.heartRate > 0 ? "\(record.heartRate) bpm" : "--",
                                     color: heartColor)
                        DetailMetric(icon: "battery.50", label: "電量",
                                     value: "\(record.battery)%",
                                     color: record.battery < 20 ? NV.danger : NV.green)
                        DetailMetric(icon: "dot.radiowaves.left.and.right", label: "訊號",
                                     value: String(format: "%.0f dBm", record.rssi),
                                     color: record.rssi > -70 ? NV.green : record.rssi > -90 ? NV.warning : NV.danger)
                    }
                }

                Divider()

                // 來源 & 位置
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("來源資訊")).font(.headline)
                    HStack {
                        Text(L("回報裝置")).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(record.sourceDeviceID).font(.callout).bold()
                    }
                    HStack {
                        Text(L("部門代碼")).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(record.sourceDeptCode)
                            .font(.caption).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(NV.team.opacity(NV.tagOpacity))
                            .cornerRadius(NV.tagRadius)
                    }
                    if !record.location.isEmpty {
                        HStack {
                            Text(L("位置")).font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(record.location).font(.callout)
                        }
                    }
                }

                Divider()

                // 優先級設定
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("優先級")).font(.headline)
                    HStack(spacing: 6) {
                        ForEach(VictimPriority.allCases, id: \.self) { p in
                            Button {
                                vm.setVictimPriority(record.id, p)
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: p.icon)
                                        .font(.title3)
                                    Text(p.label)
                                        .font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(record.priority == p ? p.color.opacity(NV.tagOpacity) : Color.clear)
                                .cornerRadius(NV.tagRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: NV.tagRadius)
                                        .stroke(record.priority == p ? p.color : Color.gray.opacity(0.3), lineWidth: NV.strokeWidth)
                                )
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(record.priority == p ? p.color : .secondary)
                        }
                    }
                }

                Divider()

                // 描述
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("描述")).font(.headline)
                    TextField(L("傷勢描述、處置紀錄…"), text: $editingDescription, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...8)
                        .onAppear { editingDescription = record.description }
                        .onChange(of: record.id) { _ in editingDescription = vm.victimDescriptions[record.id] ?? "" }
                    Button(L("儲存描述")) {
                        vm.setVictimDescription(record.id, editingDescription)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider()

                // 備註
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("備註")).font(.headline)
                    TextField(L("輸入備註…"), text: $editingNote, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                        .onAppear { editingNote = record.note }
                        .onChange(of: record.id) { _ in editingNote = vm.victimNotes[record.id] ?? "" }
                        .onSubmit { vm.setVictimNote(record.id, editingNote) }
                    Button(L("儲存備註")) {
                        vm.setVictimNote(record.id, editingNote)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()
        }
        .hqThemedSurfaceBackground()
    }

    private var heartColor: Color {
        guard record.heartRate > 0 else { return .gray }
        if record.heartRate < 50 || record.heartRate > 120 { return NV.danger }
        if record.heartRate < 60 || record.heartRate > 100 { return NV.warning }
        return NV.green
    }

    private func patientPhotoKeywords(_ record: HQVictimRecord) -> [String] {
        [
            record.id,
            record.patientName,
            record.sourceDeviceID,
            record.sourceDeptCode,
            record.location
        ].filter { !$0.isEmpty }
    }
}

private struct DetailMetric: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3).foregroundColor(color)
            Text(value)
                .font(.callout).bold().monospacedDigit()
            Text(label)
                .font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(NV.tagOpacity))
        .cornerRadius(NV.cardRadius)
    }
}

private struct VStatBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title3).bold().foregroundColor(color)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }
}
