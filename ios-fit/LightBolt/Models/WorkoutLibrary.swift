import Foundation
import SwiftData

// MARK: - Deterministic RNG

/// SplitMix64 — tiny deterministic generator so the library is identical on
/// every launch and every device.
nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// FNV-1a string hash — stable across launches (unlike `hashValue`).
nonisolated func stableSeed(_ text: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
    return hash
}

// MARK: - Training level

nonisolated enum TrainingLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case beginner, intermediate, advanced, elite

    nonisolated var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var exerciseCount: Int {
        switch self {
        case .beginner: 4
        case .intermediate: 5
        case .advanced: 6
        case .elite: 7
        }
    }

    /// Rounds of each movement.
    var baseRounds: Int {
        switch self {
        case .beginner: 2
        case .intermediate: 3
        case .advanced: 3
        case .elite: 4
        }
    }

    /// Length of a work interval, in seconds.
    var workSeconds: Int {
        switch self {
        case .beginner: 30
        case .intermediate: 40
        case .advanced: 45
        case .elite: 50
        }
    }

    var restSeconds: Int {
        switch self {
        case .beginner: 25
        case .intermediate: 20
        case .advanced: 15
        case .elite: 12
        }
    }

    /// A rest day every N days inside a challenge. 0 = no scheduled rest.
    var restCadence: Int {
        switch self {
        case .beginner: 3
        case .intermediate: 4
        case .advanced: 5
        case .elite: 7
        }
    }
}

// MARK: - Muscles & splits

nonisolated enum Muscle: String, CaseIterable, Identifiable, Sendable {
    case chest, back, shoulders, arms, quads, hamstrings, glutes, calves, core, conditioning

    nonisolated var id: String { rawValue }

    var title: String {
        switch self {
        case .core: "Core & Abs"
        case .conditioning: "Conditioning"
        case .arms: "Arms"
        default: rawValue.capitalized
        }
    }

    var symbol: String {
        switch self {
        case .chest: "figure.wrestling"
        case .back: "figure.rower"
        case .shoulders: "figure.arms.open"
        case .arms: "figure.arms.open"
        case .quads: "figure.strengthtraining.functional"
        case .hamstrings: "figure.cooldown"
        case .glutes: "figure.step.training"
        case .calves: "figure.walk"
        case .core: "figure.core.training"
        case .conditioning: "flame.fill"
        }
    }
}

