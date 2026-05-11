import SwiftUI

// MARK: - Splash Screen

struct SplashView: View {
    let onComplete: () -> Void

    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.85
    @State private var progress: CGFloat = 0
    @State private var subtitleText = "INITIALIZING..."
    @State private var glowPulse = false

    var body: some View {
        ZStack {
            // 深色背景（消除白閃）
            NV.bg.ignoresSafeArea()

            // 掃描線紋理
            ScanlineOverlay()
                .opacity(0.04)
                .ignoresSafeArea()

            // 四角瞄準框
            CornerBrackets()
                .opacity(logoOpacity)

            // 中央內容
            VStack(spacing: 20) {
                Spacer()

                // Logo
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .scaleEffect(glowPulse ? 1.08 : 1.0)
                    .shadow(color: NV.green.opacity(0.6), radius: glowPulse ? 20 : 8)
                    .animation(.easeInOut(duration: 0.6), value: glowPulse)

                // 主標題
                Text("LINKGUARD")
                    .font(.system(.largeTitle, design: .monospaced).bold())
                    .foregroundColor(NV.green)
                    .tracking(6)

                // 副標題（動畫切換文字）
                Text(subtitleText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(NV.greenDim)
                    .tracking(2)
                    .contentTransition(.opacity)

                // 版本資訊
                Text("SYSTEM INIT v1.0  |  EMT-RESCUE NODE")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(NV.greenFaint)
                    .tracking(1)

                Spacer()

                // 進度條
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(NV.greenFaint)
                                .frame(height: 2)
                            Rectangle()
                                .fill(NV.green)
                                .frame(width: geo.size.width * progress, height: 2)
                                .shadow(color: NV.green.opacity(0.8), radius: 4)
                        }
                    }
                    .frame(height: 2)
                    .padding(.horizontal, 40)

                    Text("BOOT SEQUENCE \(Int(progress * 100))%")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(NV.greenDim)
                }
                .padding(.bottom, 60)
            }
            .opacity(logoOpacity)
            .scaleEffect(logoScale)
        }
        .onAppear { startAnimation() }
    }

    private func startAnimation() {
        // Phase 1: 閃現
        withAnimation(.easeOut(duration: 0.15)) {
            logoOpacity = 1
            logoScale = 1.0
        }

        // Phase 2: 圖示脈衝 + 進度條開始
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            glowPulse = true
            withAnimation(.linear(duration: 1.5)) {
                progress = 1.0
            }
        }

        // Phase 3: 切換副標題
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.4)) {
                subtitleText = L("地震救援指揮系統")
            }
        }

        // Phase 4: 完成，通知淡出
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            onComplete()
        }
    }
}

// MARK: - 掃描線紋理

private struct ScanlineOverlay: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(NV.green)
                )
                y += 4
            }
        }
    }
}

// MARK: - 四角瞄準框

private struct CornerBrackets: View {
    private let bracketSize: CGFloat = 24
    private let thickness: CGFloat = 2
    private let pad: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 左上
                BracketShape(size: bracketSize, thickness: thickness)
                    .position(x: pad + bracketSize / 2, y: pad + bracketSize / 2)
                // 右上
                BracketShape(size: bracketSize, thickness: thickness)
                    .rotationEffect(.degrees(90))
                    .position(x: geo.size.width - pad - bracketSize / 2, y: pad + bracketSize / 2)
                // 左下
                BracketShape(size: bracketSize, thickness: thickness)
                    .rotationEffect(.degrees(270))
                    .position(x: pad + bracketSize / 2, y: geo.size.height - pad - bracketSize / 2)
                // 右下
                BracketShape(size: bracketSize, thickness: thickness)
                    .rotationEffect(.degrees(180))
                    .position(x: geo.size.width - pad - bracketSize / 2,
                              y: geo.size.height - pad - bracketSize / 2)
            }
        }
        .foregroundColor(NV.greenDim)
    }
}

private struct BracketShape: View {
    let size: CGFloat
    let thickness: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().frame(width: size, height: thickness)
            Rectangle().frame(width: thickness, height: size)
        }
    }
}

// MARK: - Preview

#Preview {
    SplashView(onComplete: {})
        .preferredColorScheme(.dark)
}
