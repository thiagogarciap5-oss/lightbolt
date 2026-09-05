import Foundation

/// One movement inside a session.
///
/// LightBolt is a timed app: a movement is defined by how long you work, never
/// by how many reps you count. `move` is the stickman animation that plays for
/// exactly that long.
nonisolated struct Exercise: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let target: String
    let symbol: String
    let move: StickMove
    /// How many times this interval is repeated in the session.
    let rounds: Int
    /// Length of one work interval, in seconds.
    let workSeconds: Int
    let restSeconds: Int
    let cue: String

    /// Holds are timed but never counted in repetitions.
    var isHold: Bool { move.isHold }

    /// Repetitions the animation will pace out over the interval. Shown as
    /// guidance, not a target to chase — the clock is the target.
    var pacedReps: Int {
        guard !isHold else { return 0 }
        return max(1, Int((Double(workSeconds) / move.cycleSeconds).rounded()))
    }

    /// Actual seconds per repetition once the interval divides evenly, so the
    /// last rep finishes exactly on zero.
    var repSeconds: Double {
        guard !isHold, pacedReps > 0 else { return move.cycleSeconds }
        return Double(workSeconds) / Double(pacedReps)
    }

    var totalWorkSeconds: Int { rounds * workSeconds }

    /// "45 sec × 3" style label.
    var intervalLabel: String { "\(workSeconds) sec × \(rounds)" }
}

nonisolated struct Program: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let focus: String
    let intensity: TrainingIntensity
    let goals: [LightBoltGoal]
    let exercises: [Exercise]
    var level: TrainingLevel = .intermediate

    /// Work plus rest, rounded up to the nearest minute.
    var estimatedMinutes: Int {
        let seconds = exercises.reduce(0) { partial, exercise in
            partial + exercise.rounds * (exercise.workSeconds + exercise.restSeconds)
        }
        return max(1, Int((Double(seconds) / 60).rounded(.up)))
    }

    var totalRounds: Int { exercises.reduce(0) { $0 + $1.rounds } }

    var totalWorkSeconds: Int { exercises.reduce(0) { $0 + $1.totalWorkSeconds } }
}

