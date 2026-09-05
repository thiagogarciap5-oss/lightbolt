import Foundation
import SwiftData

// MARK: - Profile value types

nonisolated enum LightBoltGoal: String, Codable, CaseIterable, Identifiable, Sendable {
    case lose = "lose"
    case muscle = "muscle"
    case strength = "strength"

    nonisolated var id: String { rawValue }

    var title: String {
        switch self {
        case .lose: "Lose Weight"
        case .muscle: "Build Muscle"
        case .strength: "Build Strength"
        }
    }

    var blurb: String {
        switch self {
        case .lose: "Calorie deficit, higher volume, circuit-weighted sessions."
        case .muscle: "Slight surplus, hypertrophy rep ranges, progressive overload."
        case .strength: "Heavy compounds, low reps, long rests, max intent."
        }
    }

    var symbol: String {
        switch self {
        case .lose: "flame.fill"
        case .muscle: "figure.arms.open"
        case .strength: "dumbbell.fill"
        }
    }

    /// Multiplier applied to maintenance calories.
    var calorieFactor: Double {
        switch self {
        case .lose: 0.80
        case .muscle: 1.10
        case .strength: 1.05
        }
    }

    /// Grams of protein per kg of bodyweight.
    var proteinPerKg: Double {
        switch self {
        case .lose: 2.2
        case .muscle: 1.9
        case .strength: 1.8
        }
    }
}

/// How hard the generated sessions are allowed to hit the floor.
///
/// LightBolt is entirely equipment-free, so the only real question is whether
/// you can jump. Raw values are the original storage keys — renaming them would
/// orphan every profile already on a phone.
nonisolated enum TrainingIntensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case lowImpact = "bodyweight"
    case fullPower = "weights"

    nonisolated var id: String { rawValue }

    var title: String {
        switch self {
        case .lowImpact: "Low Impact"
        case .fullPower: "Full Power"
        }
    }

    var blurb: String {
        switch self {
        case .lowImpact: "No jumping, no thudding. Quiet enough for a flat at 6am."
        case .fullPower: "Jumps, burpees and sprint intervals included."
        }
    }

    var symbol: String {
        switch self {
        case .lowImpact: "figure.cooldown"
        case .fullPower: "flame.fill"
        }
    }

    /// Short label for cards and filters.
    var chip: String {
        switch self {
        case .lowImpact: "QUIET"
        case .fullPower: "EXPLOSIVE"
        }
    }
}

nonisolated enum BiologicalSex: String, Codable, CaseIterable, Identifiable, Sendable {
    case male, female

    nonisolated var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

nonisolated enum UnitSystem: String, Codable, CaseIterable, Identifiable, Sendable {
    case metric, imperial

    nonisolated var id: String { rawValue }
    var title: String { self == .metric ? "Metric" : "Imperial" }
    var weightUnit: String { self == .metric ? "kg" : "lb" }
    var lengthUnit: String { self == .metric ? "cm" : "in" }
}

// MARK: - SwiftData schema

/// The single local profile record created by the onboarding survey.
@Model
final class UserProfile {
    var goalRaw: String
    var equipmentRaw: String
    var sexRaw: String
    var unitsRaw: String
    var age: Int
    /// Always stored in centimetres.
    var heightCm: Double
    /// Always stored in kilograms.
    var weightKg: Double
    /// Optional user-entered body fat percentage.
    var bodyFatPercent: Double?
    var createdAt: Date
    var updatedAt: Date

    init(
        goal: LightBoltGoal,
        intensity: TrainingIntensity,
        sex: BiologicalSex,
        units: UnitSystem,
        age: Int,
        heightCm: Double,
        weightKg: Double,
        bodyFatPercent: Double?
    ) {
        self.goalRaw = goal.rawValue
        self.equipmentRaw = intensity.rawValue
        self.sexRaw = sex.rawValue
        self.unitsRaw = units.rawValue
        self.age = age
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
        self.createdAt = .now
        self.updatedAt = .now
    }

    var goal: LightBoltGoal { LightBoltGoal(rawValue: goalRaw) ?? .muscle }
    var intensity: TrainingIntensity { TrainingIntensity(rawValue: equipmentRaw) ?? .lowImpact }
    var sex: BiologicalSex { BiologicalSex(rawValue: sexRaw) ?? .male }
    var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }

    /// Mifflin–St Jeor basal metabolic rate.
    var basalMetabolicRate: Double {
        let base = (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age))
        return sex == .male ? base + 5 : base - 161
    }

    /// Maintenance calories at a lightly-active multiplier.
    var maintenanceCalories: Double { basalMetabolicRate * 1.45 }

    var calorieBudget: Int { Int((maintenanceCalories * goal.calorieFactor).rounded()) }
    var proteinTarget: Int { Int((weightKg * goal.proteinPerKg).rounded()) }
    var fatTarget: Int { Int((Double(calorieBudget) * 0.27 / 9).rounded()) }
    var carbTarget: Int {
        let remaining = Double(calorieBudget) - (Double(proteinTarget) * 4) - (Double(fatTarget) * 9)
        return max(0, Int((remaining / 4).rounded()))
    }

    var bodyMassIndex: Double {
        let metres = heightCm / 100
        guard metres > 0 else { return 0 }
        return weightKg / (metres * metres)
    }
}

