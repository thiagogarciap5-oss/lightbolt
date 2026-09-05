import SwiftData
import SwiftUI

/// Live workout runner.
///
/// LightBolt sessions are timed, never counted: the clock owns the session and
/// the stickman performs the movement at exactly the pace the clock allows. Each
/// interval is a countdown; each countdown finishes on a completed repetition.
struct WorkoutSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let program: Program
    /// duration in seconds, work seconds, completed intervals.
    let onFinish: (Int, Int, Int) -> Void

    @State private var intervals: [WorkInterval] = []
    @State private var index: Int = 0
    @State private var phaseEndsAt: Date = .now
    @State private var remaining: Double = 0
    @State private var isPaused = false
    @State private var isFinished = false
    @State private var sessionStart: Date = .now
    @State private var completedIntervals = 0
    @State private var workSecondsDone = 0
    @State private var lastBeep: Int = -1
    @State private var ticker: Task<Void, Never>?

    private var current: WorkInterval? { intervals.indices.contains(index) ? intervals[index] : nil }

    private var currentExercise: Exercise? {
        guard let current, program.exercises.indices.contains(current.exerciseIndex) else { return nil }
        return program.exercises[current.exerciseIndex]
    }

    private var nextExercise: Exercise? {
        guard let next = intervals.dropFirst(index + 1).first(where: { $0.kind == .work }),
              program.exercises.indices.contains(next.exerciseIndex) else { return nil }
        return program.exercises[next.exerciseIndex]
    }

    var body: some View {
        ZStack {
            LightBoltTheme.backdrop

            if isFinished {
                summary.transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                VStack(spacing: 0) {
                    topBar
                    progressRail
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                    stage

                    controls
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(!isFinished)
        .onAppear(perform: start)
        .onDisappear { ticker?.cancel() }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Button {
                Haptics.tick()
                ticker?.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(LightBoltTheme.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(LightBoltTheme.charcoal))
            }
            .buttonStyle(VoltPressStyle(scale: 0.9))
            .accessibilityLabel("Leave workout")

            Spacer()

            VStack(spacing: 1) {
                Text(program.title.uppercased())
                    .font(.fitTitle(14))
                    .tracking(1.1)
                    .foregroundStyle(LightBoltTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                EyebrowText(
                    text: "\(completedIntervals)/\(intervals.filter { $0.kind == .work }.count) intervals · \(elapsedLabel)",
                    color: LightBoltTheme.voltDim
                )
            }
            .frame(maxWidth: 220)

            Spacer()

            Button {
                Haptics.thud()
                finish()
            } label: {
                Text("END")
                    .font(.fitLabel(11))
                    .tracking(1.4)
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 36)
                    .background(Capsule().fill(LightBoltTheme.volt))
            }
            .buttonStyle(VoltPressStyle(scale: 0.92))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var progressRail: some View {
        HStack(spacing: 3) {
            ForEach(Array(intervals.enumerated().filter { $0.element.kind == .work }), id: \.offset) { offset, _ in
                Capsule()
                    .fill(
                        offset < index ? LightBoltTheme.volt
                            : offset == index ? LightBoltTheme.voltDim
                            : LightBoltTheme.charcoalHigh
                    )
                    .frame(height: 3)
            }
        }
    }

    // MARK: Stage

    private var stage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 6)

            if let current, let exercise = currentExercise {
                figureStage(current: current, exercise: exercise)
                    .frame(maxHeight: 320)

                countdown(current: current)

                caption(current: current, exercise: exercise)
            }

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 20)
    }

    /// The stickman, driven straight off the same wall clock as the countdown so
    /// the movement and the number can never drift apart.
    private func figureStage(current: WorkInterval, exercise: Exercise) -> some View {
        TimelineView(.animation(paused: isPaused)) { timeline in
            let elapsed = Double(current.seconds) - liveRemaining(at: timeline.date)
            let move = current.kind == .rest ? (nextExercise?.move ?? exercise.move) : exercise.move
            let secondsPerRep = current.kind == .rest
                ? move.cycleSeconds
                : (exercise.isHold ? move.cycleSeconds : exercise.repSeconds)
            let phase = max(0, elapsed) / max(0.2, secondsPerRep)

            StickFigureView(
                move: move,
                phase: current.kind == .ready ? phase * 0.35 : phase,
                isResting: current.kind != .work
            )
        }
        .frame(maxWidth: .infinity)
        .background(
            RadialGradient(
                colors: [LightBoltTheme.volt.opacity(current.kind == .work ? 0.12 : 0.04), .clear],
                center: .center,
                startRadius: 2,
                endRadius: 220
            )
        )
    }

    private func countdown(current: WorkInterval) -> some View {
        let seconds = max(0, Int(remaining.rounded(.up)))
        let progress = current.seconds > 0 ? max(0, min(1, remaining / Double(current.seconds))) : 0

        return VStack(spacing: 8) {
            ZStack {
                Capsule()
                    .fill(LightBoltTheme.charcoal)
                    .frame(height: 8)
                GeometryReader { proxy in
                    Capsule()
                        .fill(current.kind == .work ? LightBoltTheme.volt : LightBoltTheme.inkFaint)
                        .frame(width: proxy.size.width * progress, height: 8)
                        .animation(.linear(duration: 0.08), value: progress)
                }
                .frame(height: 8)
            }
            .frame(height: 8)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(seconds)")
                    .font(.fitNumeric(92, weight: .black))
                    .foregroundStyle(current.kind == .work ? LightBoltTheme.volt : LightBoltTheme.ink)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy(duration: 0.18), value: seconds)
                Text("SEC")
                    .font(.fitLabel(12))
                    .tracking(2)
                    .foregroundStyle(LightBoltTheme.inkFaint)
            }
            .scaleEffect(seconds <= 3 && current.kind == .work ? 1.05 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.5), value: seconds <= 3)
        }
        .padding(.top, 6)
    }

    private func caption(current: WorkInterval, exercise: Exercise) -> some View {
        VStack(spacing: 8) {
            EyebrowText(text: current.headline(exercise: exercise), color: LightBoltTheme.voltDim)

            Text((current.kind == .rest ? (nextExercise?.name ?? exercise.name) : exercise.name).uppercased())
                .font(.fitDisplay(36))
                .tracking(-0.8)
                .foregroundStyle(LightBoltTheme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            HStack(spacing: 8) {
                tag(exercise.isHold ? "HOLD" : "\(exercise.pacedReps) REPS PACED")
                tag("ROUND \(current.round)/\(current.totalRounds)")
            }

            Text(current.kind == .rest ? "Shake it out. Breathe through the nose." : exercise.cue)
                .font(.fitBody(13))
                .foregroundStyle(LightBoltTheme.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
        }
        .padding(.top, 10)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.fitLabel(9))
            .tracking(1.2)
            .foregroundStyle(LightBoltTheme.inkMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(LightBoltTheme.charcoalHigh))
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tick()
                extend(by: 15)
            } label: {
                controlLabel("+15s", filled: false)
            }
            .buttonStyle(VoltPressStyle())

            Button {
                Haptics.tap()
                isPaused.toggle()
                if !isPaused { phaseEndsAt = Date().addingTimeInterval(remaining) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 15, weight: .black))
                    Text(isPaused ? "RESUME" : "PAUSE")
                        .font(.fitTitle(15))
                        .tracking(1.4)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LightBoltTheme.volt))
            }
            .buttonStyle(VoltPressStyle())

            Button {
                Haptics.tick()
                advance(completed: false)
            } label: {
                controlLabel("SKIP", filled: false)
            }
            .buttonStyle(VoltPressStyle())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func controlLabel(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.fitTitle(14))
            .tracking(1.2)
            .foregroundStyle(LightBoltTheme.ink)
            .frame(width: 84, height: 56)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LightBoltTheme.charcoal))
    }

    // MARK: Summary

    private var summary: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowText(text: "Session complete", color: LightBoltTheme.voltDim)
                    Text("DONE.")
                        .font(.fitDisplay(72))
                        .tracking(-2)
                        .voltWash()
                }

                HStack(spacing: 10) {
                    summaryTile("\(max(1, Int(Date.now.timeIntervalSince(sessionStart) / 60)))", "minutes")
                    summaryTile("\(completedIntervals)", "intervals")
                    summaryTile("\(workSecondsDone / 60):\(String(format: "%02d", workSecondsDone % 60))", "working")
                }

                VoltButton(title: "Back to Training", systemImage: "checkmark") {
                    dismiss()
                }
            }
            .padding(24)
            Spacer()
        }
    }

    private func summaryTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.fitNumeric(24))
                .foregroundStyle(LightBoltTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            EyebrowText(text: label, color: LightBoltTheme.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .fitCard(radius: 16)
    }

    // MARK: Clock

    private var elapsedLabel: String {
        let seconds = Int(Date.now.timeIntervalSince(sessionStart))
        return "\(seconds / 60)m"
    }

    private func liveRemaining(at date: Date) -> Double {
        isPaused ? remaining : max(0, phaseEndsAt.timeIntervalSince(date))
    }

    private func start() {
        intervals = WorkInterval.build(from: program)
        sessionStart = .now
        Haptics.prepare()
        beginCurrentPhase()

        ticker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                guard !isPaused, !isFinished else { continue }

                remaining = max(0, phaseEndsAt.timeIntervalSinceNow)
                let whole = Int(remaining.rounded(.up))

                if whole != lastBeep, whole <= 3, whole > 0, current?.kind != .ready || whole <= 3 {
                    lastBeep = whole
                    LightBoltChime.countdownBeep()
                    Haptics.tick()
                }
                if remaining <= 0.02 { advance(completed: true) }
            }
        }
    }

    private func beginCurrentPhase() {
        guard let current else { return }
        remaining = Double(current.seconds)
        phaseEndsAt = Date().addingTimeInterval(remaining)
        lastBeep = -1
    }

    private func extend(by seconds: Int) {
        remaining += Double(seconds)
        phaseEndsAt = phaseEndsAt.addingTimeInterval(Double(seconds))
    }

    /// Moves to the next interval. `completed` is false when the user skipped,
    /// in which case only the seconds actually worked are credited.
    private func advance(completed: Bool) {
        guard let current else { return }

        if current.kind == .work, let exercise = currentExercise {
            let worked = completed
                ? current.seconds
                : max(0, current.seconds - Int(remaining.rounded()))
            if worked >= 5 {
                context.insert(
                    SetLog(
                        exerciseID: exercise.id,
                        exerciseName: exercise.name,
                        setIndex: current.round,
                        holdSeconds: worked
                    )
                )
                workSecondsDone += worked
                completedIntervals += 1
            }
            completed ? LightBoltChime.intervalEnd() : Haptics.tick()
            if completed { Haptics.success() }
        }

        if index + 1 >= intervals.count {
            finish()
            return
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { index += 1 }
        beginCurrentPhase()
    }

    private func finish() {
        ticker?.cancel()
        guard completedIntervals > 0 else {
            dismiss()
            return
        }
        onFinish(Int(Date.now.timeIntervalSince(sessionStart)), workSecondsDone, completedIntervals)
        LightBoltChime.sessionComplete()
        Haptics.success()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { isFinished = true }
    }
}

