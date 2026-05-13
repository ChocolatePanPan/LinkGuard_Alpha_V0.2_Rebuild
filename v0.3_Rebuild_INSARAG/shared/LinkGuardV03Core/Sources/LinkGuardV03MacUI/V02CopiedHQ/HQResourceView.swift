import SwiftUI

// MARK: - HQ 資源管理

struct HQResourceView: View {
    @ObservedObject var vm: HQViewModel

    @State private var selectedZoneName = ""
    @State private var selectedResourceID = ""
    @State private var deploymentNote = ""
    @State private var newResourceName = ""
    @State private var newResourceType = "medical_kit"
    @State private var newResourceTotal = 1
    @State private var newResourceLocation = ""
    @State private var isRefreshing = false
    @State private var isMutating = false
    @State private var operationMessage: String?
    @State private var operationIsError = false

    private let resourceTypes = ["medical_kit", "stretcher", "ambulance", "radio", "tool", "personnel"]

    private let actionPanelColumns = [
        GridItem(.flexible(minimum: 360), spacing: NV.panelSpacing, alignment: .top),
        GridItem(.flexible(minimum: 360), spacing: NV.panelSpacing, alignment: .top)
    ]

    private var resourceData: [String: Any] {
        let raw = vm.latestResourceUpdate ?? [:]
        return raw["data"] as? [String: Any] ?? raw
    }

    private var resources: [ManagedResource] {
        (resourceData["resources"] as? [[String: Any]] ?? []).map(ManagedResource.init)
    }

    private var zones: [RescueZone] {
        vm.disasterSite?.zones ?? []
    }

    private var zoneNames: [String] {
        var names = zones.map(\.name)
        for resource in resources {
            for deployment in resource.deployments where !deployment.zoneName.isEmpty && !names.contains(deployment.zoneName) {
                names.append(deployment.zoneName)
            }
        }
        return names
    }

    private var deployableResources: [ManagedResource] {
        resources.filter { $0.available > 0 && !$0.resourceID.isEmpty }
    }

    private var resourceDeployments: [ResourceDeployment] {
        resources.flatMap(\.deployments).filter { !$0.zoneName.isEmpty }
    }

    private var summaryCards: [(type: String, total: Int, available: Int)] {
        if let summary = resourceData["summary"] as? [String: Any], !summary.isEmpty {
            return summary.keys.sorted().compactMap { key in
                guard let info = summary[key] as? [String: Any] else { return nil }
                return (key, intValue(info["total"]), intValue(info["available"]))
            }
        }
        let grouped = Dictionary(grouping: resources, by: \.type)
        return grouped.keys.sorted().map { type in
            let items = grouped[type] ?? []
            return (type, items.reduce(0) { $0 + $1.total }, items.reduce(0) { $0 + $1.available })
        }
    }

