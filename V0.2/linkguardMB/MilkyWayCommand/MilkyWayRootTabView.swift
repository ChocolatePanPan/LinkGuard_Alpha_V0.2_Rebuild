import SwiftUI

// MARK: - 根 TabView（6 個主功能，無 AI）

struct MilkyWayRootTabView: View {
    @ObservedObject var vm: MilkyWayCommandViewModel

    var body: some View {
        TabView {
            Tab("戰情橋", systemImage: "command") {
                MilkyWayCommandCenterView(vm: vm)
            }
            Tab("醫療轉運", systemImage: "cross.case.fill") {
                MWHospitalTab()
            }
            Tab("通訊中繼", systemImage: "antenna.radiowaves.left.and.right") {
                MWRadioTab(vm: vm)
            }
            Tab("傷患收容", systemImage: "stethoscope") {
                MWPatientTab()
            }
            Tab("備援接管", systemImage: "arrow.triangle.2.circlepath.circle.fill") {
                MWBackupServerTab(vm: vm)
            }
            Tab("影像回報", systemImage: "camera.fill") {
                MWPhotoTab()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(MWTheme.green)
        .preferredColorScheme(.dark)
    }
}