nonisolated enum WorkoutSplit: String, CaseIterable, Identifiable, Sendable {
    case push, pull, legs, upper, lower, fullBody, coreAbs, hiit, arms, chestBack, shouldersArms, glutesHams

    nonisolated var id: String { rawValue }

    var displayName: String {
        switch self {
        case .push: "Push"
        case .pull: "Pull"
        case .legs: "Legs"
        case .upper: "Upper"
        case .lower: "Lower"
        case .fullBody: "Full Body"
        case .coreAbs: "Core & Abs"
        case .hiit: "HIIT"
        case .arms: "Arms"
        case .chestBack: "Chest & Back"
        case .shouldersArms: "Delts & Arms"
        case .glutesHams: "Glutes & Hams"
        }
    }

    var focus: String {
        switch self {
        case .push: "Chest · Shoulders · Arms"
        case .pull: "Back · Arms · Core"
        case .legs: "Quads · Hams · Glutes"
        case .upper: "Chest · Back · Arms"
        case .lower: "Quads · Glutes · Calves"
        case .fullBody: "Everything · One Session"
        case .coreAbs: "Abs · Obliques · Stability"
        case .hiit: "Conditioning · Fat Burn"
        case .arms: "Arms · Shoulders"
        case .chestBack: "Chest & Back Circuit"
        case .shouldersArms: "Delts · Arms"
        case .glutesHams: "Glutes · Hamstrings"
        }
    }

    /// Muscle slots the generator fills, in order. Trimmed/extended by level.
    var slots: [Muscle] {
        switch self {
        case .push: [.chest, .shoulders, .chest, .arms, .shoulders, .arms, .core]
        case .pull: [.back, .back, .arms, .back, .core, .core, .conditioning]
        case .legs: [.quads, .hamstrings, .glutes, .quads, .calves, .core, .hamstrings]
        case .upper: [.chest, .back, .shoulders, .arms, .chest, .core, .back]
        case .lower: [.quads, .glutes, .hamstrings, .quads, .calves, .glutes, .core]
        case .fullBody: [.quads, .chest, .back, .shoulders, .core, .conditioning, .glutes]
        case .coreAbs: [.core, .core, .core, .conditioning, .core, .core, .core]
        case .hiit: [.conditioning, .quads, .conditioning, .core, .conditioning, .conditioning, .core]
        case .arms: [.arms, .shoulders, .arms, .chest, .shoulders, .arms, .core]
        case .chestBack: [.chest, .back, .chest, .back, .chest, .back, .core]
        case .shouldersArms: [.shoulders, .arms, .shoulders, .arms, .chest, .core, .arms]
        case .glutesHams: [.glutes, .hamstrings, .glutes, .hamstrings, .glutes, .core, .calves]
        }
    }

    var goals: [LightBoltGoal] {
        switch self {
        case .hiit, .coreAbs: [.lose]
        case .legs, .lower, .fullBody, .glutesHams: [.lose, .muscle, .strength]
        default: [.muscle, .strength]
        }
    }

    var symbol: String {
        switch self {
        case .push: "figure.wrestling"
        case .pull: "figure.rower"
        case .legs, .lower: "figure.strengthtraining.functional"
        case .upper, .arms, .shouldersArms: "figure.arms.open"
        case .fullBody: "figure.mixed.cardio"
        case .coreAbs: "figure.core.training"
        case .hiit: "flame.fill"
        case .chestBack: "figure.strengthtraining.traditional"
        case .glutesHams: "figure.step.training"
        }
    }

    /// Plain-English session names used to title generated workouts.
    var sessionNames: [String] {
        switch self {
        case .push:
            ["Push-Up Builder", "Chest Circuit", "Push Volume", "Triceps Burner", "Floor Press",
             "Push-Up Ladder", "Chest & Shoulders", "Push Endurance", "Explosive Push", "Push Burnout"]
        case .pull:
            ["Back Circuit", "Posture Pull", "Back Volume", "Spinal Strength", "Pull Endurance",
             "Rear Chain", "Back Burner", "Superman Sets", "Pull Ladder", "Back Burnout"]
        case .legs:
            ["Leg Day", "Squat Volume", "Quad Burner", "Hamstring Focus", "Leg Endurance",
             "Single-Leg Focus", "Leg Burnout", "Wall Sit Legs", "Silent Legs", "Leg Ladder"]
        case .upper:
            ["Upper Body", "Upper Volume", "Push & Pull", "Upper Endurance", "Upper Sculpt",
             "Torso Burner", "Upper Circuit", "Arms & Chest", "Upper Ladder", "Upper Burnout"]
        case .lower:
            ["Lower Body", "Lower Volume", "Glute & Quad", "Lower Endurance", "Hip Burner",
             "Lower Sculpt", "Lower Circuit", "Leg & Glute", "Lower Ladder", "Lower Burnout"]
        case .fullBody:
            ["Full Body", "Full Body Circuit", "Total Body Burn", "Full Body Stamina", "Whole Body",
             "Full Body Sculpt", "Full Body Ladder", "Total Body Volume", "Full Body Burnout", "Morning Full Body"]
        case .coreAbs:
            ["Abs Crusher", "Core Circuit", "Six-Pack Burner", "Core Burner", "Lower Abs Focus",
             "Oblique Burner", "Abs Ladder", "Core Stability", "Flat Stomach", "Abs Burnout"]
        case .hiit:
            ["Cardio Blast", "Fat Burn HIIT", "Cardio Burner", "Sweat Circuit", "No-Jump Cardio",
             "Cardio Ladder", "Fat Burn Express", "Stamina Builder", "Cardio Burnout", "Quick Sweat"]
        case .arms:
            ["Arm Day", "Arm Burner", "Triceps Focus", "Arm Volume", "Arm Endurance",
             "Arm Sculpt", "Arm Ladder", "Push & Hold", "Arm Circuit", "Arm Burnout"]
        case .chestBack:
            ["Chest & Back", "Push Pull Circuit", "Torso Burner", "Chest Back Volume", "Torso Endurance",
             "Torso Sculpt", "Push Pull Ladder", "Torso Stamina", "Chest Back Home", "Torso Burnout"]
        case .shouldersArms:
            ["Delts & Arms", "Shoulder Burner", "Delt Volume", "Pike & Dip", "Shoulder Sculpt",
             "Delt Endurance", "Shoulder Ladder", "Arms & Delts", "Delt Circuit", "Shoulder Burnout"]
        case .glutesHams:
            ["Glutes & Hams", "Glute Builder", "Bridge Volume", "Hamstring Focus", "Glute Endurance",
             "Glute Sculpt", "Glute Ladder", "Hip Burner", "Glute Circuit", "Glute Burnout"]
        }
    }
}

