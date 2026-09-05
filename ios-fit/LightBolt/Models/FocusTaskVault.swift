import Foundation

/// The offline task vault: exactly 10,000 tasks per difficulty (30,000 total),
/// generated deterministically from curated word banks — no AI, no network.
///
/// Every task is addressed by a stable index in `0..<perDifficulty`, so the
/// same index always renders the same sentence on every device and every
/// launch. Families each own a fixed quota; within a family the quota is
/// spread evenly across the family's full combination space, which keeps the
/// generated set both varied and provably free of duplicates.
nonisolated enum FocusTaskVault {
    /// Tasks available per difficulty tier.
    static let perDifficulty = 10_000

    /// Total tasks across all three tiers.
    static var total: Int { perDifficulty * FocusDifficulty.allCases.count }

    // MARK: Public API

    /// Renders the task at `index` for `difficulty`. Index wraps, so callers
    /// never need to range-check.
    static func description(_ difficulty: FocusDifficulty, index: Int) -> String {
        let plan = plan(for: difficulty)
        let slot = ((index % perDifficulty) + perDifficulty) % perDifficulty
        var cursor = slot
        for entry in plan {
            if cursor < entry.quota {
                // Spread this family's quota evenly across its whole
                // combination space so neighbouring indices differ a lot.
                let stride = entry.family.capacity / entry.quota
                return entry.family.render(cursor * stride)
            }
            cursor -= entry.quota
        }
        return plan[0].family.render(0)
    }

    /// Draws a task the user has not seen recently.
    static func draw(_ difficulty: FocusDifficulty, excluding recent: [String]) -> FocusTask {
        let seen = Set(recent)
        for _ in 0..<24 {
            let index = Int.random(in: 0..<perDifficulty)
            let text = description(difficulty, index: index)
            if !seen.contains(text) {
                return FocusTask(taskDescription: text, difficulty: difficulty, vaultIndex: index)
            }
        }
        let index = Int.random(in: 0..<perDifficulty)
        return FocusTask(
            taskDescription: description(difficulty, index: index),
            difficulty: difficulty,
            vaultIndex: index
        )
    }

    // MARK: Family machinery

    /// A sentence shape plus the interchangeable word banks that fill it.
    nonisolated struct Family: Sendable {
        let template: String
        let axes: [[String]]

        var capacity: Int { axes.reduce(1) { $0 * $1.count } }

        /// Mixed-radix render: each axis consumes one digit of `index`.
        func render(_ index: Int) -> String {
            var remainder = max(0, index) % max(1, capacity)
            var output = template
            for (position, values) in axes.enumerated() {
                let digit = remainder % values.count
                remainder /= values.count
                output = output.replacingOccurrences(of: "{\(position)}", with: values[digit])
            }
            return output
        }
    }

    nonisolated struct Allocation: Sendable {
        let family: Family
        let quota: Int
    }

    private static func plan(for difficulty: FocusDifficulty) -> [Allocation] {
        switch difficulty {
        case .easy: easyPlan
        case .medium: mediumPlan
        case .hard: hardPlan
        }
    }

    // MARK: - Word banks

    private static let reps = ["10", "12", "15", "18", "20", "24", "25", "30", "40", "50"]
    private static let setReps = ["10", "12", "15", "20", "25"]
    private static let heldSeconds = ["20", "25", "30", "35", "40", "45", "50", "60"]
    private static let longSeconds = ["60", "75", "90", "120", "150", "180"]
    private static let bigTotals = ["60", "75", "80", "100", "120", "150"]
    private static let rounds = ["3", "4", "5", "6", "7"]
    private static let shortRounds = ["2", "3", "4", "5"]
    private static let restSeconds = ["20", "30", "45", "60"]

    private static let moves = [
        "jumping jacks", "bodyweight squats", "push-ups", "sit-ups", "crunches",
        "glute bridges", "calf raises", "arm circles", "high knees", "butt kicks",
        "shoulder taps", "mountain climbers", "forward lunges", "reverse lunges",
        "lying leg raises", "bicycle crunches", "squat pulses", "standing side bends",
        "torso twists", "toe touches", "knee tucks", "good mornings", "hip circles",
        "wall push-ups", "chair dips", "step-ups", "skater hops", "air punches"
    ]

    private static let finishers = [
        "squat jumps", "flutter kicks", "russian twists", "dead bugs", "bird dogs",
        "lateral lunges", "inchworms", "sumo squats", "plank shoulder taps",
        "heel taps", "wall sits (seconds)", "burpees", "star jumps", "seal jacks",
        "single-leg glute bridges", "hip thrusts", "scapular squeezes", "cossack squats",
        "reverse crunches", "leg flutters", "standing knee drives", "jump lunges",
        "half burpees", "tuck jumps"
    ]

    private static let coreMoves = [
        "sit-ups", "crunches", "leg raises", "russian twists", "flutter kicks",
        "dead bugs", "hollow rocks", "reverse crunches", "bicycle crunches",
        "toe touches", "heel taps", "v-ups", "plank jacks", "knee tucks",
        "side crunches", "scissor kicks", "windshield wipers", "seated twists",
        "lying knee raises", "boat pose pulses"
    ]

    private static let holds = [
        "plank", "wall sit", "side plank", "glute bridge hold", "hollow body hold",
        "dead hang", "squat hold", "superman hold", "forearm plank", "high plank",
        "calf raise hold", "chair pose", "bird dog hold", "boat pose"
    ]

    private static let areas = [
        "neck and shoulders", "hamstrings", "hip flexors", "lower back",
        "chest and front delts", "calves", "quads", "upper back",
        "wrists and forearms", "ankles", "glutes", "inner thighs",
        "lats", "spine", "IT bands", "triceps", "adductors", "thoracic spine"
    ]

    private static let stretchMinutes = ["2", "3", "4", "5"]
    private static let longStretchMinutes = ["5", "6", "8", "10"]
    private static let tidyMinutes = ["3", "4", "5"]
    private static let choreMinutes = ["8", "10", "12"]
    private static let deepMinutes = ["20", "25", "30", "40"]
    private static let focusMinutes = ["25", "30", "40", "45"]
    private static let meditateMinutes = ["5", "8", "10", "12"]
    private static let stillMinutes = ["2", "3", "4", "5"]
    private static let walkMinutes = ["8", "10", "12", "15"]
    private static let runMinutes = ["15", "20", "25", "30"]
    private static let breathCounts = ["8", "10", "12", "15", "20", "25"]

    private static let places = [
        "your desk", "your nightstand", "the kitchen counter", "one drawer",
        "your bag", "the bathroom sink", "your phone's home screen",
        "your downloads folder", "the sofa area", "one shelf",
        "your wardrobe rail", "the entryway", "your car's front seats",
        "the dish rack", "your email inbox", "the last 50 photos on your camera roll",
        "the fridge door", "your bedside books", "the laundry basket", "your desktop files"
    ]

    private static let chores = [
        "washing every dish in the sink", "folding and putting away laundry",
        "wiping down the kitchen surfaces", "vacuuming one room",
        "clearing your inbox to zero", "unsubscribing from junk email",
        "sorting the recycling", "changing your bedsheets",
        "cleaning the bathroom mirror and sink", "watering and checking your plants",
        "organising your fridge shelves", "taking out every bin in the house",
        "wiping your screens and keyboard", "clearing your phone's storage",
        "sorting a pile of paperwork", "sweeping the floors",
        "cleaning the inside of the microwave", "tidying your shoe rack",
        "backing up your photos", "prepping tomorrow's clothes"
    ]

    private static let volumes = ["250 ml", "300 ml", "400 ml", "500 ml", "600 ml", "750 ml"]

    private static let breathStyles = [
        "slow belly", "4-count box", "deep nasal", "long-exhale",
        "steady diaphragmatic", "quiet seated", "5-second inhale", "extended sigh"
    ]

    private static let notes = [
        "three things you're grateful for", "the one task that would make today a win",
        "what you'll eat at your next meal", "how many hours you slept last night",
        "the excuse you keep reaching for", "one thing you did well yesterday",
        "your target weight and today's weight", "the workout you'll do tomorrow",
        "who you want to be in six months", "the habit you want to drop",
        "three wins from this week", "what drained your energy today",
        "your next three meals", "the reason you started training",
        "one thing you're avoiding", "how your body feels right now",
        "your water intake so far today", "a person you should thank",
        "the last time you felt genuinely proud", "your top priority for tomorrow",
        "something you learned this week", "your biggest time sink today",
        "one boundary you need to hold", "the next step on a stalled project",
        "what you'd tell your past self", "your training goal for this month",
        "three foods you'll stop buying", "the last thing that made you laugh",
        "one small promise to keep tomorrow", "what success looks like this year"
    ]

    private static let journalPrompts = [
        "why this goal actually matters to you", "the habit costing you the most",
        "what you want your body to feel like in a year",
        "the version of you that never skips a session",
        "a setback you're still carrying", "what you'd do with an extra hour a day",
        "the people who lift your standards", "your relationship with food",
        "what you're proud of this month", "the fear behind your procrastination",
        "how you want to spend your evenings", "your definition of discipline",
        "what you'd change about last week", "the story you tell yourself when you quit",
        "your ideal morning, in detail", "a promise you broke to yourself",
        "what rest should actually look like", "the next milestone you want to hit",
        "how you handle a bad day", "what you'd do if failure was impossible",
        "your energy across a typical day", "one comparison you need to drop",
        "what you want to be known for", "the smallest change with the biggest payoff"
    ]

    private static let shortWalks = [
        "to the end of your street and back", "around the block",
        "up and down three flights of stairs", "to the nearest shop and back",
        "for five minutes outside", "around your garden or yard",
        "one full lap of your building", "to the nearest green space",
        "for 400 steady steps", "to the postbox and back",
        "around the car park twice", "for three songs' worth of music"
    ]

    private static let meals = [
        "a proper breakfast", "an omelette with vegetables", "a big mixed salad",
        "a chicken and rice bowl", "overnight oats for tomorrow",
        "a lentil or bean stew", "grilled fish with greens", "a protein smoothie",
        "roast vegetables for the week", "a stir-fry with lean protein",
        "a home-made soup", "eggs with wholegrain toast",
        "tomorrow's lunch box", "a yoghurt and fruit bowl",
        "a tuna and chickpea salad", "baked chicken with sweet potato",
        "a vegetable curry", "cottage cheese with fruit",
        "a wrap with lean protein and salad", "steamed greens and a protein of choice",
        "a batch of hard-boiled eggs", "porridge with nuts and berries",
        "a tofu and vegetable tray bake", "a prawn and quinoa bowl"
    ]

    private static let learnings = [
        "five new words in a language you're studying", "one keyboard shortcut you'll actually use",
        "the name of every muscle you trained today", "a two-minute breathing technique",
        "how to read a nutrition label properly", "one new stretch and its purpose",
        "the difference between two macros", "a short poem by heart",
        "one fact about how sleep affects training", "a new recipe start to finish",
        "how compound interest works", "the basics of one country's geography",
        "a chord or scale on an instrument", "one first-aid procedure",
        "how to tie a knot you don't know", "the meaning of three unfamiliar words",
        "one historical event in depth", "a mental maths trick",
        "the anatomy of the shoulder joint", "how to calculate your maintenance calories",
        "one principle of progressive overload", "the rules of a sport you don't play",
        "a short passage in another language", "how to properly warm up a joint",
        "one thing about your own family history", "the science of hydration",
        "a two-line summary of a book you own", "how to plan a week of meals",
        "the difference between mobility and flexibility", "one breathing drill for stress"
    ]

    private static let skills = [
        "a language", "an instrument", "a coding problem", "your handwriting",
        "mental arithmetic", "public speaking out loud", "sketching from life",
        "a chess opening", "typing speed", "a card or coin trick",
        "reading music", "a cooking technique", "photography composition",
        "juggling", "knot tying", "a dance routine", "chess endgames",
        "your posture and breathing", "sight-reading text aloud", "map reading",
        "a craft you started and dropped", "your golf or tennis swing",
        "note-taking from a book", "memorising a poem", "speed reading",
        "a spreadsheet formula set", "drawing perspective", "singing scales",
        "writing by hand for speed", "a bodyweight skill like a handstand"
    ]

    private static let words = ["200", "300", "400", "500"]
    private static let pages = ["8", "10", "12", "15", "20"]
    private static let bigPages = ["25", "30", "35", "40"]

    private static let people = [
        "a friend you've lost touch with", "a parent", "a sibling",
        "an old teammate", "someone who helped you this year",
        "a colleague you respect", "a neighbour", "a grandparent",
        "someone you owe a reply", "a friend having a hard week",
        "someone you admire", "a cousin you rarely speak to"
    ]

    // MARK: - Easy plan (10,000)

    private static let easyPlan: [Allocation] = [
        Allocation(
            family: Family(
                template: "Do {0} {1}, then drink {2} of water.",
                axes: [reps, moves, volumes]
            ),
            quota: 1_200
        ),
        Allocation(
            family: Family(
                template: "Hold a {0}-second {1}, then do {2} {3}.",
                axes: [heldSeconds, holds, reps, moves]
            ),
            quota: 2_200
        ),
        Allocation(
            family: Family(
                template: "Stretch your {0} for {1} minutes.",
                axes: [areas, stretchMinutes]
            ),
            quota: 72
        ),
        Allocation(
            family: Family(
                template: "Spend {0} minutes tidying {1}, then do {2} {3}.",
                axes: [tidyMinutes, places, reps, moves]
            ),
            quota: 1_800
        ),
        Allocation(
            family: Family(
                template: "Take {0} {1} breaths, then write down {2}.",
                axes: [breathCounts, breathStyles, notes]
            ),
            quota: 1_200
        ),
        Allocation(
            family: Family(
                template: "Walk {0} without touching your phone.",
                axes: [shortWalks]
            ),
            quota: 12
        ),
        Allocation(
            family: Family(
                template: "Do {0} {1} and {2} {3} back to back.",
                axes: [reps, moves, reps, finishers]
            ),
            quota: 2_500
        ),
        Allocation(
            family: Family(
                template: "Do {0} {1}, rest 30 seconds, then repeat the set.",
                axes: [reps, moves]
            ),
            quota: 280
        ),
        Allocation(
            family: Family(
                template: "Drink {0} of water and stretch your {1} for {2} minutes.",
                axes: [volumes, areas, stretchMinutes]
            ),
            quota: 432
        ),
        Allocation(
            family: Family(
                template: "Sit still for {0} minutes, then write down {1}.",
                axes: [stillMinutes, notes]
            ),
            quota: 120
        ),
        Allocation(
            family: Family(
                template: "Walk {0}, then do {1} {2}.",
                axes: [shortWalks, reps, coreMoves]
            ),
            quota: 184
        )
    ]

    // MARK: - Medium plan (10,000)

    private static let mediumPlan: [Allocation] = [
        Allocation(
            family: Family(
                template: "Do {0} rounds of {1} {2} and {3} {4}.",
                axes: [shortRounds, setReps, moves, setReps, finishers]
            ),
            quota: 2_600
        ),
        Allocation(
            family: Family(
                template: "Read {0} pages of a book, then stretch your {1} for {2} minutes.",
                axes: [pages, areas, longStretchMinutes]
            ),
            quota: 360
        ),
        Allocation(
            family: Family(
                template: "Walk briskly for {0} minutes, then do {1} {2}.",
                axes: [walkMinutes, setReps, moves]
            ),
            quota: 560
        ),
        Allocation(
            family: Family(
                template: "Spend {0} minutes {1}, then journal about {2}.",
                axes: [choreMinutes, chores, journalPrompts]
            ),
            quota: 1_440
        ),
        Allocation(
            family: Family(
                template: "Meditate for {0} minutes, then write down {1}.",
                axes: [meditateMinutes, notes]
            ),
            quota: 120
        ),
        Allocation(
            family: Family(
                template: "Accumulate a {0}-second {1}, then do {2} {3}.",
                axes: [longSeconds, holds, setReps, finishers]
            ),
            quota: 1_800
        ),
        Allocation(
            family: Family(
                template: "Cook or prepare {0}, then drink {1} of water.",
                axes: [meals, volumes]
            ),
            quota: 144
        ),
        Allocation(
            family: Family(
                template: "Learn {0}, then say it out loud from memory.",
                axes: [learnings]
            ),
            quota: 30
        ),
        Allocation(
            family: Family(
                template: "Do {0} rounds of {1} {2}, resting {3} seconds between rounds.",
                axes: [shortRounds, setReps, moves, restSeconds]
            ),
            quota: 2_240
        ),
        Allocation(
            family: Family(
                template: "Take a {0}-minute walk and message {1}.",
                axes: [walkMinutes, people]
            ),
            quota: 48
        ),
        Allocation(
            family: Family(
                template: "Complete {0} {1}, then stretch your {2} for {3} minutes.",
                axes: [setReps, moves, areas, longStretchMinutes]
            ),
            quota: 658
        )
    ]

    // MARK: - Hard plan (10,000)

    private static let hardPlan: [Allocation] = [
        Allocation(
            family: Family(
                template: "Do {0} rounds of {1} {2}, {3} {4} and a {5}-second {6}.",
                axes: [rounds, setReps, moves, setReps, finishers, longSeconds, holds]
            ),
            quota: 3_000
        ),
        Allocation(
            family: Family(
                template: "Run or power-walk for {0} minutes, then do {1} {2}.",
                axes: [runMinutes, setReps, moves]
            ),
            quota: 560
        ),
        Allocation(
            family: Family(
                template: "Complete {0} {1} in as many sets as you need.",
                axes: [bigTotals, moves]
            ),
            quota: 168
        ),
        Allocation(
            family: Family(
                template: "Practise {0} for {1} fully focused minutes.",
                axes: [skills, focusMinutes]
            ),
            quota: 120
        ),
        Allocation(
            family: Family(
                template: "Deep-clean {0} for {1} minutes.",
                axes: [places, deepMinutes]
            ),
            quota: 80
        ),
        Allocation(
            family: Family(
                template: "Read {0} pages, then write {1} words about {2}.",
                axes: [bigPages, words, journalPrompts]
            ),
            quota: 384
        ),
        Allocation(
            family: Family(
                template: "Do {0} rounds: {1} {2}, {3} {4}, {5} {6}.",
                axes: [rounds, setReps, moves, setReps, finishers, setReps, coreMoves]
            ),
            quota: 3_200
        ),
        Allocation(
            family: Family(
                template: "Accumulate a {0}-second {1}, then walk or run for {2} minutes.",
                axes: [longSeconds, holds, runMinutes]
            ),
            quota: 336
        ),
        Allocation(
            family: Family(
                template: "Cook {0} from scratch and clean the kitchen fully afterwards.",
                axes: [meals]
            ),
            quota: 24
        ),
        Allocation(
            family: Family(
                template: "Meditate for {0} minutes phone-free, then journal about {1}.",
                axes: [meditateMinutes, journalPrompts]
            ),
            quota: 96
        ),
        Allocation(
            family: Family(
                template: "Do {0} {1} and {2} {3}, then finish with a {4}-minute walk.",
                axes: [bigTotals, moves, bigTotals, finishers, runMinutes]
            ),
            quota: 2_032
        )
    ]
}
