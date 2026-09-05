import MessageUI
import SwiftUI

/// Star rating + written feedback, delivered through the device's own Mail app.
/// No server round trip: the composer opens pre-addressed and pre-filled with
/// the user's name/username, star rating and raw feedback text.
struct FeedbackView: View {
    @Environment(AccountService.self) private var account
    @Environment(\.dismiss) private var dismiss

    /// Where this form was opened from — included in the email for context.
    var source: String = "profile"
    var prompt: String = "Tell us what's working and what isn't."

    @State private var name: String = ""
    @State private var rating: Int = 0
    @State private var message: String = ""
    @State private var isPresentingMail = false
    @State private var mailError: String?
    @State private var didSend = false
    @FocusState private var isWriting: Bool

    nonisolated static let supportEmail = "thiagogarciap5@gmail.com"

    var body: some View {
        NavigationStack {
            ZStack {
                LightBoltTheme.backdrop

                if didSend {
                    sentState
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    form
                        .transition(.opacity)
                }
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
        .presentationDetents([.large])
        .presentationContentInteraction(.scrolls)
        .onAppear { name = account.username ?? "" }
        .sheet(isPresented: $isPresentingMail) {
            MailComposer(
                name: name,
                username: account.username,
                rating: rating,
                message: message,
                source: source,
                onFinished: handleMailFinished
            )
            .ignoresSafeArea()
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: didSend)
        .animation(.easeOut(duration: 0.2), value: mailError)
    }

    // MARK: Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowText(text: "Feedback", color: LightBoltTheme.voltDim)
                    Text("TELL US")
                        .font(.fitDisplay(46))
                        .tracking(-1.6)
                        .foregroundStyle(LightBoltTheme.ink)
                    Text("STRAIGHT.")
                        .font(.fitDisplay(46))
                        .tracking(-1.6)
                        .voltWash()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)

                Text(prompt)
                    .font(.fitBody(14))
                    .foregroundStyle(LightBoltTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                starPicker
                nameField
                messageField

                if let mailError {
                    Text(mailError)
                        .font(.fitBody(12))
                        .foregroundStyle(LightBoltTheme.alert)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }

                VoltButton(
                    title: "Open Mail",
                    systemImage: "envelope.fill",
                    isEnabled: rating > 0 && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    send()
                }

                Text("Opens your Mail app pre-addressed to the LightBolt team with your name, star rating and message. Nothing is sent without you hitting send.")
                    .font(.fitBody(11))
                    .foregroundStyle(LightBoltTheme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var starPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowText(text: "Your rating")

            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { rating = star }
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(star <= rating ? LightBoltTheme.volt : LightBoltTheme.inkFaint)
                            .scaleEffect(star == rating ? 1.14 : 1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(VoltPressStyle(scale: 0.86))
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                }
            }
            .padding(.horizontal, 8)
            .fitCard(radius: 18)

            if rating > 0 {
                Text(ratingBlurb)
                    .font(.fitBody(12))
                    .foregroundStyle(LightBoltTheme.volt)
                    .transition(.opacity)
            }
        }
    }

    private var ratingBlurb: String {
        switch rating {
        case 1: "Rough. Tell us what broke."
        case 2: "Below par — what's missing?"
        case 3: "Middle of the road. What would move it?"
        case 4: "Good. What's the last 20%?"
        default: "Brilliant — what do you love?"
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowText(text: "Your name")
            TextField(
                "",
                text: $name,
                prompt: Text("Name or username").foregroundStyle(LightBoltTheme.inkFaint)
            )
            .font(.fitBody(16))
            .foregroundStyle(LightBoltTheme.ink)
            .autocorrectionDisabled()
            .padding(.horizontal, 16)
            .frame(height: 56)
            .fitCard(radius: 16, fill: LightBoltTheme.obsidian)
        }
    }

