import PhotosUI
import SwiftData
import SwiftUI

/// Profile, subscription management, coach settings and data controls.
struct ProfileView: View {
    @Environment(Entitlements.self) private var entitlements
    @Environment(SpeechCoach.self) private var coach
    @Environment(FocusLock.self) private var focusLock
    @Environment(AuthManager.self) private var auth
    @Environment(AccountService.self) private var account
    @Environment(\.modelContext) private var context

    @Query private var profiles: [UserProfile]
    @Query private var meals: [MealEntry]
    @Query private var scans: [BodyScan]
    @Query private var setLogs: [SetLog]

    @State private var isShowingLegal = false
    @State private var isShowingPaywall = false
    @State private var isShowingFocus = false
    @State private var isManagingSubscription = false
    @State private var isShowingAccount = false
    @State private var isEditingUsername = false
    @State private var isShowingFeedback = false
    @State private var isConfirmingLeaveFamily = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var photoError: String?
    @State private var isConfirmingErase = false
    @State private var isEditingGoal = false
    @State private var isEditingStats = false
    @State private var draftAge: Double = 28
    @State private var draftHeight: Double = 175
    @State private var draftWeight: Double = 75
    @State private var didRecalculate = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                identityCard
                accountCard
                subscriptionCard
                if account.hasFamilySeat { familySeatCard }
                if let profile { identityBlock(profile) }
                focusBlock
                coachBlock
                dataBlock
                footer
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .background(LightBoltTheme.backdrop)
        .sheet(isPresented: $isShowingLegal) { LegalCenterView() }
        .fullScreenCover(isPresented: $isShowingFocus) { FocusCenterView() }
        .sheet(isPresented: $isManagingSubscription) {
            SubscriptionManagerView(onCancelled: { isShowingPaywall = true })
        }
        .sheet(isPresented: $isShowingAccount) { AccountView() }
        .sheet(isPresented: $isShowingFeedback) { FeedbackView(source: "profile") }
        .fullScreenCover(isPresented: $isEditingUsername) {
            UsernameSetupView(isEditing: true) { isEditingUsername = false }
        }
        .alert("Leave this family plan?", isPresented: $isConfirmingLeaveFamily) {
            Button("Stay", role: .cancel) {}
            Button("Leave", role: .destructive) {
                Task { _ = await account.leaveFamily() }
            }
        } message: {
            Text("You'll lose LightBolt access immediately and the seat goes back to \(account.membership?.ownerUsername ?? "the owner"). Your data stays on this device.")
        }
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            uploadPhoto(item)
        }
        .fullScreenCover(isPresented: $isShowingPaywall) {
            PaywallView(onSubscribed: { isShowingPaywall = false })
        }
        .sheet(isPresented: $isEditingGoal) { goalSheet }
        .sheet(isPresented: $isEditingStats) { statsSheet }
        .alert("Erase all local data?", isPresented: $isConfirmingErase) {
            Button("Cancel", role: .cancel) {}
            Button("Erase Everything", role: .destructive) { eraseAll() }
        } message: {
            Text("Every profile, meal, set, habit, weight entry and body scan will be permanently deleted from this device.")
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            EyebrowText(text: "Profile", color: LightBoltTheme.voltDim)
            Text("YOU")
                .font(.fitDisplay(52))
                .tracking(-1.6)
                .foregroundStyle(LightBoltTheme.ink)
        }
    }

    /// Public identity: profile picture and username, both editable here.
    private var identityCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 15) {
                ZStack(alignment: .bottomTrailing) {
                    if let user = account.directoryUser {
                        AvatarBubble(user: user, size: 76)
                    } else {
                        Circle()
                            .fill(LightBoltTheme.charcoalHigh)
                            .frame(width: 76, height: 76)
                    }

                    if isUploadingPhoto {
                        Circle()
                            .fill(.black.opacity(0.55))
                            .frame(width: 76, height: 76)
                            .overlay(RunningWaveLoader(barCount: 4, height: 18))
                    }

                    PhotosPicker(selection: $photoSelection, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.black)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(LightBoltTheme.volt))
                            .overlay(Circle().strokeBorder(LightBoltTheme.charcoal, lineWidth: 3))
                    }
                    .buttonStyle(VoltPressStyle(scale: 0.88))
                    .offset(x: 3, y: 3)
                    .accessibilityLabel("Change profile picture")
                }

                VStack(alignment: .leading, spacing: 4) {
                    EyebrowText(text: "Username", color: LightBoltTheme.voltDim)
                    Text(account.username ?? "—")
                        .font(.fitTitle(22))
                        .foregroundStyle(LightBoltTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if account.isFamilyOwner {
                        Text("Family Plan owner · \(account.seatsUsed + 1) of \(account.seatCapacity + 1)")
                            .font(.fitBody(11))
                            .foregroundStyle(LightBoltTheme.volt)
                    } else if let owner = account.membership?.ownerUsername {
                        Text("On \(owner)'s family plan")
                            .font(.fitBody(11))
                            .foregroundStyle(LightBoltTheme.volt)
                    } else {
                        Text("How people find you in LightBolt")
                            .font(.fitBody(11))
                            .foregroundStyle(LightBoltTheme.inkMuted)
                    }
                }

                Spacer(minLength: 0)
            }

            if let photoError {
                Text(photoError)
                    .font(.fitBody(11))
                    .foregroundStyle(LightBoltTheme.alert)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    isEditingUsername = true
                } label: {
                    identityAction("pencil", "Change username")
                }
                .buttonStyle(VoltPressStyle(scale: 0.97))

                if account.cachedHasAvatar {
                    Button {
                        Haptics.warning()
                        removePhoto()
                    } label: {
                        identityAction("trash", "Remove photo", isDestructive: true)
                    }
                    .buttonStyle(VoltPressStyle(scale: 0.97))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard(radius: 22, stroke: LightBoltTheme.voltDim, fill: LightBoltTheme.obsidian)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: account.cachedHasAvatar)
        .animation(.easeOut(duration: 0.2), value: photoError)
    }

    private func identityAction(_ symbol: String, _ title: String, isDestructive: Bool = false) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .black))
            Text(title.uppercased())
                .font(.fitLabel(10))
                .tracking(1.1)
                .lineLimit(1)
        }
        .foregroundStyle(isDestructive ? LightBoltTheme.alert : LightBoltTheme.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LightBoltTheme.charcoalHigh)
        )
    }

    /// Shown to members whose access comes from someone else's Family Plan.
    private var familySeatCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(LightBoltTheme.volt))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Family seat")
                        .font(.fitTitle(16))
                        .foregroundStyle(LightBoltTheme.ink)
                    Text("\(account.membership?.ownerUsername ?? "Someone") pays for your LightBolt.")
                        .font(.fitBody(11))
                        .foregroundStyle(LightBoltTheme.inkMuted)
                }
                Spacer(minLength: 0)
            }

            Button {
                Haptics.warning()
                isConfirmingLeaveFamily = true
            } label: {
                Text("LEAVE THIS PLAN")
                    .font(.fitLabel(10))
                    .tracking(1.3)
                    .foregroundStyle(LightBoltTheme.alert)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(LightBoltTheme.alert.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(VoltPressStyle(scale: 0.98))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard(radius: 22, stroke: LightBoltTheme.voltDim, fill: LightBoltTheme.obsidian)
    }

    private func uploadPhoto(_ item: PhotosPickerItem) {
        isUploadingPhoto = true
        photoError = nil
        Task { @MainActor in
            defer {
                isUploadingPhoto = false
                photoSelection = nil
            }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                photoError = "We couldn't read that image."
                Haptics.failure()
                return
            }
            photoError = await account.uploadAvatar(image)
        }
    }

    private func removePhoto() {
        isUploadingPhoto = true
        Task { @MainActor in
            defer { isUploadingPhoto = false }
            photoError = await account.removeAvatar()
        }
    }

    /// Account row: create an account or show who's signed in.
    private var accountCard: some View {
        Button {
            Haptics.tap()
            isShowingAccount = true
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    Circle().fill(auth.isSignedIn ? LightBoltTheme.volt : LightBoltTheme.charcoalHigh)
                    if let user = auth.user {
                        Text(user.initials)
                            .font(.fitDisplay(17))
                            .foregroundStyle(.black)
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(LightBoltTheme.inkMuted)
                    }
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.user?.displayName ?? "Create an account")
                        .font(.fitTitle(16))
                        .foregroundStyle(LightBoltTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(auth.user.map { $0.email.isEmpty ? "Signed in" : $0.email }
                         ?? "Keep your plan and progress across phones.")
                        .font(.fitBody(11))
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
            .fitCard(radius: 20, stroke: auth.isSignedIn ? LightBoltTheme.voltDim : LightBoltTheme.hairline)
        }
        .buttonStyle(VoltPressStyle(scale: 0.985))
    }

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    EyebrowText(
                        text: entitlements.isPremium ? "LightBolt Premium" : "Subscription required",
                        color: entitlements.isPremium ? .black.opacity(0.6) : LightBoltTheme.voltDim
                    )
                    Text(entitlements.isPremium ? "ACTIVE" : "INACTIVE")
                        .font(.fitDisplay(38))
                        .tracking(-0.5)
                        .foregroundStyle(entitlements.isPremium ? .black : LightBoltTheme.ink)
                }
                Spacer()
                Image(systemName: entitlements.isPremium ? "checkmark.seal.fill" : "lock.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(entitlements.isPremium ? .black : LightBoltTheme.volt)
            }

            if entitlements.isPremium {
                Text(entitlements.isCancellationPending
                     ? (entitlements.renewalDate.map { "Cancellation scheduled · access until \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Cancellation scheduled")
                     : (entitlements.renewalDate.map { "Renews \($0.formatted(date: .abbreviated, time: .omitted)) · $19.00 / month" } ?? "$19.00 billed monthly via Stripe"))
                    .font(.fitBody(13))
                    .foregroundStyle(.black.opacity(0.7))

                Button {
                    Haptics.tap()
                    isManagingSubscription = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 12, weight: .black))
                        Text("MANAGE SUBSCRIPTION")
                            .font(.fitLabel(11))
                            .tracking(1.4)
                    }
                    .foregroundStyle(LightBoltTheme.volt)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.black))
                }
                .buttonStyle(VoltPressStyle())
            } else {
                Text("LightBolt is premium-only. Subscribe to unlock the 1,000+ workout library, challenges, AI plate scanning and body scanning.")
                    .font(.fitBody(13))
                    .foregroundStyle(LightBoltTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                VoltButton(title: "Subscribe — $19/mo", systemImage: "bolt.fill") {
                    isShowingPaywall = true
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(entitlements.isPremium
                      ? AnyShapeStyle(LinearGradient(colors: [LightBoltTheme.volt, LightBoltTheme.voltSoft], startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(LightBoltTheme.charcoal))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(entitlements.isPremium ? .clear : LightBoltTheme.hairline, lineWidth: 1)
        )
    }

    private func identityBlock(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Calibration")

            VStack(spacing: 0) {
                infoRow("Objective", profile.goal.title) { isEditingGoal = true }
                divider
                infoRow("Intensity", profile.intensity.title) { isEditingGoal = true }
                divider
                infoRow("Age", "\(profile.age)") { beginEditingStats(profile) }
                divider
                infoRow("Height", String(format: "%.1f %@", LightBoltUnits.displayLength(cm: profile.heightCm, units: profile.units), profile.units.lengthUnit)) { beginEditingStats(profile) }
                divider
                infoRow("Weight", String(format: "%.1f %@", LightBoltUnits.displayWeight(kg: profile.weightKg, units: profile.units), profile.units.weightUnit)) { beginEditingStats(profile) }
                divider
                infoRow("Calorie budget", "\(profile.calorieBudget) kcal")
                divider
                infoRow("Macro split", "\(profile.proteinTarget)P · \(profile.carbTarget)C · \(profile.fatTarget)F")
            }
            .padding(.horizontal, 16)
            .fitCard()
        }
    }

    private func beginEditingStats(_ profile: UserProfile) {
        draftAge = Double(profile.age)
        draftHeight = LightBoltUnits.displayLength(cm: profile.heightCm, units: profile.units)
        draftWeight = LightBoltUnits.displayWeight(kg: profile.weightKg, units: profile.units)
        didRecalculate = false
        isEditingStats = true
    }

    /// Age / height / weight editor. Saving writes the profile and instantly
    /// recomputes the calorie budget and macro targets (they are derived values).
    private var statsSheet: some View {
        let units = profile?.units ?? .metric
        return NavigationStack {
            ZStack {
                LightBoltTheme.backdrop
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("YOUR NUMBERS")
                            .font(.fitDisplay(38))
                            .foregroundStyle(LightBoltTheme.ink)

                        MetricStepperField(
                            label: "Age",
                            value: $draftAge,
                            unit: "yrs",
                            range: 14...95,
                            step: 1,
                            decimals: 0
                        )

                        MetricStepperField(
                            label: "Height",
                            value: $draftHeight,
                            unit: units.lengthUnit,
                            range: units == .metric ? 120...230 : 47...90,
                            step: units == .metric ? 1 : 0.5,
                            decimals: units == .metric ? 0 : 1
                        )

                        MetricStepperField(
                            label: "Weight",
                            value: $draftWeight,
                            unit: units.weightUnit,
                            range: units == .metric ? 35...250 : 77...550,
                            step: units == .metric ? 0.5 : 1,
                            decimals: units == .metric ? 1 : 0
                        )

                        if didRecalculate, let profile {
                            VStack(alignment: .leading, spacing: 8) {
                                EyebrowText(text: "Recalculated", color: LightBoltTheme.voltDim)
                                Text("\(profile.calorieBudget) kcal · \(profile.proteinTarget)P · \(profile.carbTarget)C · \(profile.fatTarget)F")
                                    .font(.fitNumeric(20))
                                    .voltWash()
                                    .contentTransition(.numericText())
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fitCard(radius: 18, stroke: LightBoltTheme.voltDim)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }

                        VoltButton(title: "Save & Recalculate", systemImage: "bolt.fill") {
                            saveStats(units: units)
                        }
                        .padding(.top, 8)
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tick()
                        isEditingStats = false
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
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private func saveStats(units: UnitSystem) {
        guard let profile else { return }
        profile.age = Int(draftAge.rounded())
        profile.heightCm = units == .metric ? draftHeight : LightBoltUnits.cm(fromIn: draftHeight)
        profile.weightKg = units == .metric ? draftWeight : LightBoltUnits.kg(fromLb: draftWeight)
        profile.updatedAt = .now
        context.insert(WeightEntry(weightKg: profile.weightKg))
        try? context.save()
        Haptics.success()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { didRecalculate = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            isEditingStats = false
        }
    }

    /// Focus Lock: blocks the user's chosen games / social apps through Apple
    /// Screen Time until a real-world task is completed.
    private var focusBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Focus Lock")

            Button {
                Haptics.tap()
                isShowingFocus = true
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: focusStatusSymbol)
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(.black)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(LightBoltTheme.volt))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(focusStatusTitle)
                                .font(.fitTitle(16))
                                .foregroundStyle(LightBoltTheme.ink)
                            Text(focusStatusDetail)
                                .font(.fitBody(11))
                                .foregroundStyle(LightBoltTheme.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        if focusLock.isUnlocked {
                            Text(focusLock.remainingLabel)
                                .font(.fitNumeric(19))
                                .monospacedDigit()
                                .foregroundStyle(LightBoltTheme.volt)
                                .contentTransition(.numericText(countsDown: true))
                                .animation(.default, value: focusLock.remainingSeconds)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(LightBoltTheme.inkFaint)
                        }
                    }

                    Text("Blocks the games, social and video apps you choose — system-wide via Apple Screen Time. Easy task earns 15 min, Medium 30, Hard 60.")
                        .font(.fitBody(11))
                        .foregroundStyle(LightBoltTheme.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fitCard(stroke: focusLock.isEnabled ? LightBoltTheme.voltDim : LightBoltTheme.hairline)
            }
            .buttonStyle(VoltPressStyle(scale: 0.985))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: focusLock.isEnabled)
        }
    }

    private var focusStatusSymbol: String {
        if !focusLock.isEnabled { return "lock.open.fill" }
        return focusLock.isUnlocked ? "hourglass" : "lock.fill"
    }

    private var focusStatusTitle: String {
        if !focusLock.isEnabled { return "Set up Focus Lock" }
        return focusLock.isUnlocked ? "Session running" : "Apps blocked"
    }

    private var focusStatusDetail: String {
        guard focusLock.isEnabled else {
            return "Choose which apps to block and start earning your screen time."
        }
        if focusLock.isUnlocked { return "Your apps relock when the timer ends." }
        return "\(focusLock.screenTime.totalBlockedCount) blocked · finish a task to open them."
    }

    private var coachBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Spoken Coach")
            VStack(spacing: 14) {
                Toggle(isOn: Binding(
                    get: { entitlements.isCoachEnabled },
                    set: { newValue in
                        Haptics.tick()
                        entitlements.isCoachEnabled = newValue
                        if !newValue { coach.stop() }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Daily briefing")
                            .font(.fitBody(15))
                            .foregroundStyle(LightBoltTheme.ink)
                        Text("Reads your objectives aloud once a day.")
                            .font(.fitBody(11))
                            .foregroundStyle(LightBoltTheme.inkMuted)
                    }
                }
                .tint(LightBoltTheme.volt)
            }
            .padding(16)
            .fitCard()
        }
    }

    private var dataBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Your Data")

            HStack(spacing: 10) {
                countTile("\(meals.count)", "meals")
                countTile("\(setLogs.count)", "sets")
                countTile("\(scans.count)", "scans")
            }

            VStack(spacing: 0) {
                infoRow("Send feedback", "Rate & write") { isShowingFeedback = true }
                divider
                infoRow("Terms & Privacy", "View") { isShowingLegal = true }
                divider
                Button {
                    Haptics.warning()
                    isConfirmingErase = true
                } label: {
                    HStack {
                        Text("Erase all local data")
                            .font(.fitBody(15))
                            .foregroundStyle(LightBoltTheme.alert)
                        Spacer()
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(LightBoltTheme.alert)
                    }
                    .padding(.vertical, 16)
                }
                .buttonStyle(VoltPressStyle(scale: 0.99))
            }
            .padding(.horizontal, 16)
            .fitCard()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LightBolt stores your health data locally on this device. Meal photos are analysed and discarded — never sold, never shared.")
                .font(.fitBody(11))
                .foregroundStyle(LightBoltTheme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            EyebrowText(text: "LightBolt · version 1.0", color: LightBoltTheme.inkFaint)
        }
        .padding(.top, 4)
    }

    private var divider: some View {
        Rectangle().fill(LightBoltTheme.hairline).frame(height: 1)
    }

    private func infoRow(_ label: String, _ value: String, action: (() -> Void)? = nil) -> some View {
        Button {
            guard let action else { return }
            Haptics.tick()
            action()
        } label: {
            HStack {
                Text(label)
                    .font(.fitBody(15))
                    .foregroundStyle(LightBoltTheme.ink)
                Spacer()
                Text(value)
                    .font(.fitBody(14))
                    .foregroundStyle(LightBoltTheme.inkMuted)
                    .lineLimit(1)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(LightBoltTheme.inkFaint)
                }
            }
            .padding(.vertical, 16)
        }
        .buttonStyle(VoltPressStyle(scale: 0.995))
        .disabled(action == nil)
    }

    private func countTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.fitNumeric(22))
                .foregroundStyle(LightBoltTheme.volt)
            EyebrowText(text: label, color: LightBoltTheme.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .fitCard(radius: 16)
    }

    // MARK: Goal editing

    private var goalSheet: some View {
        NavigationStack {
            ZStack {
                LightBoltTheme.backdrop
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("RECALIBRATE")
                            .font(.fitDisplay(38))
                            .foregroundStyle(LightBoltTheme.ink)

                        EyebrowText(text: "Objective")
                        VStack(spacing: 10) {
                            ForEach(LightBoltGoal.allCases) { option in
                                optionRow(
                                    title: option.title,
                                    symbol: option.symbol,
                                    isSelected: profile?.goal == option
                                ) {
                                    profile?.goalRaw = option.rawValue
                                    profile?.updatedAt = .now
                                    Haptics.success()
                                }
                            }
                        }

                        EyebrowText(text: "Intensity")
                        VStack(spacing: 10) {
                            ForEach(TrainingIntensity.allCases) { option in
                                optionRow(
                                    title: option.title,
                                    symbol: option.symbol,
                                    isSelected: profile?.intensity == option
                                ) {
                                    profile?.equipmentRaw = option.rawValue
                                    profile?.updatedAt = .now
                                    Haptics.success()
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tick()
                        isEditingGoal = false
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
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private func optionRow(title: String, symbol: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { action() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isSelected ? .black : LightBoltTheme.inkMuted)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(isSelected ? LightBoltTheme.volt : LightBoltTheme.charcoalHigh)
                    )
                Text(title)
                    .font(.fitBody(15))
                    .foregroundStyle(LightBoltTheme.ink)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(LightBoltTheme.volt)
                }
            }
            .padding(13)
            .fitCard(radius: 16, stroke: isSelected ? LightBoltTheme.voltDim : LightBoltTheme.hairline)
        }
        .buttonStyle(VoltPressStyle(scale: 0.98))
    }

    private func eraseAll() {
        do {
            try context.delete(model: MealEntry.self)
            try context.delete(model: BodyScan.self)
            try context.delete(model: SetLog.self)
            try context.delete(model: WorkoutSession.self)
            try context.delete(model: Habit.self)
            try context.delete(model: WeightEntry.self)
            try context.delete(model: UserProfile.self)
            try context.save()
            entitlements.hasCompletedOnboarding = false
            Haptics.success()
        } catch {
            Haptics.failure()
        }
    }
}
