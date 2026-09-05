import Foundation
import SwiftData

/// One entry on a day's schedule. The order is user-owned: `orderIndex` is what
/// the drag-and-drop planner rewrites, and nothing else is allowed to resort it.
@Model
final class PlannedWorkout {
    /// `DayKey.make(date)` — the day this entry is scheduled for.
    var dayKey: String
    var programID: String
    var title: String
    var focus: String
    var symbol: String
    /// Work intervals in the session. Legacy field name, kept so existing
    /// stores migrate without a schema break.
    var plannedSets: Int
    var estimatedMinutes: Int
    /// True when the session avoids jumping — the quiet-flat variant.
    var isBodyweight: Bool
    var orderIndex: Int
    var completedAt: Date?
    var createdAt: Date
    /// Seconds of actual work the session schedules.
    var plannedWorkSeconds: Int = 0

    init(
        dayKey: String,
        programID: String,
        title: String,
        focus: String,
        symbol: String,
        intervals: Int,
        estimatedMinutes: Int,
        workSeconds: Int,
        isLowImpact: Bool,
        orderIndex: Int
    ) {
        self.dayKey = dayKey
        self.programID = programID
        self.title = title
        self.focus = focus
        self.symbol = symbol
        self.plannedSets = intervals
        self.estimatedMinutes = estimatedMinutes
        self.isBodyweight = isLowImpact
        self.orderIndex = orderIndex
        self.completedAt = nil
        self.createdAt = .now
        self.plannedWorkSeconds = workSeconds
    }

    var isDone: Bool { completedAt != nil }

    /// Work intervals the session schedules.
    var intervals: Int { plannedSets }

    var isLowImpact: Bool { isBodyweight }

    convenience init(program: Program, dayKey: String, orderIndex: Int) {
        self.init(
            dayKey: dayKey,
            programID: program.id,
            title: program.title,
            focus: program.focus,
            symbol: program.exercises.first?.symbol ?? "figure.run",
            intervals: program.totalRounds,
            estimatedMinutes: program.estimatedMinutes,
            workSeconds: program.totalWorkSeconds,
            isLowImpact: program.intensity == .lowImpact,
            orderIndex: orderIndex
        )
    }
}

/// Everything the expandable panel on a planner row shows.
nonisolated struct WorkoutMetrics: Sendable {
    /// Seconds of work, excluding rest.
    let workSeconds: Int
    let intervals: Int
    let durationSeconds: Int
    /// Modelled, never measured — the app has no heart-rate sensor access, so
    /// this is always surfaced with an "est." qualifier in the UI.
    let peakHeartRate: Int
    let averageHeartRate: Int
    let activeCalories: Int
    let isCompleted: Bool

    var durationMinutes: Int { max(1, durationSeconds / 60) }

    var workMinutesLabel: String {
        "\(workSeconds / 60):\(String(format: "%02d", workSeconds % 60))"
    }

    /// Share of the session actually spent working rather than resting — the
    /// number that decides how hard an interval workout feels.
    var workDensity: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(1, Double(workSeconds) / Double(durationSeconds))
    }
}

/// Derives per-workout metrics from what LightBolt actually recorded, and
/// projects them from history when a session hasn't happened yet.
enum WorkoutMetricsEngine {
    /// Tanaka: more accurate across ages than the old 220 − age rule.
    static func maxHeartRate(age: Int) -> Int {
        Int((208 - 0.7 * Double(max(14, min(95, age)))).rounded())
    }

    static func metrics(
        for plan: PlannedWorkout,
        session: WorkoutSession?,
        logs: [SetLog],
        profile: UserProfile?
    ) -> WorkoutMetrics {
        let age = profile?.age ?? 30
        let ceiling = maxHeartRate(age: age)

        if let session {
            let density = session.durationSeconds > 0
                ? Double(session.workSeconds) / Double(session.durationSeconds)
                : 0
            let peak = Int((Double(ceiling) * peakFraction(isLowImpact: plan.isLowImpact, workDensity: density)).rounded())
            return WorkoutMetrics(
                workSeconds: session.workSeconds,
                intervals: session.setCount,
                durationSeconds: session.durationSeconds,
                peakHeartRate: peak,
                averageHeartRate: Int((Double(peak) * 0.78).rounded()),
                activeCalories: calories(
                    minutes: Double(session.durationSeconds) / 60,
                    weightKg: profile?.weightKg ?? 75,
                    isLowImpact: plan.isLowImpact
                ),
                isCompleted: true
            )
        }

        let minutes = max(1, plan.estimatedMinutes)
        let projectedWork = plan.plannedWorkSeconds > 0
            ? plan.plannedWorkSeconds
            : projectedWorkSeconds(logs: logs, intervals: plan.intervals)
        let density = Double(projectedWork) / Double(minutes * 60)
        let peak = Int((Double(ceiling) * peakFraction(isLowImpact: plan.isLowImpact, workDensity: density)).rounded())

        return WorkoutMetrics(
            workSeconds: projectedWork,
            intervals: plan.intervals,
            durationSeconds: minutes * 60,
            peakHeartRate: peak,
            averageHeartRate: Int((Double(peak) * 0.78).rounded()),
            activeCalories: calories(
                minutes: Double(minutes),
                weightKg: profile?.weightKg ?? 75,
                isLowImpact: plan.isLowImpact
            ),
            isCompleted: false
        )
    }

    /// Dense interval work with short rests drives the heart far closer to max
    /// than a quiet, long-rest session does.
    private static func peakFraction(isLowImpact: Bool, workDensity: Double) -> Double {
        let base = isLowImpact ? 0.82 : 0.88
        let densityBonus = min(0.08, max(0, workDensity - 0.45) * 0.24)
        return min(0.97, base + densityBonus)
    }

    private static func calories(minutes: Double, weightKg: Double, isLowImpact: Bool) -> Int {
        // MET ≈ 8.0 for vigorous calisthenics, 5.0 for low-impact circuits.
        let met = isLowImpact ? 5.0 : 8.0
        return Int((met * 3.5 * weightKg / 200 * minutes).rounded())
    }

    /// Mean seconds per logged interval, so projections track how long this
    /// person actually works rather than a hard-coded guess.
    private static func projectedWorkSeconds(logs: [SetLog], intervals: Int) -> Int {
        let recent = Array(logs.prefix(60)).filter { $0.holdSeconds > 0 }
        guard !recent.isEmpty else { return intervals * 40 }
        let average = recent.reduce(0) { $0 + $1.holdSeconds } / recent.count
        return max(1, intervals) * max(15, average)
    }
}