    private var messageField: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowText(text: "Your feedback")
            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text("What happened, and what would you change?")
                        .font(.fitBody(15))
                        .foregroundStyle(LightBoltTheme.inkFaint)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $message)
                    .font(.fitBody(15))
                    .foregroundStyle(LightBoltTheme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .focused($isWriting)
            }
            .frame(height: 170)
            .fitCard(radius: 16, fill: LightBoltTheme.obsidian)
        }
    }

    // MARK: Sent

    private var sentState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(LightBoltTheme.volt.opacity(0.12))
                    .frame(width: 130, height: 130)
                    .blur(radius: 18)
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 86, height: 86)
                    .background(Circle().fill(LightBoltTheme.volt))
            }

            Text("SENT")
                .font(.fitDisplay(50))
                .tracking(-1.4)
                .voltWash()

            Text("Your mail is on its way to the LightBolt team.")
                .font(.fitBody(14))
                .foregroundStyle(LightBoltTheme.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            GhostButton(title: "Close", systemImage: "xmark") {
                dismiss()
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
    }

    // MARK: Sending

    private func send() {
        guard rating > 0, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Haptics.tap()
        isWriting = false
        mailError = nil

        if MFMailComposeViewController.canSendMail() {
            isPresentingMail = true
            return
        }

        // No Mail account configured — fall back to the mailto handler, which
        // routes to whatever mail app the device prefers.
        guard let url = Self.mailtoURL(name: name, username: account.username, rating: rating, message: message, source: source) else {
            mailError = "No mail app is set up on this device. Email us at \(Self.supportEmail)."
            Haptics.failure()
            return
        }
        UIApplication.shared.open(url) { opened in
            if opened {
                didSend = true
            } else {
                mailError = "We couldn't open Mail. Email us at \(Self.supportEmail)."
                Haptics.failure()
            }
        }
    }

    private func handleMailFinished(_ result: MFMailComposeResult) {
        switch result {
        case .sent, .saved:
            Haptics.success()
            didSend = true
        default:
            // User backed out — leave the form exactly as they left it.
            break
        }
    }

    // MARK: Payload

    /// The email body explicitly maps the required fields: name/username, star
    /// rating and the raw feedback text.
    static func messageBody(name: String, username: String?, rating: Int, message: String, source: String) -> String {
        let stars = String(repeating: "★", count: rating) + String(repeating: "☆", count: max(0, 5 - rating))
        let who = name.isEmpty ? (username ?? "Unknown") : name
        if let username, !username.isEmpty, !who.localizedCaseInsensitiveContains(username) {
            // Include the handle alongside a real name when they differ.
            return """
            Name: \(who)
            Username: @\(username)
            Star rating: \(stars) (\(rating)/5)
            Context: \(source)

            Feedback:
            \(message)

            — Sent from LightBolt for iOS
            """
        }
        return """
        Name/Username: \(who)
        Star rating: \(stars) (\(rating)/5)
        Context: \(source)

        Feedback:
        \(message)

        — Sent from LightBolt for iOS
        """
    }

    static func mailtoURL(name: String, username: String?, rating: Int, message: String, source: String) -> URL? {
        let subject = "LightBolt feedback — \(rating)/5 from \(name.isEmpty ? (username ?? "Unknown") : name)"
        var components = URLComponents(string: "mailto:\(supportEmail)")
        components?.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: messageBody(name: name, username: username, rating: rating, message: message, source: source))
        ]
        return components?.url
    }
}

// MARK: - Mail composer bridge

/// Native MFMailComposeViewController styled by the system, pre-filled with the
/// feedback payload and addressed to LightBolt support.
private struct MailComposer: UIViewControllerRepresentable {
    let name: String
    let username: String?
    let rating: Int
    let message: String
    let source: String
    let onFinished: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients([FeedbackView.supportEmail])
        composer.setSubject("LightBolt feedback — \(rating)/5 from \(name.isEmpty ? (username ?? "Unknown") : name)")
        composer.setMessageBody(
            FeedbackView.messageBody(name: name, username: username, rating: rating, message: message, source: source),
            isHTML: false
        )
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinished: (MFMailComposeResult) -> Void

        init(onFinished: @escaping (MFMailComposeResult) -> Void) {
            self.onFinished = onFinished
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            onFinished(result)
        }
    }
}