/// The everyday rotation: six equipment-free sessions, all timed.
nonisolated enum ProgramLibrary {
    private static func move(
        _ id: String,
        _ name: String,
        _ target: String,
        _ move: StickMove,
        rounds: Int,
        work: Int,
        rest: Int,
        _ cue: String
    ) -> Exercise {
        Exercise(
            id: id,
            name: name,
            target: target,
            symbol: move.isHold ? "timer" : "figure.run",
            move: move,
            rounds: rounds,
            workSeconds: work,
            restSeconds: rest,
            cue: cue
        )
    }

    static let all: [Program] = [
        Program(
            id: "home-full-body",
            title: "Full Body Starter",
            focus: "Everything · One Session",
            intensity: .fullPower,
            goals: [.lose, .muscle, .strength],
            exercises: [
                move("h-jack", "Jumping Jacks", "Warm-Up", .jumpingJack, rounds: 2, work: 45, rest: 15,
                     "Full arm arc overhead, light feet, steady rhythm."),
                move("h-squat", "Bodyweight Squat", "Quads · Glutes", .squat, rounds: 3, work: 45, rest: 20,
                     "Sit back into the hips, chest tall, drive through the heels."),
                move("h-pushup", "Push-Up", "Chest · Triceps", .pushUp, rounds: 3, work: 45, rest: 25,
                     "Straight line ears to heels, elbows 45°. Drop to the knees when form goes."),
                move("h-plank", "Plank", "Core", .plank, rounds: 3, work: 45, rest: 20,
                     "Squeeze the glutes and the fists. Breathe shallow, never sag."),
                move("h-lunge", "Alternating Lunge", "Legs · Glutes", .lunge, rounds: 3, work: 45, rest: 20,
                     "Step long, torso upright, back knee toward the floor."),
                move("h-mtn", "Mountain Climbers", "Core · Cardio", .mountainClimber, rounds: 2, work: 45, rest: 20,
                     "Shoulders stacked over the hands, hips level, fast knees.")
            ]
        ),
        Program(
            id: "home-core",
            title: "Core & Abs",
            focus: "Abs · Obliques · Stability",
            intensity: .lowImpact,
            goals: [.lose, .muscle],
            exercises: [
                move("h-crunch", "Crunch", "Upper Abs", .crunch, rounds: 3, work: 45, rest: 15,
                     "Ribs toward the hips, chin off the chest, exhale at the top."),
                move("h-legraise", "Lying Leg Raise", "Lower Abs", .legRaise, rounds: 3, work: 45, rest: 15,
                     "Hands under the hips, lower to a hover, never touch down."),
                move("h-bicycle", "Bicycle Crunch", "Obliques", .bicycleCrunch, rounds: 3, work: 45, rest: 15,
                     "Slow rotation, elbow to the opposite knee, extend fully."),
                move("h-hollow", "Hollow Hold", "Deep Core", .hollowHold, rounds: 3, work: 40, rest: 20,
                     "Lower back glued to the floor, arms by the ears."),
                move("h-sideplank", "Side Plank", "Obliques", .sidePlank, rounds: 2, work: 40, rest: 20,
                     "Stack the feet, push the hip high, long neck. Swap sides each round."),
                move("h-russian", "Russian Twist", "Obliques", .russianTwist, rounds: 3, work: 45, rest: 15,
                     "Heels light, rotate from the ribs rather than the arms.")
            ]
        ),
        Program(
            id: "home-hiit",
            title: "Fat Burn HIIT",
            focus: "Conditioning · Fat Burn",
            intensity: .fullPower,
            goals: [.lose],
            exercises: [
                move("h-highknee", "High Knees", "Cardio", .highKnees, rounds: 4, work: 40, rest: 20,
                     "Knees to hip height, stay on the balls of the feet."),
                move("h-burpee", "Burpee", "Full Body", .burpee, rounds: 4, work: 40, rest: 25,
                     "Chest to floor, feet in, full hip extension at the top."),
                move("h-jumpsquat", "Jump Squat", "Legs", .jumpSquat, rounds: 4, work: 40, rest: 20,
                     "Land soft through the mid-foot and reset every rep."),
                move("h-skater", "Skater Hop", "Legs · Cardio", .skater, rounds: 4, work: 40, rest: 20,
                     "Bound side to side, stick each landing on one leg."),
                move("h-plankjack", "Plank Jack", "Core · Cardio", .plankJack, rounds: 3, work: 40, rest: 20,
                     "Plank position, jump the feet wide and back, hips dead still.")
            ]
        ),
        Program(
            id: "home-upper",
            title: "Upper Body Burn",
            focus: "Chest · Shoulders · Arms",
            intensity: .lowImpact,
            goals: [.muscle, .strength],
            exercises: [
                move("h-pushup-2", "Push-Up", "Chest", .pushUp, rounds: 4, work: 45, rest: 25,
                     "Elbows 45°, full lockout, no sagging hips."),
                move("h-pike", "Pike Push-Up", "Shoulders", .pikePushUp, rounds: 3, work: 40, rest: 25,
                     "Hips high, crown of the head toward the floor between the hands."),
                move("h-dip", "Chair Dip", "Triceps", .chairDip, rounds: 3, work: 45, rest: 25,
                     "Shoulders down and back, descend to 90°, no shrugging."),
                move("h-tap", "Shoulder Tap", "Shoulders · Core", .shoulderTap, rounds: 3, work: 40, rest: 20,
                     "Wide base, zero hip sway, tap slow and deliberate."),
                move("h-superman", "Superman", "Back", .superman, rounds: 3, work: 40, rest: 20,
                     "Lift chest and thighs, sweep the arms like a pulldown.")
            ]
        ),
        Program(
            id: "home-lower",
            title: "Legs & Glutes",
            focus: "Quads · Glutes · Hamstrings",
            intensity: .lowImpact,
            goals: [.muscle, .strength, .lose],
            exercises: [
                move("h-squat-2", "Bodyweight Squat", "Quads", .squat, rounds: 4, work: 45, rest: 20,
                     "Three seconds down, drive up. No bouncing out of the bottom."),
                move("h-split", "Split Squat", "Quads · Glutes", .splitSquat, rounds: 3, work: 45, rest: 20,
                     "Long stance, vertical front shin. Swap legs each round."),
                move("h-bridge", "Glute Bridge", "Glutes", .gluteBridge, rounds: 3, work: 45, rest: 20,
                     "Ribs down, squeeze hard at the top for a full second."),
                move("h-wallsit", "Wall Sit", "Quads", .wallSit, rounds: 3, work: 45, rest: 25,
                     "Thighs parallel, back flat on the wall, hands off the legs."),
                move("h-calf", "Calf Raise", "Calves", .calfRaise, rounds: 3, work: 40, rest: 15,
                     "Full stretch at the bottom, two-second squeeze at the top.")
            ]
        ),
        Program(
            id: "home-quiet",
            title: "Quiet Apartment",
            focus: "Full Body · No Jumping",
            intensity: .lowImpact,
            goals: [.lose, .muscle, .strength],
            exercises: [
                move("h-armcircle", "Arm Circles", "Warm-Up", .armCircle, rounds: 2, work: 40, rest: 15,
                     "Arms out, small controlled circles. Forward, then back."),
                move("h-squat-3", "Slow Squat", "Legs", .squat, rounds: 3, work: 45, rest: 20,
                     "Four seconds down, one second up. Silent feet."),
                move("h-bear", "Bear Hold", "Core", .bearHold, rounds: 3, work: 40, rest: 20,
                     "Knees an inch off the floor, back flat enough to balance a cup."),
                move("h-deadbug", "Dead Bug", "Core", .deadBug, rounds: 3, work: 45, rest: 20,
                     "Opposite arm and leg, lower slow, lower back stays flat."),
                move("h-birddog", "Bird Dog", "Back · Core", .birdDog, rounds: 3, work: 45, rest: 20,
                     "Opposite arm and leg long, hips square, pause at the top."),
                move("h-inchworm", "Inchworm", "Full Body", .inchworm, rounds: 2, work: 45, rest: 20,
                     "Walk the hands out to a plank, walk the feet back in.")
            ]
        )
    ]

    /// Programmes matching the user's objective, filtered by what their floor
    /// (and downstairs neighbour) can take.
    static func programs(for profile: UserProfile) -> [Program] {
        let allowed = profile.intensity == .lowImpact
            ? all.filter { $0.intensity == .lowImpact }
            : all
        let matches = allowed.filter { $0.goals.contains(profile.goal) }
        return matches.isEmpty ? allowed : matches
    }

    /// Deterministic rotation so "today's session" is stable within a day.
    static func todaysProgram(for profile: UserProfile) -> Program? {
        let available = programs(for: profile)
        guard !available.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
        return available[day % available.count]
    }
}
