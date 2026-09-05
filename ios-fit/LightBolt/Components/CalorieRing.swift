import SwiftUI

/// Circular calorie budget gauge: deep black track, animated volt overlay,
/// numeric hero readout in the middle.
struct CalorieRing: View {
    let consumed: Int
    let budget: Int
    var size: CGFloat = 236

    @State private var animatedFraction: CGFloat = 0

    private var fraction: CGFloat {
        guard budget > 0 else { return 0 }
        return min(1.35, CGFloat(consumed) / CGFloat(budget))
    }

    private var remaining: Int { budget - consumed }
    private var isOver: Bool { remaining < 0 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(LightBoltTheme.charcoal, lineWidth: 18)

            Circle()
                .stroke(LightBoltTheme.hairline, lineWidth: 1)
                .scaleEffect(0.855)

            Circle()
                .trim(from: 0, to: min(1, animatedFraction))
                .stroke(
                    AngularGradient(
                        colors: [LightBoltTheme.voltDim, LightBoltTheme.volt, LightBoltTheme.voltSoft, LightBoltTheme.volt],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: LightBoltTheme.volt.opacity(0.35), radius: 12)

            if animatedFraction > 1 {
                Circle()
                    .trim(from: 0, to: min(0.35, animatedFraction - 1))
                    .stroke(LightBoltTheme.alert, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(0.855)
            }

            VStack(spacing: 2) {
                EyebrowText(text: isOver ? "Over budget" : "Remaining", color: LightBoltTheme.inkFaint)
                Text("\(abs(remaining))")
                    .font(.fitNumeric(66, weight: .black))
                    .foregroundStyle(isOver ? LightBoltTheme.alert : LightBoltTheme.volt)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("of \(budget) kcal")
                    .font(.fitBody(12))
                    .foregroundStyle(LightBoltTheme.inkMuted)
            }
            .padding(.horizontal, 34)
        }
        .frame(width: size, height: size)
        .onAppear { animate() }
        .onChange(of: fraction) { _, _ in animate() }
    }

    private func animate() {
        withAnimation(.spring(response: 0.9, dampingFraction: 0.78)) {
            animatedFraction = fraction
        }
    }
}

/// Thin horizontal macro meter.
struct MacroMeter: View {
    let label: String
    let value: Double
    let target: Int
    var tint: Color = LightBoltTheme.volt

    @State private var animated: CGFloat = 0

    private var fraction: CGFloat {
        guard target > 0 else { return 0 }
        return min(1, CGFloat(value) / CGFloat(target))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                EyebrowText(text: label)
                Spacer()
                Text("\(Int(value))")
                    .font(.fitNumeric(15))
                    .foregroundStyle(LightBoltTheme.ink)
                Text("/ \(target)g")
                    .font(.fitBody(11))
                    .foregroundStyle(LightBoltTheme.inkFaint)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(LightBoltTheme.charcoalHigh)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(3, geo.size.width * animated))
                }
            }
            .frame(height: 6)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.08)) { animated = fraction }
        }
        .onChange(of: fraction) { _, newValue in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { animated = newValue }
        }
    }
}
