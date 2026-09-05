import SwiftUI

/// Renames the handle other people search for when they add you to a Family
/// Plan. Account creation itself lives in `AccountSetupView`.
struct UsernameSetupView: View {
    @Environment(AccountService.self) private var account
    @Environment(AuthManager.self) private var auth

    /// Always true today — kept so existing call sites read unchanged.
    var isEditing: Bool = true
    var onDone: (() -> Void)?

    @State private var draft: String = ""
    @State private var availability: Availability = .idle
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var isFocused: Bool

    private enum Availability: Equatable {
        case idle
        case checking
        case free
        case taken(String)
    }

    var body: some View {
        ZStack {
            LightBoltTheme.backdrop

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    mark
                    headline
                    field
                    statusRow
                    rules
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 22)
                .padding(.top, isEditing ? 22 : 60)
                .padding(.bottom, 200)
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
            if isEditing { draft = account.username ?? "" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { isFocused = true }
        }
        .task(id: draft) {
            await evaluate()
        }
    }

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
            if isEditing {
                Button {
                    Haptics.tick()
                    onDone?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(LightBoltTheme.ink)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(LightBoltTheme.charcoal))
                }
            }
        }
        .padding(.bottom, 34)
    }

    private var titleLines: [String] {
        ["CHANGE", "YOUR NAME."]
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            EyebrowText(text: "Change username", color: LightBoltTheme.voltDim)
            .padding(.bottom, 10)

            ForEach(Array(titleLines.enumerated()), id: \.offset) { index, line in
                if index == titleLines.count - 1 {
                    Text(line)
                        .font(.fitDisplay(62))
                        .tracking(-2)
                        .voltWash()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(line)
                        .font(.fitDisplay(62))
                        .tracking(-2)
                        .foregroundStyle(LightBoltTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Text("Your new handle has to be free too. Anyone who already invited you will see the change.")
                .font(.fitBody(14))
                .foregroundStyle(LightBoltTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(nil)
                .padding(.top, 14)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .padding(.bottom, 30)
    }

    private var field: some View {
        HStack(spacing: 10) {
            Text("@")
                .font(.fitDisplay(26))
                .foregroundStyle(fieldAccent)

            TextField(
                "",
                text: $draft,
                prompt: Text("yourname").foregroundStyle(LightBoltTheme.inkFaint)
            )
            .font(.fitTitle(24))
            .foregroundStyle(LightBoltTheme.ink)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($isFocused)
            .onSubmit { Task { await save() } }

            if !draft.isEmpty {
                Button {
                    Haptics.tick()
                    draft = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(LightBoltTheme.inkFaint)
                }
                .buttonStyle(VoltPressStyle(scale: 0.86))
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 68)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LightBoltTheme.obsidian)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(fieldAccent, lineWidth: 1.4)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: availability)
        .animation(.easeOut(duration: 0.18), value: draft.isEmpty)
    }

    private var fieldAccent: Color {
        switch availability {
        case .free: LightBoltTheme.volt
        case .taken: LightBoltTheme.alert
        default: LightBoltTheme.hairline
        }
    }

    private var statusRow: some View {
        HStack(spacing: 9) {
            switch availability {
            case .idle:
                Text("3–50 characters, any alphabet, no spaces.")
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
                Text("@\(draft.trimmingCharacters(in: .whitespaces)) is yours")
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
        .animation(.easeOut(duration: 0.2), value: availability)
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 0) {
            rule("globe", "Any alphabet — Latin, Cyrillic, Arabic, 日本語, emoji")
            Rectangle().fill(LightBoltTheme.hairline).frame(height: 1)
            rule("person.2.fill", "How family members find you when they invite you")
            Rectangle().fill(LightBoltTheme.hairline).frame(height: 1)
            rule("arrow.triangle.2.circlepath", "Changeable later from your profile")
        }
        .padding(.horizontal, 16)
        .fitCard(radius: 20)
        .padding(.top, 30)
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

    private var dock: some View {
        VStack(spacing: 12) {
            if let saveError {
                Text(saveError)
                    .font(.fitBody(12))
                    .foregroundStyle(LightBoltTheme.alert)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            VoltButton(
                title: "Save username",
                systemImage: "checkmark",
                isEnabled: availability == .free,
                isBusy: isSaving
            ) {
                Task { await save() }
            }

            Text("Changing your handle doesn't affect your subscription or your family plan.")
                .font(.fitBody(11))
                .foregroundStyle(LightBoltTheme.inkFaint)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 26)
        .background(
            LinearGradient(
                colors: [LightBoltTheme.void.opacity(0), LightBoltTheme.void.opacity(0.94), LightBoltTheme.void],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .animation(.easeOut(duration: 0.2), value: saveError)
    }

    // MARK: Logic

    /// Debounced availability check — one request per pause in typing.
    private func evaluate() async {
        let candidate = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        if candidate.isEmpty {
            availability = .idle
            return
        }
        if isEditing, candidate.compare(account.username ?? "", options: .caseInsensitive) == .orderedSame {
            availability = .free
            return
        }
        if let local = AccountService.localValidation(candidate) {
            availability = .taken(local)
            return
        }

        availability = .checking
        try? await Task.sleep(for: .milliseconds(450))
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

    private func save() async {
        guard availability == .free, !isSaving else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let candidate = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = await account.claimUsername(candidate, authUserId: auth.user?.id) {
            saveError = error
            availability = .taken(error)
            return
        }
        isFocused = false
        onDone?()
    }
}