    var body: some View {
        HQPage {
            HQPageTitleBar(L("資源管理"), subtitle: L("分區調度 / 庫存 / 回收"), icon: "shippingbox", accent: NV.green) {
                Button {
                    refreshResources()
                } label: {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(L("重新整理"), systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing || isMutating)
            }

            if let operationMessage {
                resourceNotice(operationMessage, isError: operationIsError)
            }

            resourceSummarySection

            LazyVGrid(columns: actionPanelColumns, spacing: NV.panelSpacing) {
                deploymentPanel
                createResourcePanel
            }

            zoneResourceSection
            inventorySection
        }
        .onAppear {
            ensureSelections()
            if vm.latestResourceUpdate == nil {
                refreshResources()
            }
        }
        .onChange(of: zoneNames) { _ in ensureSelections() }
        .onChange(of: deployableResources.map(\.resourceID)) { _ in ensureSelections() }
    }

    private var resourceSummarySection: some View {
        Group {
            if summaryCards.isEmpty {
                HQEmptyStateView(
                    icon: "shippingbox",
                    title: L("尚無資源資料"),
                    subtitle: L("可先新增資源，或啟動 Resource Server 後重新整理。")
                )
                .hqPanelChrome(accent: NV.green)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: NV.panelSpacing)], spacing: NV.panelSpacing) {
                    ForEach(summaryCards, id: \.type) { card in
                        ResourceMetricCard(
                            name: resourceTypeLabel(card.type),
                            total: card.total,
                            available: card.available,
                            icon: resourceTypeIcon(card.type)
                        )
                    }
                }
            }
        }
    }

    private var deploymentPanel: some View {
        HQPanel(title: L("部署到分區"), icon: "arrow.up.right.square.fill", accent: NV.green) {
            VStack(alignment: .leading, spacing: 12) {
                resourceFormRow(label: L("分區")) {
                    Picker(L("分區"), selection: $selectedZoneName) {
                        if zoneNames.isEmpty {
                            Text(L("尚無分區")).tag("")
                        } else {
                            ForEach(zoneNames, id: \.self) { zoneName in
                                Text(zoneName).tag(zoneName)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(zoneNames.isEmpty)
                }

                resourceFormRow(label: L("資源")) {
                    Picker(L("資源"), selection: $selectedResourceID) {
                        if deployableResources.isEmpty {
                            Text(L("沒有可部署資源")).tag("")
                        } else {
                            ForEach(deployableResources) { resource in
                                Text("\(resource.name) · \(resource.available)/\(resource.total)")
                                    .tag(resource.resourceID)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(deployableResources.isEmpty)
                }

                TextField(L("位置 / 備註（選填）"), text: $deploymentNote, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1...3)

                Button {
                    deploySelectedResource()
                } label: {
                    Label(L("部署資源"), systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isMutating || selectedZoneName.isEmpty || selectedResourceID.isEmpty)
            }
            .frame(maxWidth: .infinity, minHeight: 188, alignment: .topLeading)
        }
    }

    private var createResourcePanel: some View {
        HQPanel(title: L("新增真實資源"), icon: "plus.app.fill", accent: NV.info) {
            VStack(alignment: .leading, spacing: 12) {
                TextField(L("資源名稱"), text: $newResourceName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                resourceFormRow(label: L("類型")) {
                    Picker(L("類型"), selection: $newResourceType) {
                        ForEach(resourceTypes, id: \.self) { type in
                            Label(resourceTypeLabel(type), systemImage: resourceTypeIcon(type)).tag(type)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                resourceFormRow(label: L("數量")) {
                    Stepper(value: $newResourceTotal, in: 1...99) {
                        Text("\(newResourceTotal)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                TextField(L("存放位置（選填）"), text: $newResourceLocation)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                Button {
                    createResource()
                } label: {
                    Label(L("新增到庫存"), systemImage: "tray.and.arrow.down.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isMutating || newResourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(maxWidth: .infinity, minHeight: 188, alignment: .topLeading)
        }
    }

    private func resourceFormRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .frame(width: 52, alignment: .leading)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var zoneResourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("分區資源配置"))
                .font(.headline)
                .foregroundColor(NV.green)

            if zoneNames.isEmpty {
                HQEmptyStateView(
                    icon: "map",
                    title: L("尚未建立分區"),
                    subtitle: L("先到分區地圖或災害狀態建立分區後，即可把資源部署到各區。")
                )
                .hqPanelChrome(accent: NV.green)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: NV.panelSpacing)], spacing: NV.panelSpacing) {
                    ForEach(zoneNames, id: \.self) { zoneName in
                        ZoneResourcePanel(
                            zoneName: zoneName,
                            zone: zones.first(where: { $0.name == zoneName }),
                            deployments: deployments(for: zoneName),
                            personnel: personnel(for: zoneName),
                            onReturn: { deployment in
                                returnResource(deployment.resourceID, from: zoneName)
                            }
                        )
                    }
                }
            }
        }
    }

    private var inventorySection: some View {
        HQPanel(title: L("資源清單"), icon: "list.bullet.rectangle", accent: NV.green) {
            if resources.isEmpty {
                Text(L("尚無資源紀錄"))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(resources) { resource in
                        ResourceInventoryRow(
                            resource: resource,
                            typeLabel: resourceTypeLabel(resource.type),
                            typeIcon: resourceTypeIcon(resource.type),
                            selectedZoneName: selectedZoneName,
                            isBusy: isMutating,
                            onDeploy: {
                                deployResource(resource.resourceID, to: selectedZoneName)
                            },
                            onReturn: {
                                returnResource(resource.resourceID, from: resource.returnZoneName)
                            }
                        )
                        if resource.id != resources.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
    }

    private func deployments(for zoneName: String) -> [ResourceDeployment] {
        resourceDeployments.filter { $0.zoneName == zoneName }
    }

    private func personnel(for zoneName: String) -> [PersonnelAssignment] {
        vm.personnelAssignments.filter { $0.assignedZone == zoneName }
    }

    private func ensureSelections() {
        if selectedZoneName.isEmpty || !zoneNames.contains(selectedZoneName) {
            selectedZoneName = zoneNames.first ?? ""
        }
        if selectedResourceID.isEmpty || !deployableResources.contains(where: { $0.resourceID == selectedResourceID }) {
            selectedResourceID = deployableResources.first?.resourceID ?? ""
        }
    }

    private func refreshResources() {
        isRefreshing = true
        vm.backendBridge.refreshResources { result in
            isRefreshing = false
            switch result {
            case .success:
                ensureSelections()
                setOperationMessage(L("資源資料已更新。"))
            case .failure(let error):
                setOperationMessage(error.localizedDescription, isError: true)
            }
        }
    }

    private func createResource() {
        let name = newResourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isMutating = true
        let resourceID = "\(newResourceType)-\(Int(Date().timeIntervalSince1970))"
        vm.backendBridge.createResource(
            resourceID: resourceID,
            type: newResourceType,
            name: name,
            total: newResourceTotal,
            locationDesc: newResourceLocation
        ) { result in
            isMutating = false
            switch result {
            case .success:
                newResourceName = ""
                newResourceTotal = 1
                newResourceLocation = ""
                setOperationMessage(L("已新增資源：%@", name))
                vm.logEvent(type: .zoneUpdate, title: L("新增資源：%@", name), detail: resourceTypeLabel(newResourceType))
            case .failure(let error):
                setOperationMessage(error.localizedDescription, isError: true)
            }
        }
    }

    private func deploySelectedResource() {
        deployResource(selectedResourceID, to: selectedZoneName)
    }

    private func deployResource(_ resourceID: String, to zoneName: String) {
        guard !resourceID.isEmpty, !zoneName.isEmpty else { return }
        isMutating = true
        let resourceName = resources.first(where: { $0.resourceID == resourceID })?.name ?? resourceID
        vm.backendBridge.deployResource(
            resourceID: resourceID,
            assignedZone: zoneName,
            locationDesc: deploymentNote
        ) { result in
            isMutating = false
            switch result {
            case .success:
                deploymentNote = ""
                ensureSelections()
                setOperationMessage(L("已部署 %@ 到 %@", resourceName, zoneName))
                vm.logEvent(type: .zoneUpdate, title: L("部署資源：%@", resourceName), detail: zoneName)
            case .failure(let error):
                setOperationMessage(error.localizedDescription, isError: true)
            }
        }
    }

    private func returnResource(_ resourceID: String, from zoneName: String?) {
        guard !resourceID.isEmpty else { return }
        isMutating = true
        let resourceName = resources.first(where: { $0.resourceID == resourceID })?.name ?? resourceID
        vm.backendBridge.returnResource(resourceID: resourceID, assignedZone: zoneName) { result in
            isMutating = false
            switch result {
            case .success:
                ensureSelections()
                setOperationMessage(L("已回收資源：%@", resourceName))
                vm.logEvent(type: .zoneUpdate, title: L("回收資源：%@", resourceName), detail: zoneName ?? "")
            case .failure(let error):
                setOperationMessage(error.localizedDescription, isError: true)
            }
        }
    }

    private func setOperationMessage(_ message: String, isError: Bool = false) {
        operationMessage = message
        operationIsError = isError
    }

    private func resourceNotice(_ message: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? NV.danger : NV.green)
            Text(message)
                .font(.caption)
                .foregroundColor(isError ? NV.danger : .secondary)
            Spacer()
        }
        .padding(10)
        .background((isError ? NV.danger : NV.green).opacity(0.08))
        .cornerRadius(NV.cardRadius)
    }

    private func resourceTypeLabel(_ type: String) -> String {
        switch type {
        case "medical_kit": return L("醫療包")
        case "stretcher": return L("擔架")
        case "ambulance": return L("救護車")
        case "radio": return L("通訊裝置")
        case "tool": return L("工具")
        case "personnel": return L("人員")
        default: return type.isEmpty ? L("未分類") : type
        }
    }

    private func resourceTypeIcon(_ type: String) -> String {
        switch type {
        case "medical_kit": return "cross.case.fill"
        case "stretcher": return "bed.double.fill"
        case "ambulance": return "cross.circle.fill"
        case "radio": return "antenna.radiowaves.left.and.right"
        case "tool": return "wrench.and.screwdriver.fill"
        case "personnel": return "person.3.fill"
        default: return "shippingbox.fill"
        }
    }
}

private struct ResourceMetricCard: View {
    let name: String
    let total: Int
    let available: Int
    let icon: String

    private var ratio: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(available) / Double(total)))
    }

    private var color: Color {
        if total == 0 { return .gray }
        if ratio > 0.5 { return NV.green }
        if ratio > 0.2 { return NV.warning }
        return NV.danger
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(name, systemImage: icon)
                .font(.headline)
                .foregroundColor(color)
            ProgressView(value: ratio)
                .tint(color)
            HStack(alignment: .firstTextBaseline) {
                Text("\(available)")
                    .font(.title2.bold())
                    .foregroundColor(color)
                Text("/ \(total)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hqPanelChrome(accent: color)
    }
}

private struct ZoneResourcePanel: View {
    let zoneName: String
    let zone: RescueZone?
    let deployments: [ResourceDeployment]
    let personnel: [PersonnelAssignment]
    let onReturn: (ResourceDeployment) -> Void

    private var accent: Color { zone?.status.color ?? NV.green }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(zoneName)
                        .font(.headline)
                    Text(zone?.status.label ?? L("未定義分區"))
                        .font(.caption)
                        .foregroundColor(accent)
                }
                Spacer()
                Label("\(deployments.reduce(0) { $0 + $1.quantity })", systemImage: "shippingbox.fill")
                    .font(.caption.bold())
                    .foregroundColor(accent)
            }

            HStack(spacing: 10) {
                Label("\(personnel.count)", systemImage: "person.3.fill")
                Label("\(deployments.count)", systemImage: "list.bullet")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            if deployments.isEmpty {
                Text(L("尚無資源部署"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(deployments) { deployment in
                        HStack(spacing: 8) {
                            Image(systemName: "shippingbox.fill")
                                .foregroundColor(accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(deployment.resourceName)
                                    .font(.caption.bold())
                                Text(deployment.locationDesc.isEmpty ? deployment.resourceType : deployment.locationDesc)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("x\(deployment.quantity)")
                                .font(.caption.monospacedDigit())
                            Button(L("回收")) { onReturn(deployment) }
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .padding(NV.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hqThemedSurfaceBackground()
        .cornerRadius(NV.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: NV.cardRadius)
                .stroke(accent.opacity(0.35), lineWidth: NV.strokeWidth)
        )
    }
}

private struct ResourceInventoryRow: View {
    let resource: ManagedResource
    let typeLabel: String
    let typeIcon: String
    let selectedZoneName: String
    let isBusy: Bool
    let onDeploy: () -> Void
    let onReturn: () -> Void

    private var statusColor: Color {
        switch resource.status {
        case "available": return NV.green
        case "in_use": return NV.warning
        case "offline": return .gray
        default: return resource.available > 0 ? NV.green : NV.danger
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: typeIcon)
                .foregroundColor(statusColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(resource.name)
                    .font(.subheadline.bold())
                HStack(spacing: 8) {
                    Text(typeLabel)
                    if !resource.locationDesc.isEmpty {
                        Text(resource.locationDesc)
                    }
                    if let zone = resource.primaryZoneName, !zone.isEmpty {
                        Text("→ \(zone)")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            Spacer()
            Text(resource.statusLabel)
                .font(.caption.bold())
                .foregroundColor(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.12))
                .cornerRadius(NV.tagRadius)
            Text("\(resource.available)/\(resource.total)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 54, alignment: .trailing)
            Button(L("部署"), action: onDeploy)
                .font(.caption)
                .disabled(isBusy || selectedZoneName.isEmpty || resource.available <= 0)
            Button(L("回收"), action: onReturn)
                .font(.caption)
                .disabled(isBusy || resource.deployedQuantity <= 0)
        }
        .padding(.vertical, 10)
    }
}

private struct ManagedResource: Identifiable {
    let id: String
    let type: String
    let name: String
    let total: Int
    let available: Int
    let locationDesc: String
    let assignedTo: String
    let assignedZone: String
    let status: String
    let allocations: [ResourceAllocation]

    var resourceID: String { id }

    init(_ dict: [String: Any]) {
        let resourceID = stringValue(dict["resource_id"])
        let fallbackName = stringValue(dict["name"])
        self.id = resourceID.isEmpty ? fallbackName : resourceID
        self.type = stringValue(dict["type"])
        self.name = fallbackName.isEmpty ? self.id : fallbackName
        self.total = max(0, intValue(dict["total"]))
        self.available = max(0, intValue(dict["available"]))
        self.locationDesc = stringValue(dict["location_desc"])
        self.assignedTo = stringValue(dict["assigned_to"])
        self.assignedZone = stringValue(dict["assigned_zone"])
        self.status = stringValue(dict["status"], fallback: "available")
        self.allocations = (dict["allocations"] as? [[String: Any]] ?? []).map(ResourceAllocation.init)
    }

    var deployedQuantity: Int {
        max(0, total - available)
    }

    var primaryZoneName: String? {
        if !assignedZone.isEmpty { return assignedZone }
        if let zone = allocations.first?.zoneName, !zone.isEmpty { return zone }
        if !assignedTo.isEmpty { return assignedTo }
        return nil
    }

    var returnZoneName: String? {
        if let zone = allocations.first?.zoneName, !zone.isEmpty { return zone }
        if !assignedZone.isEmpty { return assignedZone }
        return nil
    }

    var statusLabel: String {
        switch status {
        case "available": return L("可用")
        case "in_use": return L("使用中")
        case "offline": return L("離線")
        default: return status.isEmpty ? L("未知") : status
        }
    }

    var deployments: [ResourceDeployment] {
        if !allocations.isEmpty {
            return allocations.map {
                ResourceDeployment(resource: self, zoneName: $0.zoneName, quantity: $0.quantity, locationDesc: $0.locationDesc)
            }
        }
        guard let zoneName = primaryZoneName, !zoneName.isEmpty, deployedQuantity > 0 else { return [] }
        return [ResourceDeployment(resource: self, zoneName: zoneName, quantity: deployedQuantity, locationDesc: locationDesc)]
    }
}

private struct ResourceAllocation {
    let zoneName: String
    let quantity: Int
    let assignedTo: String
    let locationDesc: String

    init(_ dict: [String: Any]) {
        self.zoneName = stringValue(dict["assigned_zone"])
        self.quantity = max(1, intValue(dict["quantity"], fallback: 1))
        self.assignedTo = stringValue(dict["assigned_to"])
        self.locationDesc = stringValue(dict["location_desc"])
    }
}

private struct ResourceDeployment: Identifiable {
    let id: String
    let resourceID: String
    let resourceName: String
    let resourceType: String
    let zoneName: String
    let quantity: Int
    let locationDesc: String

    init(resource: ManagedResource, zoneName: String, quantity: Int, locationDesc: String) {
        self.id = "\(resource.resourceID)-\(zoneName)"
        self.resourceID = resource.resourceID
        self.resourceName = resource.name
        self.resourceType = resource.type
        self.zoneName = zoneName
        self.quantity = quantity
        self.locationDesc = locationDesc
    }
}

private func intValue(_ value: Any?, fallback: Int = 0) -> Int {
    if let int = value as? Int { return int }
    if let double = value as? Double { return Int(double) }
    if let string = value as? String, let int = Int(string) { return int }
    return fallback
}

private func stringValue(_ value: Any?, fallback: String = "") -> String {
    if let string = value as? String { return string }
    if let value { return "\(value)" }
    return fallback
}
