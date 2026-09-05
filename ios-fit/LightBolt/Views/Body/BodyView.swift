import Charts
import SwiftData
import SwiftUI

/// Body composition tab: the yellow wireframe dashboard driven by the real
/// measurements solved on-device by `BodyMeasurementEngine`, plus the
/// historical progress graph.
struct BodyView: View {
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.modelContext) private var context

    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyScan.capturedAt, order: .reverse) private var scans: [BodyScan]

    @State private var isScanning = false
    @State private var quota: ScanQuotaDTO?
    @State private var metric: BodyMetric = .waist

    private var profile: UserProfile? { profiles.first }
    private var latest: BodyScan? { scans.first }
    private var previous: BodyScan? { scans.count > 1 ? scans[1] : nil }
    private var units: UnitSystem { profile?.units ?? .metric }

    /// Local fallback used only while the authoritative server quota is loading.
    private var scansToday: Int {
        scans.filter { Calendar.current.isDateInToday($0.capturedAt) }.count
    }

    private var remainingScans: Int {
        quota?.bodyRemaining ?? max(0, entitlements.dailyBodyScanLimit - scansToday)
    }

    private var canScan: Bool { remainingScans > 0 }

    private var subject: BodyScanSubject {
        BodyScanSubject(
            heightCm: profile?.heightCm ?? 0,
            weightKg: profile?.weightKg ?? 0,
            age: profile?.age ?? 30,
            isFemale: profile?.sex == .female
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                scanCTA

                if !subject.isComplete {
                    LimitBanner(message: "Add your height and weight in Profile — the scanner measures you against your real height to convert pixels into centimetres.")
                }

                if let latest {
                    silhouetteBlock(latest)
                    measurementGrid(latest)
                    if scans.count > 1 { trendBlock }
                    if scans.count > 1 { historyBlock }
                } else {
                    EmptyStateCard(
                        symbol: "figure.stand",
                        title: "No scans yet",
                        message: "Stand your phone up, step back, and turn through a full circle. LightBolt measures your waist, hips and chest from four angles right here on your device — no photo ever leaves your phone."
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .background(LightBoltTheme.backdrop)
        .task { await refreshQuota() }
        .fullScreenCover(isPresented: $isScanning) {
            BodyScannerView(subject: subject) { result in
                context.insert(
                    BodyScan(
                        chestCm: result.chestCm,
                        waistCm: result.waistCm,
                        hipCm: result.hipCm,
                        shoulderCm: result.shoulderCm,
                        thighCm: result.thighCm,
                        quality: result.confidence,
                        frameCount: result.frameCount,
                        bodyFatPercent: result.bodyFatPercent,
                        provider: result.provider
                    )
                )
            }
            .onDisappear { Task { await refreshQuota() } }
        }
    }

    /// Pulls the authoritative rolling-24h allowance from the Worker. A failure
    /// here silently keeps the local estimate — it must never block the tab.
    private func refreshQuota() async {
        quota = try? await BackendClient.shared.scanQuota()
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            EyebrowText(text: "Body Dimensions", color: LightBoltTheme.voltDim)
            Text("THE SCAN")
                .font(.fitDisplay(52))
                .tracking(-1.2)
                .foregroundStyle(LightBoltTheme.ink)
            if let latest {
                Text("Last measured \(latest.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.fitBody(12))
                    .foregroundStyle(LightBoltTheme.inkMuted)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var scanCTA: some View {
        Button {
            Haptics.tap()
            isScanning = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LightBoltTheme.volt)
                        .frame(width: 58, height: 58)
                    Image(systemName: "figure.stand")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.black)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("START 360° SCAN")
                        .font(.fitTitle(20))
                        .tracking(1.1)
                        .foregroundStyle(LightBoltTheme.ink)
                    Text("4 angles · 18 seconds · \(remainingScans) of \(entitlements.dailyBodyScanLimit) left today")
                        .font(.fitBody(12))
                        .foregroundStyle(LightBoltTheme.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(LightBoltTheme.volt)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .fitCard(radius: 22, stroke: canScan ? LightBoltTheme.voltDim : LightBoltTheme.hairline)
        }
        .buttonStyle(VoltPressStyle(scale: 0.98))
        .disabled(!canScan || !subject.isComplete)
        .overlay { if !canScan { limitOverlay } }
    }

    /// Locked state shown over the CTA once the single daily scan is spent.
    private var limitOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LightBoltTheme.void.opacity(0.86))
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(LightBoltTheme.volt)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DAILY SCAN USED")
                        .font(.fitTitle(15))
                        .tracking(1.2)
                        .foregroundStyle(LightBoltTheme.ink)
                    Text(quota?.bodyResetDate.map(resetText) ?? "Resets 24h after your last scan.")
                        .font(.fitBody(11))
                        .foregroundStyle(LightBoltTheme.inkMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(LightBoltTheme.voltDim.opacity(0.5), lineWidth: 1)
        )
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func resetText(_ date: Date) -> String {
        let interval = max(0, date.timeIntervalSinceNow)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return hours > 0 ? "Unlocks in \(hours)h \(minutes)m" : "Unlocks in \(minutes)m"
    }

    private func silhouetteBlock(_ scan: BodyScan) -> some View {
        VStack(spacing: 16) {
            BodyDiagram(scan: scan, units: units)
                .frame(height: 300)

            HStack(spacing: 10) {
                ratioTile(
                    title: "Waist : Hip",
                    value: String(format: "%.2f", scan.waistToHip),
                    note: scan.waistToHip < 0.9 ? "Healthy range" : "Watch this"
                )
                if let fat = scan.bodyFatPercent {
                    ratioTile(
                        title: "Body Fat",
                        value: String(format: "%.1f%%", fat),
                        note: "Navy method estimate"
                    )
                } else if scan.shoulderCm > 0 {
                    ratioTile(
                        title: "Shoulder : Waist",
                        value: String(format: "%.2f", scan.waistCm > 0 ? scan.shoulderCm / scan.waistCm : 0),
                        note: "V-taper index"
                    )
                }
            }
        }
        .padding(18)
        .fitCard()
    }

    private func ratioTile(title: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            EyebrowText(text: title, color: LightBoltTheme.inkFaint)
            Text(value)
                .font(.fitNumeric(24))
                .foregroundStyle(LightBoltTheme.volt)
            Text(note)
                .font(.fitBody(11))
                .foregroundStyle(LightBoltTheme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(LightBoltTheme.charcoalHigh))
    }

    private func measurementGrid(_ scan: BodyScan) -> some View {
        // Not every girth resolves on every scan — only show what was measured.
        let rows: [(String, Double, Double?)] = [
            ("Waist", scan.waistCm, previous?.waistCm),
            ("Hips", scan.hipCm, previous?.hipCm),
            ("Chest", scan.chestCm, previous?.chestCm),
            ("Shoulder Breadth", scan.shoulderCm, previous?.shoulderCm),
            ("Thigh", scan.thighCm, previous?.thighCm)
        ].filter { $0.1 > 0 }

        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Measurements", trailing: "Confidence \(Int(scan.quality * 100))%")
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    MeasurementRow(
                        label: row.0,
                        valueCm: row.1,
                        previousCm: row.2,
                        units: units
                    )
                    if index < rows.count - 1 {
                        Rectangle().fill(LightBoltTheme.hairline).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .fitCard()
        }
    }

    // MARK: Progress graph

    private var trendPoints: [TrendPoint] {
        scans.reversed().map { scan in
            TrendPoint(
                date: scan.capturedAt,
                value: LightBoltUnits.displayLength(cm: metric.value(in: scan), units: units)
            )
        }
        .filter { $0.value > 0 }
    }

    private var trendBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Progress", trailing: metric.title)
            VStack(spacing: 16) {
                SegmentedVoltPicker(options: BodyMetric.allCases, selection: $metric, label: { $0.title })
                MetricTrendChart(points: trendPoints, unit: units.lengthUnit)
                    .frame(height: 186)
                    .animation(.easeInOut(duration: 0.35), value: metric)
            }
            .padding(16)
            .fitCard()
        }
    }

    private var historyBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "History", trailing: "\(scans.count) scans")
            VStack(spacing: 10) {
                ForEach(scans.prefix(8)) { scan in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scan.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.fitBody(13))
                                .foregroundStyle(LightBoltTheme.ink)
                            EyebrowText(
                                text: scan.provider.isEmpty
                                    ? "\(scan.frameCount) angles"
                                    : "\(scan.frameCount) angles · \(scan.provider)",
                                color: LightBoltTheme.inkFaint
                            )
                        }
                        Spacer()
                        Text(String(format: "W %.1f", LightBoltUnits.displayLength(cm: scan.waistCm, units: units)))
                            .font(.fitNumeric(15))
                            .foregroundStyle(LightBoltTheme.volt)
                    }
                    .padding(14)
                    .fitCard(radius: 15)
                    .contextMenu {
                        Button("Delete Scan", systemImage: "trash", role: .destructive) {
                            withAnimation { context.delete(scan) }
                            Haptics.warning()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Trend chart

private struct TrendPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Volt line graph of one circumference across every saved scan.
private struct MetricTrendChart: View {
    let points: [TrendPoint]
    let unit: String

    private var domain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = max(1.5, (high - low) * 0.35)
        return (low - pad)...(high + pad)
    }

    var body: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Date", point.date),
                y: .value(unit, point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    colors: [LightBoltTheme.volt.opacity(0.30), LightBoltTheme.volt.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Date", point.date),
                y: .value(unit, point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(LightBoltTheme.volt)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            PointMark(
                x: .value("Date", point.date),
                y: .value(unit, point.value)
            )
            .foregroundStyle(LightBoltTheme.volt)
            .symbolSize(34)
        }
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(LightBoltTheme.hairline)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .font(.fitLabel(9))
                    .foregroundStyle(LightBoltTheme.inkFaint)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(LightBoltTheme.hairline)
                AxisValueLabel()
                    .font(.fitLabel(9))
                    .foregroundStyle(LightBoltTheme.inkFaint)
            }
        }
    }
}

