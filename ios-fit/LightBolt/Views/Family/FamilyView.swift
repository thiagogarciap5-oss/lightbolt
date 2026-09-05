import SwiftUI

/// Family Plan management, visible only to the billing owner of an active
/// Family Plan. Search a username, tap +, and a seat is offered.
struct FamilyView: View {
    @Environment(AccountService.self) private var account

    @State private var query: String = ""
    @State private var searchState: SearchState = .idle
    @State private var isInviting = false
    @State private var banner: Banner?
    @State private var confirmRemoval: DirectoryUserDTO?
    @FocusState private var isSearchFocused: Bool

    private enum SearchState: Equatable {
        case idle
        case searching
        case miss(String)
        case hit(DirectoryUserDTO, status: String)
    }

    private struct Banner: Equatable {
        let text: String
        let isError: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                seatMeter
                searchBlock
                rosterBlock
                footnote
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(LightBoltTheme.backdrop)
        .refreshable { await account.refresh() }
        .task(id: query) { await runSearch() }
        .alert(
            "Remove \(confirmRemoval?.username ?? "member")?",
            isPresented: Binding(get: { confirmRemoval != nil }, set: { if !$0 { confirmRemoval = nil } })
        ) {
            Button("Keep them", role: .cancel) { confirmRemoval = nil }
            Button("Remove", role: .destructive) {
                if let target = confirmRemoval { remove(target) }
                confirmRemoval = nil
            }
        } message: {
            Text("They lose LightBolt access straight away and the seat returns to your plan.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            EyebrowText(text: "Family plan", color: LightBoltTheme.voltDim)
            Text("FAMILY PLAN")
                .font(.fitDisplay(46))
                .tracking(-1.6)
                .foregroundStyle(LightBoltTheme.ink)
            Text("USERS")
                .font(.fitDisplay(46))
                .tracking(-1.6)
                .voltWash()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    /// Five-slot seat strip: the owner plus four invitable seats.
    private var seatMeter: some View {
        let capacity = account.seatCapacity
        let used = account.seatsUsed

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(used + 1)")
                    .font(.fitNumeric(38))
                    .voltWash()
                    .contentTransition(.numericText())
                Text("of \(capacity + 1) people")
                    .font(.fitBody(14))
                    .foregroundStyle(LightBoltTheme.inkMuted)
                Spacer()
                Text(used >= capacity ? "FULL" : "\(capacity - used) FREE")
                    .font(.fitLabel(10))
                    .tracking(1.6)
                    .foregroundStyle(used >= capacity ? LightBoltTheme.alert : LightBoltTheme.volt)
            }

            HStack(spacing: 6) {
                ForEach(0...capacity, id: \.self) { index in
                    Capsule()
                        .fill(index <= used ? LightBoltTheme.volt : LightBoltTheme.charcoalHigh)
                        .frame(height: 6)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: used)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitCard(radius: 22, stroke: LightBoltTheme.voltDim, fill: LightBoltTheme.obsidian)
    }

    // MARK: Search + invite

    private var searchBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Add a member")

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(LightBoltTheme.inkFaint)

                TextField(
                    "",
                    text: $query,
                    prompt: Text("Search exact username").foregroundStyle(LightBoltTheme.inkFaint)
                )
                .font(.fitBody(15))
                .foregroundStyle(LightBoltTheme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)

                if !query.isEmpty {
                    Button {
                        Haptics.tick()
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(LightBoltTheme.inkFaint)
                    }
                    .buttonStyle(VoltPressStyle(scale: 0.86))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .fitCard(radius: 17, fill: LightBoltTheme.obsidian)

            searchResult

            if let banner {
                Text(banner.text)
                    .font(.fitBody(12))
                    .foregroundStyle(banner.isError ? LightBoltTheme.alert : LightBoltTheme.volt)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: searchState)
        .animation(.easeOut(duration: 0.22), value: banner)
    }

    @ViewBuilder
    private var searchResult: some View {
        switch searchState {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: 10) {
                RunningWaveLoader(barCount: 4, height: 14)
                Text("Looking up @\(query)…")
                    .font(.fitBody(12))
                    .foregroundStyle(LightBoltTheme.inkMuted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        case .miss(let reason):
            HStack(spacing: 10) {
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LightBoltTheme.inkFaint)
                Text(reason)
                    .font(.fitBody(13))
                    .foregroundStyle(LightBoltTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(16)
            .fitCard(radius: 18)
        case .hit(let user, let status):
            resultRow(user, status: status)
        }
    }

    private func resultRow(_ user: DirectoryUserDTO, status: String) -> some View {
        HStack(spacing: 13) {
            AvatarBubble(user: user, size: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.username)
                    .font(.fitTitle(17))
                    .foregroundStyle(LightBoltTheme.ink)
                    .lineLimit(1)
                Text(statusBlurb(status))
                    .font(.fitBody(11))
                    .foregroundStyle(canInvite(status) ? LightBoltTheme.volt : LightBoltTheme.inkMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)

            if canInvite(status) {
                Button {
                    invite(user)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LightBoltTheme.volt)
                        if isInviting {
                            RunningWaveLoader(barCount: 3, height: 14, tint: .black)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 19, weight: .black))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(width: 48, height: 48)
                }
                .buttonStyle(VoltPressStyle(scale: 0.9))
                .disabled(isInviting || account.seatsUsed >= account.seatCapacity)
                .opacity(account.seatsUsed >= account.seatCapacity ? 0.4 : 1)
                .accessibilityLabel("Invite \(user.username)")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(LightBoltTheme.inkFaint)
            }
        }
        .padding(14)
        .fitCard(radius: 20, stroke: canInvite(status) ? LightBoltTheme.voltDim : LightBoltTheme.hairline)
    }

    private func canInvite(_ status: String) -> Bool { status == "available" }

    private func statusBlurb(_ status: String) -> String {
        switch status {
        case "available": "Free to join your plan"
        case "self": "That's you"
        case "member": "Already on your plan"
        case "invited": "You've already invited them"
        case "invited_elsewhere": "They have another invitation pending"
        case "in_other_family": "Already on someone else's family plan"
        case "has_own_plan": "They already pay for their own plan"
        default: "Unavailable"
        }
    }

    // MARK: Roster

    private var rosterBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "On your plan")

            VStack(spacing: 10) {
                ownerRow

                ForEach(account.family?.members ?? []) { member in
                    memberRow(member)
                }

                ForEach(account.family?.invites ?? []) { invite in
                    if let user = invite.user { inviteRow(user, inviteId: invite.inviteId) }
                }

                if (account.family?.members.isEmpty ?? true), (account.family?.invites.isEmpty ?? true) {
                    emptySeats
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: account.family)
        }
    }

