import LinkGuardV03Core
import Foundation
import SwiftUI

public enum MapDrawingMode: String, CaseIterable, Identifiable, Sendable {
    case select
    case point
    case polyline
    case polygon

    public var id: String { rawValue }
}

public struct MapDraftGeometry: Equatable, Sendable {
    public var mode: MapDrawingMode
    public var coordinates: [MapCoordinate]

    public init(mode: MapDrawingMode, coordinates: [MapCoordinate]) {
        self.mode = mode
        self.coordinates = coordinates
    }
}

@MainActor
public final class MapMarkupViewModel: ObservableObject {
    @Published public private(set) var features: [MapMarkupFeature]
    @Published public var drawingMode: MapDrawingMode
    @Published public var visibleLayers: Set<MapDrawingMode>
    @Published public private(set) var selectedFeatureID: LinkGuardID?
    @Published public private(set) var draftGeometry: MapDraftGeometry?

    private var undoStack: [[MapMarkupFeature]] = []
    private var redoStack: [[MapMarkupFeature]] = []

    public init(features: [MapMarkupFeature] = []) {
        self.features = features
        self.drawingMode = .select
        self.visibleLayers = [.point, .polyline, .polygon]
        self.selectedFeatureID = nil
        self.draftGeometry = nil
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func beginDraft(at coordinate: MapCoordinate) {
        switch drawingMode {
        case .select:
            return
        case .point:
            draftGeometry = MapDraftGeometry(mode: .point, coordinates: [coordinate])
        case .polyline:
            draftGeometry = MapDraftGeometry(mode: .polyline, coordinates: [coordinate])
        case .polygon:
            draftGeometry = MapDraftGeometry(mode: .polygon, coordinates: [coordinate])
        }
    }

    public func appendDraftPoint(_ coordinate: MapCoordinate) {
        guard var draft = draftGeometry else { return }
        switch draft.mode {
        case .point:
            draft.coordinates = [coordinate]
        case .polyline, .polygon:
            draft.coordinates.append(coordinate)
        case .select:
            return
        }
        draftGeometry = draft
    }

    public func updateDraftPreview(_ coordinate: MapCoordinate) {
        guard var draft = draftGeometry else { return }
        guard !draft.coordinates.isEmpty else { return }

        switch draft.mode {
        case .polyline, .polygon:
            draft.coordinates[draft.coordinates.count - 1] = coordinate
            draftGeometry = draft
        case .point, .select:
            break
        }
    }

    public func cancelDraft() {
        draftGeometry = nil
    }

    public func selectFeature(_ featureID: LinkGuardID?) {
        selectedFeatureID = featureID
    }

    public func deleteSelectedFeature() {
        guard let selectedFeatureID else { return }
        pushUndoSnapshot()
        features.removeAll { $0.id == selectedFeatureID }
        self.selectedFeatureID = nil
    }

    public func toggleLayer(_ mode: MapDrawingMode) {
        guard mode != .select else { return }
        if visibleLayers.contains(mode) {
            visibleLayers.remove(mode)
        } else {
            visibleLayers.insert(mode)
        }
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(features)
        features = previous
        selectedFeatureID = nil
        draftGeometry = nil
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(features)
        features = next
        selectedFeatureID = nil
        draftGeometry = nil
    }

    @discardableResult
    public func commitDraft(
        incidentID: LinkGuardID,
        sectionID: ICSMapArea,
        searchState: SearchState,
        title: String,
        createdBy: LinkGuardID,
        pointType: MapPointType = .hazardPoint,
        lineType: MapLineType = .searchPath,
        polygonType: MapPolygonType = .searchArea,
        now: Date = Date()
    ) -> MapMarkupFeature? {
        guard let draft = draftGeometry else { return nil }

        let geometry: MapMarkupFeature.MarkupGeometry
        switch draft.mode {
        case .point:
            guard let point = draft.coordinates.first else { return nil }
            geometry = .point(pointType, point.latitude, point.longitude)
        case .polyline:
            guard draft.coordinates.count >= 2 else { return nil }
            geometry = .line(lineType, draft.coordinates)
        case .polygon:
            guard draft.coordinates.count >= 3 else { return nil }
            geometry = .polygon(polygonType, draft.coordinates)
        case .select:
            return nil
        }

        pushUndoSnapshot()
        let feature = MapMarkupFeature(
            incidentID: incidentID,
            sectionID: sectionID,
            geometry: geometry,
            searchState: searchState,
            title: title,
            createdBy: createdBy,
            createdAt: now,
            updatedAt: now
        )
        features.append(feature)
        selectedFeatureID = feature.id
        draftGeometry = nil
        return feature
    }

    private func pushUndoSnapshot() {
        undoStack.append(features)
        redoStack.removeAll()
    }
}
