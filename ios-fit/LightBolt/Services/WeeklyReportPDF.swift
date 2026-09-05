import Foundation
import UIKit

/// A finished session as it appears in the exported report.
nonisolated struct ReportSessionLine: Sendable {
    let title: String
    let finishedAt: Date
    let durationMinutes: Int
    /// Seconds of actual work, excluding rest.
    let workSeconds: Int
    let intervals: Int
    let estimatedPeakHeartRate: Int

    var workLabel: String {
        workSeconds >= 60 ? "\(workSeconds / 60)m \(workSeconds % 60)s" : "\(workSeconds)s"
    }
}

/// A body scan as it appears in the exported report.
nonisolated struct ReportScanLine: Sendable {
    let capturedAt: Date
    let chestCm: Double
    let waistCm: Double
    let hipCm: Double
    let shoulderCm: Double
    let thighCm: Double
    let bodyFatPercent: Double?
    let quality: Double
}

nonisolated struct WeeklyReportInput: Sendable {
    let username: String
    let digest: ConsistencyDigest
    let sessions: [ReportSessionLine]
    let scans: [ReportScanLine]
    let units: UnitSystem
    let generatedAt: Date
}

/// Renders the weekly performance + body composition summary as a shareable
/// PDF. Drawn with Core Graphics so the document is real vector text, not a
/// screenshot of the UI.
nonisolated enum WeeklyReportPDF {
    private static let pageSize = CGSize(width: 595, height: 842) // A4 at 72dpi
    private static let margin: CGFloat = 44
    private static let volt = UIColor(red: 1, green: 0.96, blue: 0, alpha: 1)
    private static let ink = UIColor(white: 0.09, alpha: 1)
    private static let muted = UIColor(white: 0.45, alpha: 1)
    private static let hairline = UIColor(white: 0.87, alpha: 1)

    /// Writes the PDF to a temporary file and returns its URL.
    static func write(_ input: WeeklyReportInput) throws -> URL {
        let data = render(input)
        let stamp = ISO8601DateFormatter.reportStamp.string(from: input.generatedAt)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightBolt-Weekly-\(stamp).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: Rendering

    private static func render(_ input: WeeklyReportInput) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "LightBolt Weekly Report",
            kCGPDFContextAuthor as String: "LightBolt"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)

        return renderer.pdfData { context in
            context.beginPage()
            var y = drawMasthead(input)

            y = drawKPIs(input, y: y + 26)
            y = drawWeekChart(input, y: y + 30)
            y = section("Sessions this week", y: y + 34)
            y = drawSessions(input, y: y + 8, context: context)
            y = section("Body composition", y: y + 26, context: context, pageBreakBefore: 220)
            y = drawScans(input, y: y + 8)
            drawFootnote(input, y: max(y + 24, pageSize.height - 96))
        }
    }

    private static func drawMasthead(_ input: WeeklyReportInput) -> CGFloat {
        let band = CGRect(x: 0, y: 0, width: pageSize.width, height: 138)
        UIColor.black.setFill()
        UIBezierPath(rect: band).fill()

        volt.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: 40, width: 5, height: 26)).fill()

        draw("LIGHTBOLT", at: CGPoint(x: margin + 14, y: 38), font: .systemFont(ofSize: 22, weight: .black), color: .white)
        draw(
            "WEEKLY PERFORMANCE REPORT",
            at: CGPoint(x: margin + 14, y: 66),
            font: .systemFont(ofSize: 10, weight: .bold),
            color: volt,
            tracking: 2
        )

        let range = dateRange(input.digest)
        draw(range, at: CGPoint(x: margin, y: 96), font: .systemFont(ofSize: 11, weight: .medium), color: UIColor(white: 0.65, alpha: 1))

        let handle = "@\(input.username)"
        let width = handle.size(withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .heavy)]).width
        draw(
            handle,
            at: CGPoint(x: pageSize.width - margin - width, y: 94),
            font: .systemFont(ofSize: 13, weight: .heavy),
            color: .white
        )

        return band.maxY
    }

    private static func drawKPIs(_ input: WeeklyReportInput, y: CGFloat) -> CGFloat {
        let digest = input.digest
        let tiles: [(String, String)] = [
            ("\(digest.completionPercent)%", "Consistency"),
            ("\(digest.completedSessions)", "Sessions"),
            (workText(digest.totalWorkSeconds), "Time working"),
            ("\(digest.streak)", "Day streak")
        ]

        let gap: CGFloat = 12
        let width = (pageSize.width - margin * 2 - gap * CGFloat(tiles.count - 1)) / CGFloat(tiles.count)
        let height: CGFloat = 74

        for (index, tile) in tiles.enumerated() {
            let rect = CGRect(x: margin + CGFloat(index) * (width + gap), y: y, width: width, height: height)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
            UIColor(white: 0.97, alpha: 1).setFill()
            path.fill()
            hairline.setStroke()
            path.lineWidth = 1
            path.stroke()

            draw(tile.0, at: CGPoint(x: rect.minX + 12, y: rect.minY + 16), font: .systemFont(ofSize: 22, weight: .heavy), color: ink)
            draw(
                tile.1.uppercased(),
                at: CGPoint(x: rect.minX + 12, y: rect.minY + 48),
                font: .systemFont(ofSize: 8, weight: .bold),
                color: muted,
                tracking: 1.2
            )
        }

        return y + height
    }

    /// Seven-day completion bars — the same data the in-app chart renders.
    private static func drawWeekChart(_ input: WeeklyReportInput, y: CGFloat) -> CGFloat {
        let top = section("Seven-day completion", y: y)
        let chartTop = top + 12
        let chartHeight: CGFloat = 118
        let days = input.digest.days
        guard !days.isEmpty else { return chartTop }

        let usable = pageSize.width - margin * 2
        let slot = usable / CGFloat(days.count)
        let barWidth = min(38, slot - 14)
        let peak = max(1, days.map(\.completed).max() ?? 1)

        // Baseline
        hairline.setStroke()
        let base = UIBezierPath()
        base.move(to: CGPoint(x: margin, y: chartTop + chartHeight))
        base.addLine(to: CGPoint(x: margin + usable, y: chartTop + chartHeight))
        base.lineWidth = 1
        base.stroke()

        for (index, day) in days.enumerated() {
            let centre = margin + slot * CGFloat(index) + slot / 2
            let ratio = CGFloat(day.completed) / CGFloat(peak)
            let height = max(3, ratio * (chartHeight - 18))
            let rect = CGRect(x: centre - barWidth / 2, y: chartTop + chartHeight - height, width: barWidth, height: height)
            let bar = UIBezierPath(roundedRect: rect, cornerRadius: 5)

            if day.completed > 0 {
                volt.setFill()
            } else {
                UIColor(white: 0.92, alpha: 1).setFill()
            }
            bar.fill()

            if day.planned > 0 {
                // Ghost outline showing what was scheduled.
                let plannedHeight = max(3, CGFloat(day.planned) / CGFloat(peak) * (chartHeight - 18))
                let ghost = UIBezierPath(
                    roundedRect: CGRect(
                        x: centre - barWidth / 2,
                        y: chartTop + chartHeight - plannedHeight,
                        width: barWidth,
                        height: plannedHeight
                    ),
                    cornerRadius: 5
                )
                UIColor(white: 0.6, alpha: 1).setStroke()
                ghost.lineWidth = 1
                ghost.setLineDash([3, 3], count: 2, phase: 0)
                ghost.stroke()
            }

            if day.completed > 0 {
                let label = "\(day.completed)"
                let size = label.size(withAttributes: [.font: UIFont.systemFont(ofSize: 9, weight: .heavy)])
                draw(
                    label,
                    at: CGPoint(x: centre - size.width / 2, y: rect.minY - 13),
                    font: .systemFont(ofSize: 9, weight: .heavy),
                    color: ink
                )
            }

            let caption = day.short.uppercased()
            let captionSize = caption.size(withAttributes: [.font: UIFont.systemFont(ofSize: 8, weight: .bold)])
            draw(
                caption,
                at: CGPoint(x: centre - captionSize.width / 2, y: chartTop + chartHeight + 6),
                font: .systemFont(ofSize: 8, weight: .bold),
                color: day.isToday ? ink : muted
            )
        }

        draw(
            "Solid bars = completed · dashed outline = scheduled",
            at: CGPoint(x: margin, y: chartTop + chartHeight + 24),
            font: .systemFont(ofSize: 8, weight: .medium),
            color: muted
        )

        return chartTop + chartHeight + 36
    }

    private static func drawSessions(
        _ input: WeeklyReportInput,
        y: CGFloat,
        context: UIGraphicsPDFRendererContext
    ) -> CGFloat {
        guard !input.sessions.isEmpty else {
            draw(
                "No sessions finished in this window.",
                at: CGPoint(x: margin, y: y + 4),
                font: .systemFont(ofSize: 11, weight: .medium),
                color: muted
            )
            return y + 24
        }

        var cursor = y
        drawRow(
            ["SESSION", "DAY", "MIN", "INTERVALS", "WORKING", "PEAK HR"],
            y: cursor,
            font: .systemFont(ofSize: 8, weight: .bold),
            color: muted
        )
        cursor += 16

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d"

        for session in input.sessions {
            if cursor > pageSize.height - 120 {
                context.beginPage()
                cursor = margin
            }
            hairline.setStroke()
            let line = UIBezierPath()
            line.move(to: CGPoint(x: margin, y: cursor - 4))
            line.addLine(to: CGPoint(x: pageSize.width - margin, y: cursor - 4))
            line.lineWidth = 0.5
            line.stroke()

            drawRow(
                [
                    session.title,
                    formatter.string(from: session.finishedAt),
                    "\(session.durationMinutes)",
                    "\(session.intervals)",
                    session.workLabel,
                    "~\(session.estimatedPeakHeartRate)"
                ],
                y: cursor + 2,
                font: .systemFont(ofSize: 10, weight: .medium),
                color: ink
            )
            cursor += 22
        }

        return cursor
    }

    private static func drawScans(_ input: WeeklyReportInput, y: CGFloat) -> CGFloat {
        guard let latest = input.scans.first else {
            draw(
                "No body scan recorded yet. Run one from the Body tab to include measurements here.",
                at: CGPoint(x: margin, y: y + 4),
                font: .systemFont(ofSize: 11, weight: .medium),
                color: muted
            )
            return y + 26
        }

        let previous = input.scans.dropFirst().first
        let unit = input.units.lengthUnit
        let rows: [(String, Double, Double?)] = [
            ("Chest", latest.chestCm, previous?.chestCm),
            ("Shoulders", latest.shoulderCm, previous?.shoulderCm),
            ("Waist", latest.waistCm, previous?.waistCm),
            ("Hips", latest.hipCm, previous?.hipCm),
            ("Thigh", latest.thighCm, previous?.thighCm)
        ]

        var cursor = y
        let captured = DateFormatter.localizedString(from: latest.capturedAt, dateStyle: .medium, timeStyle: .short)
        draw(
            "Latest scan · \(captured) · quality \(Int((latest.quality * 100).rounded()))%",
            at: CGPoint(x: margin, y: cursor),
            font: .systemFont(ofSize: 10, weight: .medium),
            color: muted
        )
        cursor += 22

        drawRow(["MEASUREMENT", "CURRENT", "CHANGE"], y: cursor, font: .systemFont(ofSize: 8, weight: .bold), color: muted, columns: 3)
        cursor += 16

        for row in rows {
            hairline.setStroke()
            let line = UIBezierPath()
            line.move(to: CGPoint(x: margin, y: cursor - 4))
            line.addLine(to: CGPoint(x: pageSize.width - margin, y: cursor - 4))
            line.lineWidth = 0.5
            line.stroke()

            let current = LightBoltUnits.displayLength(cm: row.1, units: input.units)
            var change = "—"
            if let old = row.2 {
                let delta = LightBoltUnits.displayLength(cm: row.1 - old, units: input.units)
                change = String(format: "%+.1f %@", delta, unit)
            }
            drawRow(
                [row.0, String(format: "%.1f %@", current, unit), change],
                y: cursor + 2,
                font: .systemFont(ofSize: 10, weight: .medium),
                color: ink,
                columns: 3
            )
            cursor += 22
        }

        if let fat = latest.bodyFatPercent {
            cursor += 6
            draw(
                String(format: "Estimated body fat: %.1f%%", fat),
                at: CGPoint(x: margin, y: cursor),
                font: .systemFont(ofSize: 11, weight: .semibold),
                color: ink
            )
            cursor += 20
        }

        return cursor
    }

    private static func drawFootnote(_ input: WeeklyReportInput, y: CGFloat) {
        hairline.setStroke()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: margin, y: y))
        line.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
        line.lineWidth = 1
        line.stroke()

        let generated = DateFormatter.localizedString(from: input.generatedAt, dateStyle: .medium, timeStyle: .short)
        draw(
            "Generated by LightBolt on \(generated).",
            at: CGPoint(x: margin, y: y + 10),
            font: .systemFont(ofSize: 9, weight: .medium),
            color: muted
        )
        draw(
            "Peak heart rate is modelled from session density, duration and age — not measured by a sensor. Body measurements come from on-device scans and are estimates, not medical readings.",
            at: CGPoint(x: margin, y: y + 24),
            font: .systemFont(ofSize: 8, weight: .regular),
            color: muted,
            width: pageSize.width - margin * 2
        )
    }

    // MARK: Primitives

    private static func section(
        _ title: String,
        y: CGFloat,
        context: UIGraphicsPDFRendererContext? = nil,
        pageBreakBefore requiredSpace: CGFloat = 0
    ) -> CGFloat {
        var cursor = y
        if let context, requiredSpace > 0, cursor + requiredSpace > pageSize.height - margin {
            context.beginPage()
            cursor = margin
        }
        draw(title.uppercased(), at: CGPoint(x: margin, y: cursor), font: .systemFont(ofSize: 10, weight: .black), color: ink, tracking: 1.6)
        volt.setFill()
        UIBezierPath(rect: CGRect(x: margin, y: cursor + 16, width: 26, height: 3)).fill()
        return cursor + 20
    }

    private static func drawRow(
        _ values: [String],
        y: CGFloat,
        font: UIFont,
        color: UIColor,
        columns: Int? = nil
    ) {
        let count = columns ?? values.count
        let usable = pageSize.width - margin * 2
        let first = usable * (count == 3 ? 0.5 : 0.34)
        let rest = (usable - first) / CGFloat(max(1, count - 1))

        for (index, value) in values.enumerated() {
            let x = index == 0 ? margin : margin + first + rest * CGFloat(index - 1)
            let width = index == 0 ? first - 8 : rest - 8
            draw(value, at: CGPoint(x: x, y: y), font: font, color: color, width: width, truncates: true)
        }
    }

    private static func draw(
        _ text: String,
        at point: CGPoint,
        font: UIFont,
        color: UIColor,
        tracking: CGFloat = 0,
        width: CGFloat? = nil,
        truncates: Bool = false
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = truncates ? .byTruncatingTail : .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        if tracking > 0 { attributes[.kern] = tracking }

        let string = NSAttributedString(string: text, attributes: attributes)
        if let width {
            string.draw(with: CGRect(x: point.x, y: point.y, width: width, height: 200),
                        options: [.usesLineFragmentOrigin],
                        context: nil)
        } else {
            string.draw(at: point)
        }
    }

    /// Human-readable working time, e.g. "42m" or "1h 06m".
    private static func workText(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    private static func dateRange(_ digest: ConsistencyDigest) -> String {
        guard let first = digest.days.first?.date, let last = digest.days.last?.date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
    }
}

private extension ISO8601DateFormatter {
    static let reportStamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]
        return formatter
    }()
}
