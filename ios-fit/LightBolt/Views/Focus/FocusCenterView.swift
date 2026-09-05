import FamilyControls
import SwiftUI

/// Focus Lock control room. This is where the user grants Apple's Screen Time
/// permission, picks which apps get blocked, and earns time back by completing
/// a real-world task.
struct FocusCenterView: View {
    @Environment(FocusLock.self) private var focusLock
    @Environment(\.dismiss) private var dismiss

    @State private var isPickingApps = false
    @State private var draftSelection = FamilyActivitySelection()
    @State private var isConfirmingComplete = false
    @State private var appeared = false
    @State private var chosenTier: FocusDifficulty = .medium

    private var screenTime: ScreenTimeService { focusLock.screenTime }

    var body: some View {
        NavigationStack {
            ZStack {
                LightBoltTheme.backdrop

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        permissionBlock

                        if screenTime.access.isApproved {
                            selectionBlock
                            if focusLock.isEnabled {
                                statusBlock
                                if focusLock.isUnlocked {
                                    activeSessionBlock
                                } else {
                                    tierPicker
                                    taskBlock
                                }
                            } else {
                                armBlock
                            }
                        }

                        statsBlock
                        footer
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tick()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(LightBoltTheme.ink)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(LightBoltTheme.charcoal))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .familyActivityPicker(isPresented: $isPickingApps, selection: $draftSelection)
        .onChange(of: isPickingApps) { _, isOpen in
            if !isOpen {
                screenTime.update(selection: draftSelection, isLocking: focusLock.isShielding)
                Haptics.success()
            }
        }
        .alert("Task done?", isPresented: $isConfirmingComplete) {
            Button("Not yet", role: .cancel) {}
            Button("I completed it") {
                Haptics.thud()
                focusLock.completeCurrentTask()
            }
        } message: {
            if let task = focusLock.currentTask {
                Text("Confirm you finished \"\(task.taskDescription)\". Your blocked apps open for \(task.unlockMinutes) minutes.")
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: focusLock.currentTask)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: focusLock.isEnabled)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: focusLock.isUnlocked)
        .animation(.easeOut(duration: 0.25), value: screenTime.access)
        .task {
            appeared = true
            draftSelection = screenTime.selection
            screenTime.refreshAccess()
            if focusLock.currentTask == nil && !focusLock.isUnlocked {
                focusLock.drawTask(chosenTier)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: focusLock.isUnlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(LightBoltTheme.volt))
                EyebrowText(text: "Block the apps that steal your day", color: LightBoltTheme.voltDim)
            }

            Text("FOCUS\nLOCK")
                .font(.fitDisplay(70))
                .tracking(-2)
                .lineSpacing(-8)
                .foregroundStyle(LightBoltTheme.ink)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: appeared)

