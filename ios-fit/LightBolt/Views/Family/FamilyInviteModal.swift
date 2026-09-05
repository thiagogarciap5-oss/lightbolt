import SwiftUI

/// Interrupts the app the next time an invited user opens LightBolt.
/// Accept links the seat and unlocks premium; Decline hands the seat straight
/// back to the owner and opens the feedback form.
struct FamilyInviteModal: View {
    @Environment(AccountService.self) private var account

    let invite: PendingInviteDTO
    let onResolved: (Bool) -> Void

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var glow = false

    var body: some View {
        ZStack {
            LightBoltTheme.backdrop

            VStack(spacing: 0) {
                Spacer(minLength: 20)
                crest
                copy
                Spacer(minLength: 20)
                actions
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .onAppear {
            Haptics.thud()
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { glow = true }
        }
    }

    // MARK: Sections

    private var crest: some View {
        ZStack {
            Circle()
                .fill(LightBoltTheme.volt.opacity(glow ? 0.18 : 0.06))
                .frame(width: 190, height: 190)
                .blur(radius: 26)

            Circle()
                .strokeBorder(LightBoltTheme.voltDim, lineWidth: 1)
                .frame(width: 150, height: 150)

            ZStack {
                Circle().fill(LightBoltTheme.volt)
                Text(String(invite.ownerUsername.prefix(1)).uppercased())
                    .font(.fitDisplay(50))
                    .foregroundStyle(.black)
            }
            .frame(width: 108, height: 108)

            Image(systemName: "person.2.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.black)
                .frame(width: 38, height: 38)
                .background(Circle().fill(LightBoltTheme.voltSoft))
                .overlay(Circle().strokeBorder(LightBoltTheme.void, lineWidth: 4))
                .offset(x: 44, y: 44)
        }
        .padding(.bottom, 34)
    }

    private var copy: some View {
        VStack(spacing: 14) {
            EyebrowText(text: "Family plan invitation", color: LightBoltTheme.voltDim)

            Text("\(invite.ownerUsername) invited you to their family plan")
                .font(.fitDisplay(38))
                .tracking(-1)
                .foregroundStyle(LightBoltTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.6)

            Text("Accept and every LightBolt feature unlocks on this phone — workouts, challenges, plate scanning, body scanning and Focus Lock. You pay nothing; their plan covers you.")
                .font(.fitBody(14))
                .foregroundStyle(LightBoltTheme.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(.fitBody(12))
                    .foregroundStyle(LightBoltTheme.alert)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: errorMessage)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            VoltButton(title: "Accept", systemImage: "bolt.fill", isBusy: isWorking) {
                respond(accept: true)
            }

            Button {
                respond(accept: false)
            } label: {
                Text("DECLINE")
                    .font(.fitTitle(15))
                    .tracking(1.4)
                    .foregroundStyle(LightBoltTheme.inkMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LightBoltTheme.charcoal)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(LightBoltTheme.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(VoltPressStyle())
            .disabled(isWorking)

            Text("Declining returns the seat to \(invite.ownerUsername) right away.")
                .font(.fitBody(11))
                .foregroundStyle(LightBoltTheme.inkFaint)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Logic

    private func respond(accept: Bool) {
        guard !isWorking else { return }
        accept ? Haptics.tap() : Haptics.tick()
        isWorking = true
        errorMessage = nil

        Task { @MainActor in
            defer { isWorking = false }
            if let error = await account.respondToInvite(invite, accept: accept) {
                errorMessage = error
                return
            }
            onResolved(accept)
        }
    }
}
