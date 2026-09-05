import StripePaymentSheet
import SwiftUI

/// Conversion gate: $19/month solo or $70/month for a five-person Family Plan.
/// LightBolt is premium-only — there is no free tier, so this screen blocks the
/// app until a subscription is active.
struct PaywallView: View {
    @Environment(Entitlements.self) private var entitlements
    @Environment(AccountService.self) private var account
    @State private var checkout = StripeCheckout()
    @State private var plan: LightBoltPlan = .individual
    @State private var showLegal = false
    @State private var pulse = false
    @State private var isStartingTestFamily = false
    @State private var testFamilyError: String?

    let onSubscribed: () -> Void

    private var perks: [(String, String)] {
        var list = basePerks
        if plan == .family {
            list.insert(
                (
                    "person.2.fill",
                    "Up to \(LightBoltPlan.familyTotalPeople) people — invite \(LightBoltPlan.familyMemberSeats) by username, one bill"
                ),
                at: 0
            )
        }
        return list
    }

    private let basePerks: [(String, String)] = [
        ("figure.run", "1,000+ timed home workouts — zero equipment, animated coaching"),
        ("flag.checkered", "1,000+ multi-day challenges — abs, fat loss, HIIT and more"),
        ("square.grid.3x1.below.line.grid.1x2", "Build your own timed circuits from the full move library"),
        ("camera.metering.matrix", "AI plate scanning — 3 food photos a day, full macros"),
        ("figure.stand", "360° body scan — 1 scan a day, measured on-device"),
        ("waveform", "Daily spoken briefing and habit streak engine")
    ]