            Text("Pick the games, social and video apps you lose hours to. LightBolt shields them at system level until you finish one real-world task.")
                .font(.fitBody(14))
                .foregroundStyle(LightBoltTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    // MARK: Permission

    @ViewBuilder
    private var permissionBlock: some View {
        switch screenTime.access {
        case .approved:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(LightBoltTheme.volt)
                Text("Screen Time access granted")
                    .font(.fitBody(13))
                    .foregroundStyle(LightBoltTheme.ink)
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fitCard(radius: 16, stroke: LightBoltTheme.voltDim)

        case .notDetermined:
            permissionCard(
                symbol: "hourglass",
                title: "ALLOW SCREEN TIME",
                body: "LightBolt needs Apple's Screen Time permission to shield other apps. Tapping below opens the real iOS prompt — nothing is blocked until you approve it and choose your apps.",
                action: "Ask iOS for permission"
            ) {
                Task { await screenTime.requestAuthorization() }
            }

        case .denied:
            permissionCard(
                symbol: "xmark.shield.fill",
                title: "PERMISSION DENIED",
                body: "Screen Time access was turned down. Open Settings → Screen Time → Apps With Screen Time Access and switch LightBolt on, then come back.",
                action: "Open Settings"
            ) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }

        case .unavailable(let message):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(LightBoltTheme.alert)
                    EyebrowText(text: "Not available here", color: LightBoltTheme.alert)
                }
                Text(message)
                    .font(.fitBody(12))
                    .foregroundStyle(LightBoltTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                GhostButton(title: "Try again", systemImage: "arrow.clockwise") {
                    Haptics.tick()
                    Task { await screenTime.requestAuthorization() }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fitCard(radius: 18)
        }
    }

    private func permissionCard(
        symbol: String,
        title: String,
        body: String,
        action: String,
        perform: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(LightBoltTheme.volt))
                Text(title)
                    .font(.fitTitle(19))
                    .tracking(0.4)
                    .foregroundStyle(LightBoltTheme.ink)
            }
            Text(body)
                .font(.fitBody(13))
                .foregroundStyle(LightBoltTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            VoltButton(
                title: screenTime.isRequesting ? "Waiting for iOS…" : action,
                systemImage: "shield.lefthalf.filled",
                isEnabled: !screenTime.isRequesting
            ) {
                Haptics.tap()
                perform()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard(radius: 22, stroke: LightBoltTheme.voltDim, fill: LightBoltTheme.obsidian)
    }

    // MARK: App selection

    private var selectionBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Apps To Lock")

            Button {
                Haptics.tap()
                draftSelection = screenTime.selection
                isPickingApps = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(screenTime.hasSelection ? LightBoltTheme.volt : LightBoltTheme.charcoalHigh)
                        Image(systemName: screenTime.hasSelection ? "square.grid.2x2.fill" : "plus")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(screenTime.hasSelection ? .black : LightBoltTheme.inkMuted)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(screenTime.hasSelection ? "\(screenTime.totalBlockedCount) selected" : "Choose apps & categories")
                            .font(.fitTitle(17))
                            .foregroundStyle(LightBoltTheme.ink)
                        Text(screenTime.selectionSummary)
                            .font(.fitBody(12))
                            .foregroundStyle(LightBoltTheme.inkMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(LightBoltTheme.inkFaint)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fitCard(radius: 20, stroke: screenTime.hasSelection ? LightBoltTheme.voltDim : LightBoltTheme.hairline)
            }
            .buttonStyle(VoltPressStyle(scale: 0.98))

            Text("Apple keeps your app choices private — LightBolt receives anonymous tokens, never the list of what you use.")
                .font(.fitBody(10))
                .foregroundStyle(LightBoltTheme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Arm / status

    private var armBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            VoltButton(
                title: "Arm Focus Lock",
                systemImage: "bolt.fill",
                isEnabled: screenTime.hasSelection
            ) {
                Haptics.thud()
                focusLock.enable()
            }
            if !screenTime.hasSelection {
                Text("Pick at least one app or category first.")
                    .font(.fitBody(11))
                    .foregroundStyle(LightBoltTheme.inkFaint)
            }
        }
    }

    private var statusBlock: some View {
        HStack(spacing: 12) {
            Image(systemName: focusLock.isUnlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(.black)
                .frame(width: 32, height: 32)
                .background(Circle().fill(LightBoltTheme.volt))
            VStack(alignment: .leading, spacing: 2) {
                Text(focusLock.isUnlocked ? "Session running" : "Your apps are blocked")
                    .font(.fitTitle(16))
                    .foregroundStyle(LightBoltTheme.ink)
                Text(focusLock.isUnlocked
                     ? "They relock automatically when the timer ends."
                     : "\(screenTime.totalBlockedCount) blocked · finish a task to open them.")
                    .font(.fitBody(11))
                    .foregroundStyle(LightBoltTheme.inkMuted)
            }
            Spacer(minLength: 0)
            Button {
                Haptics.tick()
                focusLock.disable()
            } label: {
                Text("OFF")
                    .font(.fitLabel(11))
                    .tracking(1.4)
                    .foregroundStyle(LightBoltTheme.inkMuted)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(LightBoltTheme.charcoalHigh))
            }
            .buttonStyle(VoltPressStyle(scale: 0.92))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard(radius: 20, stroke: LightBoltTheme.voltDim)
    }

    private var activeSessionBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            EyebrowText(text: "Time remaining", color: .black.opacity(0.6))
            Text(focusLock.remainingLabel)
                .font(.fitNumeric(64))
                .monospacedDigit()
                .foregroundStyle(.black)
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: focusLock.remainingSeconds)
            Button {
                Haptics.warning()
                focusLock.endSessionEarly()
            } label: {
                Text("LOCK THEM NOW")
                    .font(.fitLabel(11))
                    .tracking(1.4)
                    .foregroundStyle(LightBoltTheme.volt)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.black))
            }
            .buttonStyle(VoltPressStyle())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(
                    colors: [LightBoltTheme.volt, LightBoltTheme.voltSoft],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
    }

    // MARK: Tier picker + task

    private var tierPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Pick Your Price")
            HStack(spacing: 8) {
                ForEach(FocusDifficulty.allCases) { tier in
                    Button {
                        Haptics.tick()
                        chosenTier = tier
                        focusLock.drawTask(tier)
                    } label: {
                        VStack(spacing: 5) {
                            Text("+\(tier.unlockMinutes)")
                                .font(.fitNumeric(24))
                                .foregroundStyle(chosenTier == tier ? .black : LightBoltTheme.ink)
                            Text("MIN")
                                .font(.fitLabel(9))
                                .tracking(1.4)
                                .foregroundStyle(chosenTier == tier ? .black.opacity(0.6) : LightBoltTheme.inkFaint)
                            Text(tier.rawValue.uppercased())
                                .font(.fitLabel(10))
                                .tracking(1.2)
                                .foregroundStyle(chosenTier == tier ? .black : LightBoltTheme.inkMuted)
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(chosenTier == tier ? LightBoltTheme.volt : LightBoltTheme.charcoal)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(chosenTier == tier ? .clear : LightBoltTheme.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(VoltPressStyle(scale: 0.96))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.78), value: chosenTier)
        }
    }

    @ViewBuilder
    private var taskBlock: some View {
        if let task = focusLock.currentTask {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        difficultyChip(task.difficulty)
                        Spacer()
                        HStack(spacing: 5) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 11, weight: .black))
                            Text("+\(task.unlockMinutes) MIN")
                                .font(.fitLabel(12))
                                .tracking(1.4)
                        }
                        .foregroundStyle(LightBoltTheme.volt)
                    }

                    Text(task.taskDescription)
                        .font(.fitTitle(27))
                        .tracking(-0.3)
                        .foregroundStyle(LightBoltTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Image(systemName: "externaldrive.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Vault #\(String(format: "%05d", task.vaultIndex + 1)) of \(FocusLock.vaultSize.formatted()) · offline")
                            .font(.fitBody(11))
                    }
                    .foregroundStyle(LightBoltTheme.inkFaint)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fitCard(radius: 26, stroke: LightBoltTheme.voltDim, fill: LightBoltTheme.obsidian)
                .id(task.taskDescription)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                VoltButton(
                    title: "I did it — unlock \(task.unlockMinutes) min",
                    systemImage: "bolt.fill"
                ) {
                    Haptics.tap()
                    isConfirmingComplete = true
                }

                GhostButton(title: "Swap this task", systemImage: "arrow.triangle.2.circlepath") {
                    Haptics.tick()
                    focusLock.drawTask(task.difficulty)
                }
            }
        }
    }

    private func difficultyChip(_ tier: FocusDifficulty) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index < tier.weight ? LightBoltTheme.volt : LightBoltTheme.charcoalHigh)
                    .frame(width: 14, height: 5)
            }
            Text(tier.rawValue.uppercased())
                .font(.fitLabel(11))
                .tracking(1.8)
                .foregroundStyle(LightBoltTheme.ink)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(LightBoltTheme.charcoal))
        .overlay(Capsule().strokeBorder(LightBoltTheme.hairline, lineWidth: 1))
    }

    // MARK: Stats + footer

    private var statsBlock: some View {
        HStack(spacing: 10) {
            statTile("\(focusLock.completedTaskCount)", "tasks done")
            statTile("\(focusLock.lifetimeEarnedMinutes)", "min earned")
            statTile(FocusTaskVault.total.formatted(), "in vault")
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.fitNumeric(20))
                .foregroundStyle(LightBoltTheme.volt)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            EyebrowText(text: label, color: LightBoltTheme.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .fitCard(radius: 16)
    }

    private var footer: some View {
        Text("Focus Lock uses Apple Screen Time. LightBolt never sees which apps you use or for how long — iOS handles the blocking and hands back anonymous tokens only. Real device blocking requires Apple's Family Controls approval on the signed build.")
            .font(.fitBody(10))
            .foregroundStyle(LightBoltTheme.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
    }
}
