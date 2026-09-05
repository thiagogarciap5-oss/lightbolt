import SwiftData
import SwiftUI

/// Full-catalogue browser over the generated programmes, with search and
/// intensity / level / split filters. Everything here is equipment-free.
struct LibraryBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var search = ""
    @State private var intensityFilter: TrainingIntensity?
    @State private var levelFilter: TrainingLevel?
    @State private var splitFilter: WorkoutSplit?
    @State private var visibleCount = 60
    @State private var detailProgram: Program?
    @State private var activeProgram: Program?

    init(initialIntensity: TrainingIntensity? = nil) {
        _intensityFilter = State(initialValue: initialIntensity)
    }

    private var filtered: [Program] {
        WorkoutLibrary.all.filter { program in
            if let intensityFilter, program.intensity != intensityFilter { return false }
            if let levelFilter, program.level != levelFilter { return false }
            if let splitFilter, !program.id.hasPrefix("lib-\(splitFilter.rawValue)-") { return false }
            if !search.isEmpty {
                let haystack = "\(program.title) \(program.focus)".localizedLowercase
                return haystack.contains(search.localizedLowercase)
            }
            return true
        }
    }

    var body: some View {
        ZStack {
            LightBoltTheme.backdrop

            VStack(spacing: 0) {
                header
                filterBar
                resultList
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $detailProgram) { program in
            WorkoutDetailSheet(program: program) {
                detailProgram = nil
                activeProgram = program
            }
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
            }
        }
    }

    // MARK: Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowText(text: "\(filtered.count.formatted()) of \(WorkoutLibrary.count.formatted()) workouts", color: LightBoltTheme.voltDim)
                    Text("THE VAULT")
                        .font(.fitDisplay(44))
                        .tracking(-1.2)
                        .foregroundStyle(LightBoltTheme.ink)
                }
                Spacer()
                Button {
                    Haptics.tick()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(LightBoltTheme.ink)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(LightBoltTheme.charcoal))
                }
                .buttonStyle(VoltPressStyle(scale: 0.9))
                .accessibilityLabel("Close library")
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LightBoltTheme.inkFaint)
                TextField("", text: $search, prompt: Text("Search workouts").foregroundStyle(LightBoltTheme.inkFaint))
                    .font(.fitBody(15))
                    .foregroundStyle(LightBoltTheme.ink)
                    .autocorrectionDisabled()
                if !search.isEmpty {
                    Button {
                        Haptics.tick()
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(LightBoltTheme.inkFaint)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .fitCard(radius: 15)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    filterChip("Any Intensity", isOn: intensityFilter == nil) { intensityFilter = nil }
                    ForEach(TrainingIntensity.allCases) { option in
                        filterChip(option.title, isOn: intensityFilter == option) {
                            intensityFilter = intensityFilter == option ? nil : option
                        }
                    }
                    Rectangle().fill(LightBoltTheme.hairline).frame(width: 1, height: 20)
                    ForEach(TrainingLevel.allCases) { option in
                        filterChip(option.title, isOn: levelFilter == option) {
                            levelFilter = levelFilter == option ? nil : option
                        }
                    }
                }
            }
            .contentMargins(.horizontal, 20)
            .scrollIndicators(.hidden)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    filterChip("All Splits", isOn: splitFilter == nil) { splitFilter = nil }
                    ForEach(WorkoutSplit.allCases) { option in
                        filterChip(option.displayName, isOn: splitFilter == option) {
                            splitFilter = splitFilter == option ? nil : option
                        }
                    }
                }
            }
            .contentMargins(.horizontal, 20)
            .scrollIndicators(.hidden)
        }
        .padding(.top, 12)
    }

    private func filterChip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tick()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                action()
                visibleCount = 60
            }
        } label: {
            Text(label.uppercased())
                .font(.fitLabel(10))
                .tracking(1.2)
                .foregroundStyle(isOn ? .black : LightBoltTheme.inkMuted)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    Capsule().fill(isOn ? LightBoltTheme.volt : LightBoltTheme.charcoal)
                )
                .overlay(
                    Capsule().strokeBorder(isOn ? .clear : LightBoltTheme.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(VoltPressStyle(scale: 0.94))
    }

    // MARK: Results

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filtered.prefix(visibleCount)) { program in
                    WorkoutRow(program: program) {
                        Haptics.tap()
                        detailProgram = program
                    }
                }

                if filtered.count > visibleCount {
                    GhostButton(title: "Show \(min(120, filtered.count - visibleCount)) more", systemImage: "chevron.down") {
                        withAnimation { visibleCount += 120 }
                    }
                    .padding(.top, 4)
                }

                if filtered.isEmpty {
                    EmptyStateCard(
                        symbol: "magnifyingglass",
                        title: "No matches",
                        message: "Loosen the filters or try a different search term."
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Shared row

struct WorkoutRow: View {
    let program: Program
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LightBoltTheme.charcoalHigh)
                        .frame(width: 46, height: 46)
                    if let move = program.exercises.first?.move {
                        StickFigureLoop(move: move, speed: 0.85)
                            .frame(width: 42, height: 42)
                    } else {
                        Image(systemName: "figure.run")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(LightBoltTheme.volt)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(program.title)
                        .font(.fitTitle(16))
                        .tracking(0.6)
                        .foregroundStyle(LightBoltTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(program.focus) · \(program.totalRounds) intervals · ~\(program.estimatedMinutes) min")
                        .font(.fitBody(11))
                        .foregroundStyle(LightBoltTheme.inkMuted)
                        .lineLimit(1)
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

// MARK: - Detail sheet

/// Exercise rundown with a start button; shown before committing to a session.
struct WorkoutDetailSheet: View {
    let program: Program
    let onStart: () -> Void

    var body: some View {
        ZStack {
            LightBoltTheme.backdrop

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            EyebrowText(text: "\(program.level.title) · \(program.intensity.title) · no equipment", color: LightBoltTheme.voltDim)
                            Text(program.title)
                                .font(.fitDisplay(40))
                                .tracking(-0.8)
                                .foregroundStyle(LightBoltTheme.ink)
                                .lineLimit(2)
                                .minimumScaleFactor(0.6)
                            Text(program.focus)
                                .font(.fitBody(13))
                                .foregroundStyle(LightBoltTheme.inkMuted)
                        }

                        HStack(spacing: 12) {
                            statPill("\(program.exercises.count)", "moves")
                            statPill("\(program.totalRounds)", "intervals")
                            statPill("~\(program.estimatedMinutes)", "min")
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(program.exercises.enumerated()), id: \.element.id) { index, exercise in
                                HStack(spacing: 12) {
                                    StickFigureLoop(move: exercise.move, speed: 0.85)
                                        .frame(width: 38, height: 38)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(exercise.name)
                                            .font(.fitBody(14))
                                            .foregroundStyle(LightBoltTheme.ink)
                                            .lineLimit(1)
                                        EyebrowText(
                                            text: exercise.isHold
                                                ? "\(exercise.target) · hold"
                                                : "\(exercise.target) · ~\(exercise.pacedReps) reps paced",
                                            color: LightBoltTheme.inkFaint
                                        )
                                    }
                                    Spacer()
                                    Text(exercise.intervalLabel)
                                        .font(.fitNumeric(14))
                                        .foregroundStyle(LightBoltTheme.volt)
                                }
                                .padding(.vertical, 11)

                                if index < program.exercises.count - 1 {
                                    Rectangle().fill(LightBoltTheme.hairline).frame(height: 1)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .fitCard()
                    }
                    .padding(20)
                    .padding(.bottom, 90)
                }
                .scrollIndicators(.hidden)
            }

            VStack {
                Spacer()
                VoltButton(title: "Start Workout", systemImage: "play.fill") {
                    Haptics.thud()
                    onStart()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .presentationDetents([.large])
        .presentationContentInteraction(.scrolls)
        .preferredColorScheme(.dark)
    }

    private func statPill(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.fitNumeric(18))
                .foregroundStyle(LightBoltTheme.volt)
            EyebrowText(text: label, color: LightBoltTheme.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .fitCard(radius: 14)
    }
}
