import AuthenticationServices
import SwiftUI

/// Account creation and sign-in. An account keeps your subscription, profile
/// and streaks attached to you rather than to one phone.
struct AccountView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirmingSignOut = false

    var body: some View {
        @Bindable var auth = auth

        NavigationStack {
            ZStack {
                LightBoltTheme.backdrop

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        if auth.isLoading {
                            loadingCard
                        } else if let user = auth.user {
                            signedInCard(user)
                            benefitsBlock
                            signOutBlock
                        } else {
                            signInCard
                            benefitsBlock
                        }
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
        .alert("Error", isPresented: $auth.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(auth.errorMessage)
        }
        .alert("Sign out?", isPresented: $isConfirmingSignOut) {
            Button("Stay signed in", role: .cancel) {}
            Button("Sign out", role: .destructive) {
                Task { await auth.signOut() }
            }
        } message: {
            Text("Your workouts and meals stay on this device. Sign back in any time to reconnect your subscription.")
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.84), value: auth.user)
        .animation(.easeOut(duration: 0.25), value: auth.isLoading)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            EyebrowText(text: "Your account", color: LightBoltTheme.voltDim)
            Text(auth.isSignedIn ? "SIGNED\nIN" : "CREATE\nACCOUNT")
                .font(.fitDisplay(56))
                .tracking(-1.8)
                .lineSpacing(-8)
                .foregroundStyle(LightBoltTheme.ink)
        }
        .padding(.top, 6)
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SkeletonBlock(width: 180, height: 22, radius: 6)
            SkeletonBlock(width: 130, height: 14, radius: 5)
            VoltSweepLine()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard(radius: 22)
    }

    private func signedInCard(_ user: AuthManager.User) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LightBoltTheme.volt)
                Text(user.initials)
                    .font(.fitDisplay(22))
                    .foregroundStyle(.black)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                Text(user.displayName)
                    .font(.fitTitle(19))
                    .foregroundStyle(LightBoltTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !user.email.isEmpty {
                    Text(user.email)
                        .font(.fitBody(12))
                        .foregroundStyle(LightBoltTheme.inkMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(LightBoltTheme.volt)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard(radius: 22, stroke: LightBoltTheme.voltDim, fill: LightBoltTheme.obsidian)
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create your LightBolt account in one tap. It links your subscription, calibration and progress to you — so a new phone is a sign-in, not a restart.")
                .font(.fitBody(14))
                .foregroundStyle(LightBoltTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if auth.isSigningIn {
                HStack(spacing: 10) {
                    RunningWaveLoader(barCount: 5, height: 16)
                    Text("Waiting for sign-in…")
                        .font(.fitBody(13))
                        .foregroundStyle(LightBoltTheme.inkMuted)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .transition(.opacity)
            }

            SignInWithAppleButton(.signUp) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { _ in
                Task { await auth.signIn(provider: "apple") }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .clipShape(.rect(cornerRadius: 15, style: .continuous))
            .disabled(auth.isSigningIn)

            Button {
                Haptics.tap()
                Task { await auth.signIn(provider: "google") }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "globe")
                        .font(.system(size: 15, weight: .black))
                    Text("Continue with Google")
                        .font(.fitTitle(16))
                }
                .foregroundStyle(LightBoltTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(LightBoltTheme.charcoalHigh)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(LightBoltTheme.hairline, lineWidth: 1)
                )
            }
            .buttonStyle(VoltPressStyle(scale: 0.98))
            .disabled(auth.isSigningIn)

            if !auth.isConfigured {
                Text("Accounts aren't wired up on this build yet.")
                    .font(.fitBody(11))
                    .foregroundStyle(LightBoltTheme.alert)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard(radius: 22, stroke: LightBoltTheme.voltDim, fill: LightBoltTheme.obsidian)
    }

    private var benefitsBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Why bother")
            VStack(spacing: 0) {
                benefitRow("arrow.triangle.2.circlepath", "Move phones without losing your plan")
                divider
                benefitRow("creditcard.fill", "Your subscription follows your account")
                divider
                benefitRow("lock.shield.fill", "Health data still never leaves this device")
            }
            .padding(.horizontal, 16)
            .fitCard()
        }
    }

    private func benefitRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(LightBoltTheme.volt)
                .frame(width: 26)
            Text(text)
                .font(.fitBody(14))
                .foregroundStyle(LightBoltTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 15)
    }

    private var signOutBlock: some View {
        Button {
            Haptics.warning()
            isConfirmingSignOut = true
        } label: {
            HStack {
                Text("Sign out")
                    .font(.fitBody(15))
                    .foregroundStyle(LightBoltTheme.alert)
                Spacer()
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(LightBoltTheme.alert)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .fitCard()
        }
        .buttonStyle(VoltPressStyle(scale: 0.99))
    }

    private var divider: some View {
        Rectangle().fill(LightBoltTheme.hairline).frame(height: 1)
    }

    private var footer: some View {
        Text("Sign-in is handled by Apple and Google. LightBolt receives only your name, email and a profile picture — nothing about your training is shared. Questions: thiagogarciapimentel0111@gmail.com")
            .font(.fitBody(10))
            .foregroundStyle(LightBoltTheme.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
    }
}
