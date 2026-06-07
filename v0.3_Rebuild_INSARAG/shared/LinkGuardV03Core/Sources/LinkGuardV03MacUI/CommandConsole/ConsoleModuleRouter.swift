import SwiftUI
import LinkGuardV03Core

/// Routes a console module to its v0.3 body. Every body is backed by the live
/// `OperationSnapshot` exposed through `MacSystemUIState`.
struct ConsoleModuleRouter: View {
    let module: CommandConsoleModule
    let state: MacSystemUIState

    var body: some View {
        switch module.kind {
        // Shared
        case .radioMonitoring: RadioMonitoringModule(state: state)
        case .eventLog: EventLogModule(state: state)
        case .deviceSync: DeviceSyncModule(state: state)
        case .aarReplay: AARReplayModule(state: state)

        // UCC
        case .identityAccess: IdentityAccessModule(state: state)
        case .globalDashboard: GlobalDashboardModule(state: state)
        case .multiDisasterMap: MultiDisasterMapModule(state: state)
        case .icsArchitecture: ICSArchitectureModule(state: state)
        case .globalSOS: GlobalSOSModule(state: state)
        case .casualtyStatistics: CasualtyStatisticsModule(state: state)
        case .aiStrategy: AIStrategyModule(state: state)
        case .heatmap: HeatmapModule(state: state)
        case .resourceManagement: ResourceManagementModule(state: state)
        case .emtDispatch: EMTDispatchModule(state: state)
        case .heavyTeamDispatch: HeavyTeamDispatchModule(state: state)
        case .uavManagement: UAVManagementModule(state: state)
        case .pwsIntegration: PWSIntegrationModule(state: state)
        case .emicIntegration: EMICIntegrationModule(state: state)
        case .multiSCCMonitor: MultiSCCMonitorModule(state: state)
        case .aiRiskPrediction: AIRiskPredictionModule(state: state)

        // SCC
        case .fieldSituationMap: FieldSituationMapModule(state: state)
        case .mapMarkup: MapMarkupModule(state: state)
        case .sectorManagement: SectorManagementModule(state: state)
        case .subSectorManagement: SubSectorManagementModule(state: state)
        case .searchStatusLayer: SearchStatusLayerModule(state: state)
        case .hazardZoneManagement: HazardZoneModule(state: state)
        case .personnelTracking: PersonnelTrackingModule(state: state)
        case .fieldSOS: FieldSOSModule(state: state)
        case .taskDispatch: TaskDispatchModule(state: state)
        case .personnelAssignment: PersonnelAssignmentModule(state: state)
        case .teamCapability: TeamCapabilityModule(state: state)
        case .patientManagement: PatientManagementModule(state: state)
        case .startTriage: StartTriageModule(state: state)
        case .photoWall: PhotoWallModule(state: state)
        case .temporaryBase: TemporaryBaseModule(state: state)
        case .accessControl: AccessControlModule(state: state)
        case .aiDecisionSupport: AIDecisionSupportModule(state: state)
        case .loraIntegration: LoRaIntegrationModule(state: state)
        case .offlineMode: OfflineModeModule(state: state)
        }
    }
}

// MARK: - Shared module convenience

/// Common base helpers available to every module view.
protocol ConsoleModule: View {
    var state: MacSystemUIState { get }
}

extension ConsoleModule {
    var snapshot: OperationSnapshot { state.runtime.snapshot }
    var appID: LinkGuardAppID { state.runtime.device.appID }
    var primaryIncident: Incident? {
        snapshot.incidents.values.sorted { $0.createdAt > $1.createdAt }.first
    }
}
