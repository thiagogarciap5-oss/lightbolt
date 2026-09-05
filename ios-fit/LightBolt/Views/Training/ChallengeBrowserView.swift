import SwiftData
import SwiftUI

/// Browser over the generated multi-day challenges with duration, level and
/// intensity filters. Every plan is equipment-free.
struct ChallengeBrowserView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ChallengeProgress.startedAt, order: .reverse) private var progressRecords: [ChallengeProgress]

    @State private var durationFilter: Int?
    @State private var levelFilter: TrainingLevel?
    @State private var intensityFilter: TrainingIntensity?
    @State private var visibleCount = 50
    @State private var selectedChallenge: Challenge?

    init(initialIntensity: TrainingIntensity? = nil) {
        _intensityFilter = State(initialValue: initialIntensity)
    }

    private var filtered: [Challenge] {
        ChallengeLibrary.all.filter { challenge in
            if let durationFilter, challenge.days != durationFilter { return false }
            if let levelFilter, challenge.level != levelFilter { return false }
            if let intensityFilter, challenge.intensity != intensityFilter { return false }
            return true
        }
    }

    private var activeRecords: [ChallengeProgress] {
        progressRecords.filter { !$0.isComplete }
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
        .fullScreenCover(item: $selectedChallenge) { challenge in
            ChallengeDetailView(challenge: challenge)
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                EyebrowText(text: "\(filtered.count.formatted()) of \(ChallengeLibrary.count.formatted()) plans", color: LightBoltTheme.voltDim)
                Text("CHALLENGES")
                    .font(.fitDisplay(44))
                    .tracking(-1.2)
                    .foregroundStyle(LightBoltTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
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
            .accessibilityLabel("Close challenges")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("All", isOn: durationFilter == nil && levelFilter == nil && intensityFilter == nil) {
                    durationFilter = nil
                    levelFilter = nil
                    intensityFilter = nil
                }
                Rectangle().fill(LightBoltTheme.hairline).frame(width: 1, height: 20)
                ForEach([7, 14, 21, 30], id: \.self) { days in
                    chip("\(days) days", isOn: durationFilter == days) {
                        durationFilter = durationFilter == days ? nil : days
                    }
                }
                Rectangle().fill(LightBoltTheme.hairline).frame(width: 1, height: 20)
                ForEach(TrainingLevel.allCases) { level in
                    chip(level.title, isOn: levelFilter == level) {
                        levelFilter = levelFilter == level ? nil : level
                    }
                }
                Rectangle().fill(LightBoltTheme.hairline).frame(width: 1, height: 20)
                ForEach(TrainingIntensity.allCases) { option in
                    chip(option.title, isOn: intensityFilter == option) {
                        intensityFilter = intensityFilter == option ? nil : option
                    }
                }
            }
        }
        .contentMargins(.horizontal, 20)
        .scrollIndicators(.hidden)
        .padding(.top, 12)
    }

    private func chip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tick()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                action()
                visibleCount = 50
            }
        } label: {
            Text(label.uppercased())
                .font(.fitLabel(10))
                .tracking(1.2)
                .foregroundStyle(isOn ? .black : LightBoltTheme.inkMuted)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(isOn ? LightBoltTheme.volt : LightBoltTheme.charcoal))
                .overlay(Capsule().strokeBorder(isOn ? .clear : LightBoltTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(VoltPressStyle(scale: 0.94))
    }

    // MARK: Results

    private var resultList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if !activeRecords.isEmpty {
                    SectionHeader(title: "In Progress")
                    ForEach(activeRecords) { record in
                        if let challenge = ChallengeLibrary.challenge(id: record.challengeID) {
                            challengeRow(challenge, progress: record)
                        }
                    }
                    SectionHeader(title: "Browse")
                        .padding(.top, 10)
                }

                ForEach(filtered.prefix(visibleCount)) { challenge in
                    challengeRow(challenge, progress: progressRecords.first { $0.challengeID == challenge.id })
                }

                if filtered.count > visibleCount {
                    GhostButton(title: "Show \(min(100, filtered.count - visibleCount)) more", systemImage: "chevron.down") {
                        withAnimation { visibleCount += 100 }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private func challengeRow(_ challenge: Challenge, progress: ChallengeProgress?) -> some View {
        Button {
            Haptics.tap()
            selectedChallenge = challenge
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(progress != nil ? LightBoltTheme.volt : LightBoltTheme.charcoalHigh)
                        .frame(width: 44, height: 44)
                    Image(systemName: challenge.symbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(progress != nil ? .black : LightBoltTheme.volt)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(challenge.title)
                        .font(.fitTitle(16))
                        .tracking(0.6)
                        .foregroundStyle(LightBoltTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let progress {
                        Text("Day \(min(progress.completedDays.count + 1, challenge.days)) of \(challenge.days) · \(challenge.level.title)")
                            .font(.fitBody(11))
                            .foregroundStyle(LightBoltTheme.voltSoft)
                    } else {
                        Text("\(challenge.intensity.title) · \(challenge.workoutDayCount) sessions · \(challenge.days - challenge.workoutDayCount) rest")
                            .font(.fitBody(11))
                            .foregroundStyle(LightBoltTheme.inkMuted)
                    }
                }
                Spacer(minLength: 0)
                if let progress {
                    Text("\(Int((Double(progress.completedDays.count) / Double(max(1, challenge.days)) * 100).rounded()))%")
                        .font(.fitNumeric(15))
                        .foregroundStyle(LightBoltTheme.volt)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(LightBoltTheme.inkFaint)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fitCard(radius: 18, stroke: progress != nil ? LightBoltTheme.voltDim : LightBoltTheme.hairline)
        }
        .buttonStyle(VoltPressStyle(scale: 0.98))
    }
}

// MARK: - Challenge detail

/// Day-by-day plan with start/continue, rest-day recovery marks, and direct
/// launch of each day's session.
struct ChallengeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let challenge: Challenge

    @Query private var allProgress: [ChallengeProgress]

    @State private var activeDay: Int?

    private var progress: ChallengeProgress? {
        allProgress.first { $0.challengeID == challenge.id }
    }

    /// First not-yet-completed day.
    private var currentDay: Int {
        guard let progress else { return 0 }
        return (0..<challenge.days).first { !progress.isDayDone($0) } ?? challenge.days - 1
    }

    var body: some View {
        ZStack {
            LightBoltTheme.backdrop

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if let progress {
                        progressStrip(progress)
                    }

                    dayGrid

                    footerAction
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: Binding(
            get: { activeDay.flatMap { day in challenge.program(forDay: day).map { DayLaunch(day: day, program: $0) } } },
            set: { if $0 == nil { activeDay = nil } }
        )) { launch in
            WorkoutSessionView(program: launch.program) { duration, workSeconds, intervals in
                context.insert(
                    WorkoutSession(
                        programID: launch.program.id,
                        programTitle: "\(challenge.title) · Day \(launch.day + 1)",
                        durationSeconds: duration,
                        workSeconds: workSeconds,
                        intervals: intervals
                    )
                )
                progress?.markDone(launch.day)
                try? context.save()
            }
        }
    }

    private struct DayLaunch: Identifiable {
        let day: Int
        let program: Program
        var id: Int { day }
    }

    /// Start, continue or celebrate — split out to keep the body type-checkable.
    @ViewBuilder
    private var footerAction: some View {
        if progress == nil {
            VoltButton(title: "Start Challenge", systemImage: "flag.checkered") {
                Haptics.thud()
                context.insert(
                    ChallengeProgress(
                        challengeID: challenge.id,
                        title: challenge.title,
                        totalDays: challenge.days
                    )
                )
            }
        } else if progress?.isComplete == true {
            completeBanner
        } else {
            currentDayCard
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                EyebrowText(text: "\(challenge.level.title) · \(challenge.intensity.title)", color: LightBoltTheme.voltDim)
                Text(challenge.title)
                    .font(.fitDisplay(38))
                    .tracking(-0.8)
                    .foregroundStyle(LightBoltTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                Text("\(challenge.workoutDayCount) training days · \(challenge.days - challenge.workoutDayCount) recovery days")
                    .font(.fitBody(12))
                    .foregroundStyle(LightBoltTheme.inkMuted)
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
            .accessibilityLabel("Close challenge")
        }
    }

    private func progressStrip(_ progress: ChallengeProgress) -> some View {
        let fraction = Double(progress.completedDays.count) / Double(max(1, challenge.days))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                EyebrowText(text: "Progress", color: LightBoltTheme.inkMuted)
                Spacer()
                Text("\(progress.completedDays.count)/\(challenge.days)")
                    .font(.fitNumeric(15))
                    .foregroundStyle(LightBoltTheme.volt)
                    .contentTransition(.numericText())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(LightBoltTheme.charcoalHigh)
                    Capsule()
                        .fill(LightBoltTheme.volt)
                        .frame(width: max(8, proxy.size.width * fraction))
                        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: fraction)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .fitCard(radius: 18)
    }

    private var dayGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
            ForEach(0..<challenge.days, id: \.self) { day in
                dayChip(day)
            }
        }
    }

    private func dayChip(_ day: Int) -> some View {
        let isRest = challenge.isRestDay(day)
        let isDone = progress?.isDayDone(day) ?? false
        let isCurrent = progress != nil && day == currentDay && !(progress?.isComplete ?? false)

        return Button {
            handleDayTap(day, isRest: isRest, isDone: isDone)
        } label: {
            VStack(spacing: 3) {
                Text("\(day + 1)")
                    .font(.fitNumeric(16))
                    .foregroundStyle(isDone ? .black : isRest ? LightBoltTheme.inkFaint : LightBoltTheme.ink)
                Image(systemName: isDone ? "checkmark" : isRest ? "moon.zzz.fill" : "bolt.fill")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(isDone ? .black : isRest ? LightBoltTheme.inkFaint : LightBoltTheme.voltDim)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isDone ? LightBoltTheme.volt : LightBoltTheme.charcoal)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isCurrent ? LightBoltTheme.volt : LightBoltTheme.hairline, lineWidth: isCurrent ? 2 : 1)
            )
        }
        .buttonStyle(VoltPressStyle(scale: 0.92))
        .disabled(progress == nil)
        .accessibilityLabel("Day \(day + 1)\(isRest ? ", recovery day" : "")\(isDone ? ", completed" : "")")
    }

    private func handleDayTap(_ day: Int, isRest: Bool, isDone: Bool) {
        guard let progress, !isDone else { return }
        if isRest {
            Haptics.success()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                progress.markDone(day)
                try? context.save()
            }
        } else {
            Haptics.thud()
            activeDay = day
        }
    }

    private var currentDayCard: some View {
        Group {
            if challenge.isRestDay(currentDay) {
                GhostButton(title: "Day \(currentDay + 1): Mark Recovery Done", systemImage: "moon.zzz.fill") {
                    Haptics.success()
                    withAnimation {
                        progress?.markDone(currentDay)
                        try? context.save()
                    }
                }
            } else if let program = challenge.program(forDay: currentDay) {
                VoltButton(title: "Day \(currentDay + 1): \(program.title)", systemImage: "play.fill") {
                    Haptics.thud()
                    activeDay = currentDay
                }
            }
        }
    }

    private var completeBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.black)
            VStack(alignment: .leading, spacing: 2) {
                Text("CHALLENGE COMPLETE")
                    .font(.fitTitle(18))
                    .tracking(1)
                    .foregroundStyle(.black)
                Text("Every day closed out. Pick your next one.")
                    .font(.fitBody(12))
                    .foregroundStyle(.black.opacity(0.7))
            }
            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [LightBoltTheme.volt, LightBoltTheme.voltSoft], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
}
