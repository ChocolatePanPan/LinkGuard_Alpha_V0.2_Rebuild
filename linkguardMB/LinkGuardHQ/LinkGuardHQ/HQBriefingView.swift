import SwiftUI

struct HQBriefingView: View {
    @ObservedObject var vm: HQViewModel
    @State private var showAddSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if vm.briefings.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40)).foregroundColor(.secondary)
                        Text(L("尚未建立會報"))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .padding(.horizontal)
                } else {
                    ForEach(vm.briefings) { report in
                        BriefingCard(report: report)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(L("會報系統"))
        .overlay(alignment: .bottomLeading) {
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(vm.server.isRunning ? NV.team : Color.gray)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .padding(24)
            .disabled(!vm.server.isRunning)
            .help(L("新增會報"))
        }
        .sheet(isPresented: $showAddSheet) {
            AddBriefingSheet(vm: vm)
        }
    }
}

struct BriefingCard: View {
    let report: BriefingReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: report.type.icon)
                    .foregroundColor(NV.info)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.title)
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text(report.type.label)
                            .font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(NV.info.opacity(0.15))
                            .cornerRadius(4)
                        Text("by \(report.author)")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text(timeText)
                    .font(.caption2).foregroundColor(.secondary)
            }

            ForEach(report.sections.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.sections[i].title)
                        .font(.subheadline).bold()
                    Text(report.sections[i].content)
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(.leading, 8)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    private var timeText: String {
        let date = Date(timeIntervalSince1970: report.timestamp)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/MM/dd HH:mm"
        return fmt.string(from: date)
    }
}

// MARK: - 新增會報

struct AddBriefingSheet: View {
    @ObservedObject var vm: HQViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var briefingType: BriefingType = .initial
    @State private var title = ""
    @State private var author = "指揮官"
    @State private var sections: [BriefingSection] = [BriefingSection(title: "", content: "")]

    var body: some View {
        NavigationStack {
            Form {
                Section(L("會報資訊")) {
                    Picker(L("類型"), selection: $briefingType) {
                        ForEach(BriefingType.allCases, id: \.self) { t in
                            Label(t.label, systemImage: t.icon).tag(t)
                        }
                    }
                    TextField(L("標題"), text: $title)
                    TextField(L("作者"), text: $author)
                }
                Section(L("內容段落")) {
                    ForEach(sections.indices, id: \.self) { i in
                        VStack(spacing: 6) {
                            TextField(L("段落標題"), text: $sections[i].title)
                            TextField(L("段落內容"), text: $sections[i].content, axis: .vertical)
                                .lineLimit(2...5)
                        }
                    }
                    Button {
                        sections.append(BriefingSection(title: "", content: ""))
                    } label: {
                        Label(L("新增段落"), systemImage: "plus.circle")
                    }
                }
                Section(L("傳送目標")) {
                    HStack {
                        Image(systemName: vm.targetMode == .broadcast ? "antenna.radiowaves.left.and.right" : "person.2.circle")
                            .foregroundColor(NV.command)
                        Text(vm.targetMode == .broadcast ? L("全體廣播") : L("指定 %lld 台裝置", vm.selectedTargetDeviceIDs.count))
                            .font(.subheadline)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L("新增會報"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("發布")) {
                        let report = BriefingReport(
                            title: title,
                            type: briefingType,
                            author: author,
                            sections: sections.filter { !$0.title.isEmpty || !$0.content.isEmpty }
                        )
                        vm.addBriefing(report)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}