    private var ownerRow: some View {
        HStack(spacing: 13) {
            if let me = account.directoryUser {
                AvatarBubble(user: me, size: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(account.username ?? "You")
                    .font(.fitTitle(16))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                Text("Plan owner · billed $70/month")
                    .font(.fitBody(11))
                    .foregroundStyle(.black.opacity(0.65))
            }
            Spacer(minLength: 0)
            Image(systemName: "crown.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.black)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(
                    colors: [LightBoltTheme.volt, LightBoltTheme.voltSoft],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
    }

    private func memberRow(_ user: DirectoryUserDTO) -> some View {
        HStack(spacing: 13) {
            AvatarBubble(user: user, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.username)
                    .font(.fitTitle(16))
                    .foregroundStyle(LightBoltTheme.ink)
                    .lineLimit(1)
                Text("Member · full access")
                    .font(.fitBody(11))
                    .foregroundStyle(LightBoltTheme.volt)
            }
            Spacer(minLength: 0)
            Button {
                Haptics.warning()
                confirmRemoval = user
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(LightBoltTheme.alert)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(LightBoltTheme.charcoalHigh))
            }
            .buttonStyle(VoltPressStyle(scale: 0.9))
            .accessibilityLabel("Remove \(user.username)")
        }
        .padding(13)
        .fitCard(radius: 20)
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    private func inviteRow(_ user: DirectoryUserDTO, inviteId: String) -> some View {
        HStack(spacing: 13) {
            AvatarBubble(user: user, size: 44, isDimmed: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(user.username)
                    .font(.fitTitle(16))
                    .foregroundStyle(LightBoltTheme.inkMuted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    PulsingDot()
                    Text("Invitation sent · awaiting their answer")
                        .font(.fitBody(11))
                        .foregroundStyle(LightBoltTheme.inkFaint)
                }
            }
            Spacer(minLength: 0)
            Button {
                Haptics.tick()
                remove(user)
            } label: {
                Text("CANCEL")
                    .font(.fitLabel(10))
                    .tracking(1.2)
                    .foregroundStyle(LightBoltTheme.inkMuted)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Capsule().fill(LightBoltTheme.charcoalHigh))
            }
            .buttonStyle(VoltPressStyle(scale: 0.94))
        }
        .padding(13)
        .fitCard(radius: 20, stroke: LightBoltTheme.hairline, fill: LightBoltTheme.obsidian)
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    private var emptySeats: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(LightBoltTheme.voltDim)
            Text("No one yet")
                .font(.fitTitle(17))
                .foregroundStyle(LightBoltTheme.ink)
            Text("Search a username above and tap + to offer one of your \(account.seatCapacity) member seats.")
                .font(.fitBody(12))
                .foregroundStyle(LightBoltTheme.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity)
        .fitCard(radius: 20)
    }

    private var footnote: some View {
        Text("Members get every LightBolt feature on their own device — their workouts, meals and body scans stay private to them. You can remove anyone at any time. The daily scan caps apply per person.")
            .font(.fitBody(11))
            .foregroundStyle(LightBoltTheme.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Actions

    private func runSearch() async {
        let candidate = query.trimmingCharacters(in: .whitespacesAndNewlines)
        banner = nil

        guard !candidate.isEmpty else {
            searchState = .idle
            return
        }
        if let local = AccountService.localValidation(candidate) {
            searchState = .miss(local)
            return
        }

        searchState = .searching
        try? await Task.sleep(for: .milliseconds(400))
        if Task.isCancelled { return }

        let lookup = await account.searchUser(username: candidate)
        if Task.isCancelled { return }

        if let message = lookup.error {
            searchState = .miss(message)
            return
        }
        guard let result = lookup.result else {
            searchState = .miss("No LightBolt user with that username.")
            return
        }
        if let user = result.user, result.found {
            searchState = .hit(user, status: result.status ?? "available")
            Haptics.tick()
        } else {
            searchState = .miss(result.reason ?? "No LightBolt user with that username.")
        }
    }

    private func invite(_ user: DirectoryUserDTO) {
        guard !isInviting else { return }
        Haptics.tap()
        isInviting = true
        Task { @MainActor in
            defer { isInviting = false }
            if let error = await account.invite(user) {
                banner = Banner(text: error, isError: true)
            } else {
                banner = Banner(text: "Invitation sent to \(user.username). They'll see it next time they open LightBolt.", isError: false)
                query = ""
                searchState = .idle
                isSearchFocused = false
            }
        }
    }

    private func remove(_ user: DirectoryUserDTO) {
        Task { @MainActor in
            if let error = await account.removeMember(user.userId) {
                banner = Banner(text: error, isError: true)
            }
        }
    }
}

// MARK: - Shared pieces

/// Circular avatar with a volt monogram fallback. Works with any alphabet.
struct AvatarBubble: View {
    let user: DirectoryUserDTO
    var size: CGFloat = 44
    var isDimmed: Bool = false

    var body: some View {
        ZStack {
            Circle().fill(isDimmed ? LightBoltTheme.charcoalHigh : LightBoltTheme.volt)

            if let url = user.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        monogram
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(isDimmed ? LightBoltTheme.hairline : Color.clear, lineWidth: 1)
        )
    }

    private var monogram: some View {
        Text(user.monogram)
            .font(.fitDisplay(size * 0.44))
            .foregroundStyle(isDimmed ? LightBoltTheme.inkMuted : .black)
    }
}

/// Slow volt heartbeat used to mark "waiting on someone else".
struct PulsingDot: View {
    @State private var isOn = false

    var body: some View {
        Circle()
            .fill(LightBoltTheme.volt)
            .frame(width: 6, height: 6)
            .opacity(isOn ? 1 : 0.25)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { isOn = true }
            }
    }
}