private struct MeasurementRow: View {
    let label: String
    let valueCm: Double
    let previousCm: Double?
    let units: UnitSystem

    var body: some View {
        let value = LightBoltUnits.displayLength(cm: valueCm, units: units)
        let delta = previousCm.flatMap { $0 > 0 ? LightBoltUnits.displayLength(cm: valueCm - $0, units: units) : nil }

        HStack {
            Text(label.uppercased())
                .font(.fitLabel(11))
                .tracking(1.3)
                .foregroundStyle(LightBoltTheme.inkMuted)
            Spacer()
            if let delta, abs(delta) > 0.05 {
                HStack(spacing: 3) {
                    Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .black))
                    Text(String(format: "%.1f", abs(delta)))
                        .font(.fitLabel(10))
                }
                .foregroundStyle(delta > 0 ? LightBoltTheme.voltSoft : LightBoltTheme.inkMuted)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(LightBoltTheme.charcoalHigh))
            }
            Text(String(format: "%.1f", value))
                .font(.fitNumeric(19))
                .foregroundStyle(LightBoltTheme.ink)
                .contentTransition(.numericText())
            Text(units.lengthUnit)
                .font(.fitLabel(9))
                .foregroundStyle(LightBoltTheme.inkFaint)
        }
        .padding(.vertical, 15)
    }
}