// MARK: - Interval plan

/// One block of the session: get ready, work, or rest.
nonisolated struct WorkInterval: Sendable {
    enum Kind: Sendable { case ready, work, rest }

    let exerciseIndex: Int
    let round: Int
    /// Circuits in the whole session, so the UI can say "ROUND 2/3".
    let totalRounds: Int
    let kind: Kind
    let seconds: Int

    func headline(exercise: Exercise) -> String {
        switch kind {
        case .ready: "Get ready"
        case .work: exercise.target
        case .rest: "Rest · next up"
        }
    }

    /// Flattens a programme into the exact sequence of countdowns to run.
    ///
    /// Circuit style: every unique movement is performed exactly once, in list
    /// order, before the routine loops back to the first exercise for the next
    /// round — Knee Push-Up ➔ Plank ➔ Jumping Jacks, then round two. A movement
    /// asking for fewer rounds than the longest simply drops out of the later
    /// circuits instead of being front-loaded.
    static func build(from program: Program) -> [WorkInterval] {
        var plan: [WorkInterval] = []
        guard !program.exercises.isEmpty else { return plan }

        let totalRounds = program.exercises.map { max(1, $0.rounds) }.max() ?? 1

        plan.append(
            WorkInterval(exerciseIndex: 0, round: 1, totalRounds: totalRounds, kind: .ready, seconds: 10)
        )

        // Lay the circuit out first: round by round, exercise by exercise.
        // Knowing the full order up front makes "is this the final work block?"
        // a plain index check instead of a nested guess.
        var order: [(round: Int, index: Int)] = []
        for round in 1...totalRounds {
            for (index, exercise) in program.exercises.enumerated() where round <= max(1, exercise.rounds) {
                order.append((round, index))
            }
        }

        for (position, step) in order.enumerated() {
            let exercise = program.exercises[step.index]
            plan.append(
                WorkInterval(
                    exerciseIndex: step.index,
                    round: step.round,
                    totalRounds: totalRounds,
                    kind: .work,
                    seconds: exercise.workSeconds
                )
            )
            // Every block but the very last one earns a breather.
            if position < order.count - 1 {
                plan.append(
                    WorkInterval(
                        exerciseIndex: step.index,
                        round: step.round,
                        totalRounds: totalRounds,
                        kind: .rest,
                        seconds: exercise.restSeconds
                    )
                )
            }
        }
        return plan
    }
}
