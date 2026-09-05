import StripePaymentSheet
import SwiftUI

/// Real subscription management: see the card on file, swap it for another one,
/// or cancel the plan outright. Cancelling stops billing at Stripe immediately
/// and drops the app back to the paywall.
struct SubscriptionManagerView: View {
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    /// Called after a successful cancellation so the parent can send the user
    /// back to the paywall.
    let onCancelled: () -> Void

    @State private var checkout = StripeCheckout()
    @State private var isConfirmingCancel = false
    @State private var isCancelling = false
    @State private var isLoadingCard = true
    @State private var banner: Banner?

    private struct Banner: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LightBoltTheme.backdrop

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        planCard
                        cardBlock
                        if let banner { bannerView(banner) }
                        dangerBlock
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
        .paymentSheet(
            isPresented: Binding(
                get: { checkout.isPresentingSheet && checkout.paymentSheet != nil },
                set: { checkout.isPresentingSheet = $0 }
            ),
            paymentSheet: checkout.paymentSheet ?? PaymentSheet(
                setupIntentClientSecret: "seti_placeholder_secret_placeholder",
                configuration: PaymentSheet.Configuration()
            ),
            onCompletion: handleSheet
        )
        .alert("Cancel your plan?", isPresented: $isConfirmingCancel) {
            Button("Keep my plan", role: .cancel) {}
            Button("Yes, cancel", role: .destructive) { cancelPlan() }
        } message: {
            Text("Billing stops right now and you won't be charged again. You'll lose the workout vault, plate scanning and body scanning straight away, and go back to the subscribe screen.")
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: banner)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isLoadingCard)
        .task {
            await entitlements.refreshCard()
            isLoadingCard = false
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            EyebrowText(text: "Billing", color: LightBoltTheme.voltDim)
            Text("MANAGE\nPLAN")
                .font(.fitDisplay(56))
                .tracking(-1.8)
                .lineSpacing(-8)
                .foregroundStyle(LightBoltTheme.ink)
        }
        .padding(.top, 6)
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    EyebrowText(text: "LightBolt Premium", color: .black.opacity(0.6))
                    Text("$19 / MONTH")
                        .font(.fitDisplay(32))
                        .tracking(-0.5)
                        .foregroundStyle(.black)
                }
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.black)
            }
            Text(entitlements.renewalDate.map { "Renews \($0.formatted(date: .abbreviated, time: .omitted))" }
                 ?? "Billed monthly via Stripe")
                .font(.fitBody(13))
                .foregroundStyle(.black.opacity(0.7))
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

    private var cardBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Payment Method")

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(LightBoltTheme.volt))

                    if isLoadingCard {
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBlock(width: 140, height: 16, radius: 5)
                            SkeletonBlock(width: 90, height: 12, radius: 4)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entitlements.card?.displayLabel ?? "No card on file")
                                .font(.fitTitle(17))
                                .foregroundStyle(LightBoltTheme.ink)
                            if let expiry = entitlements.card?.expiryLabel {
                                Text(expiry)
                                    .font(.fitBody(12))
                                    .foregroundStyle(LightBoltTheme.inkMuted)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                VoltButton(
                    title: checkout.phase == .preparing ? "Opening…" : "Change card",
                    systemImage: "arrow.left.arrow.right",
                    isEnabled: checkout.phase != .preparing && entitlements.stripeCustomerId != nil
                ) {
                    Haptics.tap()
                    beginCardUpdate()
                }

                if entitlements.stripeCustomerId == nil {
                    Text("No Stripe customer is linked to this device yet — subscribe first to add a card.")
                        .font(.fitBody(11))
                        .foregroundStyle(LightBoltTheme.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Your new card replaces the old one and is billed from the next renewal. Card details go straight to Stripe — LightBolt never stores them.")
                        .font(.fitBody(11))
                        .foregroundStyle(LightBoltTheme.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fitCard(radius: 20)
        }
    }

    private var dangerBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Cancel")

            VStack(alignment: .leading, spacing: 14) {
                Text("Cancelling stops all future charges immediately and returns you to the subscribe screen. You can resubscribe at any time.")
                    .font(.fitBody(13))
                    .foregroundStyle(LightBoltTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Haptics.warning()
                    isConfirmingCancel = true
                } label: {
                    HStack(spacing: 8) {
                        if isCancelling {
                            RunningWaveLoader(barCount: 4, height: 14, tint: LightBoltTheme.alert)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13, weight: .black))
                        }
                        Text(isCancelling ? "CANCELLING…" : "CANCEL MY PLAN")
                            .font(.fitLabel(12))
                            .tracking(1.4)
                    }
                    .foregroundStyle(LightBoltTheme.alert)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LightBoltTheme.charcoalHigh)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(LightBoltTheme.alert.opacity(0.45), lineWidth: 1)
                    )
                }
                .buttonStyle(VoltPressStyle(scale: 0.98))
                .disabled(isCancelling)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fitCard(radius: 20)
        }
    }

    private func bannerView(_ banner: Banner) -> some View {
        HStack(spacing: 10) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(banner.isError ? LightBoltTheme.alert : LightBoltTheme.volt)
            Text(banner.text)
                .font(.fitBody(12))
                .foregroundStyle(LightBoltTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard(radius: 16, stroke: banner.isError ? LightBoltTheme.alert.opacity(0.4) : LightBoltTheme.voltDim)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var footer: some View {
        Text("Payments are processed by Stripe. Questions about billing: thiagogarciapimentel0111@gmail.com")
            .font(.fitBody(10))
            .foregroundStyle(LightBoltTheme.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Actions

    private func beginCardUpdate() {
        guard let customerId = entitlements.stripeCustomerId else { return }
        banner = nil
        Task { await checkout.prepareCardUpdate(customerId: customerId) }
    }

    private func handleSheet(_ result: PaymentSheetResult) {
        checkout.isPresentingSheet = false
        switch result {
        case .completed:
            guard let customerId = entitlements.stripeCustomerId else { return }
            Task {
                let card = await checkout.confirmCardUpdate(customerId: customerId)
                await entitlements.refreshCard()
                banner = card == nil
                    ? Banner(text: "Card saved, but we couldn't make it the default. Try again.", isError: true)
                    : Banner(text: "Card updated. Future renewals bill \(entitlements.card?.displayLabel ?? "your new card").", isError: false)
                checkout.reset()
            }
        case .canceled:
            checkout.reset()
        case .failed(let error):
            banner = Banner(text: error.localizedDescription, isError: true)
            Haptics.failure()
            checkout.reset()
        }
    }

    private func cancelPlan() {
        guard !isCancelling else { return }
        isCancelling = true
        banner = nil
        Task {
            do {
                try await entitlements.cancelSubscriptionNow()
                Haptics.success()
                isCancelling = false
                dismiss()
                onCancelled()
            } catch {
                isCancelling = false
                banner = Banner(
                    text: (error as? LocalizedError)?.errorDescription ?? "We couldn't cancel right now. Please try again.",
                    isError: true
                )
                Haptics.failure()
            }
        }
    }
}