/// One analysed meal. Created only from a real camera capture + server response.
@Model
final class MealEntry {
    var mealName: String
    var estimatedGrams: Double
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var confidence: Double
    var items: [String]
    var loggedAt: Date
    /// JPEG thumbnail of the captured plate.
    @Attribute(.externalStorage) var thumbnail: Data?

    init(
        mealName: String,
        estimatedGrams: Double,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        confidence: Double,
        items: [String],
        thumbnail: Data?,
        loggedAt: Date = .now
    ) {
        self.mealName = mealName
        self.estimatedGrams = estimatedGrams
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.confidence = confidence
        self.items = items
        self.thumbnail = thumbnail
        self.loggedAt = loggedAt
    }
}

/// One completed body scan, solved on-device by `BodyMeasurementEngine`.
/// This is the local historical record used to graph progress over time.
@Model
final class BodyScan {
    var chestCm: Double
    var waistCm: Double
    var hipCm: Double
    var shoulderCm: Double
    var thighCm: Double
    /// 0..1 confidence in this solve, from joint quality and angles measured.
    var quality: Double
    var frameCount: Int
    var capturedAt: Date
    /// Body fat estimate, when neck and waist both resolved cleanly.
    var bodyFatPercent: Double?
    /// What measured this scan — currently always "On-device Vision".
    var provider: String = ""

    init(
        chestCm: Double,
        waistCm: Double,
        hipCm: Double,
        shoulderCm: Double,
        thighCm: Double,
        quality: Double,
        frameCount: Int,
        bodyFatPercent: Double? = nil,
        provider: String = "",
        capturedAt: Date = .now
    ) {
        self.chestCm = chestCm
        self.waistCm = waistCm
        self.hipCm = hipCm
        self.shoulderCm = shoulderCm
        self.thighCm = thighCm
        self.quality = quality
        self.frameCount = frameCount
        self.bodyFatPercent = bodyFatPercent
        self.provider = provider
        self.capturedAt = capturedAt
    }

    /// Waist-to-hip ratio, a standard body-composition indicator.
    var waistToHip: Double { hipCm > 0 ? waistCm / hipCm : 0 }
}

/// The three headline circumferences the scanner surfaces on the dashboard.
nonisolated enum BodyMetric: String, CaseIterable, Identifiable, Sendable {
    case waist, hip, chest

    nonisolated var id: String { rawValue }

    var title: String {
        switch self {
        case .waist: "Waist"
        case .hip: "Hips"
        case .chest: "Chest"
        }
    }

    func value(in scan: BodyScan) -> Double {
        switch self {
        case .waist: scan.waistCm
        case .hip: scan.hipCm
        case .chest: scan.chestCm
        }
    }
}

/// One completed work interval — the time-under-tension history.
@Model
final class SetLog {
    var exerciseID: String
    var exerciseName: String
    var weightKg: Double
    var reps: Int
    var setIndex: Int
    var isBodyweight: Bool
    var loggedAt: Date
    /// Seconds of work actually completed in this interval.
    var holdSeconds: Int = 0

    init(
        exerciseID: String,
        exerciseName: String,
        setIndex: Int,
        holdSeconds: Int,
        loggedAt: Date = .now
    ) {
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.weightKg = 0
        self.reps = 0
        self.setIndex = setIndex
        self.isBodyweight = true
        self.loggedAt = loggedAt
        self.holdSeconds = holdSeconds
    }

