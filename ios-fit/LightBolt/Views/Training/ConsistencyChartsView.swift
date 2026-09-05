import Charts
import SwiftUI

/// Compact seven-day consistency read-out for the Train tab. Tapping opens the
/// full chart sheet.
struct ConsistencyCard: View {
    let digest: ConsistencyDigest
    let action: () -> Void

    @State private var grow: CGFloat = 0

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        EyebrowText(text: "Last 7 days", color: LightBoltTheme.voltDim)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(digest.completionPercent)")
                                .font(.fitDisplay(44))
                                .tracking(-1.5)
                                .voltWash()
                                .contentTransition(.numericText())
                            Text("%")
                                .font(.fitTitle(18))
                                .foregroundStyle(LightBoltTheme.voltDim)
                        }
                        Text(subtitle)
                            .font(.fitBody(11))
                            .foregroundStyle(LightBoltTheme.inkMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 6) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(LightBoltTheme.volt)
                        trendPill
                    }
                }

                sparkline
                    .padding(.top, 16)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fitCard(radius: 20)
        }
        .buttonStyle(VoltPressStyle(scale: 0.98))
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.05)) { grow = 1 }
        }
    }

    private var subtitle: String {
        let sessions = digest.completedSessions
        let days = digest.activeDays
        return "\(sessions) session\(sessions == 1 ? "" : "s") · \(days)/7 active days"
    }

    private var trendPill: some View {
        let delta = digest.trendDelta
        let symbol = delta > 0 ? "arrow.up.right" : (delta < 0 ? "arrow.down.right" : "equal")
        let tint = delta > 0 ? LightBoltTheme.volt : (delta < 0 ? LightBoltTheme.alert : LightBoltTheme.inkMuted)
        return HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .black))
            Text(delta == 0 ? "flat" : "\(abs(delta))")
                .font(.fitLabel(9))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Capsule().fill(tint.opacity(0.12)))
    }

    /// Seven tiny columns — enough signal to read consistency at a glance.
    private var sparkline: some View {
        let peak = max(1, digest.days.map { max($0.completed, $0.planned) }.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(digest.days) { day in
                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LightBoltTheme.charcoalHigh)
                            .frame(height: 46)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(day.completed > 0 ? LightBoltTheme.volt : LightBoltTheme.charcoalHigh)
                            .frame(height: max(4, 46 * CGFloat(day.completed) / CGFloat(peak) * grow))
                    }
                    Text(day.initial)
                        .font(.fitLabel(8))
                        .foregroundStyle(day.isToday ? LightBoltTheme.volt : LightBoltTheme.inkFaint)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Full-screen consistency analytics for the last seven days.
struct ConsistencyChartsView: View {
    let digest: ConsistencyDigest
    let units: UnitSystem
    var onExport: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    var body: some View {
        ZStack {
            LightBoltTheme.backdrop

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    hero
                    sessionsChart
                    rateChart
                    tiles
                    exportRow
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .task {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.8)) { appeared = true }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                EyebrowText(text: rangeCaption, color: LightBoltTheme.voltDim)
                Text("CONSISTENCY")
                    .font(.fitDisplay(44))
                    .tracking(-1.4)
                    .foregroundStyle(LightBoltTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
            Button {
                Haptics.tick()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(LightBoltTheme.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(LightBoltTheme.charcoal))
            }
            .buttonStyle(VoltPressStyle(scale: 0.9))
            .accessibilityLabel("Close charts")
        }
        .padding(.top, 18)
    }

    private var hero: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .strokeBorder(LightBoltTheme.charcoalHigh, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: appeared ? digest.completionRate : 0)
                    .stroke(
                        AngularGradient(
                            colors: [LightBoltTheme.voltDim, LightBoltTheme.volt, LightBoltTheme.voltSoft],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(digest.completionPercent)")
                        .font(.fitNumeric(28))
                        .foregroundStyle(LightBoltTheme.ink)
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.fitLabel(9))
                        .foregroundStyle(LightBoltTheme.inkFaint)
                }
            }
            .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 8) {
                heroLine(
                    value: "\(digest.completedSessions)",
                    label: digest.plannedTotal > 0 ? "of \(digest.plannedTotal) planned" : "sessions finished"
                )
                heroLine(value: "\(digest.streak)", label: "day streak")
                heroLine(value: "\(digest.activeDays)/7", label: "days trained")
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard(radius: 22, stroke: LightBoltTheme.voltDim)
    }

    private func heroLine(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(value)
                .font(.fitNumeric(19))
                .foregroundStyle(LightBoltTheme.volt)
            Text(label.uppercased())
                .font(.fitLabel(9))
                .tracking(1.2)
                .foregroundStyle(LightBoltTheme.inkMuted)
        }
    }

    private var sessionsChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Workouts Completed", trailing: "per day")

            Chart(digest.days) { day in
                if day.planned > 0 {
                    BarMark(
                        x: .value("Day", day.short),
                        y: .value("Planned", Double(day.planned)),
                        width: .fixed(26)
                    )
                    .foregroundStyle(LightBoltTheme.charcoalHigh)
                    .cornerRadius(6)
                }

                BarMark(
                    x: .value("Day", day.short),
                    y: .value("Completed", appeared ? Double(day.completed) : 0),
                    width: .fixed(26)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [LightBoltTheme.volt, LightBoltTheme.voltSoft],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .cornerRadius(6)
                .annotation(position: .top, spacing: 4) {
                    if day.completed > 0 {
                        Text("\(day.completed)")
                            .font(.fitLabel(9))
                            .foregroundStyle(LightBoltTheme.volt)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(LightBoltTheme.hairline.opacity(0.6))
                    AxisValueLabel().font(.fitLabel(9)).foregroundStyle(LightBoltTheme.inkFaint)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label.uppercased())
                                .font(.fitLabel(9))
                                .foregroundStyle(LightBoltTheme.inkMuted)
                        }
                    }
                }
            }
            .frame(height: 178)
            .padding(.top, 6)
            .animation(.spring(response: 0.8, dampingFraction: 0.78), value: appeared)

            HStack(spacing: 14) {
                legend(color: LightBoltTheme.volt, label: "Completed")
                legend(color: LightBoltTheme.charcoalHigh, label: "Scheduled")
            }
        }
        .padding(16)
        .fitCard(radius: 22)
    }

    private var rateChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Completion Trend", trailing: "% of plan")

            Chart(digest.days) { day in
                AreaMark(
                    x: .value("Day", day.short),
                    y: .value("Rate", appeared ? day.completionRate * 100 : 0)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [LightBoltTheme.volt.opacity(0.28), LightBoltTheme.volt.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Day", day.short),
                    y: .value("Rate", appeared ? day.completionRate * 100 : 0)
                )
                .foregroundStyle(LightBoltTheme.volt)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Day", day.short),
                    y: .value("Rate", appeared ? day.completionRate * 100 : 0)
                )
                .foregroundStyle(day.didTrain ? LightBoltTheme.volt : LightBoltTheme.inkFaint)
                .symbolSize(day.isToday ? 90 : 44)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { _ in
                    AxisGridLine().foregroundStyle(LightBoltTheme.hairline.opacity(0.6))
                    AxisValueLabel().font(.fitLabel(9)).foregroundStyle(LightBoltTheme.inkFaint)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label.uppercased())
                                .font(.fitLabel(9))
                                .foregroundStyle(LightBoltTheme.inkMuted)
                        }
                    }
                }
            }
            .frame(height: 150)
            .padding(.top, 6)
            .animation(.spring(response: 0.9, dampingFraction: 0.82), value: appeared)
        }
        .padding(16)
        .fitCard(radius: 22)
    }

    private var tiles: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatTile(
                    eyebrow: "Time working",
                    value: workValue,
                    unit: "minutes",
                    footnote: nil,
                    height: 92
                )
                StatTile(
                    eyebrow: "Intervals",
                    value: "\(digest.totalIntervals)",
                    unit: "completed",
                    footnote: nil,
                    height: 92
                )
            }
            HStack(spacing: 12) {
                StatTile(
                    eyebrow: "Session time",
                    value: "\(digest.totalMinutes)",
                    unit: "minutes",
                    footnote: nil,
                    height: 92
                )
                StatTile(
                    eyebrow: "Best day",
                    value: digest.busiestDay?.short.uppercased() ?? "—",
                    unit: "\(digest.busiestDay?.completed ?? 0) sessions",
                    footnote: nil,
                    height: 92
                )
            }
        }
    }

    private var exportRow: some View {
        VStack(spacing: 10) {
            GhostButton(title: "Export weekly PDF", systemImage: "square.and.arrow.up") {
                Haptics.tap()
                onExport()
            }
            Text("Includes every session in this window plus your latest body scan measurements.")
                .font(.fitBody(11))
                .foregroundStyle(LightBoltTheme.inkFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Bits

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 12, height: 8)
            Text(label.uppercased())
                .font(.fitLabel(9))
                .tracking(1)
                .foregroundStyle(LightBoltTheme.inkMuted)
        }
    }

    private var workValue: String {
        let minutes = digest.totalWorkSeconds / 60
        return minutes > 0 ? "\(minutes)" : "—"
    }

    private var rangeCaption: String {
        guard let first = digest.days.first?.date, let last = digest.days.last?.date else { return "Last 7 days" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
    }
}
