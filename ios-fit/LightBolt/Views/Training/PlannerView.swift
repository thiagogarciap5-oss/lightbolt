import SwiftData
import SwiftUI

/// Today's schedule: a hand-ordered stack of workouts. Rows are dragged by the
/// grip handle and reorder live under the finger; each row expands to reveal
/// the deep metrics for that entry.
struct DayPlannerSection: View {
    let plans: [PlannedWorkout]
    let profile: UserProfile?
    let logs: [SetLog]
    let sessions: [WorkoutSession]
    let onStart: (PlannedWorkout) -> Void
    let onAdd: () -> Void
    let onDelete: (PlannedWorkout) -> Void
    let onToggleDone: (PlannedWorkout) -> Void
    let onReorder: ([PlannedWorkout]) -> Void

    /// Collapsed row height. Fixed on purpose: uniform rows make the drag maths
    /// exact, so a row never lands one slot away from where the finger is.
    private static let rowHeight: CGFloat = 78
    private static let spacing: CGFloat = 10
    private var pitch: CGFloat { Self.rowHeight + Self.spacing }

    @State private var order: [PlannedWorkout] = []
    @State private var draggingID: PersistentIdentifier?
    @State private var dragOffset: CGFloat = 0
    @State private var expandedID: PersistentIdentifier?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Today's Plan", trailing: order.isEmpty ? nil : progressCaption)
                Spacer()
                addButton
            }

            if order.isEmpty {
                emptyState
            } else {
                VStack(spacing: Self.spacing) {
                    ForEach(Array(order.enumerated()), id: \.element.id) { index, plan in
                        row(plan, index: index)
                    }
                }
                hint
            }
        }
        .onAppear { syncOrder() }
        .onChange(of: plans.map(\.id)) { _, _ in syncOrder() }
    }

    // MARK: Rows

    private func row(_ plan: PlannedWorkout, index: Int) -> some View {
        let isDragging = draggingID == plan.id
        let isExpanded = expandedID == plan.id

        return PlannerRow(
            plan: plan,
            metrics: metrics(for: plan),
            units: profile?.units ?? .metric,
            isExpanded: isExpanded,
            isDragging: isDragging,
            rowHeight: Self.rowHeight,
            onToggleExpand: {
                Haptics.tick()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    expandedID = isExpanded ? nil : plan.id
                }
            },
            onStart: { onStart(plan) },
            onToggleDone: { onToggleDone(plan) },
            onDelete: { onDelete(plan) },
            gripGesture: gripGesture(for: plan)
        )
        .offset(y: offset(for: plan, at: index))
        .scaleEffect(isDragging ? 1.03 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.55 : 0), radius: isDragging ? 18 : 0, y: isDragging ? 10 : 0)
        .zIndex(isDragging ? 1 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: draggingID)
    }

    private func offset(for plan: PlannedWorkout, at index: Int) -> CGFloat {
        draggingID == plan.id ? dragOffset : 0
    }

    /// Live reordering: as the dragged row passes a neighbour's midpoint the
    /// array is mutated and the drag baseline shifts, so the card stays glued
    /// to the finger while everything else springs into place.
    private func gripGesture(for plan: PlannedWorkout) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                if draggingID != plan.id {
                    draggingID = plan.id
                    dragOffset = 0
                    Haptics.thud()
                    // Uniform row heights are the contract the maths relies on.
                    if expandedID != nil {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { expandedID = nil }
                    }
                }

                dragOffset = value.translation.height

                guard let from = order.firstIndex(where: { $0.id == plan.id }) else { return }
                let shift = Int((dragOffset / pitch).rounded())
                let target = max(0, min(order.count - 1, from + shift))
                guard target != from else { return }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                    let moved = order.remove(at: from)
                    order.insert(moved, at: target)
                }
                dragOffset -= CGFloat(target - from) * pitch
                Haptics.tick()
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                    dragOffset = 0
                    draggingID = nil
                }
                onReorder(order)
                Haptics.tap()
            }
    }

    // MARK: Chrome

    private var addButton: some View {
        Button {
            Haptics.tap()
            onAdd()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .black))
                Text("ADD")
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

    private var emptyState: some View {
        Button {
            Haptics.tap()
            onAdd()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(LightBoltTheme.volt)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Schedule today")
                        .font(.fitTitle(16))
                        .foregroundStyle(LightBoltTheme.ink)
                    Text("Stack your sessions, then drag them into the order you'll actually do them.")
                        .font(.fitBody(12))
                        .foregroundStyle(LightBoltTheme.inkMuted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fitCard(radius: 18)
        }
        .buttonStyle(VoltPressStyle(scale: 0.98))
    }

    private var hint: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .black))
            Text("Drag the handle to reorder · tap a card to open its metrics")
                .font(.fitBody(10))
        }
        .foregroundStyle(LightBoltTheme.inkFaint)
    }

    private var progressCaption: String {
        let done = order.filter(\.isDone).count
        return "\(done)/\(order.count) done"
    }

    // MARK: Data

    private func syncOrder() {
        guard draggingID == nil else { return }
        order = plans.sorted { lhs, rhs in
            lhs.orderIndex == rhs.orderIndex ? lhs.createdAt < rhs.createdAt : lhs.orderIndex < rhs.orderIndex
        }
    }

    private func metrics(for plan: PlannedWorkout) -> WorkoutMetrics {
        let session = sessions.first { candidate in
            candidate.programID == plan.programID && DayKey.make(candidate.finishedAt) == plan.dayKey
        }
        return WorkoutMetricsEngine.metrics(for: plan, session: session, logs: logs, profile: profile)
    }
}

