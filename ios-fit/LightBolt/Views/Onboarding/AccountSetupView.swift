import SwiftUI

/// The first screen of LightBolt: one account, created in one step.
///
/// Username and password are set together so iOS and iCloud Keychain (or Google
/// Password Manager on Android) recognise the pair and offer to save it — the
/// fields carry the native `.username` / `.newPassword` semantic tags that make
/// that prompt appear. Apple and Google sign-in sit underneath as one-tap
/// alternatives for people who would rather not invent another password.
struct AccountSetupView: View {
    @Environment(AccountService.self) private var account
    @Environment(AuthManager.self) private var auth

    /// Optional fast lane: skips account creation entirely and jumps the user
    /// to the payment screen. Used by the "Prep account" shortcut.
    var onPrepAccount: (() -> Void)? = nil

    private enum Mode: String, CaseIterable, Identifiable {
        case create, signIn

        var id: String { rawValue }
        var title: String { self == .create ? "Create account" : "Sign in" }
    }

    private enum Availability: Equatable {
        case idle
        case checking
        case free
        case taken(String)
    }

    private enum Field: Hashable { case username, password }

    @State private var mode: Mode = .create
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isPasswordVisible = false
    @State private var availability: Availability = .idle
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    /// True once an OAuth sign-in succeeded but the account still needs a handle.
    private var needsHandleForOAuth: Bool { auth.isSignedIn && !account.hasUsername }

