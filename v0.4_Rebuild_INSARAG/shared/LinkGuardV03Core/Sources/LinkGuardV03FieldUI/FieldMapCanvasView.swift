import LinkGuardV03Core
import SwiftUI

public struct FieldMapCanvasView: View {
    public var features: [MapMarkupFeature]
    public var draftGeometry: MapDraftGeometry?
    public var onTapCoordinate: (MapCoordinate) -> Void

    public init(
        features: [MapMarkupFeature],
        draftGeometry: MapDraftGeometry?,
        onTapCoordinate: @escaping (MapCoordinate) -> Void
    ) {
        self.features = features
        self.draftGeometry = draftGeometry
        self.onTapCoordinate = onTapCoordinate
    }

    public var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                drawFeatures(context: context, size: size)
                drawDraft(context: context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let coordinate = mapCoordinate(from: value.location, in: proxy.size)
                        onTapCoordinate(coordinate)
                    }
            )
            .background(Color.black.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topLeading) {
                Text("Tactical Map")
                    .font(.caption.weight(.semibold))
                    .padding(8)
                    .background(Color.black.opacity(0.35), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(10)
            }
        }
    }

    private func drawFeatures(context: GraphicsContext, size: CGSize) {
        for feature in features {
            switch feature.geometry {
            case .point(_, let lat, let lon):
                let p = pointFromCoordinate(MapCoordinate(latitude: lat, longitude: lon), size: size)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.red))
            case .line(_, let coordinates):
                guard coordinates.count >= 2 else { continue }
                var path = Path()
                for (idx, coordinate) in coordinates.enumerated() {
                    let p = pointFromCoordinate(coordinate, size: size)
                    if idx == 0 {
                        path.move(to: p)
                    } else {
                        path.addLine(to: p)
                    }
                }
                context.stroke(path, with: .color(.cyan), lineWidth: 2)
            case .polygon(_, let coordinates):
                guard coordinates.count >= 3 else { continue }
                var path = Path()
                for (idx, coordinate) in coordinates.enumerated() {
                    let p = pointFromCoordinate(coordinate, size: size)
                    if idx == 0 {
                        path.move(to: p)
                    } else {
                        path.addLine(to: p)
                    }
                }
                path.closeSubpath()
                context.fill(path, with: .color(.yellow.opacity(0.28)))
                context.stroke(path, with: .color(.yellow), lineWidth: 2)
            }
        }
    }

    private func drawDraft(context: GraphicsContext, size: CGSize) {
        guard let draftGeometry else { return }
        let points = draftGeometry.coordinates.map { pointFromCoordinate($0, size: size) }
        guard points.isEmpty == false else { return }

        var path = Path()
        for (idx, point) in points.enumerated() {
            if idx == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        if draftGeometry.mode == .polygon, points.count >= 3 {
            path.closeSubpath()
        }
        context.stroke(path, with: .color(.green), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

        for point in points {
            context.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)), with: .color(.green))
        }
    }

    private func mapCoordinate(from point: CGPoint, in size: CGSize) -> MapCoordinate {
        let latitude = max(-90, min(90, 90 - (point.y / max(size.height, 1)) * 180))
        let longitude = max(-180, min(180, (point.x / max(size.width, 1)) * 360 - 180))
        return MapCoordinate(latitude: latitude, longitude: longitude)
    }

    private func pointFromCoordinate(_ coordinate: MapCoordinate, size: CGSize) -> CGPoint {
        let x = ((coordinate.longitude + 180) / 360) * size.width
        let y = ((90 - coordinate.latitude) / 180) * size.height
        return CGPoint(x: x, y: y)
    }
}