    var body: some View {
        ZStack {
            LightBoltTheme.backdrop

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    priceBlock
                    planPicker
                    perkList
                    if case .failed(let message) = checkout.phase {
                        errorBanner(message)
                    }
                    Spacer(minLength: 18)
                }
                .padding(.horizontal, 22)
                .padding(.top, 46)
                .padding(.bottom, 220)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 0) {
                Spacer()
                actionDock
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .paymentSheet(
            isPresented: $checkout.isPresentingSheet,
            paymentSheet: checkout.paymentSheet ?? PaymentSheet(
                paymentIntentClientSecret: "pi_placeholder_secret_placeholder",
                configuration: PaymentSheet.Configuration()
            ),
            onCompletion: handleCompletion
        )
        .sheet(isPresented: $showLegal) { LegalCenterView() }
        .onAppear {
            StripeConfig.configure()
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    // MARK: Sections

    private var priceBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Rectangle().fill(LightBoltTheme.volt).frame(width: 4, height: 18)
                EyebrowText(text: "LightBolt Premium", color: LightBoltTheme.volt)
            }
            .padding(.bottom, 20)

            Text("THE WHOLE")
                .font(.fitDisplay(58))
                .tracking(-1.5)
                .foregroundStyle(LightBoltTheme.ink)
            Text("ARSENAL.")
                .font(.fitDisplay(58))
                .tracking(-1.5)
                .voltWash()

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(plan.priceLabel)
                    .font(.fitNumeric(34))
                    .foregroundStyle(LightBoltTheme.volt)
                    .contentTransition(.numericText())
                Text(plan == .family
                     ? "/ month for \(LightBoltPlan.familyTotalPeople) people"
                     : "/ month · cancel anytime")
                    .font(.fitBody(14))
                    .foregroundStyle(LightBoltTheme.inkMuted)
            }
            .padding(.top, 18)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: plan)

            ZStack(alignment: .leading) {
                Capsule().fill(LightBoltTheme.charcoalHigh).frame(height: 2)
                Capsule()
                    .fill(LightBoltTheme.volt)
                    .frame(width: pulse ? 180 : 40, height: 2)
            }
            .padding(.top, 22)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.55)
    }

    /// Solo vs Family. Family is the headline offer — five people for less than
    /// four solo seats.
    private var planPicker: some View {
        VStack(spacing: 10) {
            ForEach(LightBoltPlan.allCases) { option in
                Button {
                    guard plan != option else { return }
                    Haptics.tap()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { plan = option }
                } label: {
                    HStack(alignment: .top, spacing: 13) {
                        ZStack {
                            Circle()
                                .strokeBorder(plan == option ? LightBoltTheme.volt : LightBoltTheme.hairline, lineWidth: 1.6)
                                .frame(width: 22, height: 22)
                            if plan == option {
                                Circle()
                                    .fill(LightBoltTheme.volt)
                                    .frame(width: 12, height: 12)
                                    .transition(.scale)
                            }
                        }
                        .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(option.title.uppercased())
                                    .font(.fitTitle(17))
                                    .tracking(0.6)
                                    .foregroundStyle(LightBoltTheme.ink)
                                if option == .family {
                                    Text("SAVE \(LightBoltPlan.familyDiscountLabel)")
                                        .font(.fitLabel(9))
                                        .tracking(1.1)
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(LightBoltTheme.volt))
                                }
                            }
                            Text(option.blurb)
                                .font(.fitBody(12))
                                .foregroundStyle(LightBoltTheme.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .trailing, spacing: 1) {
                            Text(option.priceLabel)
                                .font(.fitNumeric(21))
                                .foregroundStyle(plan == option ? LightBoltTheme.volt : LightBoltTheme.ink)
                            Text("/mo")
                                .font(.fitLabel(9))
                                .tracking(1)
                                .foregroundStyle(LightBoltTheme.inkFaint)
                        }
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fitCard(
                        radius: 20,
                        stroke: plan == option ? LightBoltTheme.volt : LightBoltTheme.hairline,
                        fill: plan == option ? LightBoltTheme.charcoalHigh : LightBoltTheme.charcoal
                    )
                }
                .buttonStyle(VoltPressStyle(scale: 0.985))
            }

            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(LightBoltTheme.volt)
                Text("Family Plan works out \(LightBoltPlan.familyDiscountLabel) cheaper per person than paying individually.")
                    .font(.fitBody(11))
                    .foregroundStyle(LightBoltTheme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(.top, 28)
    }

    private var perkList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(perks.enumerated()), id: \.offset) { index, perk in
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: perk.0)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(LightBoltTheme.volt)
                        .frame(width: 26)
                    Text(perk.1)
                        .font(.fitBody(14))
                        .foregroundStyle(LightBoltTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 15)

                if index < perks.count - 1 {
                    Rectangle().fill(LightBoltTheme.hairline).frame(height: 1)
                }
            }
        }
        .padding(.top, 26)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(LightBoltTheme.alert)
            Text(message)
                .font(.fitBody(13))
                .foregroundStyle(LightBoltTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard(radius: 14, stroke: LightBoltTheme.alert.opacity(0.45), fill: LightBoltTheme.charcoal)
        .padding(.top, 22)
    }

    private var actionDock: some View {
        VStack(spacing: 14) {
            VoltButton(
                title: checkout.phase == .preparing
                    ? "Opening Checkout"
                    : (plan == .family ? "Start Family Plan — $70/mo" : "Start Premium — $19/mo"),
                systemImage: checkout.phase == .preparing ? nil : "bolt.fill",
                isBusy: checkout.phase == .preparing
            ) {
                Task {
                    await checkout.prepare(
                        existingCustomerId: entitlements.stripeCustomerId,
                        plan: plan,
                        accountId: account.accountId
                    )
                }
            }

            if Entitlements.isPaywallBypassedForTesting {
                testSkipButtons
            }

            Button {
                Haptics.tick()
                showLegal = true
            } label: {
                Text("Terms & Privacy")
                    .font(.fitBody(12))
                    .foregroundStyle(LightBoltTheme.inkFaint)
                    .underline()
            }
            .buttonStyle(VoltPressStyle())

            Text(plan == .family
                 ? "Billed $70.00 USD monthly through Stripe until cancelled. Covers you plus \(LightBoltPlan.familyMemberSeats) people you invite by username — \(LightBoltPlan.familyTotalPeople) in total. AI photo analysis is capped at 3 food photos and 1 body photo per day for every member."
                 : "Billed $19.00 USD monthly through Stripe until cancelled. AI photo analysis is capped at 3 food photos and 1 body photo per day for every member.")
                .font(.fitBody(11))
                .foregroundStyle(LightBoltTheme.inkFaint)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 30)
        .background(
            LinearGradient(
                colors: [LightBoltTheme.void.opacity(0), LightBoltTheme.void.opacity(0.92), LightBoltTheme.void],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    /// TEST MODE only. Two doors past the paywall: a plain solo unlock, and one
    /// that also makes this account a Family Plan owner on the server so the
    /// Family tab and the invitation flow can be exercised without paying.
    private var testSkipButtons: some View {
        VStack(spacing: 9) {
            Button {
                Haptics.success()
                entitlements.beginTestSession()
                onSubscribed()
            } label: {
                testSkipLabel(icon: "hammer.fill", title: "SKIP PAYMENT — SOLO", isBusy: false)
            }
            .buttonStyle(VoltPressStyle(scale: 0.98))
            .disabled(isStartingTestFamily)

            Button {
                startTestFamilyPlan()
            } label: {
                testSkipLabel(
                    icon: "person.2.fill",
                    title: isStartingTestFamily ? "STARTING FAMILY PLAN" : "SKIP PAYMENT — FAMILY PLAN",
                    isBusy: isStartingTestFamily
                )
            }
            .buttonStyle(VoltPressStyle(scale: 0.98))
            .disabled(isStartingTestFamily)

            if let testFamilyError {
                Text(testFamilyError)
                    .font(.fitBody(11))
                    .foregroundStyle(LightBoltTheme.alert)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeOut(duration: 0.22), value: isStartingTestFamily)
        .animation(.easeOut(duration: 0.22), value: testFamilyError)
    }

    private func testSkipLabel(icon: String, title: String, isBusy: Bool) -> some View {
        HStack(spacing: 8) {
            if isBusy {
                RunningWaveLoader(barCount: 3, height: 12)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
            }
            Text(title)
                .font(.fitLabel(11))
                .tracking(1.3)
        }
        .foregroundStyle(LightBoltTheme.volt)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(LightBoltTheme.voltDim, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
    }

    /// Grants the comp Family Plan server-side first — the Family tab only
    /// appears once the account really is an owner, so entering the app before
    /// the grant lands would show no tab.
    private func startTestFamilyPlan() {
        guard !isStartingTestFamily else { return }
        Haptics.tap()
        isStartingTestFamily = true
        testFamilyError = nil

        Task { @MainActor in
            defer { isStartingTestFamily = false }
            if let message = await account.activateTestFamilyPlan() {
                testFamilyError = message
                return
            }
            entitlements.beginTestSession()
            onSubscribed()
        }
    }

    private func handleCompletion(_ result: PaymentSheetResult) {
        let succeeded = checkout.handle(result: result)
        guard succeeded, let customerId = checkout.customerId else { return }
        entitlements.grantPremium(
            customerId: customerId,
            renewal: Calendar.current.date(byAdding: .month, value: 1, to: .now)
        )
        // Re-reads the plan from Stripe so the Family tab appears immediately
        // for a family purchase.
        Task { await account.refresh(customerId: customerId) }
        onSubscribed()
    }
}
