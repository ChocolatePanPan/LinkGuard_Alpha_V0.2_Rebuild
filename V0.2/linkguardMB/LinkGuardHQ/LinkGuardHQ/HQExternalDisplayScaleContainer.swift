import SwiftUI

struct HQExternalDisplayScaleContainer<Content: View>: View {
    let scale: Double
    @ViewBuilder var content: () -> Content

    private var clampedScale: CGFloat {
        CGFloat(min(max(scale, 0.8), 1.6))
    }

    var body: some View {
        GeometryReader { proxy in
            content()
                .frame(width: proxy.size.width / clampedScale,
                       height: proxy.size.height / clampedScale,
                       alignment: .topLeading)
                .scaleEffect(clampedScale, anchor: .topLeading)
                .frame(width: proxy.size.width,
                       height: proxy.size.height,
                       alignment: .topLeading)
                .clipped()
        }
    }
}
