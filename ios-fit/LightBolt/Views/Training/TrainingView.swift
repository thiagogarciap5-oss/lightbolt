import SwiftData
import SwiftUI

/// Programme library + progressive overload history.
struct TrainingView: View {
    @Environment(\.modelContext) private var context
    @Environment(AccountService.self) private var account
    @Query private var profiles: [UserProfile]
    @Query(sort: \SetLog.loggedAt, order: .reverse) private var setLogs: [SetLog]
    @Query(sort: \WorkoutSession.finishedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \CustomWorkout.createdAt, order: .reverse) private var customWorkouts: [CustomWorkout]
    @Query(sort: \PlannedWorkout.orderIndex) private var allPlans: [PlannedWorkout]
    @Query(sort: \BodyScan.capturedAt, order: .reverse) private var scans: [BodyScan]

    @State private var activeProgram: Program?
    @State private var isBrowsingLibrary = false
    @State private var isBrowsingChallenges = false
    @State private var isBuildingWorkout = false
    @State private var isShowingCharts = false
    @State private var isPickingPlan = false
    @State private var report: ReportDocument?
    @State private var exportError: String?

    private var profile: UserProfile? { profiles.first }

    private var todayKey: String { DayKey.make(.now) }

    private var todaysPlans: [PlannedWorkout] {
        allPlans.filter { $0.dayKey == todayKey }
    }

    private var digest: ConsistencyDigest {
        ConsistencyEngine.digest(sessions: sessions, plans: allPlans)
    }

