import SwiftData
import SwiftUI

/// Build-your-own workout: name it, set the interval length and rounds, then
/// pick moves from the full equipment-free library, grouped by muscle.
struct WorkoutBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var rounds: Double = 3
    @State private var workSeconds: Double = 45
    @State private var intensity: TrainingIntensity = .fullPower
    @State private var selectedIDs: [String] = []
    @State private var search = ""

    private var pool: [HomeMove] {
        let source = MoveLibrary.moves(for: intensity)
        guard !search.isEmpty else { return source }
        return source.filter { $0.name.localizedStandardContains(search) }
    }

    private var groupedPool: [(muscle: Muscle, exercises: [HomeMove])] {
        Muscle.allCases.compactMap { muscle in
            let matches = pool.filter { $0.muscle == muscle }
            return matches.isEmpty ? nil : (muscle, matches)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && selectedIDs.count >= 2
    }

    /// Work plus rest for the whole build, so the length is honest up front.
    private var estimatedMinutes: Int {
        let perRound = Int(workSeconds.rounded()) + 20
        let total = selectedIDs.count * Int(rounds.rounded()) * perRound
        return max(1, Int((Double(total) / 60).rounded(.up)))
    }

    var body: some View {
        ZStack {
            LightBoltTheme.backdrop

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        nameField
                        SegmentedVoltPicker(
                            options: TrainingIntensity.allCases,
                            selection: $intensity,
                            label: { $0.title }
                        )
                        MetricStepperField(
                            label: "Work interval",
                            value: $workSeconds,
                            unit: "sec",
                            range: 15...90,
                            step: 5,
                            decimals: 0
                        )
                        MetricStepperField(
                            label: "Rounds per move",
                            value: $rounds,
                            unit: "rounds",
                            range: 1...6,
                            step: 1,
                            decimals: 0
                        )
                        searchField
                        exercisePicker
                    }
                    .padding(20)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
            }

            VStack {
                Spacer()
                saveDock
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: intensity) { _, _ in
            // Low Impact hides the jumping moves; drop any pick that just left.
            let valid = Set(MoveLibrary.moves(for: intensity).map(\.id))
            selectedIDs.removeAll { !valid.contains($0) }
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                EyebrowText(
                    text: selectedIDs.isEmpty
                        ? "Pick your moves"
                        : "\(selectedIDs.count) moves · ~\(estimatedMinutes) min",
                    color: LightBoltTheme.voltDim
                )
                Text("BUILD YOURS")
                    .font(.fitDisplay(40))
                    .tracking(-1)
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
            .accessibilityLabel("Close builder")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowText(text: "Workout name")
            TextField("", text: $name, prompt: Text("e.g. Monday Destroyer").foregroundStyle(LightBoltTheme.inkFaint))
                .font(.fitTitle(20))
                .foregroundStyle(LightBoltTheme.volt)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .frame(height: 56)
                .fitCard(radius: 16)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(LightBoltTheme.inkFaint)
            TextField("", text: $search, prompt: Text("Search moves").foregroundStyle(LightBoltTheme.inkFaint))
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

    private var exercisePicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(groupedPool, id: \.muscle) { group in
                VStack(alignment: .leading, spacing: 8) {
                    EyebrowText(text: group.muscle.title, color: LightBoltTheme.inkMuted)
                    VStack(spacing: 6) {
                        ForEach(group.exercises) { exercise in
                            pickRow(exercise)
                        }
                    }
                }
            }
        }
    }

    private func pickRow(_ exercise: HomeMove) -> some View {
        let isPicked = selectedIDs.contains(exercise.id)
        return Button {
            Haptics.tick()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                if isPicked {
                    selectedIDs.removeAll { $0 == exercise.id }
                } else {
                    selectedIDs.append(exercise.id)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isPicked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isPicked ? LightBoltTheme.volt : LightBoltTheme.inkFaint)

                // The stickman previews the move right in the picker.
                StickFigureLoop(move: exercise.move, speed: 0.9)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 1) {
                    Text(exercise.name)
                        .font(.fitBody(14))
                        .foregroundStyle(LightBoltTheme.ink)
                        .lineLimit(1)
                    Text(exercise.cue)
                        .font(.fitBody(10))
                        .foregroundStyle(LightBoltTheme.inkFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if exercise.isHold {
                    Text("HOLD")
                        .font(.fitLabel(8))
                        .tracking(1)
                        .foregroundStyle(LightBoltTheme.voltDim)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fitCard(radius: 14, stroke: isPicked ? LightBoltTheme.voltDim : LightBoltTheme.hairline)
        }
        .buttonStyle(VoltPressStyle(scale: 0.985))
    }

    private var saveDock: some View {
        VoltButton(
            title: canSave ? "Save Workout · \(selectedIDs.count) moves" : "Pick at least 2 moves",
            systemImage: "bolt.fill",
            isEnabled: canSave
        ) {
            save()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background(
            LinearGradient(
                colors: [LightBoltTheme.void.opacity(0), LightBoltTheme.void.opacity(0.92), LightBoltTheme.void],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private func save() {
        let workout = CustomWorkout(
            name: name.trimmingCharacters(in: .whitespaces),
            exerciseIDs: selectedIDs,
            rounds: Int(rounds.rounded()),
            workSeconds: Int(workSeconds.rounded())
        )
        context.insert(workout)
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
