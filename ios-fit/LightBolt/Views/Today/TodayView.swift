import SwiftData
import SwiftUI

/// The command centre: calorie ring, macro meters, spoken briefing, habits and
/// bodyweight trend — all derived from live local records.
struct TodayView: View {
    @Environment(Entitlements.self) private var entitlements
    @Environment(SpeechCoach.self) private var coach
    @Environment(\.modelContext) private var context

    @Query private var profiles: [UserProfile]
    @Query(sort: \MealEntry.loggedAt, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \Habit.createdAt, order: .forward) private var habits: [Habit]
    @Query(sort: \WeightEntry.recordedAt, order: .reverse) private var weights: [WeightEntry]
    @Query(sort: \WorkoutSession.finishedAt, order: .reverse) private var sessions: [WorkoutSession]

    @State private var isAddingHabit = false
    @State private var newHabitTitle = ""
    @State private var newHabitSymbol = "drop.fill"
    @State private var isCheckingInWeight = false
    @State private var checkInWeight: Double = 0
    @State private var isConfirmingCancel = false
    @State private var isCancelling = false
    @State private var cancelResultMessage: String?

    private var profile: UserProfile? { profiles.first }

    private var todaysMeals: [MealEntry] {
        meals.filter { Calendar.current.isDateInToday($0.loggedAt) }
    }

    private var caloriesToday: Int { todaysMeals.reduce(0) { $0 + $1.calories } }
    private var proteinToday: Double { todaysMeals.reduce(0) { $0 + $1.protein } }
    private var carbsToday: Double { todaysMeals.reduce(0) { $0 + $1.carbs } }
    private var fatToday: Double { todaysMeals.reduce(0) { $0 + $1.fat } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                ringBlock
                macroBlock
                habitBlock
                statsBlock
                cancelSubscriptionBlock
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .background(LightBoltTheme.backdrop)
        .sheet(isPresented: $isAddingHabit) { addHabitSheet }
        .sheet(isPresented: $isCheckingInWeight) { weightSheet }
        .alert("Cancel your subscription?", isPresented: $isConfirmingCancel) {
            Button("Keep Premium", role: .cancel) {}
            Button("Cancel Subscription", role: .destructive) { cancelSubscription() }
        } message: {
            Text("Renewals stop immediately. You keep full access until the end of the period you've already paid for.")
        }
        .alert("Subscription", isPresented: Binding(
            get: { cancelResultMessage != nil },
            set: { if !$0 { cancelResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) { cancelResultMessage = nil }
        } message: {
            Text(cancelResultMessage ?? "")
        }
        .onAppear(perform: maybeSpeakBriefing)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowText(text: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)), color: LightBoltTheme.voltDim)
                    Text(greeting.uppercased())
                        .font(.fitDisplay(42))
                        .tracking(-0.8)
                        .foregroundStyle(LightBoltTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let profile {
                        Text(profile.goal.title.uppercased())
                            .font(.fitTitle(15))
                            .tracking(1.6)
                            .voltWash()
                    }
                }
                Spacer(minLength: 8)

                Button {
                    Haptics.tap()
                    if coach.isSpeaking { coach.stop() } else { speakBriefing() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(coach.isSpeaking ? LightBoltTheme.volt : LightBoltTheme.charcoal)
                            .frame(width: 52, height: 52)
                        Circle()
                            .strokeBorder(LightBoltTheme.hairline, lineWidth: 1)
                            .frame(width: 52, height: 52)
                        Image(systemName: coach.isSpeaking ? "stop.fill" : "waveform")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(coach.isSpeaking ? .black : LightBoltTheme.volt)
                            .symbolEffect(.variableColor.iterative, isActive: coach.isSpeaking)
                    }
                }
                .buttonStyle(VoltPressStyle(scale: 0.9))
                .accessibilityLabel(coach.isSpeaking ? "Stop briefing" : "Play spoken briefing")
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        return hour < 12 ? "Morning" : hour < 18 ? "Afternoon" : "Evening"
    }

    // MARK: Calories

