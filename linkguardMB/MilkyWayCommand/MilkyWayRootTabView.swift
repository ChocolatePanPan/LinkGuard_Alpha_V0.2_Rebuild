import SwiftUI

// MARK: - 根 TabView（6 個主功能，無 AI）

struct MilkyWayRootTabView: View {
    @ObservedObject var vm: MilkyWayCommandViewModel

    var body: some View {
        TabView {
            Tab("指揮中心", systemImage: "sparkles") {
                MilkyWayCommandCenterView(vm: vm)
            }
            Tab("後送醫院", systemImage: "cross.case.fill") {
                MWHospitalTab()
            }
            Tab("電台通訊", systemImage: "antenna.radiowaves.left.and.right") {
                MWRadioTab(vm: vm)
            }
            Tab("傷患表單", systemImage: "stethoscope") {
                MWPatientTab()
            }
            Tab("替代伺服器", systemImage: "server.rack") {
                MWBackupServerTab(vm: vm)
            }
            Tab("照片報告", systemImage: "camera.fill") {
                MWPhotoTab()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(MWTheme.green)
        .preferredColorScheme(.dark)
    }
}