/// Yellow tracking wireframe whose band widths AND printed values come straight
/// from the on-device measurement solve.
private struct BodyDiagram: View {
    let scan: BodyScan
    let units: UnitSystem
    @State private var reveal: CGFloat = 0

    private struct Band: Identifiable {
        let id: String
        let label: String
        let cm: Double
        let widthFraction: Double
        let isPrimary: Bool
    }

    private var bands: [Band] {
        // Shoulder breadth and thigh girth are scaled so they read proportionally
        // against the three torso circumferences on the same wireframe.
        // The printed numbers are always the true measured values.
        let shoulderEquivalent = scan.shoulderCm * 2.6
        let thighEquivalent = scan.thighCm * 1.6
        let reference = max(shoulderEquivalent, scan.chestCm, scan.hipCm, scan.waistCm, 1)

        var out: [Band] = []
        if scan.shoulderCm > 0 {
            out.append(Band(id: "shoulders", label: "Shoulders", cm: scan.shoulderCm,
                            widthFraction: shoulderEquivalent / reference, isPrimary: false))
        }
        out.append(Band(id: "chest", label: "Chest", cm: scan.chestCm,
                        widthFraction: scan.chestCm / reference, isPrimary: true))
        out.append(Band(id: "waist", label: "Waist", cm: scan.waistCm,
                        widthFraction: scan.waistCm / reference, isPrimary: true))
        out.append(Band(id: "hips", label: "Hips", cm: scan.hipCm,
                        widthFraction: scan.hipCm / reference, isPrimary: true))
        if scan.thighCm > 0 {
            out.append(Band(id: "thigh", label: "Thigh", cm: scan.thighCm,
                            widthFraction: thighEquivalent / reference, isPrimary: false))
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle()
                    .fill(LightBoltTheme.hairline)
                    .frame(width: 1)

                VStack(spacing: 0) {
                    ForEach(Array(bands.enumerated()), id: \.element.id) { index, band in
                        bandRow(band, maxWidth: geo.size.width * 0.5)
                            .frame(maxHeight: .infinity)
                            .animation(
                                .spring(response: 0.7, dampingFraction: 0.75).delay(Double(index) * 0.07),
                                value: reveal
                            )
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75)) { reveal = 1 }
        }
    }

