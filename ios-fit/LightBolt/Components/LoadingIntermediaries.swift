import SwiftUI

/// Bespoke replacement for the system spinner: a row of volt bars that runs
/// like a wave. Used inside buttons and compact inline states.
struct RunningWaveLoader: View {
    var barCount: Int = 5
    var height: CGFloat = 18
    var tint: Color = LightBoltTheme.volt

    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: 3, height: barHeight(for: index))
            }
        }
        .frame(height: height, alignment: .center)
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let offset = Double(index) / Double(barCount)
        let wave = sin((phase + offset) * 2 * .pi)
        return height * (0.35 + 0.65 * (0.5 + 0.5 * wave))
    }
}

/// Pulsing charcoal block — the skeleton primitive for all async layouts.
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var radius: CGFloat = 10

    @State private var isPulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LightBoltTheme.charcoal)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LightBoltTheme.charcoalHigh)
                    .opacity(isPulsing ? 0.95 : 0.25)
            )
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
            .onAppear {
                withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

/// A single volt line sweeping left→right across a track. Used as a
/// determinate-looking header loader while server work is in flight.
struct VoltSweepLine: View {
    @State private var travel: CGFloat = -0.4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LightBoltTheme.charcoalHigh)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, LightBoltTheme.volt, LightBoltTheme.voltSoft, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * 0.45)
                    .offset(x: travel * geo.size.width)
            }
        }
        .frame(height: 3)
        .clipShape(Capsule())
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: false)) {
                travel = 1.05
            }
        }
    }
}

/// Skeleton stand-in for a meal analysis card while the server responds.
struct MealAnalysisSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SkeletonBlock(width: 150, height: 22, radius: 6)
                Spacer()
                SkeletonBlock(width: 54, height: 22, radius: 6)
            }
            VoltSweepLine()
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonBlock(height: 58, radius: 14)
                }
            }
            EyebrowText(text: "Reading your plate", color: LightBoltTheme.voltDim)
        }
        .padding(18)
        .fitCard()
    }
}