    private var ringBlock: some View {
        VStack(spacing: 18) {
            CalorieRing(consumed: caloriesToday, budget: profile?.calorieBudget ?? 2000)
                .padding(.top, 6)

            HStack(spacing: 10) {
                pill(value: "\(caloriesToday)", label: "eaten")
                pill(value: "\(todaysMeals.count)", label: "meals")
                pill(value: "\(profile?.calorieBudget ?? 0)", label: "budget")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func pill(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.fitNumeric(19))
                .foregroundStyle(LightBoltTheme.ink)
                .contentTransition(.numericText())
            EyebrowText(text: label, color: LightBoltTheme.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .fitCard(radius: 15)
    }

    // MARK: Macros

    private var macroBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Macro Split", trailing: todaysMeals.isEmpty ? "Nothing logged" : nil)

            VStack(spacing: 15) {
                MacroMeter(label: "Protein", value: proteinToday, target: profile?.proteinTarget ?? 150)
                MacroMeter(label: "Carbs", value: carbsToday, target: profile?.carbTarget ?? 220, tint: LightBoltTheme.voltSoft)
                MacroMeter(label: "Fat", value: fatToday, target: profile?.fatTarget ?? 70, tint: LightBoltTheme.voltDim)
            }
            .padding(18)
            .fitCard()
        }
    }

    // MARK: Habits

    private var habitBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeader(title: "Daily Habits")
                Spacer()
                Button {
                    Haptics.tap()
                    isAddingHabit = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(LightBoltTheme.volt))
                }
                .buttonStyle(VoltPressStyle(scale: 0.88))
            }

            if habits.isEmpty {
                EmptyStateCard(
                    symbol: "checklist",
                    title: "No habits yet",
                    message: "Add the two or three behaviours that actually move your objective. LightBolt tracks the streak."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(habits) { habit in
                        HabitRow(habit: habit) {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                                habit.toggle(on: .now)
                            }
                            habit.isDone(on: .now) ? Haptics.success() : Haptics.tick()
                        } onDelete: {
                            withAnimation(.easeOut(duration: 0.2)) { context.delete(habit) }
                            Haptics.warning()
                        }
                    }
                }
            }
        }
    }

    // MARK: Stats

    private var statsBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Signals")

            HStack(alignment: .top, spacing: 12) {
                Button {
                    Haptics.tap()
                    checkInWeight = LightBoltUnits.displayWeight(
                        kg: weights.first?.weightKg ?? profile?.weightKg ?? 75,
                        units: profile?.units ?? .metric
                    )
                    isCheckingInWeight = true
                } label: {
                    StatTile(
                        eyebrow: "Bodyweight",
                        value: weightDisplay,
                        unit: profile?.units.weightUnit ?? "kg",
                        footnote: weightTrend,
                        height: 148,
                        isAccented: true
                    )
                }
                .buttonStyle(VoltPressStyle(scale: 0.97))

                VStack(spacing: 12) {
                    StatTile(
                        eyebrow: "BMI",
                        value: profile.map { String(format: "%.1f", $0.bodyMassIndex) } ?? "—",
                        unit: "index",
                        footnote: nil,
                        height: 68
                    )
                    StatTile(
                        eyebrow: "Sessions",
                        value: "\(sessions.filter { Calendar.current.isDate($0.finishedAt, equalTo: .now, toGranularity: .weekOfYear) }.count)",
                        unit: "this week",
                        footnote: nil,
                        height: 68
                    )
                }
            }

            if !weights.isEmpty {
                WeightSparkline(entries: Array(weights.prefix(14).reversed()), units: profile?.units ?? .metric)
            }
        }
    }

    // MARK: Cancel subscription

    /// Accessible cancellation entry point pinned to the very bottom of Today.
    private var cancelSubscriptionBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if entitlements.stripeCustomerId != nil {
                Button {
                    Haptics.warning()
                    isConfirmingCancel = true
                } label: {
                    HStack(spacing: 10) {
                        if isCancelling {
                            RunningWaveLoader(barCount: 4, height: 15, tint: LightBoltTheme.alert)
                        } else {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 15, weight: .bold))
                        }
                        Text(isCancelling ? "CANCELLING…" : "CANCEL SUBSCRIPTION")
                            .font(.fitTitle(15))
                            .tracking(1.4)
                    }
                    .foregroundStyle(LightBoltTheme.alert)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .fitCard(radius: 16, stroke: LightBoltTheme.alert.opacity(0.45))
                }
                .buttonStyle(VoltPressStyle(scale: 0.98))
                .disabled(isCancelling)
                .accessibilityLabel("Cancel subscription")
                .accessibilityHint("Stops billing immediately and returns you to the subscribe screen.")

                Text("Cancel anytime. Billing stops immediately and you won't be charged again.")
                    .font(.fitBody(11))
                    .foregroundStyle(LightBoltTheme.inkFaint)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 12)
    }

    private func cancelSubscription() {
        isCancelling = true
        Task { @MainActor in
            defer { isCancelling = false }
            do {
                try await entitlements.cancelSubscriptionNow()
                Haptics.success()
                cancelResultMessage = "Done — billing has stopped and you won't be charged again."
            } catch {
                Haptics.failure()
                cancelResultMessage = (error as? LocalizedError)?.errorDescription
                    ?? "We couldn't reach the billing server. Please try again."
            }
        }
    }

    private var weightDisplay: String {
        guard let latest = weights.first ?? profile.map({ WeightEntry(weightKg: $0.weightKg) }) else { return "—" }
        let value = LightBoltUnits.displayWeight(kg: latest.weightKg, units: profile?.units ?? .metric)
        return String(format: value < 100 ? "%.1f" : "%.0f", value)
    }

    private var weightTrend: String? {
        guard weights.count >= 2 else { return "Tap to check in" }
        let delta = weights[0].weightKg - weights[1].weightKg
        let display = LightBoltUnits.displayWeight(kg: abs(delta), units: profile?.units ?? .metric)
        if abs(delta) < 0.05 { return "Holding steady" }
        return String(format: "%@%.1f %@ since last", delta > 0 ? "+" : "−", display, profile?.units.weightUnit ?? "kg")
    }

    // MARK: Sheets

    private var addHabitSheet: some View {
        let symbols = ["drop.fill", "moon.zzz.fill", "figure.walk", "pills.fill", "book.closed.fill", "sun.max.fill", "leaf.fill", "flame.fill"]
        return NavigationStack {
            ZStack {
                LightBoltTheme.backdrop
                VStack(alignment: .leading, spacing: 22) {
                    Text("NEW HABIT")
                        .font(.fitDisplay(38))
                        .foregroundStyle(LightBoltTheme.ink)

                    TextField("", text: $newHabitTitle, prompt: Text("Drink 3 L of water").foregroundStyle(LightBoltTheme.inkFaint))
                        .font(.fitBody(17))
                        .foregroundStyle(LightBoltTheme.ink)
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .fitCard(radius: 16)

                    EyebrowText(text: "Icon")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(symbols, id: \.self) { symbol in
                            Button {
                                Haptics.tick()
                                newHabitSymbol = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(newHabitSymbol == symbol ? .black : LightBoltTheme.inkMuted)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 54)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(newHabitSymbol == symbol ? LightBoltTheme.volt : LightBoltTheme.charcoal)
                                    )
                            }
                            .buttonStyle(VoltPressStyle(scale: 0.92))
                        }
                    }

                    Spacer()

                    VoltButton(title: "Add Habit", isEnabled: !newHabitTitle.trimmingCharacters(in: .whitespaces).isEmpty) {
                        let habit = Habit(title: newHabitTitle.trimmingCharacters(in: .whitespaces), symbol: newHabitSymbol)
                        context.insert(habit)
                        newHabitTitle = ""
                        Haptics.success()
                        isAddingHabit = false
                    }
                }
                .padding(20)
            }
            .toolbar { closeButton { isAddingHabit = false } }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private var weightSheet: some View {
        let units = profile?.units ?? .metric
        return NavigationStack {
            ZStack {
                LightBoltTheme.backdrop
                VStack(alignment: .leading, spacing: 24) {
                    Text("CHECK IN")
                        .font(.fitDisplay(38))
                        .foregroundStyle(LightBoltTheme.ink)

                    MetricStepperField(
                        label: "Bodyweight",
                        value: $checkInWeight,
                        unit: units.weightUnit,
                        range: units == .metric ? 35...250 : 77...550,
                        step: units == .metric ? 0.1 : 0.2,
                        decimals: 1
                    )

                    Spacer()

                    VoltButton(title: "Log Weight", systemImage: "checkmark") {
                        let kg = units == .metric ? checkInWeight : LightBoltUnits.kg(fromLb: checkInWeight)
                        context.insert(WeightEntry(weightKg: kg))
                        profile?.weightKg = kg
                        profile?.updatedAt = .now
                        Haptics.success()
                        isCheckingInWeight = false
                    }
                }
                .padding(20)
            }
            .toolbar { closeButton { isCheckingInWeight = false } }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private func closeButton(_ action: @escaping () -> Void) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Haptics.tick()
                action()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(LightBoltTheme.ink)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(LightBoltTheme.charcoal))
            }
        }
    }

    // MARK: Briefing

    private func maybeSpeakBriefing() {
        guard entitlements.isCoachEnabled, !entitlements.hasCoachSpoken(on: .now) else { return }
        entitlements.markCoachSpoken(on: .now)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            speakBriefing()
        }
    }

    private func speakBriefing() {
        guard let profile else { return }
        let outstanding = habits.filter { !$0.isDone(on: .now) }.map(\.title)
        let script = CoachScript.morning(
            goal: profile.goal,
            calorieBudget: profile.calorieBudget,
            caloriesLogged: caloriesToday,
            proteinTarget: profile.proteinTarget,
            proteinLogged: Int(proteinToday),
            habitsRemaining: outstanding,
            workoutTitle: ProgramLibrary.todaysProgram(for: profile)?.title
        )
        coach.speak(script)
    }
}

