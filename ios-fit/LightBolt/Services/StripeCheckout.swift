import Foundation
import Observation
import StripePaymentSheet
import SwiftUI

/// Stripe publishable key. Publishable keys are designed to ship inside client
/// binaries; the secret key lives only in the Cloudflare Worker environment.
nonisolated enum StripeConfig {
    static let publishableKey = "pk_live_51U2iu3C6bUwmRNQKLPIiA8GTcM25GUIWqxz1RRhlbec5FjR87ox6pphzQKSrGtzq6B6FpZvmbxIi49lZLxXywnTK007QSm05cW"
    static let monthlyPriceDisplay = "$19"
    static let familyPriceDisplay = "$70"
    static let merchantName = "LightBolt"

    static func configure() {
        StripeAPI.defaultPublishableKey = publishableKey
    }
}

nonisolated enum CheckoutPhase: Equatable, Sendable {
    case idle
    case preparing
    case ready
    case completed
    case failed(String)
}

/// Drives the $19/month subscription purchase: asks the Worker for a
/// `default_incomplete` subscription, then presents Stripe's PaymentSheet
/// restyled into the LightBolt black/volt theme.
@Observable
final class StripeCheckout {
    var phase: CheckoutPhase = .idle
    var paymentSheet: PaymentSheet?
    var isPresentingSheet: Bool = false

    private(set) var customerId: String?
    private(set) var subscriptionId: String?

    /// The plan the current sheet is buying, so the caller knows what was sold.
    private(set) var plan: LightBoltPlan = .individual

    /// Requests the subscription bootstrap payload and builds the PaymentSheet.
    func prepare(existingCustomerId: String?, plan: LightBoltPlan = .individual, accountId: String) async {
        guard phase != .preparing else { return }
        phase = .preparing
        paymentSheet = nil
        self.plan = plan

        StripeConfig.configure()

        do {
            let bootstrap = try await BackendClient.shared.createSubscription(
                customerId: existingCustomerId,
                email: nil,
                plan: plan,
                userId: accountId
            )
            customerId = bootstrap.customerId
            subscriptionId = bootstrap.subscriptionId

            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = StripeConfig.merchantName
            configuration.allowsDelayedPaymentMethods = false
            configuration.appearance = Self.voltAppearance
            configuration.primaryButtonLabel = "Start — \(plan.priceLabel)/month"
            if let ephemeralKeySecret = bootstrap.ephemeralKeySecret {
                configuration.customer = .init(
                    id: bootstrap.customerId,
                    ephemeralKeySecret: ephemeralKeySecret
                )
            }

            paymentSheet = PaymentSheet(
                paymentIntentClientSecret: bootstrap.clientSecret,
                configuration: configuration
            )
            phase = .ready
            isPresentingSheet = true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Checkout is unavailable right now."
            phase = .failed(message)
        }
    }

    func handle(result: PaymentSheetResult) -> Bool {
        isPresentingSheet = false
        switch result {
        case .completed:
            phase = .completed
            Haptics.success()
            return true
        case .canceled:
            phase = .idle
            paymentSheet = nil
            return false
        case .failed(let error):
            phase = .failed(error.localizedDescription)
            Haptics.failure()
            return false
        }
    }

    func reset() {
        phase = .idle
        paymentSheet = nil
        isPresentingSheet = false
        setupIntentId = nil
    }

    // MARK: Changing the card on file

    /// Id of the SetupIntent currently being confirmed, needed to promote the
    /// new card to default once the sheet reports success.
    private(set) var setupIntentId: String?

    /// Presents PaymentSheet in setup mode so the user can attach a different
    /// card. Nothing is charged; the card becomes the default on success.
    func prepareCardUpdate(customerId: String) async {
        guard phase != .preparing else { return }
        phase = .preparing
        paymentSheet = nil
        setupIntentId = nil

        StripeConfig.configure()

        do {
            let bootstrap = try await BackendClient.shared.createSetupIntent(customerId: customerId)
            setupIntentId = bootstrap.setupIntentId

            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = StripeConfig.merchantName
            configuration.allowsDelayedPaymentMethods = false
            configuration.appearance = Self.voltAppearance
            configuration.primaryButtonLabel = "Save this card"
            if let ephemeralKeySecret = bootstrap.ephemeralKeySecret {
                configuration.customer = .init(
                    id: bootstrap.customerId,
                    ephemeralKeySecret: ephemeralKeySecret
                )
            }

            paymentSheet = PaymentSheet(
                setupIntentClientSecret: bootstrap.clientSecret,
                configuration: configuration
            )
            phase = .ready
            isPresentingSheet = true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "We couldn't open the card form. Please try again."
            phase = .failed(message)
        }
    }

    /// Finishes the card change: tells the Worker to make the freshly saved
    /// card the default for the customer and every live subscription.
    func confirmCardUpdate(customerId: String) async -> CardDTO? {
        guard let setupIntentId else { return nil }
        do {
            let card = try await BackendClient.shared.updatePaymentMethod(
                customerId: customerId,
                setupIntentId: setupIntentId
            )
            self.setupIntentId = nil
            Haptics.success()
            return card
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? "The card was saved but we couldn't set it as default.")
            Haptics.failure()
            return nil
        }
    }

    /// Absolute black fields with electric-yellow focus lines.
    private static var voltAppearance: PaymentSheet.Appearance {
        var appearance = PaymentSheet.Appearance()
        appearance.cornerRadius = 14
        appearance.borderWidth = 1.2

        appearance.colors.background = UIColor(LightBoltTheme.void)
        appearance.colors.componentBackground = UIColor(LightBoltTheme.obsidian)
        appearance.colors.componentBorder = UIColor(LightBoltTheme.hairline)
        appearance.colors.componentDivider = UIColor(LightBoltTheme.hairline)
        appearance.colors.primary = UIColor(LightBoltTheme.volt)
        appearance.colors.text = UIColor.white
        appearance.colors.textSecondary = UIColor(LightBoltTheme.inkMuted)
        appearance.colors.componentText = UIColor.white
        appearance.colors.componentPlaceholderText = UIColor(LightBoltTheme.inkFaint)
        appearance.colors.icon = UIColor(LightBoltTheme.volt)
        appearance.colors.danger = UIColor(LightBoltTheme.alert)

        appearance.primaryButton.backgroundColor = UIColor(LightBoltTheme.volt)
        appearance.primaryButton.textColor = .black
        appearance.primaryButton.cornerRadius = 14
        appearance.primaryButton.borderColor = UIColor(LightBoltTheme.volt)

        appearance.font.base = UIFont.systemFont(ofSize: 16, weight: .medium)
        appearance.font.sizeScaleFactor = 1.02

        return appearance
    }
}
