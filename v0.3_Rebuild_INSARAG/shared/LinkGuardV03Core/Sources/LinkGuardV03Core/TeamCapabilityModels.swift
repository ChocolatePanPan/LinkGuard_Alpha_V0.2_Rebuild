import Foundation

public enum USARTeamResponseType: String, Codable, CaseIterable, Sendable {
    case light
    case medium
    case heavy
    case other

    public var displayName: String {
        switch self {
        case .light: return "輕型"
        case .medium: return "中型"
        case .heavy: return "重型"
        case .other: return "其他"
        }
    }
}

public enum USARTeamClassificationStatus: String, Codable, CaseIterable, Sendable {
    case classified
    case notClassified
    case unclassified
    case reclassificationInProgress

    public var displayName: String {
        switch self {
        case .classified: return "已通過分級測評"
        case .notClassified: return "未通過分級測評"
        case .unclassified: return "未分級"
        case .reclassificationInProgress: return "重新分級中"
        }
    }
}

public struct USARTeamInformationSection: Codable, Hashable, Sendable {
    public var teamCode: String
    public var country: String
    public var teamName: String
    public var totalMembers: Int
    public var searchDogCount: Int
    public var responseType: USARTeamResponseType
    public var classificationStatus: USARTeamClassificationStatus
    public var hasTechnicalSearch: Bool
    public var hasDogSearch: Bool
    public var hasRescueCapability: Bool
    public var hasMedicalCapability: Bool
    public var hasHazmatDetection: Bool
    public var structuralEngineerCount: Int
    public var canEstablishOSOCCRDC: Bool
    public var canSupportUSARCoordination: Bool
    public var otherCapabilities: String
    public var arrivalDate: String
    public var arrivalTime: String
    public var arrivalPoint: String
    public var aircraftType: String

    public init(
        teamCode: String,
        country: String,
        teamName: String,
        totalMembers: Int,
        searchDogCount: Int = 0,
        responseType: USARTeamResponseType = .medium,
        classificationStatus: USARTeamClassificationStatus = .classified,
        hasTechnicalSearch: Bool = true,
        hasDogSearch: Bool = false,
        hasRescueCapability: Bool = true,
        hasMedicalCapability: Bool = true,
        hasHazmatDetection: Bool = false,
        structuralEngineerCount: Int = 0,
        canEstablishOSOCCRDC: Bool = false,
        canSupportUSARCoordination: Bool = false,
        otherCapabilities: String = "",
        arrivalDate: String = "",
        arrivalTime: String = "",
        arrivalPoint: String = "",
        aircraftType: String = ""
    ) {
        self.teamCode = teamCode
        self.country = country
        self.teamName = teamName
        self.totalMembers = totalMembers
        self.searchDogCount = searchDogCount
        self.responseType = responseType
        self.classificationStatus = classificationStatus
        self.hasTechnicalSearch = hasTechnicalSearch
        self.hasDogSearch = hasDogSearch
        self.hasRescueCapability = hasRescueCapability
        self.hasMedicalCapability = hasMedicalCapability
        self.hasHazmatDetection = hasHazmatDetection
        self.structuralEngineerCount = structuralEngineerCount
        self.canEstablishOSOCCRDC = canEstablishOSOCCRDC
        self.canSupportUSARCoordination = canSupportUSARCoordination
        self.otherCapabilities = otherCapabilities
        self.arrivalDate = arrivalDate
        self.arrivalTime = arrivalTime
        self.arrivalPoint = arrivalPoint
        self.aircraftType = aircraftType
    }
}

public struct USARTeamSupportNeedsSection: Codable, Hashable, Sendable {
    public var waterDays: Int
    public var foodDays: Int
    public var needsGroundTransport: Bool
    public var needsLogisticsSupport: Bool
    public var transportPersonnelCount: Int
    public var transportDogCount: Int
    public var equipmentWeightTons: Double
    public var equipmentVolumeCubicMeters: Double
    public var dailyGasolineLiters: Double
    public var dailyDieselLiters: Double
    public var needsCuttingOxygen: Bool
    public var needsCuttingPropane: Bool
    public var needsMedicalOxygen: Bool
    public var baseAreaSquareMeters: Double
    public var otherLogisticsNeeds: String