    /// Seconds of actual work logged this calendar week.
    private var weeklyWorkSeconds: Int {
        sessions
            .filter { Calendar.current.isDate($0.finishedAt, equalTo: .now, toGranularity: .weekOfYear) }
            .reduce(0) { $0 + $1.workSeconds }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let profile {
                    if let today = ProgramLibrary.todaysProgram(for: profile) {
                        todayCard(today)
                    }
                    plannerBlock
                    ConsistencyCard(digest: digest) { isShowingCharts = true }
                    vaultBlock
                    volumeStrip
                    buildsBlock
                    libraryBlock(for: profile)
                    if !setLogs.isEmpty { overloadBlock }
                } else {
                    EmptyStateCard(
                        symbol: "figure.run",
                        title: "Profile missing",
                        message: "Complete calibration so LightBolt can pick the right sessions for your objective."
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .background(LightBoltTheme.backdrop)
        .fullScreenCover(isPresented: $isBrowsingLibrary) {
            LibraryBrowserView(initialIntensity: profile?.intensity)
        }
        .fullScreenCover(isPresented: $isBrowsingChallenges) {
            ChallengeBrowserView(initialIntensity: profile?.intensity)
        }
        .sheet(isPresented: $isBuildingWorkout) {
            WorkoutBuilderView()
        }
        .fullScreenCover(isPresented: $isShowingCharts) {
            ConsistencyChartsView(digest: digest, units: profile?.units ?? .metric) {
                isShowingCharts = false
                // Let the cover finish dismissing before the report appears.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(320))
                    exportReport()
                }
            }
        }
        .sheet(isPresented: $isPickingPlan) {
            PlannerPickerSheet(
                programs: profile.map { ProgramLibrary.programs(for: $0) } ?? ProgramLibrary.all,
                builds: customWorkouts.map { $0.asProgram() },
                onPick: schedule
            )
        }
        .sheet(item: $report) { document in
            WeeklyReportSheet(document: document)
        }
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .fullScreenCover(item: $activeProgram) { program in
            WorkoutSessionView(program: program) { duration, workSeconds, intervals in
                context.insert(
                    WorkoutSession(
                        programID: program.id,
                        programTitle: program.title,
                        durationSeconds: duration,
                        workSeconds: workSeconds,
                        intervals: intervals
                    )
                )
                // Finishing a scheduled session ticks it off the plan.
                if let planned = todaysPlans.first(where: { $0.programID == program.id && !$0.isDone }) {
                    planned.completedAt = .now
                }
                try? context.save()
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                EyebrowText(
                    text: profile.map { "\($0.intensity.title) · no equipment" } ?? "Training",
                    color: LightBoltTheme.voltDim
                )
                Text("TRAIN")
                    .font(.fitDisplay(52))
                    .tracking(-1.4)
                    .foregroundStyle(LightBoltTheme.ink)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Spacer(minLength: 8)

            Button {
                Haptics.tap()
                exportReport()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(LightBoltTheme.volt))
            }
            .buttonStyle(VoltPressStyle(scale: 0.9))
            .accessibilityLabel("Export weekly PDF report")
            .padding(.top, 12)
        }
    }

    private var plannerBlock: some View {
        DayPlannerSection(
            plans: todaysPlans,
            profile: profile,
            logs: setLogs,
            sessions: sessions,
            onStart: { plan in
                guard let program = program(for: plan) else { return }
                activeProgram = program
            },
            onAdd: { isPickingPlan = true },
            onDelete: { plan in
                context.delete(plan)
                try? context.save()
            },
            onToggleDone: { plan in
                Haptics.tick()
                plan.completedAt = plan.isDone ? nil : .now
                try? context.save()
            },
            onReorder: { ordered in
                for (index, plan) in ordered.enumerated() where plan.orderIndex != index {
                    plan.orderIndex = index
                }
                try? context.save()
            }
        )
    }

    private func todayCard(_ program: Program) -> some View {
        Button {
            Haptics.thud()
            activeProgram = program
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    EyebrowText(text: "Today's session", color: .black.opacity(0.6))
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.black)
                }

                Text(program.title.uppercased())
                    .font(.fitDisplay(42))
                    .tracking(-0.8)
                    .foregroundStyle(.black)
                    .padding(.top, 10)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(program.focus)
                    .font(.fitBody(13))
                    .foregroundStyle(.black.opacity(0.72))

                HStack(spacing: 18) {
                    metaItem("\(program.exercises.count)", "moves")
                    metaItem("\(program.totalRounds)", "intervals")
                    metaItem("~\(program.estimatedMinutes)", "min")
                }
                .padding(.top, 18)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [LightBoltTheme.volt, LightBoltTheme.voltSoft],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
        }
        .buttonStyle(VoltPressStyle(scale: 0.98))
    }

    private func metaItem(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.fitNumeric(20))
                .foregroundStyle(.black)
            Text(label.uppercased())
                .font(.fitLabel(9))
                .tracking(1.4)
                .foregroundStyle(.black.opacity(0.55))
        }
    }

    /// Entry cards into the full generated catalogue — asymmetric on purpose.
    private var vaultBlock: some View {
        HStack(spacing: 12) {
            vaultCard(
                eyebrow: "The Vault",
                count: WorkoutLibrary.count,
                label: "workouts",
                symbol: "square.grid.3x3.fill",
                height: 130
            ) { isBrowsingLibrary = true }

            vaultCard(
                eyebrow: "Challenges",
                count: ChallengeLibrary.count,
                label: "plans",
                symbol: "flag.checkered",
                height: 130
            ) { isBrowsingChallenges = true }
        }
    }

    private func vaultCard(eyebrow: String, count: Int, label: String, symbol: String, height: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    EyebrowText(text: eyebrow, color: LightBoltTheme.voltDim)
                    Spacer()
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(LightBoltTheme.volt)
                }
                Spacer()
                Text(count.formatted())
                    .font(.fitDisplay(34))
                    .tracking(-0.5)
                    .voltWash()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label.uppercased())
                    .font(.fitLabel(9))
                    .tracking(1.6)
                    .foregroundStyle(LightBoltTheme.inkMuted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .fitCard(radius: 20)
        }
        .buttonStyle(VoltPressStyle(scale: 0.97))
    }

    /// User-built workouts plus the entry into the builder.
    private var buildsBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Your Builds")
                Spacer()
                Button {
                    Haptics.tap()
                    isBuildingWorkout = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .black))
                        Text("NEW")
                            .font(.fitLabel(11))
                            .tracking(1.4)
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(LightBoltTheme.volt))
                }
                .buttonStyle(VoltPressStyle(scale: 0.92))
            }

            if customWorkouts.isEmpty {
                Button {
                    Haptics.tap()
                    isBuildingWorkout = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.grid.3x1.below.line.grid.1x2")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(LightBoltTheme.volt)
                        Text("Assemble your own timed circuit from \(MoveLibrary.count) equipment-free moves.")
                            .font(.fitBody(13))
                            .foregroundStyle(LightBoltTheme.inkMuted)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(LightBoltTheme.inkFaint)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fitCard(radius: 18)
                }
                .buttonStyle(VoltPressStyle(scale: 0.98))
            } else {
                VStack(spacing: 10) {
                    ForEach(customWorkouts) { workout in
                        let program = workout.asProgram()
                        WorkoutRow(program: program) {
                            Haptics.tap()
                            activeProgram = program
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                Haptics.warning()
                                context.delete(workout)
                                try? context.save()
                            } label: {
                                Label("Delete Build", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var volumeStrip: some View {
        HStack(spacing: 12) {
            StatTile(
                eyebrow: "Work this week",
                value: weeklyWorkSeconds > 0 ? "\(weeklyWorkSeconds / 60)" : "—",
                unit: "min working",
                footnote: nil,
                height: 92
            )
            StatTile(
                eyebrow: "Intervals logged",
                value: "\(setLogs.count)",
                unit: "all time",
                footnote: nil,
                height: 92
            )
        }
    }

    private func libraryBlock(for profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Featured", trailing: profile.goal.title)
            VStack(spacing: 10) {
                ForEach(ProgramLibrary.programs(for: profile)) { program in
                    Button {
                        Haptics.tap()
                        activeProgram = program
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(LightBoltTheme.charcoalHigh)
                                    .frame(width: 46, height: 46)
                                if let move = program.exercises.first?.move {
                                    StickFigureLoop(move: move, speed: 0.85)
                                        .frame(width: 42, height: 42)
                                }
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(program.title.uppercased())
                                    .font(.fitTitle(17))
                                    .tracking(0.8)
                                    .foregroundStyle(LightBoltTheme.ink)
                                Text("\(program.focus) · ~\(program.estimatedMinutes) min")
                                    .font(.fitBody(11))
                                    .foregroundStyle(LightBoltTheme.inkMuted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(LightBoltTheme.inkFaint)
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fitCard(radius: 18)
                    }
                    .buttonStyle(VoltPressStyle(scale: 0.98))
                }
            }
        }
    }

    /// Time under tension per movement — the overload metric that means
    /// something when every set is a countdown rather than a load.
    private var overloadBlock: some View {
        let grouped = Dictionary(grouping: setLogs, by: \.exerciseID)
        let ranked = grouped
            .compactMap { _, logs -> (name: String, seconds: Int, intervals: Int)? in
                guard let first = logs.first else { return nil }
                let seconds = logs.reduce(0) { $0 + $1.holdSeconds }
                guard seconds > 0 else { return nil }
                return (first.exerciseName, seconds, logs.count)
            }
            .sorted { $0.seconds > $1.seconds }
            .prefix(6)

        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Time Under Tension", trailing: "all time")
            VStack(spacing: 0) {
                ForEach(Array(ranked.enumerated()), id: \.offset) { index, row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .font(.fitBody(14))
                                .foregroundStyle(LightBoltTheme.ink)
                                .lineLimit(1)
                            EyebrowText(text: "\(row.intervals) intervals", color: LightBoltTheme.inkFaint)
                        }
                        Spacer()
                        Text(row.seconds >= 60
                             ? "\(row.seconds / 60)m \(row.seconds % 60)s"
                             : "\(row.seconds)s")
                            .font(.fitNumeric(16))
                            .foregroundStyle(LightBoltTheme.volt)
                    }
                    .padding(.vertical, 14)

                    if index < ranked.count - 1 {
                        Rectangle().fill(LightBoltTheme.hairline).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .fitCard()
        }
    }

    // MARK: Planner plumbing

    /// Resolves a scheduled entry back to a runnable programme, wherever it
    /// originally came from.
    private func program(for plan: PlannedWorkout) -> Program? {
        if let match = ProgramLibrary.all.first(where: { $0.id == plan.programID }) { return match }
        if let match = WorkoutLibrary.byID[plan.programID] { return match }
        return customWorkouts.map { $0.asProgram() }.first { $0.id == plan.programID }
    }

    private func schedule(_ program: Program) {
        let next = (todaysPlans.map(\.orderIndex).max() ?? -1) + 1
        context.insert(PlannedWorkout(program: program, dayKey: todayKey, orderIndex: next))
        try? context.save()
        Haptics.success()
    }

    // MARK: Export

    private func exportReport() {
        let snapshot = digest
        let window = snapshot.days.first?.date ?? Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .now
        let profileForReport = profile

        let lines: [ReportSessionLine] = sessions
            .filter { $0.finishedAt >= window }
            .map { session in
                let density = session.durationSeconds > 0
                    ? Double(session.workSeconds) / Double(session.durationSeconds)
                    : 0
                let ceiling = WorkoutMetricsEngine.maxHeartRate(age: profileForReport?.age ?? 30)
                let fraction = min(0.97, 0.84 + min(0.08, max(0, density - 0.45) * 0.24))
                return ReportSessionLine(
                    title: session.programTitle,
                    finishedAt: session.finishedAt,
                    durationMinutes: max(1, session.durationSeconds / 60),
                    workSeconds: session.workSeconds,
                    intervals: session.setCount,
                    estimatedPeakHeartRate: Int((Double(ceiling) * fraction).rounded())
                )
            }

        let scanLines: [ReportScanLine] = scans.prefix(2).map { scan in
            ReportScanLine(
                capturedAt: scan.capturedAt,
                chestCm: scan.chestCm,
                waistCm: scan.waistCm,
                hipCm: scan.hipCm,
                shoulderCm: scan.shoulderCm,
                thighCm: scan.thighCm,
                bodyFatPercent: scan.bodyFatPercent,
                quality: scan.quality
            )
        }

        let input = WeeklyReportInput(
            username: account.username ?? "athlete",
            digest: snapshot,
            sessions: lines,
            scans: scanLines,
            units: profileForReport?.units ?? .metric,
            generatedAt: .now
        )

        do {
            let url = try WeeklyReportPDF.write(input)
            report = ReportDocument(url: url, sessions: lines.count, scans: scanLines.count)
            Haptics.success()
        } catch {
            Haptics.failure()
            exportError = "We couldn't write the PDF to this device. Free up some storage and try again."
        }
    }
}
