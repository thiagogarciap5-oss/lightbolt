import SwiftData
import SwiftUI

/// Three-step calibration survey. Nothing is written to SwiftData until the
/// user compiles the profile on the final slide.
struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements

    @State private var step: Int = 0
    @State private var goal: LightBoltGoal?
    @State private var intensity: TrainingIntensity?
    @State private var sex: BiologicalSex = .male
    @State private var units: UnitSystem = .imperial
    @State private var age: Int = 28
    @State private var heightValue: Double = 70
    @State private var weightValue: Double = 175
    @State private var bodyFatText: String = ""
    @State private var showPaywall = false
    @State private var showLegal = false

    private let totalSteps = 3

    var body: some View {
        ZStack {
            LightBoltTheme.backdrop

            VStack(alignment: .leading, spacing: 0) {
                header

                TabView(selection: $step) {
                    objectiveStep.tag(0)
                    baselineStep.tag(1)
                    intensityStep.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.42, dampingFraction: 0.82), value: step)

                footer
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(onSubscribed: { showPaywall = false })
        }
        .sheet(isPresented: $showLegal) {
            LegalCenterView()
        }
    }

    // MARK: Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                HStack(spacing: 7) {
                    Rectangle()
                        .fill(LightBoltTheme.volt)
                        .frame(width: 4, height: 22)
                    Text("FIT")
                        .font(.fitDisplay(30))
                        .tracking(-1)
                        .foregroundStyle(LightBoltTheme.ink)
                }
                Spacer()
                Button {
                    Haptics.tap()
                    showLegal = true
                } label: {
                    EyebrowText(text: "Legal", color: LightBoltTheme.inkFaint)
                }
                .buttonStyle(VoltPressStyle())
            }

            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? LightBoltTheme.volt : LightBoltTheme.charcoalHigh)
                        .frame(height: 3)
                        .frame(maxWidth: index == step ? .infinity : 40)
                        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: step)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            VoltButton(
                title: step == totalSteps - 1 ? "Compile my plan" : "Continue",
                systemImage: step == totalSteps - 1 ? "bolt.fill" : nil,
                isEnabled: isStepValid
            ) {
                advance()
            }

            if step > 0 {
                Button {
                    Haptics.tick()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step -= 1 }
                } label: {
                    EyebrowText(text: "Back", color: LightBoltTheme.inkFaint)
                }
                .buttonStyle(VoltPressStyle())
            } else {
                EyebrowText(text: "Step 1 of 3 · takes 40 seconds", color: LightBoltTheme.inkFaint)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 26)
    }

    // MARK: Step 1

    private var objectiveStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                StepHeadline(eyebrow: "Calibration", index: "01", lines: ["WHAT ARE", "YOU HERE", "TO DO?"])

                VStack(spacing: 12) {
                    ForEach(LightBoltGoal.allCases) { option in
                        SelectionRow(
                            title: option.title,
                            blurb: option.blurb,
                            symbol: option.symbol,
                            isSelected: goal == option
                        ) {
                            Haptics.tap()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { goal = option }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Step 2

    private var baselineStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                StepHeadline(eyebrow: "Calibration", index: "02", lines: ["YOUR", "NUMBERS", "TODAY."])

                SegmentedVoltPicker(
                    options: UnitSystem.allCases,
                    selection: $units,
                    label: { $0.title }
                )
                .onChange(of: units) { oldValue, newValue in
                    convertUnits(from: oldValue, to: newValue)
                }

                SegmentedVoltPicker(
                    options: BiologicalSex.allCases,
                    selection: $sex,
                    label: { $0.title }
                )

                MetricStepperField(
                    label: "Age",
                    value: Binding(get: { Double(age) }, set: { age = Int($0.rounded()) }),
                    unit: "yrs",
                    range: 14...95,
                    step: 1,
                    decimals: 0
                )

                MetricStepperField(
                    label: "Height",
                    value: $heightValue,
                    unit: units.lengthUnit,
                    range: units == .metric ? 120...230 : 47...90,
                    step: units == .metric ? 1 : 0.5,
                    decimals: units == .metric ? 0 : 1
                )

                MetricStepperField(
                    label: "Weight",
                    value: $weightValue,
                    unit: units.weightUnit,
                    range: units == .metric ? 35...250 : 77...550,
                    step: units == .metric ? 0.5 : 1,
                    decimals: units == .metric ? 1 : 0
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        EyebrowText(text: "Body fat %")
                        Spacer()
                        EyebrowText(text: "Optional", color: LightBoltTheme.inkFaint)
                    }
                    TextField("", text: $bodyFatText, prompt: Text("—").foregroundStyle(LightBoltTheme.inkFaint))
                        .keyboardType(.decimalPad)
                        .font(.fitNumeric(22))
                        .foregroundStyle(LightBoltTheme.volt)
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .fitCard(radius: 16)
                }

                if let preview = calorieProjection {
                    ProjectionStrip(calories: preview.calories, protein: preview.protein)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Step 3

    private var intensityStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                StepHeadline(eyebrow: "Calibration", index: "03", lines: ["HOW HARD", "CAN YOUR", "FLOOR TAKE IT?"])

                VStack(spacing: 12) {
                    ForEach(TrainingIntensity.allCases) { option in
                        SelectionRow(
                            title: option.title,
                            blurb: option.blurb,
                            symbol: option.symbol,
                            isSelected: intensity == option
                        ) {
                            Haptics.tap()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { intensity = option }
                        }
                    }
                }

                Text("Every LightBolt workout is equipment-free and run on a timer — no dumbbells, no counting reps. Low Impact simply removes the jumping. You can change any of this later in Profile.")
                    .font(.fitBody(13))
                    .foregroundStyle(LightBoltTheme.inkMuted)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Logic

    private var isStepValid: Bool {
        switch step {
        case 0: goal != nil
        case 1: age >= 14 && heightValue > 0 && weightValue > 0
        default: intensity != nil
        }
    }

    private var heightCm: Double {
        units == .metric ? heightValue : LightBoltUnits.cm(fromIn: heightValue)
    }

    private var weightKg: Double {
        units == .metric ? weightValue : LightBoltUnits.kg(fromLb: weightValue)
    }

    private var calorieProjection: (calories: Int, protein: Int)? {
        guard let goal else { return nil }
        let base = (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age)) + (sex == .male ? 5 : -161)
        let calories = Int((base * 1.45 * goal.calorieFactor).rounded())
        let protein = Int((weightKg * goal.proteinPerKg).rounded())
        return (calories, protein)
    }

    private func convertUnits(from old: UnitSystem, to new: UnitSystem) {
        guard old != new else { return }
        if new == .metric {
            heightValue = (LightBoltUnits.cm(fromIn: heightValue)).rounded()
            weightValue = (LightBoltUnits.kg(fromLb: weightValue) * 10).rounded() / 10
        } else {
            heightValue = (LightBoltUnits.inches(fromCm: heightValue) * 2).rounded() / 2
            weightValue = LightBoltUnits.lb(fromKg: weightValue).rounded()
        }
    }

    private func advance() {
        guard isStepValid else { return }
        Haptics.tap()
        if step < totalSteps - 1 {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { step += 1 }
            return
        }
        compileProfile()
    }

    private func compileProfile() {
        guard let goal, let intensity else { return }
        let bodyFat = Double(bodyFatText.replacingOccurrences(of: ",", with: "."))
        let profile = UserProfile(
            goal: goal,
            intensity: intensity,
            sex: sex,
            units: units,
            age: age,
            heightCm: heightCm,
            weightKg: weightKg,
            bodyFatPercent: (bodyFat.map { min(70, max(2, $0)) })
        )

        do {
            let existing = try context.fetch(FetchDescriptor<UserProfile>())
            existing.forEach(context.delete)
            context.insert(profile)
            context.insert(WeightEntry(weightKg: weightKg))
            try context.save()
        } catch {
            Haptics.failure()
            return
        }

        Haptics.success()
        showPaywall = true
    }
}

// MARK: - Building blocks

private struct StepHeadline: View {
    let eyebrow: String
    let index: String
    /// Display lines in the user's chosen language; the last one takes the accent.
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            EyebrowText(text: "\(eyebrow) \(index)", color: LightBoltTheme.voltDim)
                .padding(.bottom, 8)
            ForEach(Array(lines.enumerated()), id: \.offset) { position, line in
                Text(line)
                    .font(.fitDisplay(46))
                    .tracking(-0.5)
                    .foregroundStyle(position == lines.count - 1 ? LightBoltTheme.volt : LightBoltTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

private struct SelectionRow: View {
    let title: String
    let blurb: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? LightBoltTheme.volt : LightBoltTheme.charcoalHigh)
                        .frame(width: 44, height: 44)
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(isSelected ? .black : LightBoltTheme.inkMuted)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title.uppercased())
                        .font(.fitTitle(19))
                        .tracking(0.4)
                        .foregroundStyle(LightBoltTheme.ink)
                    Text(blurb)
                        .font(.fitBody(13))
                        .foregroundStyle(LightBoltTheme.inkMuted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fitCard(
                radius: 20,
                stroke: isSelected ? LightBoltTheme.volt : LightBoltTheme.hairline,
                fill: isSelected ? LightBoltTheme.charcoalHigh : LightBoltTheme.charcoal
            )
        }
        .buttonStyle(VoltPressStyle(scale: 0.98))
    }
}

struct SegmentedVoltPicker<Option: Identifiable & Equatable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                Button {
                    Haptics.tick()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selection = option }
                } label: {
                    Text(label(option).uppercased())
                        .font(.fitLabel(12))
                        .tracking(1.2)
                        .foregroundStyle(selection == option ? .black : LightBoltTheme.inkMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(selection == option ? LightBoltTheme.volt : Color.clear)
                        )
                }
                .buttonStyle(VoltPressStyle(scale: 0.97))
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(LightBoltTheme.charcoal)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(LightBoltTheme.hairline, lineWidth: 1)
        )
    }
}

