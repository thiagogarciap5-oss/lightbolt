import Foundation
import Observation
import UIKit

/// The two subscription shapes LightBolt sells.
nonisolated enum LightBoltPlan: String, CaseIterable, Identifiable, Sendable {
    case individual
    case family

    nonisolated var id: String { rawValue }

    var title: String {
        switch self {
        case .individual: "Solo"
        case .family: "Family Plan"
        }
    }

    var priceLabel: String {
        switch self {
        case .individual: "$19"
        case .family: "$70"
        }
    }

    var amountCents: Int {
        switch self {
        case .individual: 1_900
        case .family: 7_000
        }
    }

    var blurb: String {
        switch self {
        case .individual: "One athlete. Everything unlocked."
        case .family: "You plus 4 people. One bill."
        }
    }

    /// Seats the owner can hand out. Owner + 4 = 5 people, the plan maximum.
    static let familyMemberSeats = 4

    /// Total people covered, owner included.
    static let familyTotalPeople = familyMemberSeats + 1

    /// Marketing figure quoted on the paywall and in the plan comparison.
    /// $70 for five people versus 5 × $19 solo = 26.3% less.
    static let familyDiscountLabel = "26.3%"
}

/// Stable, device-independent account identity.
///
/// Stored in the Keychain so it survives a reinstall — the username, family
/// seat and subscription stay attached to the person, not to the install.
nonisolated enum LightBoltIdentity {
    private static let key = "fit.accountId.v1"
    private static let mirror = "fit.accountId.mirror.v1"

    static var accountId: String {
        if let existing = KeychainHelper.get(key), existing.count >= 8 { return existing }
        if let mirrored = UserDefaults.standard.string(forKey: mirror), mirrored.count >= 8 {
            KeychainHelper.set(key, value: mirrored)
            return mirrored
        }
        let fresh = UUID().uuidString
        KeychainHelper.set(key, value: fresh)
        UserDefaults.standard.set(fresh, forKey: mirror)
        return fresh
    }

    /// Takes over an existing account id after a password sign-in, so a new
    /// phone becomes the same LightBolt user instead of a stranger.
    static func adopt(_ userId: String) {
        guard userId.count >= 8 else { return }
        KeychainHelper.set(key, value: userId)
        UserDefaults.standard.set(userId, forKey: mirror)
    }
}

/// Owns the LightBolt social identity: username, profile picture, Family Plan
/// membership and the invitations that flow between users.
///
/// Health data never passes through here — this is only the thin public layer
/// that lets one person share a subscription with another.
@Observable
final class AccountService {
    private enum Key {
        static let username = "fit.username.v1"
        static let avatarVersion = "fit.avatarVersion.v1"
        static let hasAvatar = "fit.hasAvatar.v1"
    }

    /// Last snapshot from the server. `nil` until the first successful load.
    private(set) var snapshot: AccountDTO?
    private(set) var isLoading = true
    private(set) var isSyncing = false

    /// Cached locally so a cold, offline launch doesn't re-ask for a username.
    private(set) var cachedUsername: String?
    private(set) var cachedHasAvatar: Bool
    private(set) var cachedAvatarVersion: Double

    var errorMessage: String?

    /// The invitation modal that interrupts the next app open.
    var pendingInvite: PendingInviteDTO?

    private let defaults: UserDefaults
    private var entitlements: Entitlements?

