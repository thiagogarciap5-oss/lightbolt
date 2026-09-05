import Foundation

/// One day in the seven-day consistency window.
nonisolated struct DaySlice: Identifiable, Sendable {
    let date: Date
    let dayKey: String
    /// Single-letter weekday initial, e.g. "M".
    let initial: String
    /// Short weekday name, e.g. "Mon".
    let short: String
    let completed: Int
    let planned: Int
    /// Seconds of actual work logged that day, excluding rest.
    let workSeconds: Int
    let minutes: Int
    let isToday: Bool

    nonisolated var id: String { dayKey }

    /// Share of the day's plan that got done. Days with nothing scheduled score
    /// 1 only if something was trained anyway, otherwise 0.
    var completionRate: Double {
        if planned > 0 { return min(1, Double(completed) / Double(planned)) }
        return completed > 0 ? 1 : 0
    }

    var didTrain: Bool { completed > 0 }
}

nonisolated struct ConsistencyDigest: Sendable {
    let days: [DaySlice]
    let completedSessions: Int
    let plannedTotal: Int
    let activeDays: Int
    /// Seconds of actual work across the window.
    let totalWorkSeconds: Int
    let totalIntervals: Int
    let totalMinutes: Int
    let streak: Int
    let previousWeekSessions: Int

    /// Headline consistency number. Uses the plan when there is one, otherwise
    /// falls back to days trained out of seven.
    var completionRate: Double {
        if plannedTotal > 0 { return min(1, Double(completedSessions) / Double(plannedTotal)) }
        return Double(activeDays) / 7
    }

    var completionPercent: Int { Int((completionRate * 100).rounded()) }

    /// Sessions versus the previous seven days.
    var trendDelta: Int { completedSessions - previousWeekSessions }

    var busiestDay: DaySlice? { days.max { $0.completed < $1.completed } }

    static let empty = ConsistencyDigest(
        days: [],
        completedSessions: 0,
        plannedTotal: 0,
        activeDays: 0,
        totalWorkSeconds: 0,
        totalIntervals: 0,
        totalMinutes: 0,
        streak: 0,
        previousWeekSessions: 0
    )
}

/// Single source of truth for consistency maths — the charts and the exported
/// PDF both read from here so the two can never disagree.
enum ConsistencyEngine {
    static func digest(
        sessions: [WorkoutSession],
        plans: [PlannedWorkout],
        now: Date = .now
    ) -> ConsistencyDigest {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        let window: [Date] = (0..<7)
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            .reversed()

        guard let earliest = window.first else { return .empty }

        let sessionsByDay = Dictionary(grouping: sessions) { DayKey.make($0.finishedAt) }
        let plansByDay = Dictionary(grouping: plans, by: \.dayKey)

        let formatter = DateFormatter()
        formatter.locale = .current

        var days: [DaySlice] = []
        for date in window {
            let key = DayKey.make(date)
            let daySessions = sessionsByDay[key] ?? []
            let dayPlans = plansByDay[key] ?? []
            let weekdayIndex = calendar.component(.weekday, from: date) - 1
            let short = formatter.shortWeekdaySymbols[weekdayIndex]

            days.append(
                DaySlice(
                    date: date,
                    dayKey: key,
                    initial: String(formatter.veryShortWeekdaySymbols[weekdayIndex].prefix(2)),
                    short: short,
                    completed: daySessions.count,
                    planned: dayPlans.count,
                    workSeconds: daySessions.reduce(0) { $0 + $1.workSeconds },
                    minutes: daySessions.reduce(0) { $0 + $1.durationSeconds } / 60,
                    isToday: calendar.isDate(date, inSameDayAs: today)
                )
            )
        }

        let windowSessions = sessions.filter { $0.finishedAt >= earliest }
        let previousStart = calendar.date(byAdding: .day, value: -7, to: earliest) ?? earliest
        let previousSessions = sessions.filter { $0.finishedAt >= previousStart && $0.finishedAt < earliest }

        return ConsistencyDigest(
            days: days,
            completedSessions: days.reduce(0) { $0 + $1.completed },
            plannedTotal: days.reduce(0) { $0 + $1.planned },
            activeDays: days.filter(\.didTrain).count,
            totalWorkSeconds: windowSessions.reduce(0) { $0 + $1.workSeconds },
            totalIntervals: windowSessions.reduce(0) { $0 + $1.setCount },
            totalMinutes: windowSessions.reduce(0) { $0 + $1.durationSeconds } / 60,
            streak: streak(from: sessions, endingOn: today),
            previousWeekSessions: previousSessions.count
        )
    }

    /// Consecutive trained days counting back from today. Today not being
    /// trained yet doesn't break a streak that is still alive from yesterday.
    private static func streak(from sessions: [WorkoutSession], endingOn today: Date) -> Int {
        let calendar = Calendar.current
        let trained = Set(sessions.map { DayKey.make($0.finishedAt) })
        guard !trained.isEmpty else { return 0 }

        var cursor = today
        if !trained.contains(DayKey.make(cursor)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while trained.contains(DayKey.make(cursor)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
