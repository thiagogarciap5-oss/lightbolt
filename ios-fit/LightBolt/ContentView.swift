import SwiftData
import SwiftUI

/// Root router: account first, then calibration, then the paywall, then the
/// tab shell. A waiting family invitation interrupts everything on open.
struct ContentView: View {
    @Environment(Entitlements.self) private var entitlements
    @Environment(FocusLock.self) private var focusLock
    @Environment(AccountService.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [UserProfile]

    @State private var selection: LightBoltTab = .today
    @State private var isShowingFeedback = false
    @State private var justJoinedOwner: String?
    @State private var isPrepPaywall = false

    private var needsAccount: Bool { !account.hasUsername }

    private var needsOnboarding: Bool {
        profiles.isEmpty || !entitlements.hasCompletedOnboarding
    }

    /// The Family tab belongs to the billing owner of an active Family Plan.
    private var tabs: [LightBoltTab] {
        account.isFamilyOwner ? LightBoltTab.withFamily : LightBoltTab.standard
    }

    var body: some View {
        ZStack {
            LightBoltTheme.void.ignoresSafeArea()

            if isPrepPaywall {
                // Prep lane: payment first, everything else after.
                PaywallView(onSubscribed: { isPrepPaywall = false })
                    .transition(.opacity)
            } else if needsAccount {
                // Absolute step zero: a username and password before the
                // calibration survey and long before any mention of money.
                // The prep shortcut fast-forwards straight to the paywall.
                AccountSetupView {
                    account.prepareLocalAccount()
                    entitlements.hasCompletedOnboarding = true
                    isPrepPaywall = true
                }
                .transition(.opacity)
            } else if needsOnboarding {
                OnboardingFlow()
                    .transition(.opacity)
            } else if !entitlements.isPremium {
                // Premium-only: no free tier. The app stays behind the paywall
                // until a subscription — or a family seat — is active.
                PaywallView(onSubscribed: {})
                    .transition(.opacity)
            } else {
                mainShell
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: needsAccount)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: needsOnboarding)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: entitlements.isPremium)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: isPrepPaywall)
        .fullScreenCover(item: Binding(
            get: { needsAccount ? nil : account.pendingInvite },
            set: { if $0 == nil { account.pendingInvite = nil } }
        )) { invite in
            FamilyInviteModal(invite: invite) { accepted in
                account.pendingInvite = nil
                if accepted {
                    justJoinedOwner = invite.ownerUsername
                    selection = .today
                } else {
                    // Declining frees the seat immediately; ask why, gently.
                    isShowingFeedback = true
                }
            }
            .environment(account)
        }
        .sheet(isPresented: $isShowingFeedback) {
            FeedbackView(
                source: "invite_declined",
                prompt: "You turned down a family plan invitation. If something about LightBolt put you off, we'd genuinely like to know."
            )
        }
        .onChange(of: scenePhase) { _, phase in
            // Re-check the wall clock immediately on foreground so a reward
            // window that expired while backgrounded re-shields right away,
            // and pick up any invitation sent while we were away.
            if phase == .active {
                focusLock.resync()
                Task { await account.refresh(customerId: entitlements.stripeCustomerId) }
            }
        }
        .onChange(of: account.isFamilyOwner) { _, isOwner in
            if !isOwner, selection == .family { selection = .profile }
        }
        .task {
            Haptics.prepare()
            account.attach(entitlements)
            await entitlements.refreshSubscription()
            await account.refresh(customerId: entitlements.stripeCustomerId)
        }
    }

    private var mainShell: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selection {
                case .today: TodayView()
                case .nutrition: NutritionView()
                case .body: BodyView()
                case .train: TrainingView()
                case .family: FamilyView()
                case .profile: ProfileView()
                }
            }
            .safeAreaPadding(.top, 8)

            LightBoltTabBar(selection: $selection, tabs: tabs)
                .padding(.bottom, 6)

            if let owner = justJoinedOwner {
                JoinedFamilyToast(owner: owner) { justJoinedOwner = nil }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

/// Confirmation that a family seat just unlocked the app, shown once.
private struct JoinedFamilyToast: View {
    let owner: String
    let onDone: () -> Void

    @State private var isVisible = false

    var body: some View {
        VStack {
            HStack(spacing: 11) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(LightBoltTheme.volt))
                VStack(alignment: .leading, spacing: 1) {
                    Text("You're in")
                        .font(.fitTitle(15))
                        .foregroundStyle(LightBoltTheme.ink)
                    Text("\(owner)'s family plan unlocked everything.")
                        .font(.fitBody(11))
                        .foregroundStyle(LightBoltTheme.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fitCard(radius: 18, stroke: LightBoltTheme.voltDim, fill: LightBoltTheme.obsidian)
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .offset(y: isVisible ? 0 : -110)
            .opacity(isVisible ? 1 : 0)

            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { isVisible = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3.4))
                withAnimation(.easeIn(duration: 0.28)) { isVisible = false }
                try? await Task.sleep(for: .milliseconds(300))
                onDone()
            }
        }
    }
}