    var minutes: Double { Double(holdSeconds) / 60 }
}

/// A finished workout session summary.
@Model
final class WorkoutSession {
    var programID: String
    var programTitle: String
    var durationSeconds: Int
    /// Seconds spent working, excluding rest. Legacy name kept so existing
    /// stores migrate without a schema break.
    var totalVolumeKg: Double
    /// Work intervals completed.
    var setCount: Int
    var finishedAt: Date

    init(
        programID: String,
        programTitle: String,
        durationSeconds: Int,
        workSeconds: Int,
        intervals: Int,
        finishedAt: Date = .now
    ) {
        self.programID = programID
        self.programTitle = programTitle
        self.durationSeconds = durationSeconds
        self.totalVolumeKg = Double(workSeconds)
        self.setCount = intervals
        self.finishedAt = finishedAt
    }

    /// Seconds of actual work in this session.
    var workSeconds: Int { Int(totalVolumeKg) }

    var workMinutes: Int { workSeconds / 60 }
}

/// A user-created daily habit plus its completion marks.
@Model
final class Habit {
    var title: String
    var symbol: String
    var createdAt: Date
    var completedDayKeys: [String]

    init(title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
        self.createdAt = .now
        self.completedDayKeys = []
    }

    func isDone(on date: Date) -> Bool {
        completedDayKeys.contains(DayKey.make(date))
    }

    func toggle(on date: Date) {
        let key = DayKey.make(date)
        if let index = completedDayKeys.firstIndex(of: key) {
            completedDayKeys.remove(at: index)
        } else {
            completedDayKeys.append(key)
        }
    }

    /// Consecutive days completed, counting back from `date`.
    func streak(endingOn date: Date) -> Int {
        var count = 0
        var cursor = date
        let calendar = Calendar.current
        while completedDayKeys.contains(DayKey.make(cursor)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}

/// A user-built workout: named list of moves from the library.
@Model
final class CustomWorkout {
    var name: String
    var exerciseIDs: [String]
    /// Rounds performed of each move. Legacy name, kept for store compatibility.
    var setsPerExercise: Int
    var createdAt: Date
    /// Length of each work interval, in seconds.
    var workSeconds: Int = 45

    init(name: String, exerciseIDs: [String], rounds: Int, workSeconds: Int) {
        self.name = name
        self.exerciseIDs = exerciseIDs
        self.setsPerExercise = rounds
        self.createdAt = .now
        self.workSeconds = workSeconds
    }

    var rounds: Int { setsPerExercise }
}

/// Progress through a started multi-day challenge.
@Model
final class ChallengeProgress {
    /// Stable id into `ChallengeLibrary`.
    var challengeID: String
    var title: String
    var totalDays: Int
    var completedDays: [Int]
    var startedAt: Date

    init(challengeID: String, title: String, totalDays: Int) {
        self.challengeID = challengeID
        self.title = title
        self.totalDays = totalDays
        self.completedDays = []
        self.startedAt = .now
    }

    var isComplete: Bool { completedDays.count >= totalDays }

    func isDayDone(_ day: Int) -> Bool { completedDays.contains(day) }

    func markDone(_ day: Int) {
        guard !completedDays.contains(day) else { return }
        completedDays.append(day)
    }
}

/// A daily bodyweight check-in.
@Model
final class WeightEntry {
    var weightKg: Double
    var recordedAt: Date

    init(weightKg: Double, recordedAt: Date = .now) {
        self.weightKg = weightKg
        self.recordedAt = recordedAt
    }
}

// MARK: - Helpers

nonisolated enum DayKey {
    static func make(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

nonisolated enum LightBoltUnits {
    static func kg(fromLb value: Double) -> Double { value * 0.45359237 }
    static func lb(fromKg value: Double) -> Double { value / 0.45359237 }
    static func cm(fromIn value: Double) -> Double { value * 2.54 }
    static func inches(fromCm value: Double) -> Double { value / 2.54 }

    static func displayWeight(kg: Double, units: UnitSystem) -> Double {
        units == .metric ? kg : lb(fromKg: kg)
    }

    static func displayLength(cm: Double, units: UnitSystem) -> Double {
        units == .metric ? cm : inches(fromCm: cm)
    }
}