    public init(
        waterDays: Int = 0,
        foodDays: Int = 0,
        needsGroundTransport: Bool = false,
        needsLogisticsSupport: Bool = false,
        transportPersonnelCount: Int = 0,
        transportDogCount: Int = 0,
        equipmentWeightTons: Double = 0,
        equipmentVolumeCubicMeters: Double = 0,
        dailyGasolineLiters: Double = 0,
        dailyDieselLiters: Double = 0,
        needsCuttingOxygen: Bool = false,
        needsCuttingPropane: Bool = false,
        needsMedicalOxygen: Bool = false,
        baseAreaSquareMeters: Double = 0,
        otherLogisticsNeeds: String = ""
    ) {
        self.waterDays = waterDays
        self.foodDays = foodDays
        self.needsGroundTransport = needsGroundTransport
        self.needsLogisticsSupport = needsLogisticsSupport
        self.transportPersonnelCount = transportPersonnelCount
        self.transportDogCount = transportDogCount
        self.equipmentWeightTons = equipmentWeightTons
        self.equipmentVolumeCubicMeters = equipmentVolumeCubicMeters
        self.dailyGasolineLiters = dailyGasolineLiters
        self.dailyDieselLiters = dailyDieselLiters
        self.needsCuttingOxygen = needsCuttingOxygen
        self.needsCuttingPropane = needsCuttingPropane
        self.needsMedicalOxygen = needsMedicalOxygen
        self.baseAreaSquareMeters = baseAreaSquareMeters
        self.otherLogisticsNeeds = otherLogisticsNeeds
    }
}

public struct USARTeamContactsSection: Codable, Hashable, Sendable {
    public var teamContactNameOrRole: String
    public var teamContactMobile: String
    public var teamContactSatellite: String
    public var teamContactEmail: String
    public var operationsContactNameOrTitle: String
    public var operationsContactMobile: String
    public var operationsContactEmail: String
    public var policyContactNameOrTitle: String
    public var policyContactMobile: String
    public var policyContactEmail: String
    public var baseLocationAddress: String
    public var baseRadioFrequencyMHz: String
    public var baseGPSCoordinates: String

    public init(
        teamContactNameOrRole: String = "",
        teamContactMobile: String = "",
        teamContactSatellite: String = "",
        teamContactEmail: String = "",
        operationsContactNameOrTitle: String = "",
        operationsContactMobile: String = "",
        operationsContactEmail: String = "",
        policyContactNameOrTitle: String = "",
        policyContactMobile: String = "",
        policyContactEmail: String = "",
        baseLocationAddress: String = "",
        baseRadioFrequencyMHz: String = "",
        baseGPSCoordinates: String = ""
    ) {
        self.teamContactNameOrRole = teamContactNameOrRole
        self.teamContactMobile = teamContactMobile
        self.teamContactSatellite = teamContactSatellite
        self.teamContactEmail = teamContactEmail
        self.operationsContactNameOrTitle = operationsContactNameOrTitle
        self.operationsContactMobile = operationsContactMobile
        self.operationsContactEmail = operationsContactEmail
        self.policyContactNameOrTitle = policyContactNameOrTitle
        self.policyContactMobile = policyContactMobile
        self.policyContactEmail = policyContactEmail
        self.baseLocationAddress = baseLocationAddress
        self.baseRadioFrequencyMHz = baseRadioFrequencyMHz
        self.baseGPSCoordinates = baseGPSCoordinates
    }
}

public struct USARTeamEvacuationSection: Codable, Hashable, Sendable {
    public var evacuationDate: String
    public var evacuationTime: String
    public var evacuationPoint: String
    public var departureTransportInfo: String
    public var needsGroundTransport: Bool
    public var needsLogisticsSupport: Bool
    public var transportPersonnelCount: Int
    public var transportDogCount: Int
    public var equipmentWeightTons: Double
    public var equipmentVolumeCubicMeters: Double
    public var loadingAssistanceNeeds: String
    public var temporaryAccommodationNeeds: String
    public var otherInfoOrLogisticsNeeds: String

