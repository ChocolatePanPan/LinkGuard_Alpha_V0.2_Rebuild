import XCTest
@testable import LinkGuardV03Core
@testable import LinkGuardV03FieldUI

@MainActor
final class MapMarkupViewModelTests: XCTestCase {
    func testCommitPointDraftCreatesMapFeature() {
        let vm = MapMarkupViewModel()
        vm.drawingMode = .point

        vm.beginDraft(at: MapCoordinate(latitude: 25.03, longitude: 121.56))
        let created = vm.commitDraft(
            incidentID: LinkGuardID("INC-1"),
            sectionID: .sectionA,
            searchState: .searching,
            title: "SOS 點",
            createdBy: LinkGuardID("DEVICE-1"),
            pointType: .sos,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertNotNil(created)
        XCTAssertEqual(vm.features.count, 1)
        XCTAssertEqual(vm.features.first?.title, "SOS 點")
    }

    func testPolylineDraftRequiresAtLeastTwoPoints() {
        let vm = MapMarkupViewModel()
        vm.drawingMode = .polyline
        vm.beginDraft(at: MapCoordinate(latitude: 25.0, longitude: 121.0))

        let firstAttempt = vm.commitDraft(
            incidentID: LinkGuardID("INC-1"),
            sectionID: .sectionA,
            searchState: .searching,
            title: "線",
            createdBy: LinkGuardID("DEVICE-1")
        )
        XCTAssertNil(firstAttempt)

        vm.appendDraftPoint(MapCoordinate(latitude: 25.1, longitude: 121.1))
        let secondAttempt = vm.commitDraft(
            incidentID: LinkGuardID("INC-1"),
            sectionID: .sectionA,
            searchState: .searching,
            title: "線",
            createdBy: LinkGuardID("DEVICE-1")
        )
        XCTAssertNotNil(secondAttempt)
        XCTAssertEqual(vm.features.count, 1)
    }

    func testUndoRedoForFeatureOperations() {
        let vm = MapMarkupViewModel()
        vm.drawingMode = .point
        vm.beginDraft(at: MapCoordinate(latitude: 24.9, longitude: 121.2))
        _ = vm.commitDraft(
            incidentID: LinkGuardID("INC-2"),
            sectionID: .sectionB,
            searchState: .unconfirmed,
            title: "點1",
            createdBy: LinkGuardID("DEVICE-2")
        )

        XCTAssertEqual(vm.features.count, 1)
        XCTAssertTrue(vm.canUndo)

        vm.undo()
        XCTAssertEqual(vm.features.count, 0)
        XCTAssertTrue(vm.canRedo)

        vm.redo()
        XCTAssertEqual(vm.features.count, 1)
    }

    func testToggleLayerVisibility() {
        let vm = MapMarkupViewModel()
        XCTAssertTrue(vm.visibleLayers.contains(.polygon))

        vm.toggleLayer(.polygon)
        XCTAssertFalse(vm.visibleLayers.contains(.polygon))

        vm.toggleLayer(.polygon)
        XCTAssertTrue(vm.visibleLayers.contains(.polygon))
    }
}
