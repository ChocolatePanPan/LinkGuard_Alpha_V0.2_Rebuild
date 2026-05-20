import Foundation

private enum HQTeamCapabilityDateFormatters {
    static let hhmmss: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        return formatter
    }()
}

struct TeamCapabilityReport: Codable, Identifiable, Equatable {
    let id: String
    var usarTeamCode: String?
    var country: String?
    var teamName: String
    var unitCode: String
    var leaderName: String
    var contactPhone: String
    var currentLocation: String
    var stagingArea: String
    var missionStatus: String
    var totalMembers: Int
    var rescueMembers: Int
    var medicalMembers: Int
    var logisticsMembers: Int
    var availableInMinutes: Int
    var operationalHours: Int
    var selfSufficiencyHours: Int
    var ambulances: Int
    var rescueVehicles: Int
    var heavyEquipment: Int
    var boats: Int
    var drones: Int
    var radios: Int
    var capabilities: [String]
    var equipmentNotes: String
    var supportNeeds: String
    var remarks: String
    var searchDogCount: Int?
    var responseType: String?
    var classificationStatus: String?
    var hasTechnicalSearch: Bool?
    var hasDogSearch: Bool?
    var hasRescueCapability: Bool?
    var hasMedicalCapability: Bool?
    var hasHazmatDetection: Bool?
    var structuralEngineerCount: Int?
    var canEstablishOSOCCRDC: Bool?
    var canSupportUSARCoordination: Bool?
    var otherCapabilities: String?
    var arrivalDate: String?
    var arrivalTime: String?
    var arrivalPoint: String?
    var aircraftType: String?
    var waterDays: Int?
    var foodDays: Int?
    var needsGroundTransport: Bool?
    var needsLogisticsSupport: Bool?
    var transportPersonnelCount: Int?
    var transportDogCount: Int?
    var equipmentWeightTons: Double?
    var equipmentVolumeCubicMeters: Double?
    var dailyGasolineLiters: Double?
    var dailyDieselLiters: Double?
    var needsCuttingOxygen: Bool?
    var needsCuttingPropane: Bool?
    var needsMedicalOxygen: Bool?
    var baseAreaSquareMeters: Double?
    var otherLogisticsNeeds: String?
    var teamContactNameOrRole: String?
    var teamContactMobile: String?
    var teamContactSatellite: String?
    var teamContactEmail: String?
    var operationsContactNameOrTitle: String?
    var operationsContactMobile: String?
    var operationsContactEmail: String?
    var policyContactNameOrTitle: String?
    var policyContactMobile: String?
    var policyContactEmail: String?
    var baseLocationAddress: String?
    var baseRadioFrequencyMHz: String?
    var baseGPSCoordinates: String?
    var evacuationDate: String?
    var evacuationTime: String?
    var evacuationPoint: String?
    var departureTransportInfo: String?
    var evacuationNeedsGroundTransport: Bool?
    var evacuationNeedsLogisticsSupport: Bool?
    var evacuationTransportPersonnelCount: Int?
    var evacuationTransportDogCount: Int?
    var evacuationEquipmentWeightTons: Double?
    var evacuationEquipmentVolumeCubicMeters: Double?
    var loadingAssistanceNeeds: String?
    var evacuationTemporaryAccommodationNeeds: String?
    var evacuationOtherInfo: String?
    var reporterID: String
    var reporterName: String
    var timestamp: Double