// MARK: - Move library

/// One equipment-free movement, animated by the stickman.
nonisolated struct HomeMove: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let muscle: Muscle
    let move: StickMove
    let cue: String

    var symbol: String { muscle.symbol }
    var isHold: Bool { move.isHold }
    /// Both feet leave the floor at some point.
    var isExplosive: Bool { move.isExplosive }
}

/// Everything LightBolt can ask you to do in a living room: no bar, no bench,
/// no dumbbells. Every entry is animated — nothing is listed that the stickman
/// cannot demonstrate.
nonisolated enum MoveLibrary {
    private static func m(_ id: String, _ name: String, _ muscle: Muscle, _ move: StickMove, _ cue: String) -> HomeMove {
        HomeMove(id: id, name: name, muscle: muscle, move: move, cue: cue)
    }

    // MARK: Chest

    private static let chest: [HomeMove] = [
        m("m-pushup", "Push-Up", .chest, .pushUp, "Straight line ears to heels, elbows 45°, full lockout."),
        m("m-pushup-wide", "Wide Push-Up", .chest, .pushUp, "Hands wide of the shoulders — the chest leads the descent."),
        m("m-pushup-knee", "Knee Push-Up", .chest, .pushUp, "Knees down, hips locked in line, full range every rep."),
        m("m-pushup-tempo", "Tempo Push-Up", .chest, .pushUp, "Four seconds down, one second up. Brutal without any weight."),
        m("m-pushup-incline", "Incline Push-Up", .chest, .pushUp, "Hands on a chair or a sofa arm — perfect for building volume."),
        m("m-pushup-archer", "Archer Push-Up", .chest, .pushUp, "Shift the load over one arm, the other stays long."),
        m("m-pushup-stagger", "Staggered Push-Up", .chest, .pushUp, "One hand forward, one back. Swap the lead each round.")
    ]

    // MARK: Back

    private static let back: [HomeMove] = [
        m("m-superman", "Superman", .back, .superman, "Lift the chest and thighs, sweep the arms like a pulldown."),
        m("m-swimmer", "Swimmer Kick", .back, .superman, "Face down, flutter the arms and legs, chest off the floor."),
        m("m-snowangel", "Reverse Snow Angel", .back, .superman, "Chest lifted, sweep slow arcs, palms off the floor."),
        m("m-birddog", "Bird Dog", .back, .birdDog, "Opposite arm and leg long, hips square, pause at the top."),
        m("m-doorrow", "Door Row", .back, .doorRow, "Grip a solid door frame, lean back, pull the chest to your hands."),
        m("m-towelrow", "Towel Row", .back, .doorRow, "Towel around a post, sit back, row to the sternum.")
    ]

    // MARK: Shoulders

    private static let shoulders: [HomeMove] = [
        m("m-pike", "Pike Push-Up", .shoulders, .pikePushUp, "Hips high, crown of the head to the floor between the hands."),
        m("m-pike-elev", "Elevated Pike Push-Up", .shoulders, .pikePushUp, "Feet on a chair, torso vertical, press like a handstand."),
        m("m-armcircle", "Arm Circles", .shoulders, .armCircle, "Arms out, small fast circles. Forward, then back. No rest."),
        m("m-tap", "Shoulder Tap", .shoulders, .shoulderTap, "Wide base, zero hip sway, slow and deliberate."),
        m("m-bearhold", "Bear Hold", .shoulders, .bearHold, "Knees an inch off the floor, shoulders stacked, breathe.")
    ]

    // MARK: Arms

    private static let arms: [HomeMove] = [
        m("m-dip", "Chair Dip", .arms, .chairDip, "Shoulders down and back, descend to 90°, no shrugging."),
        m("m-diamond", "Diamond Push-Up", .arms, .pushUp, "Thumbs and index fingers touch, elbows brush the ribs."),
        m("m-close-pu", "Close-Grip Push-Up", .arms, .pushUp, "Hands under the chest, elbows travel straight back."),
        m("m-dip-neg", "Slow Chair Dip", .arms, .chairDip, "Five seconds down, press up. Triceps under tension the whole time."),
        m("m-row-under", "Underhand Door Row", .arms, .doorRow, "Palms up on the frame, pull the chest up, biceps lead."),
        m("m-pushup-tri", "Sphinx Push-Up", .arms, .pushUp, "Forearms to palms and back, elbows under the shoulders.")
    ]

    // MARK: Quads

    private static let quads: [HomeMove] = [
        m("m-squat", "Bodyweight Squat", .quads, .squat, "Three-second descent, explode up, no bouncing."),
        m("m-squat-slow", "Slow Squat", .quads, .squat, "Four seconds down, one up. Silent feet the whole set."),
        m("m-pulse", "Pulse Squat", .quads, .squatPulse, "Bottom third only, small fast pulses, never fully stand."),
        m("m-wallsit", "Wall Sit", .quads, .wallSit, "Thighs parallel, back flat on the wall, hands off the legs."),
        m("m-split", "Split Squat", .quads, .splitSquat, "Long stance, vertical front shin. Swap legs each round."),
        m("m-lunge", "Alternating Lunge", .quads, .lunge, "Step long, torso upright, push through the front heel."),
        m("m-jumpsquat", "Jump Squat", .quads, .jumpSquat, "Land soft through the mid-foot and reset every rep.")
    ]

    // MARK: Hamstrings

    private static let hamstrings: [HomeMove] = [
        m("m-bridge-march", "Bridge March", .hamstrings, .bridgeMarch, "Hold the bridge, lift one knee at a time, hips dead level."),
        m("m-sl-bridge", "Single-Leg Bridge", .hamstrings, .bridgeMarch, "One knee to the chest, drive through the planted heel."),
        m("m-toe-touch", "Standing Toe Touch", .hamstrings, .toeTouch, "Soft knees, hinge back, reach long. Stand tall between reps."),
        m("m-goodmorning", "Bodyweight Good Morning", .hamstrings, .toeTouch, "Hands behind the head, hinge back, flat spine."),
        m("m-donkey", "Donkey Kick", .hamstrings, .donkeyKick, "Heel to the ceiling, hips square, squeeze at the top.")
    ]

    // MARK: Glutes

    private static let glutes: [HomeMove] = [
        m("m-bridge", "Glute Bridge", .glutes, .gluteBridge, "Ribs down, squeeze at the top for two full seconds."),
        m("m-frog", "Frog Pump", .glutes, .gluteBridge, "Soles together, knees wide, pulse the hips up."),
        m("m-donkey-2", "Donkey Kick", .glutes, .donkeyKick, "Kick the heel to the ceiling, no arching the lower back."),
        m("m-split-glute", "Deep Split Squat", .glutes, .splitSquat, "Sink straight down, front heel loaded, chest tall."),
        m("m-lunge-rev", "Reverse Lunge", .glutes, .lunge, "Step back and down, push the floor away with the front heel."),
        m("m-bridge-hold", "Bridge Hold", .glutes, .gluteBridge, "Hold the top position, glutes locked, ribs down.")
    ]

    // MARK: Calves

    private static let calves: [HomeMove] = [
        m("m-calf", "Calf Raise", .calves, .calfRaise, "Full stretch at the bottom, two-second squeeze at the top."),
        m("m-calf-single", "Single-Leg Calf Raise", .calves, .calfRaise, "Fingertips on the wall, one leg, full range. Swap each round."),
        m("m-pogo", "Pogo Hop", .calves, .jumpRope, "Stiff knees, bounce off the ankles, quick contacts."),
        m("m-calf-slow", "Slow Calf Raise", .calves, .calfRaise, "Three seconds up, three down. Quiet and controlled.")
    ]

    // MARK: Core

    private static let core: [HomeMove] = [
        m("m-plank", "Plank", .core, .plank, "Squeeze the glutes and the fists, breathe shallow, never sag."),
        m("m-sideplank", "Side Plank", .core, .sidePlank, "Stack the feet, push the hip high, long neck. Swap sides."),
        m("m-hollow", "Hollow Hold", .core, .hollowHold, "Lower back glued to the floor, arms by the ears."),
        m("m-crunch", "Crunch", .core, .crunch, "Ribs to hips, chin off the chest, exhale at the top."),
        m("m-situp", "Sit-Up", .core, .sitUp, "Curl up one vertebra at a time, control the way down."),
        m("m-legraise", "Lying Leg Raise", .core, .legRaise, "Hands under the hips, lower to a hover, never touch down."),
        m("m-flutter", "Flutter Kick", .core, .flutterKick, "Small fast kicks, lower back pressed into the floor."),
        m("m-bicycle", "Bicycle Crunch", .core, .bicycleCrunch, "Slow rotation, elbow to opposite knee, extend fully."),
        m("m-russian", "Russian Twist", .core, .russianTwist, "Heels light, rotate from the ribs, not the arms."),
        m("m-deadbug", "Dead Bug", .core, .deadBug, "Opposite arm and leg, lower slow, back stays flat."),
        m("m-tap-core", "Plank Shoulder Tap", .core, .shoulderTap, "Wide base, zero hip sway, slow and deliberate."),
        m("m-plankjack", "Plank Jack", .core, .plankJack, "Plank position, jump the feet wide and back, hips still."),
        m("m-bear-core", "Bear Hold", .core, .bearHold, "Knees hovering, back flat enough to balance a cup."),
        m("m-birddog-core", "Bird Dog", .core, .birdDog, "Opposite arm and leg long, pause, switch under control.")
    ]

    // MARK: Conditioning

    private static let conditioning: [HomeMove] = [
        m("m-jack", "Jumping Jack", .conditioning, .jumpingJack, "Full arm arc overhead, light feet, steady rhythm."),
        m("m-star", "Star Jump", .conditioning, .starJump, "Explode into a star shape, land soft and coiled."),
        m("m-highknee", "High Knees", .conditioning, .highKnees, "Knees to hip height, stay on the balls of the feet."),
        m("m-buttkick", "Butt Kick", .conditioning, .buttKick, "Heels to the glutes, fast turnover, tall posture."),
        m("m-skater", "Skater Hop", .conditioning, .skater, "Bound side to side, stick each landing on one leg."),
        m("m-rope", "Jump Rope", .conditioning, .jumpRope, "Small bounces, wrists do the work, stay on the balls of the feet."),
        m("m-burpee", "Burpee", .conditioning, .burpee, "Chest to floor, feet in, full hip extension at the top."),
        m("m-thrust", "Squat Thrust", .conditioning, .squatThrust, "Hands down, feet back to a plank, snap them in. No jump."),
        m("m-mtn", "Mountain Climber", .conditioning, .mountainClimber, "Hips level, drive the knees, shoulders stacked."),
        m("m-shadow", "Shadow Boxing", .conditioning, .shadowBox, "Hands up, rotate the hips into every punch, stay light."),
        m("m-inchworm", "Inchworm", .conditioning, .inchworm, "Walk the hands out to a plank, walk the feet back in."),
        m("m-march", "Marching In Place", .conditioning, .highKnees, "Drive the knees, pump the arms. Quiet, controlled, no hop.")
    ]

    static let all: [HomeMove] = chest + back + shoulders + arms + quads + hamstrings
        + glutes + calves + core + conditioning

    static let byID: [String: HomeMove] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static var count: Int { all.count }

    /// Moves for a muscle, filtered to what the chosen intensity allows.
    static func pool(for muscle: Muscle, intensity: TrainingIntensity) -> [HomeMove] {
        let matches = all.filter { $0.muscle == muscle }
        guard intensity == .lowImpact else { return matches }
        let quiet = matches.filter { !$0.isExplosive }
        return quiet.isEmpty ? matches : quiet
    }

    static func moves(for intensity: TrainingIntensity) -> [HomeMove] {
        intensity == .lowImpact ? all.filter { !$0.isExplosive } : all
    }
}

