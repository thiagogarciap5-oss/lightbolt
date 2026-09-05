import SwiftUI

/// In-app legal centre: subscription terms and the biometric privacy policy.
struct LegalCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var document: LegalDocument = .terms

    var body: some View {
        NavigationStack {
            ZStack {
                LightBoltTheme.backdrop

                VStack(spacing: 16) {
                    SegmentedVoltPicker(
                        options: LegalDocument.allCases,
                        selection: $document,
                        label: { $0.title }
                    )
                    .padding(.horizontal, 18)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(document.title.uppercased())
                                    .font(.fitDisplay(38))
                                    .tracking(-0.5)
                                    .foregroundStyle(LightBoltTheme.ink)
                                EyebrowText(text: "Last updated \(document.updated)", color: LightBoltTheme.voltDim)
                            }

                            ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(section.heading.uppercased())
                                        .font(.fitTitle(15))
                                        .tracking(1.1)
                                        .foregroundStyle(LightBoltTheme.volt)
                                    Text(section.body)
                                        .font(.fitBody(14))
                                        .foregroundStyle(LightBoltTheme.inkMuted)
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Text("Contact: thiagogarciapimentel0111@gmail.com")
                                .font(.fitBody(13))
                                .foregroundStyle(LightBoltTheme.inkFaint)
                                .padding(.top, 6)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 60)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.top, 10)
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
            .toolbarBackground(LightBoltTheme.void, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

nonisolated enum LegalDocument: String, CaseIterable, Identifiable, Sendable {
    case terms
    case privacy

    nonisolated var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: "Terms"
        case .privacy: "Privacy"
        }
    }

    var updated: String { "10 August 2026" }

    var sections: [LegalSection] {
        switch self {
        case .terms: Self.termsSections
        case .privacy: Self.privacySections
        }
    }

    private static let termsSections: [LegalSection] = [
        .init(
            heading: "1. Agreement",
            body: "These Terms and Conditions form a binding agreement between you and LightBolt covering your use of the LightBolt iOS application and its supporting server infrastructure. By creating a profile, subscribing, or otherwise using LightBolt you accept these terms in full. If you do not accept them, do not use the application."
        ),
        .init(
            heading: "2. LightBolt Premium subscription — $19.00 / month",
            body: "LightBolt is a premium-only application: an active LightBolt Premium subscription, billed at US $19.00 per month, is required to use the app. There is no free tier. Billing is processed by Stripe, Inc. as our payment processor. The first charge is taken when you complete checkout, and each subsequent charge is taken on the same calendar day of each following month until you cancel. Prices are exclusive of any local taxes that Stripe is required to collect. If a renewal payment fails, Stripe will retry according to its standard schedule and your Premium features will pause until payment succeeds."
        ),
        .init(
            heading: "3. Cancellation and refunds",
            body: "You may cancel at any time using the Cancel Subscription button at the bottom of the Today tab. Cancellation stops all future renewals; your Premium access continues until the end of the billing period you have already paid for. Because LightBolt delivers digital services immediately, part-month refunds are not offered except where required by the law of your country of residence."
        ),
        .init(
            heading: "4. AI photo limits",
            body: "To keep AI analysis sustainable, every member — regardless of subscription status — may submit a maximum of 3 food photographs and 1 body photograph per day. These caps reset at local midnight and may be adjusted as the product develops; any change will be surfaced in-app."
        ),
        .init(
            heading: "5. Not medical advice",
            body: "LightBolt is a fitness and self-tracking utility, not a medical device or a healthcare provider. Calorie budgets, macro splits, one-rep-max estimates, and body circumference figures are algorithmic estimates produced from the data you supply and the images you capture. They are not diagnoses and must not be used to treat or manage any medical condition. Consult a qualified physician before starting any exercise or nutrition programme, and stop immediately if you feel unwell."
        ),
        .init(
            heading: "6. Estimate accuracy",
            body: "AI meal recognition and photographic body measurement are inherently approximate. Lighting, camera angle, clothing, occluded food, and portion depth all affect results. You are responsible for reviewing and correcting any value before relying on it."
        ),
        .init(
            heading: "7. Your conduct",
            body: "You agree not to reverse-engineer, resell, scrape, or interfere with LightBolt or its servers; not to upload unlawful content; not to submit photographs of other people without their informed consent; and not to attempt to access another user's data. You must be at least 16 years old, or the minimum digital-consent age in your jurisdiction, to use LightBolt."
        ),
        .init(
            heading: "8. Intellectual property",
            body: "LightBolt, its programme library, interface designs, and source code are the property of the developer. All third-party trademarks referenced anywhere in the product belong to their respective owners; LightBolt is an independent application and is not affiliated with, endorsed by, or derived from any other fitness brand or product."
        ),
        .init(
            heading: "9. Limitation of liability",
            body: "To the maximum extent permitted by law, LightBolt is provided \"as is\" without warranties of any kind. We are not liable for indirect, incidental, or consequential damages, for injury arising from exercise you choose to perform, or for loss of data. Where liability cannot be excluded, it is limited to the total subscription fees you paid in the twelve months preceding the claim."
        ),
        .init(
            heading: "10. Changes and termination",
            body: "We may modify these terms or the service; material changes to pricing or billing frequency will be surfaced in-app before they take effect. We may suspend accounts that breach these terms. You may stop using LightBolt and delete all local data at any time from Profile → Erase All Local Data."
        ),
        .init(
            heading: "11. Governing law",
            body: "These terms are governed by the laws of the developer's country of establishment, without regard to conflict-of-law rules. Nothing here limits mandatory consumer rights available to you locally."
        )
    ]

    private static let privacySections: [LegalSection] = [
        .init(
            heading: "1. Our position in one line",
            body: "LightBolt does not sell, rent, license, or share your private biometric information with third parties for advertising, profiling, data-brokerage, or any other commercial purpose. Ever."
        ),
        .init(
            heading: "2. What stays on your device",
            body: "Your profile (objective, age, sex, height, weight, optional body-fat percentage), every logged meal and its macro values, every weight-training set with loads and reps, every habit completion, every bodyweight check-in, and every 3D body-scan measurement are stored exclusively in a local SwiftData database inside the app's private container on your iPhone. There is no LightBolt user account, and this database is never uploaded to us."
        ),
        .init(
            heading: "3. Meal photographs (Nutrition tab)",
            body: "When you capture a meal, the still image is compressed on-device and transmitted over TLS to our own analysis endpoint, which forwards it to a multimodal AI model solely to produce the nutrition estimate returned to your phone. The image is processed in memory for the duration of that single request. We do not persist your meal photographs on our servers, we do not attach an identity to them, and they are not used to train models. A small thumbnail is kept locally on your device so you can review your log."
        ),
        .init(
            heading: "4. Body scans and 3D dimensions (Body tab)",
            body: "Body scanning runs entirely on-device. The camera feed is analysed locally using Apple's Vision framework to detect your silhouette and body landmarks, and the resulting circumference estimates for chest, waist, hips, shoulders, and thigh are written straight into the local database. No scan video, no scan frames, no silhouette masks, and no wireframe geometry are ever uploaded, transmitted, or backed up to us."
        ),
        .init(
            heading: "5. Camera permission",
            body: "Camera access is requested only when you open the Nutrition capture view or the Body scanner, and is used only for those features. You can revoke it at any time in iOS Settings; LightBolt continues to work with manual entry."
        ),
        .init(
            heading: "6. Payments",
            body: "Subscription payments are handled by Stripe, Inc. Card numbers are entered inside Stripe's own payment sheet and are never seen by, transmitted through, or stored in LightBolt. Our server retains only a Stripe customer reference and a subscription reference so we can confirm whether your subscription is active. Stripe processes your payment data as an independent controller under its own privacy policy."
        ),
        .init(
            heading: "7. Analytics and tracking",
            body: "LightBolt contains no advertising SDKs, no cross-app tracking, no third-party analytics libraries, and no device-fingerprinting code. We do not use the Advertising Identifier and we do not ask for tracking permission because we do not track you."
        ),
        .init(
            heading: "8. Your rights and control",
            body: "Because your health data lives on your device, you retain direct control. Profile → Erase All Local Data permanently deletes every profile, meal, set, habit, and scan record from the device. Deleting the app removes the database with it. To delete the Stripe customer reference held on our server, cancel your subscription and email thiagogarciapimentel0111@gmail.com."
        ),
        .init(
            heading: "9. Children",
            body: "LightBolt is not directed at children under 16 and we do not knowingly collect their data."
        ),
        .init(
            heading: "10. Changes to this policy",
            body: "If our data handling changes materially, the updated policy will be published in this screen and dated before the change takes effect."
        )
    ]
}

nonisolated struct LegalSection: Sendable {
    let heading: String
    let body: String
}