    var body: some View {
        ZStack {
            LightBoltTheme.backdrop

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    mark
                    headline
                    if !needsHandleForOAuth { modePicker }
                    usernameField
                    if !needsHandleForOAuth { passwordField }
                    statusRow
                    if mode == .create, !needsHandleForOAuth { rules }
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 22)
                .padding(.top, 54)
                .padding(.bottom, 260)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            VStack {
                Spacer()
                dock
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { focus = .username }
        }
        .task(id: usernameProbe) { await evaluate() }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mode)
        .animation(.easeOut(duration: 0.2), value: errorMessage)
        .animation(.easeOut(duration: 0.2), value: availability)
    }

    /// Only re-checks availability when it can matter.
    private var usernameProbe: String { mode == .signIn ? "" : username }

    // MARK: Sections

    private var mark: some View {
        HStack(spacing: 7) {
            Rectangle()
                .fill(LightBoltTheme.volt)
                .frame(width: 4, height: 22)
            Text("LIGHTBOLT")
                .font(.fitDisplay(24))
                .tracking(-0.4)
                .foregroundStyle(LightBoltTheme.ink)
            Spacer()
        }
        .padding(.bottom, 30)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            EyebrowText(
                text: needsHandleForOAuth ? "Almost there" : "Step one of one",
                color: LightBoltTheme.voltDim
            )
            .padding(.bottom, 10)

            Text(mode == .create ? "CLAIM" : "WELCOME")
                .font(.fitDisplay(58))
                .tracking(-2)
                .foregroundStyle(LightBoltTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(mode == .create ? "YOUR NAME." : "BACK.")
                .font(.fitDisplay(58))
                .tracking(-2)
                .voltWash()
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(subtitle)
                .font(.fitBody(14))
                .foregroundStyle(LightBoltTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .padding(.bottom, 24)
    }

    private var subtitle: String {
        if needsHandleForOAuth {
            return "Signed in as \(auth.user?.displayName ?? "your account"). Pick the handle other people will use to add you to a Family Plan."
        }
        return mode == .create
            ? "One username, one password. Your handle is how family members find you; your password brings this account back on any phone."
            : "Sign back in and your subscription, family seat and history come with you."
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            ForEach(Mode.allCases) { option in
                Button {
                    Haptics.tick()
                    mode = option
                    errorMessage = nil
                    availability = .idle
                } label: {
                    Text(option.title.uppercased())
                        .font(.fitLabel(11))
                        .tracking(1.3)
                        .foregroundStyle(mode == option ? .black : LightBoltTheme.inkMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(mode == option ? LightBoltTheme.volt : LightBoltTheme.charcoal)
                        )
                }
                .buttonStyle(VoltPressStyle(scale: 0.96))
            }
        }
        .padding(.bottom, 18)
    }

    private var usernameField: some View {
        HStack(spacing: 10) {
            Text("@")
                .font(.fitDisplay(24))
                .foregroundStyle(fieldAccent)

            TextField(
                "",
                text: $username,
                prompt: Text("yourname").foregroundStyle(LightBoltTheme.inkFaint)
            )
            .font(.fitTitle(22))
            .foregroundStyle(LightBoltTheme.ink)
            // Semantic tag: this is what makes iOS offer to save and autofill.
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused($focus, equals: .username)
            .onSubmit { focus = needsHandleForOAuth ? nil : .password }

            if !username.isEmpty {
                Button {
                    Haptics.tick()
                    username = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(LightBoltTheme.inkFaint)
                }
                .buttonStyle(VoltPressStyle(scale: 0.86))
                .accessibilityLabel("Clear username")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LightBoltTheme.obsidian))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(fieldAccent, lineWidth: 1.4)
        )
    }

    private var passwordField: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(passwordAccent)

                Group {
                    if isPasswordVisible {
                        TextField(
                            "",
                            text: $password,
                            prompt: Text("password").foregroundStyle(LightBoltTheme.inkFaint)
                        )
                        .textContentType(mode == .create ? .newPassword : .password)
                    } else {
                        SecureField(
                            "",
                            text: $password,
                            prompt: Text("password").foregroundStyle(LightBoltTheme.inkFaint)
                        )
                        // .newPassword triggers the strong-password suggestion
                        // and the "save to Keychain" prompt on sign-up.
                        .textContentType(mode == .create ? .newPassword : .password)
                    }
                }
                .font(.fitTitle(20))
                .foregroundStyle(LightBoltTheme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focus, equals: .password)
                .onSubmit { Task { await submit() } }

                Button {
                    Haptics.tick()
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(LightBoltTheme.inkFaint)
                }
                .buttonStyle(VoltPressStyle(scale: 0.86))
                .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
            }
            .padding(.horizontal, 18)
            .frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LightBoltTheme.obsidian))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(passwordAccent, lineWidth: 1.4)
            )

            if mode == .create, !password.isEmpty {
                strengthMeter
            }
        }
        .padding(.top, 12)
    }

    private var strengthMeter: some View {
        let score = PasswordStrength.score(password)
        return HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { step in
                    Capsule()
                        .fill(step < score.bars ? score.color : LightBoltTheme.charcoalHigh)
                        .frame(height: 4)
                }
            }
            Text(score.label.uppercased())
                .font(.fitLabel(9))
                .tracking(1.2)
                .foregroundStyle(score.color)
        }
        .transition(.opacity)
    }

    private var fieldAccent: Color {
        switch availability {
        case .free: LightBoltTheme.volt
        case .taken: LightBoltTheme.alert
        default: LightBoltTheme.hairline
        }
    }

    private var passwordAccent: Color {
        guard mode == .create, !password.isEmpty else { return LightBoltTheme.hairline }
        return AccountService.localPasswordValidation(password) == nil ? LightBoltTheme.volt : LightBoltTheme.hairline
    }

    private var statusRow: some View {
        HStack(spacing: 9) {
            switch availability {
            case .idle:
                Text(mode == .create ? "3–50 characters, any alphabet, no spaces." : "Use the username you signed up with.")
                    .font(.fitBody(12))
                    .foregroundStyle(LightBoltTheme.inkFaint)
            case .checking:
                RunningWaveLoader(barCount: 4, height: 13)
                Text("Checking that name…")
                    .font(.fitBody(12))
                    .foregroundStyle(LightBoltTheme.inkMuted)
            case .free:
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(LightBoltTheme.volt)
                Text("@\(username.trimmingCharacters(in: .whitespaces)) is yours")
                    .font(.fitBody(12))
                    .foregroundStyle(LightBoltTheme.volt)
                    .lineLimit(1)
            case .taken(let reason):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LightBoltTheme.alert)
                Text(reason)
                    .font(.fitBody(12))
                    .foregroundStyle(LightBoltTheme.alert)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 22, alignment: .leading)
        .padding(.top, 14)
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 0) {
            rule("key.fill", "Save it to iCloud Keychain when iOS offers — that's your way back in")
            Rectangle().fill(LightBoltTheme.hairline).frame(height: 1)
            rule("globe", "Any alphabet — Latin, Cyrillic, Arabic, 日本語, emoji")
            Rectangle().fill(LightBoltTheme.hairline).frame(height: 1)
            rule("person.2.fill", "How family members find you when they invite you")
        }
        .padding(.horizontal, 16)
        .fitCard(radius: 20)
        .padding(.top, 24)
    }

    private func rule(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(LightBoltTheme.volt)
                .frame(width: 24)
            Text(text)
                .font(.fitBody(13))
                .foregroundStyle(LightBoltTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }

    // MARK: Dock

    private var dock: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.fitBody(12))
                    .foregroundStyle(LightBoltTheme.alert)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            VoltButton(
                title: primaryTitle,
                systemImage: mode == .create ? "arrow.right" : "checkmark",
                isEnabled: canSubmit,
                isBusy: isSubmitting
            ) {
                Task { await submit() }
            }

            if !needsHandleForOAuth, auth.isConfigured {
                HStack(spacing: 10) {
                    line
                    Text("OR")
                        .font(.fitLabel(9))
                        .tracking(1.6)
                        .foregroundStyle(LightBoltTheme.inkFaint)
                    line
                }
                .padding(.vertical, 2)

                HStack(spacing: 10) {
                    providerButton(title: "Apple", symbol: "apple.logo", provider: "apple")
                    providerButton(title: "Google", symbol: "g.circle.fill", provider: "google")
                }
            }

            Text(mode == .create
                 ? "Your password is hashed on our server — we never see it in plain text."
                 : "Forgot it? Sign in with Apple or Google instead.")
                .font(.fitBody(11))
                .foregroundStyle(LightBoltTheme.inkFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let onPrepAccount {
                Button {
                    Haptics.tick()
                    onPrepAccount()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 11, weight: .black))
                        Text("PREP ACCOUNT")
                            .font(.fitLabel(11))
                            .tracking(1.5)
                    }
                    .foregroundStyle(LightBoltTheme.inkMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(LightBoltTheme.charcoal.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(LightBoltTheme.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(VoltPressStyle(scale: 0.97))
                .accessibilityLabel("Prep account and go to payment")
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .background(
            LinearGradient(
                colors: [LightBoltTheme.void.opacity(0), LightBoltTheme.void.opacity(0.95), LightBoltTheme.void],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var line: some View {
        Rectangle().fill(LightBoltTheme.hairline).frame(height: 1)
    }

    private func providerButton(title: String, symbol: String, provider: String) -> some View {
        Button {
            Haptics.tap()
            Task { await auth.signIn(provider: provider) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(.fitTitle(15))
            }
            .foregroundStyle(LightBoltTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LightBoltTheme.charcoal))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(LightBoltTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(VoltPressStyle())
        .disabled(auth.isSigningIn)
        .opacity(auth.isSigningIn ? 0.5 : 1)
        .accessibilityLabel("Sign in with \(title)")
    }

    private var primaryTitle: String {
        if needsHandleForOAuth { return "Claim handle" }
        return mode == .create ? "Create account" : "Sign in"
    }

    private var canSubmit: Bool {
        if needsHandleForOAuth { return availability == .free }
        switch mode {
        case .create:
            return availability == .free && AccountService.localPasswordValidation(password) == nil
        case .signIn:
            return username.trimmingCharacters(in: .whitespaces).count >= 3 && !password.isEmpty
        }
    }

    // MARK: Logic

    /// Debounced availability check — one request per pause in typing.
    private func evaluate() async {
        guard mode == .create || needsHandleForOAuth else {
            availability = .idle
            return
        }
        let candidate = username.trimmingCharacters(in: .whitespacesAndNewlines)

        if candidate.isEmpty {
            availability = .idle
            return
        }
        if let local = AccountService.localValidation(candidate) {
            availability = .taken(local)
            return
        }

        availability = .checking
        try? await Task.sleep(for: .milliseconds(420))
        if Task.isCancelled { return }

        let reason = await account.checkUsername(candidate)
        if Task.isCancelled { return }

        if let reason {
            availability = .taken(reason)
            Haptics.warning()
        } else {
            availability = .free
            Haptics.tick()
        }
    }

    private func submit() async {
        guard canSubmit, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let handle = username.trimmingCharacters(in: .whitespacesAndNewlines)

        if needsHandleForOAuth {
            if let failure = await account.claimUsername(handle, authUserId: auth.user?.id) {
                errorMessage = failure
            }
            return
        }

        switch mode {
        case .create:
            if let failure = await account.register(
                username: handle,
                password: password,
                authUserId: auth.user?.id
            ) {
                errorMessage = failure
                availability = .taken(failure)
            } else {
                focus = nil
            }
        case .signIn:
            if let failure = await account.signIn(username: handle, password: password) {
                errorMessage = failure
            } else {
                focus = nil
            }
        }
    }
}

/// Honest password feedback: length first, variety second, no security theatre.
nonisolated enum PasswordStrength {
    struct Score {
        let bars: Int
        let label: String
        let color: Color
    }

    static func score(_ password: String) -> Score {
        let length = password.count
        var variety = 0
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { variety += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { variety += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { variety += 1 }
        if password.rangeOfCharacter(from: .punctuationCharacters.union(.symbols)) != nil { variety += 1 }

        if length < 8 { return Score(bars: 1, label: "Too short", color: LightBoltTheme.alert) }
        if length >= 14 || (length >= 11 && variety >= 3) {
            return Score(bars: 3, label: "Strong", color: LightBoltTheme.volt)
        }
        if length >= 10 || variety >= 3 {
            return Score(bars: 2, label: "Fair", color: LightBoltTheme.voltDim)
        }
        return Score(bars: 1, label: "Weak", color: LightBoltTheme.alert)
    }
}
