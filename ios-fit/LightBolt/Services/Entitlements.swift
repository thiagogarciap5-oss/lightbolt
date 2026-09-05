import Foundation
import Observation

nonisolated enum AccessTier: String, Codable, Sendable {
    case locked
    case premium
}

/// Owns onboarding completion, the Stripe customer identity and the access tier.
/// Persisted in `UserDefaults` (no secrets — the Stripe customer id is a public
/// reference, the secret key never leaves the server).
@Observable
final class Entitlements {
    /// TEST MODE — set to `false` before shipping.
    ///
    /// While true the paywall no longer gates the app so the full experience can
    /// be exercised without a live Stripe subscription. Billing code paths are
    /// untouched; only the gate is bypassed. The hard daily AI scan caps are
    /// enforced on the server and are NOT affected by this flag.
    static let isPaywallBypassedForTesting = true

    private enum Key {
        static let onboarded = "fit.onboarded.v1"
        static let tier = "fit.tier.v1"
        static let customer = "fit.stripeCustomerId.v1"
        static let renewal = "fit.renewalTimestamp.v1"
        static let coachSpokenDay = "fit.coachSpokenDay.v1"
        static let coachEnabled = "fit.coachEnabled.v1"
        static let familySeatOwner = "fit.familySeatOwner.v1"
    }

    private let defaults: UserDefaults

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboarded) }
    }

    var tier: AccessTier {
        didSet { defaults.set(tier.rawValue, forKey: Key.tier) }
    }

    var stripeCustomerId: String? {
        didSet { defaults.set(stripeCustomerId, forKey: Key.customer) }
    }

    var renewalDate: Date? {
        didSet { defaults.set(renewalDate?.timeIntervalSince1970 ?? 0, forKey: Key.renewal) }
    }

    var isCoachEnabled: Bool {
        didSet { defaults.set(isCoachEnabled, forKey: Key.coachEnabled) }
    }

    var isVerifying: Bool = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarded)
        tier = AccessTier(rawValue: defaults.string(forKey: Key.tier) ?? "") ?? .locked
        stripeCustomerId = defaults.string(forKey: Key.customer)
        let stamp = defaults.double(forKey: Key.renewal)
        renewalDate = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        isCoachEnabled = defaults.object(forKey: Key.coachEnabled) as? Bool ?? true
        familySeatOwner = defaults.string(forKey: Key.familySeatOwner)
    }

    /// Username of the Family Plan owner whose seat is unlocking this app, if
    /// access is coming from someone else's plan rather than your own card.
    var familySeatOwner: String? {
        didSet { defaults.set(familySeatOwner, forKey: Key.familySeatOwner) }
    }

    var hasFamilySeat: Bool { familySeatOwner != nil }

    /// Called by `AccountService` after every account sync. A seat grants the
    /// full app exactly like a paid subscription does.
    func applyFamilySeat(_ membership: FamilyMembershipDTO?) {
        let owner = membership?.ownerUsername
        guard owner != familySeatOwner else { return }
        familySeatOwner = owner
        if owner != nil { hasCompletedOnboarding = true }
    }

    var isPremium: Bool {
        Entitlements.isPaywallBypassedForTesting || tier == .premium || hasFamilySeat
    }

    /// True only when access is coming from the test bypass rather than a real
    /// subscription — used to surface an unmistakable banner in the UI.
    var isUsingTestBypass: Bool {
        Entitlements.isPaywallBypassedForTesting && tier != .premium && !hasFamilySeat
    }

    /// Hard AI photo caps applied to EVERY user regardless of subscription:
    /// 3 food photos and 1 body photo per day. These protect AI costs and are
    /// never lifted by the subscription.
    var dailyMealScanLimit: Int { 3 }
    var dailyBodyScanLimit: Int { 1 }

    /// True once the user has requested cancellation — access continues until
    /// the already-paid period ends.
    var isCancellationPending: Bool = false

    /// The card LightBolt will bill next, refreshed from Stripe.
    var card: CardDTO?

    /// TEST MODE only: clears the onboarding gate without a Stripe subscription.
    /// `isPremium` already reports true via `isPaywallBypassedForTesting`.
    func beginTestSession() {
        guard Entitlements.isPaywallBypassedForTesting else { return }
        hasCompletedOnboarding = true
    }

    func grantPremium(customerId: String, renewal: Date?) {
        stripeCustomerId = customerId
        renewalDate = renewal
        tier = .premium
        isCancellationPending = false
        hasCompletedOnboarding = true
    }

    /// Cancels the plan at Stripe immediately: billing stops on the spot and
    /// premium access drops back to the paywall. Nothing further is charged.
    func cancelSubscriptionNow() async throws {
        guard let customerId = stripeCustomerId else {
            tier = .locked
            renewalDate = nil
            return
        }
        _ = try await BackendClient.shared.cancelSubscription(customerId: customerId, atPeriodEnd: false)
        tier = .locked
        renewalDate = nil
        isCancellationPending = false
        card = nil
    }

    /// Reads the card currently on file so the settings row can show it.
    func refreshCard() async {
        guard let customerId = stripeCustomerId else {
            card = nil
            return
        }
        card = try? await BackendClient.shared.paymentMethod(customerId: customerId)
    }

    /// Re-checks the live Stripe subscription state on launch. Never downgrades
    /// on a network error — only on an authoritative "not active" answer.
    func refreshSubscription() async {
        guard let customerId = stripeCustomerId else { return }
        isVerifying = true
        defer { isVerifying = false }
        do {
            let status = try await BackendClient.shared.subscriptionStatus(customerId: customerId)
            if status.active {
                tier = .premium
                if let end = status.currentPeriodEnd {
                    renewalDate = Date(timeIntervalSince1970: end)
                }
            } else if tier == .premium {
                tier = .locked
                renewalDate = nil
                isCancellationPending = false
            }
        } catch {
            // Offline / transient — keep the cached entitlement.
        }
    }

    // MARK: Morning coach bookkeeping

    func hasCoachSpoken(on date: Date) -> Bool {
        defaults.string(forKey: Key.coachSpokenDay) == DayKey.make(date)
    }

    func markCoachSpoken(on date: Date) {
        defaults.set(DayKey.make(date), forKey: Key.coachSpokenDay)
    }
}