// MARK: - Workout library

/// The full training vault. Every programme is generated deterministically from
/// the move library — same catalogue on every device, zero bundled data blob,
/// zero equipment, every interval on the clock.
nonisolated enum WorkoutLibrary {
    /// Named session variants available per split and intensity.
    static let variantsPerSplit = 10

    static let all: [Program] = {
        var programs: [Program] = []
        programs.reserveCapacity(WorkoutSplit.allCases.count * 2 * TrainingLevel.allCases.count * variantsPerSplit)
        for split in WorkoutSplit.allCases {
            for intensity in TrainingIntensity.allCases {
                for level in TrainingLevel.allCases {
                    for variant in 1...variantsPerSplit {
                        programs.append(make(split: split, intensity: intensity, level: level, variant: variant))
                    }
                }
            }
        }
        return programs
    }()

    static var count: Int { all.count }

    static let byID: [String: Program] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func workouts(split: WorkoutSplit, intensity: TrainingIntensity, level: TrainingLevel) -> [Program] {
        all.filter { $0.id.hasPrefix("lib-\(split.rawValue)-\(intensity.rawValue)-\(level.rawValue)-") }
    }

    // MARK: Generation

    private static func make(
        split: WorkoutSplit,
        intensity: TrainingIntensity,
        level: TrainingLevel,
        variant: Int
    ) -> Program {
        let id = "lib-\(split.rawValue)-\(intensity.rawValue)-\(level.rawValue)-\(variant)"
        var rng = SplitMix64(seed: stableSeed(id))

        var cursors: [Muscle: [HomeMove]] = [:]
        var exercises: [Exercise] = []
        let slots = Array(split.slots.prefix(level.exerciseCount))

        for (index, muscle) in slots.enumerated() {
            if cursors[muscle] == nil {
                cursors[muscle] = MoveLibrary.pool(for: muscle, intensity: intensity).shuffled(using: &rng)
            }
            guard var remaining = cursors[muscle], !remaining.isEmpty else { continue }
            let pick = remaining.removeFirst()
            cursors[muscle] = remaining

            let isOpener = index == 0
            exercises.append(
                Exercise(
                    id: pick.id,
                    name: pick.name,
                    target: pick.muscle.title,
                    symbol: pick.symbol,
                    move: pick.move,
                    rounds: min(5, level.baseRounds + (isOpener ? 1 : 0)),
                    workSeconds: work(for: pick, level: level),
                    restSeconds: rest(for: pick.muscle, level: level),
                    cue: pick.cue
                )
            )
        }

        let names = split.sessionNames
        let sessionName = names[(variant - 1) % names.count]
        let suffix = intensity == .lowImpact ? " · QUIET" : ""

        return Program(
            id: id,
            title: "\(sessionName.uppercased()) · \(level.title.uppercased())\(suffix)",
            focus: split.focus,
            intensity: intensity,
            goals: split.goals,
            exercises: exercises,
            level: level
        )
    }

    /// Holds run a touch shorter than dynamic work — 50 seconds of plank is a
    /// very different ask from 50 seconds of squats.
    private static func work(for move: HomeMove, level: TrainingLevel) -> Int {
        move.isHold ? max(20, level.workSeconds - 5) : level.workSeconds
    }

    private static func rest(for muscle: Muscle, level: TrainingLevel) -> Int {
        switch muscle {
        case .conditioning: level.restSeconds + 5
        case .core, .calves: max(10, level.restSeconds - 5)
        default: level.restSeconds
        }
    }
}