// MARK: - Row

private struct PlannerRow<Grip: Gesture>: View {
    let plan: PlannedWorkout
    let metrics: WorkoutMetrics
    let units: UnitSystem
    let isExpanded: Bool
    let isDragging: Bool
    let rowHeight: CGFloat
    let onToggleExpand: () -> Void
    let onStart: () -> Void
    let onToggleDone: () -> Void
    let onDelete: () -> Void
    let gripGesture: Grip

    var body: some View {
        VStack(spacing: 0) {
            head
            if isExpanded {
                details
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard(
            radius: 18,
            stroke: isDragging ? LightBoltTheme.volt : (isExpanded ? LightBoltTheme.voltDim : LightBoltTheme.hairline),
            fill: isDragging ? LightBoltTheme.charcoalHigh : LightBoltTheme.charcoal
        )
    }

    private var head: some View {
        HStack(spacing: 12) {
            // Grip: the only surface that starts a drag, so scrolling stays natural.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(isDragging ? LightBoltTheme.volt : LightBoltTheme.inkFaint)
                .frame(width: 34, height: rowHeight)
                .contentShape(.rect)
                .gesture(gripGesture)
                .accessibilityLabel("Reorder \(plan.title)")

            Button(action: onToggleDone) {
                Image(systemName: plan.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(plan.isDone ? LightBoltTheme.volt : LightBoltTheme.inkFaint)
            }
            .buttonStyle(VoltPressStyle(scale: 0.86))
            .accessibilityLabel(plan.isDone ? "Mark not done" : "Mark done")

            Button(action: onToggleExpand) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(plan.title.uppercased())
                            .font(.fitTitle(16))
                            .tracking(0.6)
                            .foregroundStyle(plan.isDone ? LightBoltTheme.inkMuted : LightBoltTheme.ink)
                            .strikethrough(plan.isDone, color: LightBoltTheme.inkFaint)
                            .lineLimit(1)
                        Text("\(plan.intervals) intervals · ~\(plan.estimatedMinutes) min · \(plan.focus)")
                            .font(.fitBody(11))
                            .foregroundStyle(LightBoltTheme.inkFaint)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(isExpanded ? LightBoltTheme.volt : LightBoltTheme.inkFaint)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(height: rowHeight)
                .contentShape(.rect)
            }
            .buttonStyle(VoltPressStyle(scale: 0.99))
        }
        .padding(.trailing, 14)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(LightBoltTheme.hairline)
                .frame(height: 1)

            HStack(spacing: 10) {
                metricTile(
                    value: metrics.workMinutesLabel,
                    unit: "min:sec",
                    label: metrics.isCompleted ? "Time worked" : "Time scheduled",
                    symbol: "stopwatch.fill"
                )
                metricTile(
                    value: "\(metrics.peakHeartRate)",
                    unit: "bpm",
                    label: "Peak HR · est.",
                    symbol: "heart.fill"
                )
            }

            HStack(spacing: 10) {
                metricTile(
                    value: "\(metrics.intervals)",
                    unit: "rounds",
                    label: metrics.isCompleted ? "Intervals done" : "Intervals planned",
                    symbol: "square.stack.3d.up.fill"
                )
                metricTile(
                    value: "\(metrics.durationMinutes)",
                    unit: "min",
                    label: metrics.isCompleted ? "Duration" : "Estimate",
                    symbol: "timer"
                )
            }

            HStack(spacing: 0) {
                inlineFact(
                    label: "Work rate",
                    value: String(format: "%.0f%% working", metrics.workDensity * 100)
                )
                Rectangle().fill(LightBoltTheme.hairline).frame(width: 1, height: 26)
                inlineFact(label: "Avg HR", value: "~\(metrics.averageHeartRate) bpm")
                Rectangle().fill(LightBoltTheme.hairline).frame(width: 1, height: 26)
                inlineFact(label: "Burn", value: "~\(metrics.activeCalories) kcal")
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LightBoltTheme.obsidian)
            )

            Text(metrics.isCompleted
                 ? "Measured from the session you ran. Heart rate is modelled from work density, duration and your age — not from a sensor."
                 : "Projected from your logged history. Finish the session to replace these with real numbers.")
                .font(.fitBody(10))
                .foregroundStyle(LightBoltTheme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    Haptics.thud()
                    onStart()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .black))
                        Text(plan.isDone ? "REPEAT" : "START")
                            .font(.fitLabel(12))
                            .tracking(1.4)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(LightBoltTheme.volt))
                }
                .buttonStyle(VoltPressStyle(scale: 0.96))

                Button {
                    Haptics.warning()
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(LightBoltTheme.alert)
                        .frame(width: 46, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(LightBoltTheme.alert.opacity(0.12))
                        )
                }
                .buttonStyle(VoltPressStyle(scale: 0.92))
                .accessibilityLabel("Remove from plan")
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, 2)
    }

    private func metricTile(value: String, unit: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(LightBoltTheme.voltDim)
                Text(label.uppercased())
                    .font(.fitLabel(8))
                    .tracking(1)
                    .foregroundStyle(LightBoltTheme.inkMuted)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.fitNumeric(21))
                    .voltWash()
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.fitLabel(9))
                    .foregroundStyle(LightBoltTheme.inkFaint)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LightBoltTheme.obsidian)
        )
    }

    private func inlineFact(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.fitBody(12))
                .foregroundStyle(LightBoltTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.fitLabel(8))
                .tracking(1)
                .foregroundStyle(LightBoltTheme.inkFaint)
        }
        .frame(maxWidth: .infinity)
    }

}