    /// Not `let`: a password sign-in can adopt an existing account id.
    private(set) var accountId: String = LightBoltIdentity.accountId

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cachedUsername = defaults.string(forKey: Key.username)
        cachedHasAvatar = defaults.bool(forKey: Key.hasAvatar)
        cachedAvatarVersion = defaults.double(forKey: Key.avatarVersion)
    }

    /// Lets the service publish a family seat into the entitlement gate.
    func attach(_ entitlements: Entitlements) {
        self.entitlements = entitlements
    }

    // MARK: Derived state

    var username: String? { snapshot?.user?.username ?? cachedUsername }
    var hasUsername: Bool { (username?.isEmpty == false) }

    var isFamilyOwner: Bool { snapshot?.isFamilyOwner ?? false }
    var family: FamilyDTO? { snapshot?.family }
    var membership: FamilyMembershipDTO? { snapshot?.membership }
    var hasFamilySeat: Bool { snapshot?.membership != nil }

    var seatsUsed: Int { snapshot?.family?.seatsUsed ?? 0 }

    /// Invitable seats beside the owner. Owner + 4 = 5 people on the plan.
    var seatCapacity: Int { snapshot?.family?.capacity ?? snapshot?.capacity ?? LightBoltPlan.familyMemberSeats }

    /// The signed-in user as other members see them.
    var directoryUser: DirectoryUserDTO? {
        if let user = snapshot?.user { return user }
        guard let cachedUsername else { return nil }
        return DirectoryUserDTO(
            userId: accountId,
            username: cachedUsername,
            hasAvatar: cachedHasAvatar,
            avatarVersion: cachedAvatarVersion
        )
    }

    var avatarURL: URL? { directoryUser?.avatarURL }

    // MARK: Prep flow

    /// Creates a local-only prep account so a tester can hop from the first
    /// screen straight to the paywall. The handle is derived from the device
    /// account id and is deliberately never registered on the server — no junk
    /// rows in the user directory, and no password to remember.
    func prepareLocalAccount() {
        let handle = "prep" + String(accountId.suffix(6)).lowercased()
        cachedUsername = handle
        defaults.set(handle, forKey: Key.username)
    }

    // MARK: Loading

    /// Refreshes the whole account picture. Never throws — an offline launch
    /// keeps whatever was cached rather than locking the user out.
    func refresh(customerId: String? = nil) async {
        isSyncing = true
        defer {
            isSyncing = false
            isLoading = false
        }
        do {
            let account = try await BackendClient.shared.account(userId: accountId, customerId: customerId)
            apply(account)
        } catch {
            // Keep the cached identity; the gate must not flap on a dropped call.
        }
    }

    private func apply(_ account: AccountDTO) {
        snapshot = account
        if let user = account.user {
            cachedUsername = user.username
            cachedHasAvatar = user.hasAvatar
            cachedAvatarVersion = user.avatarVersion
            defaults.set(user.username, forKey: Key.username)
            defaults.set(user.hasAvatar, forKey: Key.hasAvatar)
            defaults.set(user.avatarVersion, forKey: Key.avatarVersion)
        }
        pendingInvite = account.pendingInvite
        entitlements?.applyFamilySeat(account.membership)
    }

    // MARK: Username

    /// Local mirror of the server rules so typing feedback is instant.
    static func localValidation(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCompatibilityMapping
        let count = trimmed.count
        if count == 0 { return "Pick a username." }
        if count < 3 { return "At least 3 characters." }
        if count > 50 { return "At most 50 characters." }
        if trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { return "No spaces — try a dot or underscore." }
        if trimmed.contains("@") { return "Usernames can't contain @." }
        return nil
    }

    /// Asks the server whether a name is free. Returns nil when it is.
    func checkUsername(_ candidate: String) async -> String? {
        if let local = Self.localValidation(candidate) { return local }
        do {
            let result = try await BackendClient.shared.checkUsername(userId: accountId, username: candidate)
            return result.available ? nil : (result.reason ?? "That username is already taken.")
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "We couldn't reach the username service."
        }
    }

    /// Reserves the username for this account. Returns nil on success.
    func claimUsername(_ candidate: String, authUserId: String?) async -> String? {
        if let local = Self.localValidation(candidate) { return local }
        do {
            let result = try await BackendClient.shared.claimUsername(
                userId: accountId,
                username: candidate,
                authUserId: authUserId
            )
            if let user = result.user {
                cachedUsername = user.username
                defaults.set(user.username, forKey: Key.username)
            }
            await refresh()
            Haptics.success()
            return nil
        } catch {
            Haptics.failure()
            return (error as? LocalizedError)?.errorDescription ?? "We couldn't save that username."
        }
    }

    // MARK: Password accounts

    /// Mirrors the server's password rule so the field can react as you type.
    static func localPasswordValidation(_ raw: String) -> String? {
        let password = raw.precomposedStringWithCompatibilityMapping
        if password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Choose a password." }
        if password.count < 8 { return "At least 8 characters." }
        if password.count > 200 { return "That password is too long." }
        return nil
    }

    /// Creates the account — username and password together. Returns nil on
    /// success, or a message to show under the failing field.
    func register(username: String, password: String, authUserId: String?) async -> String? {
        if let local = Self.localValidation(username) { return local }
        if let local = Self.localPasswordValidation(password) { return local }
        do {
            let result = try await BackendClient.shared.register(
                userId: accountId,
                username: username,
                password: password,
                authUserId: authUserId
            )
            if let user = result.user { cache(user) }
            await refresh()
            Haptics.success()
            return nil
        } catch {
            Haptics.failure()
            return (error as? LocalizedError)?.errorDescription ?? "We couldn't create that account."
        }
    }

    /// Signs in on a new device and adopts the account id the server returns,
    /// so the subscription, username and family seat all come back with it.
    func signIn(username: String, password: String) async -> String? {
        do {
            let result = try await BackendClient.shared.login(username: username, password: password)
            guard let user = result.user else { return "Check your username and password." }

            LightBoltIdentity.adopt(user.userId)
            accountId = user.userId
            cache(user)
            await refresh()
            Haptics.success()
            return nil
        } catch {
            Haptics.failure()
            return (error as? LocalizedError)?.errorDescription ?? "Check your username and password."
        }
    }

    private func cache(_ user: DirectoryUserDTO) {
        cachedUsername = user.username
        cachedHasAvatar = user.hasAvatar
        cachedAvatarVersion = user.avatarVersion
        defaults.set(user.username, forKey: Key.username)
        defaults.set(user.hasAvatar, forKey: Key.hasAvatar)
        defaults.set(user.avatarVersion, forKey: Key.avatarVersion)
    }

    // MARK: Profile picture

    /// Downsizes to a 512px square JPEG before upload — a profile picture never
    /// needs more, and it keeps the payload small on cellular.
    func uploadAvatar(_ image: UIImage) async -> String? {
        guard let data = Self.encode(image) else { return "We couldn't read that image." }
        do {
            let ack = try await BackendClient.shared.uploadAvatar(userId: accountId, imageData: data)
            cachedHasAvatar = ack.hasAvatar ?? true
            cachedAvatarVersion = ack.avatarVersion ?? Date().timeIntervalSince1970 * 1_000
            defaults.set(cachedHasAvatar, forKey: Key.hasAvatar)
            defaults.set(cachedAvatarVersion, forKey: Key.avatarVersion)
            await refresh()
            Haptics.success()
            return nil
        } catch {
            Haptics.failure()
            return (error as? LocalizedError)?.errorDescription ?? "That picture didn't upload."
        }
    }

    func removeAvatar() async -> String? {
        do {
            _ = try await BackendClient.shared.uploadAvatar(userId: accountId, imageData: nil)
            cachedHasAvatar = false
            cachedAvatarVersion = Date().timeIntervalSince1970 * 1_000
            defaults.set(false, forKey: Key.hasAvatar)
            defaults.set(cachedAvatarVersion, forKey: Key.avatarVersion)
            await refresh()
            Haptics.success()
            return nil
        } catch {
            Haptics.failure()
            return (error as? LocalizedError)?.errorDescription ?? "We couldn't remove that picture."
        }
    }

    private static func encode(_ image: UIImage) -> Data? {
        let side: CGFloat = 512
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        // Square centre crop, then resize — avatars are rendered in circles.
        let shortest = min(size.width, size.height)
        let cropRect = CGRect(
            x: (size.width - shortest) / 2,
            y: (size.height - shortest) / 2,
            width: shortest,
            height: shortest
        )
        let scaled: UIImage
        if let cgImage = image.cgImage?.cropping(to: cropRect) {
            scaled = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        } else {
            scaled = image
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let output = renderer.image { _ in
            scaled.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return output.jpegData(compressionQuality: 0.82)
    }

    // MARK: Family plan

    /// Exact-username lookup for the invite flow. Returns the failure message
    /// as text so the UI can show it inline instead of throwing.
    func searchUser(username: String) async -> (result: UserSearchDTO?, error: String?) {
        do {
            let result = try await BackendClient.shared.searchUser(username: username, requesterId: accountId)
            return (result, nil)
        } catch {
            return (nil, (error as? LocalizedError)?.errorDescription ?? "Search is unavailable right now.")
        }
    }

    func invite(_ user: DirectoryUserDTO) async -> String? {
        do {
            _ = try await BackendClient.shared.inviteToFamily(ownerId: accountId, targetUserId: user.userId)
            await refresh()
            Haptics.success()
            return nil
        } catch {
            Haptics.failure()
            return (error as? LocalizedError)?.errorDescription ?? "That invitation didn't send."
        }
    }

    func removeMember(_ userId: String) async -> String? {
        do {
            _ = try await BackendClient.shared.removeFamilyMember(ownerId: accountId, memberId: userId)
            await refresh()
            Haptics.success()
            return nil
        } catch {
            Haptics.failure()
            return (error as? LocalizedError)?.errorDescription ?? "We couldn't update your plan."
        }
    }

    func leaveFamily() async -> String? {
        do {
            _ = try await BackendClient.shared.leaveFamily(userId: accountId)
            entitlements?.applyFamilySeat(nil)
            await refresh()
            Haptics.success()
            return nil
        } catch {
            Haptics.failure()
            return (error as? LocalizedError)?.errorDescription ?? "We couldn't leave that plan."
        }
    }

    // MARK: Test mode

    /// TEST MODE: turns this account into a real Family Plan owner on the server
    /// with no payment attached, so the Family tab, invitations and the five
    /// person cap can all be walked through end to end. Returns nil on success.
    func activateTestFamilyPlan() async -> String? {
        guard Entitlements.isPaywallBypassedForTesting else { return "Test mode is switched off." }
        do {
            _ = try await BackendClient.shared.grantTestFamilyPlan(userId: accountId)
            await refresh()
            Haptics.success()
            return nil
        } catch {
            Haptics.failure()
            return (error as? LocalizedError)?.errorDescription ?? "We couldn't start the test family plan."
        }
    }

    // MARK: Invitations

    /// Accepting links the seat and unlocks premium; declining hands the seat
    /// straight back to the owner.
    func respondToInvite(_ invite: PendingInviteDTO, accept: Bool) async -> String? {
        do {
            _ = try await BackendClient.shared.respondToInvite(
                inviteId: invite.inviteId,
                userId: accountId,
                accept: accept
            )
            pendingInvite = nil
            await refresh()
            accept ? Haptics.success() : Haptics.tick()
            return nil
        } catch {
            Haptics.failure()
            return (error as? LocalizedError)?.errorDescription ?? "We couldn't record your answer."
        }
    }

    // MARK: Feedback

    /// Feedback leaves through the device's Mail app (see `FeedbackView`) —
    /// no server round trip, no external email API.
}