// MARK: - Challenges

nonisolated struct Challenge: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let theme: String
    let symbol: String
    let days: Int
    let level: TrainingLevel
    let intensity: TrainingIntensity
    let split: WorkoutSplit

    /// True when the plan schedules recovery on this zero-based day.
    func isRestDay(_ day: Int) -> Bool {
        let cadence = level.restCadence
        guard cadence > 0 else { return false }
        return day % cadence == cadence - 1
    }

    /// Deterministic workout for a zero-based day; nil on rest days.
    func program(forDay day: Int) -> Program? {
        guard !isRestDay(day) else { return nil }
        let candidates = WorkoutLibrary.workouts(split: split, intensity: intensity, level: level)
        guard !candidates.isEmpty else { return nil }
        var rng = SplitMix64(seed: stableSeed("\(id)-day-\(day)"))
        return candidates[Int(rng.next() % UInt64(candidates.count))]
    }

    var workoutDayCount: Int { (0..<days).filter { !isRestDay($0) }.count }
}

/// Goal-first challenge plans, named for the outcome they chase —
/// "30 DAY ABS · BEGINNER", "21 DAY FAT LOSS · ADVANCED".
nonisolated enum ChallengeLibrary {
    private struct Theme {
        let slug: String
        let name: String
        let split: WorkoutSplit
        let symbol: String
    }

    private static let themes: [Theme] = [
        Theme(slug: "abs", name: "ABS", split: .coreAbs, symbol: "figure.core.training"),
        Theme(slug: "flat-stomach", name: "FLAT STOMACH", split: .coreAbs, symbol: "arrow.down.right.and.arrow.up.left"),
        Theme(slug: "six-pack", name: "SIX-PACK", split: .coreAbs, symbol: "square.grid.3x2.fill"),
        Theme(slug: "core-stability", name: "CORE STABILITY", split: .coreAbs, symbol: "shield.fill"),
        Theme(slug: "fat-loss", name: "FAT LOSS", split: .hiit, symbol: "flame.fill"),
        Theme(slug: "cardio", name: "CARDIO", split: .hiit, symbol: "heart.fill"),
        Theme(slug: "sweat-burn", name: "SWEAT & BURN", split: .hiit, symbol: "drop.fill"),
        Theme(slug: "full-body", name: "FULL BODY", split: .fullBody, symbol: "figure.mixed.cardio"),
        Theme(slug: "build-muscle", name: "BUILD MUSCLE", split: .fullBody, symbol: "figure.strengthtraining.traditional"),
        Theme(slug: "total-tone", name: "TOTAL TONE", split: .fullBody, symbol: "sparkles"),
        Theme(slug: "beginner-start", name: "BEGINNER START", split: .fullBody, symbol: "flag.fill"),
        Theme(slug: "upper-body", name: "UPPER BODY", split: .upper, symbol: "figure.arms.open"),
        Theme(slug: "lower-body", name: "LOWER BODY", split: .lower, symbol: "figure.strengthtraining.functional"),
        Theme(slug: "strong-legs", name: "STRONG LEGS", split: .legs, symbol: "figure.run"),
        Theme(slug: "glutes", name: "GLUTES", split: .glutesHams, symbol: "figure.step.training"),
        Theme(slug: "stronger-arms", name: "STRONGER ARMS", split: .arms, symbol: "figure.arms.open"),
        Theme(slug: "chest-back", name: "CHEST & BACK", split: .chestBack, symbol: "figure.wrestling"),
        Theme(slug: "shoulders", name: "SHOULDERS", split: .shouldersArms, symbol: "figure.cooldown"),
        Theme(slug: "push-power", name: "PUSH POWER", split: .push, symbol: "figure.wrestling"),
        Theme(slug: "pull-strength", name: "PULL STRENGTH", split: .pull, symbol: "figure.rower")
    ]

    private static let durations = [7, 14, 21, 30]

    static let all: [Challenge] = {
        var challenges: [Challenge] = []
        challenges.reserveCapacity(themes.count * durations.count * TrainingLevel.allCases.count * 2)
        for theme in themes {
            for days in durations {
                for level in TrainingLevel.allCases {
                    for intensity in TrainingIntensity.allCases {
                        let quiet = intensity == .lowImpact ? " · QUIET" : ""
                        challenges.append(
                            Challenge(
                                id: "ch-\(theme.slug)-\(days)-\(level.rawValue)-\(intensity.rawValue)",
                                title: "\(days) DAY \(theme.name) · \(level.title.uppercased())\(quiet)",
                                theme: theme.name,
                                symbol: theme.symbol,
                                days: days,
                                level: level,
                                intensity: intensity,
                                split: theme.split
                            )
                        )
                    }
                }
            }
        }
        return challenges
    }()

    static var count: Int { all.count }

    static func challenge(id: String) -> Challenge? {
        all.first { $0.id == id }
    }
}

// MARK: - Custom workout conversion

extension CustomWorkout {
    /// Materialises the saved build into a runnable `Program`.
    nonisolated func asProgram() -> Program {
        let picked = exerciseIDs.compactMap { MoveLibrary.byID[$0] }
        let seconds = max(15, workSeconds)
        let exercises = picked.map { move in
            Exercise(
                id: move.id,
                name: move.name,
                target: move.muscle.title,
                symbol: move.symbol,
                move: move.move,
                rounds: rounds,
                workSeconds: move.isHold ? max(20, seconds - 5) : seconds,
                restSeconds: 20,
                cue: move.cue
            )
        }
        let isQuiet = picked.allSatisfy { !$0.isExplosive }
        let muscles = Array(Set(picked.map(\.muscle.title))).sorted().prefix(3).joined(separator: " · ")
        return Program(
            id: "custom-\(stableSeed("\(name)-\(createdAt.timeIntervalSince1970)"))",
            title: name.uppercased(),
            focus: muscles.isEmpty ? "Custom Build" : muscles,
            intensity: isQuiet ? .lowImpact : .fullPower,
            goals: LightBoltGoal.allCases.map { $0 },
            exercises: exercises,
            level: .intermediate
        )
    }
}