    private func bandRow(_ band: Band, maxWidth: CGFloat) -> some View {
        let width = max(64, maxWidth * CGFloat(min(1, band.widthFraction)))
        let height: CGFloat = band.isPrimary ? 34 : 18
        let display = LightBoltUnits.displayLength(cm: band.cm, units: units)

        return ZStack {
            ZStack {
                Capsule().fill(LightBoltTheme.volt.opacity(band.isPrimary ? 0.16 : 0.07))
                Capsule().strokeBorder(
                    LightBoltTheme.volt.opacity(band.isPrimary ? 1 : 0.45),
                    lineWidth: band.isPrimary ? 1.8 : 1
                )
                HStack {
                    Circle().fill(LightBoltTheme.volt).frame(width: 5, height: 5)
                    Spacer(minLength: 0)
                    Circle().fill(LightBoltTheme.volt).frame(width: 5, height: 5)
                }
                .padding(.horizontal, 7)

                if band.isPrimary {
                    // The real-world measurement, printed onto the wireframe band.
                    Text(String(format: "%.1f", display))
                        .font(.fitNumeric(17))
                        .foregroundStyle(LightBoltTheme.volt)
                        .opacity(reveal)
                }
            }
            .frame(width: width * reveal, height: height)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(band.label.uppercased())
                        .font(.fitLabel(9))
                        .tracking(1.3)
                        .foregroundStyle(LightBoltTheme.inkFaint)
                    Text(band.isPrimary
                         ? units.lengthUnit
                         : String(format: "%.1f %@", display, units.lengthUnit))
                        .font(band.isPrimary ? .fitLabel(9) : .fitNumeric(12))
                        .foregroundStyle(band.isPrimary ? LightBoltTheme.inkFaint : LightBoltTheme.ink)
                }
                .frame(width: 74, alignment: .leading)
                .lineLimit(1)
            }
            .opacity(reveal)
        }
    }
}