/// Numeric field with volt +/- steppers and haptics on every tap.
struct MetricStepperField: View {
    let label: String
    @Binding var value: Double
    let unit: String
    let range: ClosedRange<Double>
    let step: Double
    let decimals: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowText(text: label)

            HStack(spacing: 12) {
                stepperButton(symbol: "minus", delta: -step)

                VStack(spacing: 0) {
                    Text(formatted)
                        .font(.fitNumeric(30))
                        .foregroundStyle(LightBoltTheme.volt)
                        .contentTransition(.numericText())
                    Text(unit.uppercased())
                        .font(.fitLabel(9))
                        .tracking(1.6)
                        .foregroundStyle(LightBoltTheme.inkFaint)
                }
                .frame(maxWidth: .infinity)

                stepperButton(symbol: "plus", delta: step)
            }
            .padding(.horizontal, 12)
            .frame(height: 72)
            .fitCard(radius: 18)
        }
    }

    private var formatted: String {
        String(format: "%.\(decimals)f", value)
    }

    private func stepperButton(symbol: String, delta: Double) -> some View {
        Button {
            Haptics.tick()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                value = min(range.upperBound, max(range.lowerBound, value + delta))
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.black)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LightBoltTheme.volt)
                )
        }
        .buttonStyle(VoltPressStyle(scale: 0.9))
    }
}

private struct ProjectionStrip: View {
    let calories: Int
    let protein: Int

    var body: some View {
        HStack(spacing: 0) {
            projection(value: "\(calories)", label: "kcal / day")
            Rectangle().fill(LightBoltTheme.hairline).frame(width: 1, height: 34)
            projection(value: "\(protein)g", label: "protein / day")
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .fitCard(radius: 18, stroke: LightBoltTheme.voltDim, fill: LightBoltTheme.charcoal)
    }

    private func projection(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.fitNumeric(24))
                .voltWash()
                .contentTransition(.numericText())
            EyebrowText(text: label, color: LightBoltTheme.inkFaint)
        }
        .frame(maxWidth: .infinity)
    }
}