// MARK: - Add to plan

/// Picker for scheduling a workout: featured programmes for the user's profile
/// plus anything they built themselves.
struct PlannerPickerSheet: View {
    let programs: [Program]
    let builds: [Program]
    let onPick: (Program) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LightBoltTheme.backdrop

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        EyebrowText(text: "Add to today", color: LightBoltTheme.voltDim)
                        Text("SCHEDULE")
                            .font(.fitDisplay(40))
                            .tracking(-1.2)
                            .foregroundStyle(LightBoltTheme.ink)
                    }
                    .padding(.top, 8)

                    if !builds.isEmpty {
                        group(title: "Your Builds", items: builds)
                    }
                    group(title: "Featured", items: programs)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
    }

    private func group(title: String, items: [Program]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title)
            VStack(spacing: 10) {
                ForEach(items) { program in
                    Button {
                        Haptics.tap()
                        onPick(program)
                        dismiss()
                    } label: {
                        HStack(spacing: 13) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(LightBoltTheme.charcoalHigh)
                                    .frame(width: 42, height: 42)
                                Image(systemName: program.exercises.first?.symbol ?? "figure.run")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(LightBoltTheme.volt)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(program.title.uppercased())
                                    .font(.fitTitle(16))
                                    .tracking(0.6)
                                    .foregroundStyle(LightBoltTheme.ink)
                                    .lineLimit(1)
                                Text("\(program.totalRounds) intervals · ~\(program.estimatedMinutes) min")
                                    .font(.fitBody(11))
                                    .foregroundStyle(LightBoltTheme.inkMuted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(LightBoltTheme.volt)
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
}