// MARK: - Pieces

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title.uppercased())
                .font(.fitTitle(20))
                .tracking(1.2)
                .foregroundStyle(LightBoltTheme.ink)
            Rectangle()
                .fill(LightBoltTheme.hairline)
                .frame(height: 1)
            if let trailing {
                EyebrowText(text: trailing, color: LightBoltTheme.inkFaint)
            }
        }
    }
}

private struct HabitRow: View {
    let habit: Habit
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let isDone = habit.isDone(on: .now)
        let streak = habit.streak(endingOn: .now)

        Button(action: onToggle) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isDone ? LightBoltTheme.volt : LightBoltTheme.charcoalHigh)
                        .frame(width: 40, height: 40)
                    Image(systemName: isDone ? "checkmark" : habit.symbol)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(isDone ? .black : LightBoltTheme.inkMuted)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.title)
                        .font(.fitBody(15))
                        .foregroundStyle(isDone ? LightBoltTheme.inkMuted : LightBoltTheme.ink)
                        .strikethrough(isDone, color: LightBoltTheme.inkFaint)
                        .lineLimit(1)
                    if streak > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill").font(.system(size: 9, weight: .bold))
                            Text("\(streak) day streak")
                                .font(.fitLabel(10))
                                .tracking(0.8)
                        }
                        .foregroundStyle(LightBoltTheme.volt)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fitCard(radius: 16, stroke: isDone ? LightBoltTheme.voltDim : LightBoltTheme.hairline)
        }
        .buttonStyle(VoltPressStyle(scale: 0.98))
        .contextMenu {
            Button("Delete Habit", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

struct StatTile: View {
    let eyebrow: String
    let value: String
    let unit: String
    let footnote: String?
    let height: CGFloat
    var isAccented: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            EyebrowText(text: eyebrow, color: isAccented ? LightBoltTheme.voltDim : LightBoltTheme.inkFaint)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.fitNumeric(isAccented ? 40 : 24))
                    .foregroundStyle(isAccented ? LightBoltTheme.volt : LightBoltTheme.ink)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(unit)
                    .font(.fitLabel(10))
                    .foregroundStyle(LightBoltTheme.inkFaint)
            }
            if let footnote {
                Text(footnote)
                    .font(.fitBody(11))
                    .foregroundStyle(LightBoltTheme.inkMuted)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .fitCard(radius: 18, stroke: isAccented ? LightBoltTheme.voltDim : LightBoltTheme.hairline)
    }
}