    public init(
        evacuationDate: String = "",
        evacuationTime: String = "",
        evacuationPoint: String = "",
        departureTransportInfo: String = "",
        needsGroundTransport: Bool = false,
        needsLogisticsSupport: Bool = false,
        transportPersonnelCount: Int = 0,
        transportDogCount: Int = 0,
        equipmentWeightTons: Double = 0,
        equipmentVolumeCubicMeters: Double = 0,
        loadingAssistanceNeeds: String = "",
        temporaryAccommodationNeeds: String = "",
        otherInfoOrLogisticsNeeds: String = ""
    ) {
        self.evacuationDate = evacuationDate
        self.evacuationTime = evacuationTime
        self.evacuationPoint = evacuationPoint
        self.departureTransportInfo = departureTransportInfo
        self.needsGroundTransport = needsGroundTransport
        self.needsLogisticsSupport = needsLogisticsSupport
        self.transportPersonnelCount = transportPersonnelCount
        self.transportDogCount = transportDogCount
        self.equipmentWeightTons = equipmentWeightTons
        self.equipmentVolumeCubicMeters = equipmentVolumeCubicMeters
        self.loadingAssistanceNeeds = loadingAssistanceNeeds
        self.temporaryAccommodationNeeds = temporaryAccommodationNeeds
        self.otherInfoOrLogisticsNeeds = otherInfoOrLogisticsNeeds
    }
}

public struct USARTeamCapabilityReport: Codable, Hashable, Identifiable, Sendable {
    public var id: LinkGuardID
    public var incidentID: LinkGuardID
    public var reporterDeviceID: LinkGuardID
    public var reporterName: String
    public var team: USARTeamInformationSection
    public var supportNeeds: USARTeamSupportNeedsSection
    public var contacts: USARTeamContactsSection
    public var evacuation: USARTeamEvacuationSection
    public var createdAt: Date

    public init(
        id: LinkGuardID = .generated(prefix: "USAR-TEAM-PROFILE"),
        incidentID: LinkGuardID,
        reporterDeviceID: LinkGuardID,
        reporterName: String,
        team: USARTeamInformationSection,
        supportNeeds: USARTeamSupportNeedsSection = USARTeamSupportNeedsSection(),
        contacts: USARTeamContactsSection = USARTeamContactsSection(),
        evacuation: USARTeamEvacuationSection = USARTeamEvacuationSection(),
        createdAt: Date
    ) {
        self.id = id
        self.incidentID = incidentID
        self.reporterDeviceID = reporterDeviceID
        self.reporterName = reporterName
        self.team = team
        self.supportNeeds = supportNeeds
        self.contacts = contacts
        self.evacuation = evacuation
        self.createdAt = createdAt
    }

    public var responseSummary: String {
        "\(team.responseType.displayName) · \(team.classificationStatus.displayName)"
    }

    public var personnelSummary: String {
        "出隊 \(team.totalMembers) · 搜救犬 \(team.searchDogCount)"
    }

    public var logisticsSummary: String {
        "裝備 \(format(supportNeeds.equipmentWeightTons))t / \(format(supportNeeds.equipmentVolumeCubicMeters))m³"
    }

    public var capabilitySummary: String {
        var items: [String] = []
        if team.hasTechnicalSearch { items.append("技術搜索") }
        if team.hasDogSearch { items.append("犬搜索") }
        if team.hasRescueCapability { items.append("營救") }
        if team.hasMedicalCapability { items.append("醫療") }
        if team.hasHazmatDetection { items.append("危險品偵檢") }
        if team.structuralEngineerCount > 0 { items.append("結構工程師 \(team.structuralEngineerCount)") }
        if team.canEstablishOSOCCRDC { items.append("OSOCC/RDC") }
        if team.canSupportUSARCoordination { items.append("USAR 協調支援") }
        if !team.otherCapabilities.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { items.append(team.otherCapabilities) }
        return items.isEmpty ? "未填寫能力項目" : items.joined(separator: "、")
    }

    private func format(_ value: Double) -> String {
        value == floor(value) ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}