    init(
        id: String = UUID().uuidString,
        usarTeamCode: String? = nil,
        country: String? = nil,
        teamName: String,
        unitCode: String,
        leaderName: String,
        contactPhone: String,
        currentLocation: String,
        stagingArea: String,
        missionStatus: String,
        totalMembers: Int,
        rescueMembers: Int,
        medicalMembers: Int,
        logisticsMembers: Int,
        availableInMinutes: Int,
        operationalHours: Int,
        selfSufficiencyHours: Int,
        ambulances: Int,
        rescueVehicles: Int,
        heavyEquipment: Int,
        boats: Int,
        drones: Int,
        radios: Int,
        capabilities: [String],
        equipmentNotes: String,
        supportNeeds: String,
        remarks: String,
        searchDogCount: Int? = nil,
        responseType: String? = nil,
        classificationStatus: String? = nil,
        hasTechnicalSearch: Bool? = nil,
        hasDogSearch: Bool? = nil,
        hasRescueCapability: Bool? = nil,
        hasMedicalCapability: Bool? = nil,
        hasHazmatDetection: Bool? = nil,
        structuralEngineerCount: Int? = nil,
        canEstablishOSOCCRDC: Bool? = nil,
        canSupportUSARCoordination: Bool? = nil,
        otherCapabilities: String? = nil,
        arrivalDate: String? = nil,
        arrivalTime: String? = nil,
        arrivalPoint: String? = nil,
        aircraftType: String? = nil,
        waterDays: Int? = nil,
        foodDays: Int? = nil,
        needsGroundTransport: Bool? = nil,
        needsLogisticsSupport: Bool? = nil,
        transportPersonnelCount: Int? = nil,
        transportDogCount: Int? = nil,
        equipmentWeightTons: Double? = nil,
        equipmentVolumeCubicMeters: Double? = nil,
        dailyGasolineLiters: Double? = nil,
        dailyDieselLiters: Double? = nil,
        needsCuttingOxygen: Bool? = nil,
        needsCuttingPropane: Bool? = nil,
        needsMedicalOxygen: Bool? = nil,
        baseAreaSquareMeters: Double? = nil,
        otherLogisticsNeeds: String? = nil,
        teamContactNameOrRole: String? = nil,
        teamContactMobile: String? = nil,
        teamContactSatellite: String? = nil,
        teamContactEmail: String? = nil,
        operationsContactNameOrTitle: String? = nil,
        operationsContactMobile: String? = nil,
        operationsContactEmail: String? = nil,
        policyContactNameOrTitle: String? = nil,
        policyContactMobile: String? = nil,
        policyContactEmail: String? = nil,
        baseLocationAddress: String? = nil,
        baseRadioFrequencyMHz: String? = nil,
        baseGPSCoordinates: String? = nil,
        evacuationDate: String? = nil,
        evacuationTime: String? = nil,
        evacuationPoint: String? = nil,
        departureTransportInfo: String? = nil,
        evacuationNeedsGroundTransport: Bool? = nil,
        evacuationNeedsLogisticsSupport: Bool? = nil,
        evacuationTransportPersonnelCount: Int? = nil,
        evacuationTransportDogCount: Int? = nil,
        evacuationEquipmentWeightTons: Double? = nil,
        evacuationEquipmentVolumeCubicMeters: Double? = nil,
        loadingAssistanceNeeds: String? = nil,
        evacuationTemporaryAccommodationNeeds: String? = nil,
        evacuationOtherInfo: String? = nil,
        reporterID: String,
        reporterName: String,
        timestamp: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.usarTeamCode = usarTeamCode
        self.country = country
        self.teamName = teamName
        self.unitCode = unitCode
        self.leaderName = leaderName
        self.contactPhone = contactPhone
        self.currentLocation = currentLocation
        self.stagingArea = stagingArea
        self.missionStatus = missionStatus
        self.totalMembers = totalMembers
        self.rescueMembers = rescueMembers
        self.medicalMembers = medicalMembers
        self.logisticsMembers = logisticsMembers
        self.availableInMinutes = availableInMinutes
        self.operationalHours = operationalHours
        self.selfSufficiencyHours = selfSufficiencyHours
        self.ambulances = ambulances
        self.rescueVehicles = rescueVehicles
        self.heavyEquipment = heavyEquipment
        self.boats = boats
        self.drones = drones
        self.radios = radios
        self.capabilities = capabilities
        self.equipmentNotes = equipmentNotes
        self.supportNeeds = supportNeeds
        self.remarks = remarks
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
        self.evacuationDate = evacuationDate
        self.evacuationTime = evacuationTime
        self.evacuationPoint = evacuationPoint
        self.departureTransportInfo = departureTransportInfo
        self.evacuationNeedsGroundTransport = evacuationNeedsGroundTransport
        self.evacuationNeedsLogisticsSupport = evacuationNeedsLogisticsSupport
        self.evacuationTransportPersonnelCount = evacuationTransportPersonnelCount
        self.evacuationTransportDogCount = evacuationTransportDogCount
        self.evacuationEquipmentWeightTons = evacuationEquipmentWeightTons
        self.evacuationEquipmentVolumeCubicMeters = evacuationEquipmentVolumeCubicMeters
        self.loadingAssistanceNeeds = loadingAssistanceNeeds
        self.evacuationTemporaryAccommodationNeeds = evacuationTemporaryAccommodationNeeds
        self.evacuationOtherInfo = evacuationOtherInfo
        self.reporterID = reporterID
        self.reporterName = reporterName
        self.timestamp = timestamp
    }

    var personnelSummary: String {
        "出隊 \(totalMembers) · 搜救犬 \(searchDogCount ?? 0)"
    }

    var responseSummary: String {
        [responseType, classificationStatus].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }.joined(separator: " · ")
    }

    var capabilitySummary: String {
        var items: [String] = []
        if hasTechnicalSearch == true { items.append("技術搜索") }
        if hasDogSearch == true { items.append("犬搜索") }
        if hasRescueCapability == true { items.append("營救") }
        if hasMedicalCapability == true { items.append("醫療") }
        if hasHazmatDetection == true { items.append("危險品偵檢") }
        if (structuralEngineerCount ?? 0) > 0 { items.append("結構工程師 \(structuralEngineerCount ?? 0)") }
        if canEstablishOSOCCRDC == true { items.append("OSOCC/RDC") }
        if canSupportUSARCoordination == true { items.append("USAR 協調支援") }
        if let other = otherCapabilities?.trimmingCharacters(in: .whitespacesAndNewlines), !other.isEmpty { items.append(other) }
        if items.isEmpty { items = capabilities }
        return items.isEmpty ? "未填寫能力項目" : items.joined(separator: "、")
    }

    var timeText: String {
        HQTeamCapabilityDateFormatters.hhmmss.string(from: Date(timeIntervalSince1970: timestamp))
    }
}