struct EmptyStateCard: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(LightBoltTheme.voltDim)
            Text(title.uppercased())
                .font(.fitTitle(17))
                .tracking(1)
                .foregroundStyle(LightBoltTheme.ink)
            Text(message)
                .font(.fitBody(13))
                .foregroundStyle(LightBoltTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard()
    }
}

/// Minimal bodyweight trend line drawn with a Path.
struct WeightSparkline: View {
    let entries: [WeightEntry]
    let units: UnitSystem

    var body: some View {
        let values = entries.map { LightBoltUnits.displayWeight(kg: $0.weightKg, units: units) }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let span = max(0.4, maxValue - minValue)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EyebrowText(text: "Last \(values.count) check-ins")
                Spacer()
                Text(String(format: "%.1f – %.1f %@", minValue, maxValue, units.weightUnit))
                    .font(.fitLabel(10))
                    .foregroundStyle(LightBoltTheme.inkFaint)
            }

            GeometryReader { geo in
                let points = values.enumerated().map { index, value in
                    CGPoint(
                        x: values.count > 1 ? geo.size.width * CGFloat(index) / CGFloat(values.count - 1) : geo.size.width / 2,
                        y: geo.size.height - (geo.size.height - 8) * CGFloat((value - minValue) / span) - 4
                    )
                }

                ZStack {
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: CGPoint(x: first.x, y: geo.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [LightBoltTheme.volt.opacity(0.28), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(LightBoltTheme.volt, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    if let last = points.last {
                        Circle()
                            .fill(LightBoltTheme.volt)
                            .frame(width: 7, height: 7)
                            .position(last)
                    }
                }
            }
            .frame(height: 74)
        }
        .padding(16)
        .fitCard(radius: 18)
    }
}
