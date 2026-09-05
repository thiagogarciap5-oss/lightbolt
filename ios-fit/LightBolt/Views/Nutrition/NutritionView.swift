import SwiftData
import SwiftUI

/// Meal log + entry point to the AI plate scanner.
struct NutritionView: View {
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.modelContext) private var context

    @Query private var profiles: [UserProfile]
    @Query(sort: \MealEntry.loggedAt, order: .reverse) private var meals: [MealEntry]

    @State private var isScanning = false
    @State private var limitMessage: String?

    private var profile: UserProfile? { profiles.first }

    private var todaysMeals: [MealEntry] {
        meals.filter { Calendar.current.isDateInToday($0.loggedAt) }
    }

    private var earlierMeals: [MealEntry] {
        meals.filter { !Calendar.current.isDateInToday($0.loggedAt) }
    }

    private var caloriesToday: Int { todaysMeals.reduce(0) { $0 + $1.calories } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                scanCTA

                if let limitMessage {
                    LimitBanner(message: limitMessage)
                }

                if todaysMeals.isEmpty && earlierMeals.isEmpty {
                    EmptyStateCard(
                        symbol: "camera.metering.matrix",
                        title: "No meals logged",
                        message: "Point the camera at your plate. LightBolt identifies the food and estimates calories, protein, carbs and fat."
                    )
                } else {
                    if !todaysMeals.isEmpty {
                        mealSection(title: "Today", entries: todaysMeals)
                    }
                    if !earlierMeals.isEmpty {
                        mealSection(title: "Earlier", entries: earlierMeals)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .background(LightBoltTheme.backdrop)
        .fullScreenCover(isPresented: $isScanning) {
            MealScannerView { analysis, thumbnail in
                let entry = MealEntry(
                    mealName: analysis.mealName,
                    estimatedGrams: analysis.estimatedGrams,
                    calories: analysis.calories,
                    protein: analysis.protein,
                    carbs: analysis.carbs,
                    fat: analysis.fat,
                    confidence: analysis.confidence,
                    items: analysis.items,
                    thumbnail: thumbnail
                )
                context.insert(entry)
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            EyebrowText(text: "Nutrition", color: LightBoltTheme.voltDim)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(caloriesToday)")
                    .font(.fitDisplay(58))
                    .tracking(-1.5)
                    .voltWash()
                    .contentTransition(.numericText())
                Text("/ \(profile?.calorieBudget ?? 2000) KCAL")
                    .font(.fitTitle(16))
                    .tracking(1.2)
                    .foregroundStyle(LightBoltTheme.inkMuted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }

    private var scanCTA: some View {
        Button {
            Haptics.tap()
            let scansToday = todaysMeals.count
            if scansToday >= entitlements.dailyMealScanLimit {
                limitMessage = "You've used all \(entitlements.dailyMealScanLimit) AI food photos for today. The counter resets at midnight — this cap applies to every member."
                Haptics.warning()
                return
            }
            limitMessage = nil
            isScanning = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LightBoltTheme.volt)
                        .frame(width: 58, height: 58)
                    Image(systemName: "camera.metering.matrix")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.black)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("SCAN A PLATE")
                        .font(.fitTitle(20))
                        .tracking(1.2)
                        .foregroundStyle(LightBoltTheme.ink)
                    Text("\(max(0, entitlements.dailyMealScanLimit - todaysMeals.count)) of \(entitlements.dailyMealScanLimit) AI food photos left today")
                        .font(.fitBody(12))
                        .foregroundStyle(LightBoltTheme.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(LightBoltTheme.volt)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .fitCard(radius: 22, stroke: LightBoltTheme.voltDim, fill: LightBoltTheme.charcoal)
        }
        .buttonStyle(VoltPressStyle(scale: 0.98))
    }

    private func mealSection(title: String, entries: [MealEntry]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title, trailing: "\(entries.count)")
            VStack(spacing: 10) {
                ForEach(entries) { meal in
                    MealRow(meal: meal) {
                        withAnimation(.easeOut(duration: 0.22)) { context.delete(meal) }
                        Haptics.warning()
                    }
                }
            }
        }
    }
}

private struct MealRow: View {
    let meal: MealEntry
    let onDelete: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tick()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 13) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meal.mealName)
                            .font(.fitTitle(16))
                            .foregroundStyle(LightBoltTheme.ink)
                            .lineLimit(1)
                        Text("\(meal.loggedAt.formatted(date: .omitted, time: .shortened)) · \(Int(meal.estimatedGrams)) g")
                            .font(.fitBody(11))
                            .foregroundStyle(LightBoltTheme.inkFaint)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(meal.calories)")
                            .font(.fitNumeric(22))
                            .foregroundStyle(LightBoltTheme.volt)
                        EyebrowText(text: "kcal", color: LightBoltTheme.inkFaint)
                    }
                }
                .padding(12)
            }
            .buttonStyle(VoltPressStyle(scale: 0.99))

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Rectangle().fill(LightBoltTheme.hairline).frame(height: 1)
                    HStack(spacing: 10) {
                        macroChip("P", value: meal.protein)
                        macroChip("C", value: meal.carbs)
                        macroChip("F", value: meal.fat)
                    }
                    if !meal.items.isEmpty {
                        Text(meal.items.joined(separator: " · "))
                            .font(.fitBody(12))
                            .foregroundStyle(LightBoltTheme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        EyebrowText(text: "Confidence \(Int(meal.confidence * 100))%", color: LightBoltTheme.inkFaint)
                        Spacer()
                        Button(role: .destructive, action: onDelete) {
                            Text("DELETE")
                                .font(.fitLabel(10))
                                .tracking(1.4)
                                .foregroundStyle(LightBoltTheme.alert)
                        }
                        .buttonStyle(VoltPressStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .fitCard(radius: 18)
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LightBoltTheme.charcoalHigh)
                .frame(width: 52, height: 52)
            if let data = meal.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .allowsHitTesting(false)
            } else {
                Image(systemName: "fork.knife")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LightBoltTheme.inkFaint)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
    }

    private func macroChip(_ letter: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(letter)
                .font(.fitLabel(9))
                .tracking(1.5)
                .foregroundStyle(LightBoltTheme.inkFaint)
            Text("\(Int(value))g")
                .font(.fitNumeric(15))
                .foregroundStyle(LightBoltTheme.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LightBoltTheme.charcoalHigh)
        )
    }
}

struct LimitBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(LightBoltTheme.volt)
            Text(message)
                .font(.fitBody(13))
                .foregroundStyle(LightBoltTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard(radius: 18, stroke: LightBoltTheme.voltDim)
    }
}
