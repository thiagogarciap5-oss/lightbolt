import Foundation

nonisolated enum LightBoltBackend {
    /// Base URL of the project's Cloudflare Worker.
    static var baseURL: URL {
        let configured = Config.EXPO_PUBLIC_RORK_FUNCTIONS_URL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty, let url = URL(string: configured) { return url }
        return URL(string: "https://fit-health-tracker-backend.rork.app")!
    }
}

/// Stable per-install identifier. Used only as the key for the server-side
/// daily scan quota — it carries no personal data and never leaves our Worker.
nonisolated enum LightBoltDevice {
    private static let key = "fit.deviceId.v1"

    static var id: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key), existing.count >= 8 { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: key)
        return fresh
    }
}

nonisolated enum BackendError: LocalizedError, Sendable {
    case offline
    case server(String)
    case aiUnavailable
    /// Daily cap hit. `resetAt` is when the next slot frees up, when known.
    case quotaReached(String, resetAt: Date?)
    case decoding
    case unexpected(Int)

    var errorDescription: String? {
        switch self {
        case .offline:
            "No connection. LightBolt will retry when you're back online."
        case .server(let message):
            message
        case .aiUnavailable:
            "AI service is temporarily down, we are currently trying to fix it."
        case .quotaReached(let message, _):
            message
        case .decoding:
            "We couldn't read the response. Please try again."
        case .unexpected(let code):
            "Unexpected server response (\(code))."
        }
    }
}

// MARK: - Wire types

nonisolated struct MealAnalysisDTO: Decodable, Sendable {
    let mealName: String
    let estimatedGrams: Double
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let confidence: Double
    let items: [String]

    /// Tolerant decoding: any missing numeric collapses to a safe zero rather
    /// than throwing and locking the capture flow.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mealName = (try? container.decode(String.self, forKey: .mealName)) ?? "Logged Meal"
        estimatedGrams = (try? container.decode(Double.self, forKey: .estimatedGrams)) ?? 0
        calories = (try? container.decode(Int.self, forKey: .calories))
            ?? Int((try? container.decode(Double.self, forKey: .calories)) ?? 0)
        protein = (try? container.decode(Double.self, forKey: .protein)) ?? 0
        carbs = (try? container.decode(Double.self, forKey: .carbs)) ?? 0
        fat = (try? container.decode(Double.self, forKey: .fat)) ?? 0
        confidence = (try? container.decode(Double.self, forKey: .confidence)) ?? 0
        items = (try? container.decode([String].self, forKey: .items)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case mealName, estimatedGrams, calories, protein, carbs, fat, confidence, items
    }
}

nonisolated struct SubscriptionBootstrapDTO: Decodable, Sendable {
    let clientSecret: String
    let customerId: String
    let subscriptionId: String
    let subscriptionStatus: String?
    let ephemeralKeySecret: String?
}

nonisolated struct SubscriptionStatusDTO: Decodable, Sendable {
    let active: Bool
    let status: String
    let currentPeriodEnd: Double?
}

nonisolated struct CancelSubscriptionDTO: Decodable, Sendable {
    let cancelled: Bool
    let immediate: Bool?
    let endsAt: Double?
}

/// Bootstrap for attaching a different card (PaymentSheet in setup mode).
nonisolated struct SetupIntentDTO: Decodable, Sendable {
    let clientSecret: String
    let setupIntentId: String
    let customerId: String
    let ephemeralKeySecret: String?
}

/// The card LightBolt will bill next.
nonisolated struct CardDTO: Decodable, Sendable {
    let hasCard: Bool?
    let updated: Bool?
    let brand: String?
    let last4: String?
    let expMonth: Int?
    let expYear: Int?

    var isPresent: Bool { (hasCard ?? (last4 != nil)) && last4 != nil }

    /// "Visa •••• 4242" style label for the settings row.
    var displayLabel: String {
        guard let last4 else { return "No card on file" }
        let name = (brand ?? "card").capitalized
        return "\(name) •••• \(last4)"
    }

    var expiryLabel: String? {
        guard let expMonth, let expYear else { return nil }
        return String(format: "Expires %02d/%02d", expMonth, expYear % 100)
    }
}

// MARK: Identity, family plan, feedback

/// A LightBolt user as other members see them: username and picture only.
nonisolated struct DirectoryUserDTO: Decodable, Sendable, Identifiable, Equatable {
    let userId: String
    let username: String
    let hasAvatar: Bool
    let avatarVersion: Double

    var id: String { userId }

    /// Cache-busted so a changed picture shows up immediately.
    var avatarURL: URL? {
        guard hasAvatar else { return nil }
        var components = URLComponents(
            url: LightBoltBackend.baseURL.appendingPathComponent("profile/avatar"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "userId", value: userId),
            URLQueryItem(name: "v", value: String(Int(avatarVersion)))
        ]
        return components?.url
    }

    /// Monogram fallback that works for any alphabet.
    var monogram: String {
        guard let first = username.first else { return "?" }
        return String(first).uppercased()
    }
}

nonisolated struct FamilyInviteDTO: Decodable, Sendable, Identifiable, Equatable {
    let inviteId: String
    let createdAt: Double
    let user: DirectoryUserDTO?

    var id: String { inviteId }
}

nonisolated struct FamilyDTO: Decodable, Sendable, Equatable {
    let capacity: Int
    let seatsUsed: Int
    let members: [DirectoryUserDTO]
    let invites: [FamilyInviteDTO]

    var seatsFree: Int { max(0, capacity - seatsUsed) }
}

nonisolated struct FamilyMembershipDTO: Decodable, Sendable, Equatable {
    let ownerId: String
    let ownerUsername: String
    let joinedAt: Double?
}

nonisolated struct PendingInviteDTO: Decodable, Sendable, Equatable, Identifiable {
    let inviteId: String
    let ownerId: String
    let ownerUsername: String

    var id: String { inviteId }
}

/// Everything the app needs on launch in one round trip.
nonisolated struct AccountDTO: Decodable, Sendable, Equatable {
    let user: DirectoryUserDTO?
    let plan: String
    let subscriptionActive: Bool
    let currentPeriodEnd: Double?
    let isFamilyOwner: Bool
    let family: FamilyDTO?
    let membership: FamilyMembershipDTO?
    let pendingInvite: PendingInviteDTO?
    let hasAccess: Bool
    /// True when the Family Plan came from the test grant rather than a payment.
    let isCompPlan: Bool?
    let capacity: Int
}

nonisolated struct UsernameCheckDTO: Decodable, Sendable {
    let available: Bool
    let reason: String?
    let username: String?
}

nonisolated struct UsernameClaimDTO: Decodable, Sendable {
    let ok: Bool?
    let user: DirectoryUserDTO?
}

/// Result of registering or signing in with a username and password.
nonisolated struct AuthAccountDTO: Decodable, Sendable {
    let ok: Bool?
    let user: DirectoryUserDTO?
}

nonisolated struct UserSearchDTO: Decodable, Sendable {
    let found: Bool
    let reason: String?
    let user: DirectoryUserDTO?
    /// available · self · member · invited · invited_elsewhere · in_other_family · has_own_plan
    let status: String?
}

nonisolated struct AvatarAckDTO: Decodable, Sendable {
    let ok: Bool?
    let hasAvatar: Bool?
    let avatarVersion: Double?
}

nonisolated struct DirectoryAckDTO: Decodable, Sendable {
    let ok: Bool?
    let status: String?
    let removed: Bool?
    let emailed: Bool?
    let stored: Bool?
}

/// Result of reserving the daily body-scan slot before the on-device solve.
nonisolated struct ScanClaimDTO: Decodable, Sendable {
    let claimed: Bool
    let used: Int
    let limit: Int
    let resetAt: Double?
}

/// Live view of the server-enforced rolling 24h scan allowance.
nonisolated struct ScanQuotaDTO: Decodable, Sendable {
    let bodyUsed: Int
    let bodyLimit: Int
    let bodyResetAt: Double?
    let mealUsed: Int
    let mealLimit: Int
    let mealResetAt: Double?

    var bodyRemaining: Int { max(0, bodyLimit - bodyUsed) }
    var mealRemaining: Int { max(0, mealLimit - mealUsed) }
    var bodyResetDate: Date? { bodyResetAt.map { Date(timeIntervalSince1970: $0) } }
    var mealResetDate: Date? { mealResetAt.map { Date(timeIntervalSince1970: $0) } }
}

nonisolated private struct ServerErrorDTO: Decodable {
    let error: String?
    let aiDown: Bool?
    let quota: Bool?
    let resetAt: Double?
}

// MARK: - Client

/// Thin, dependency-free networking layer over the LightBolt Worker. All decoding
/// paths fall back gracefully so a malformed payload can never lock the UI.
nonisolated struct BackendClient: Sendable {
    static let shared = BackendClient()

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        // The heaviest request is a single meal photo; body scans never upload.
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 90
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    /// Tab 2 — low-cost 2D meal photo analysis (Gemini Flash behind the Worker).
    func analyzeMeal(imageData: Data, note: String?) async throws -> MealAnalysisDTO {
        struct Body: Encodable {
            let deviceId: String
            let imageBase64: String
            let mimeType: String
            let note: String?
        }
        let body = Body(
            deviceId: LightBoltDevice.id,
            imageBase64: imageData.base64EncodedString(),
            mimeType: "image/jpeg",
            note: note?.isEmpty == false ? note : nil
        )
        do {
            return try await post(path: "analyze-meal", body: body)
        } catch BackendError.server(let message) where message.localizedCaseInsensitiveContains("temporarily down") {
            throw BackendError.aiUnavailable
        } catch BackendError.unexpected(let code) where code == 502 || code == 503 {
            throw BackendError.aiUnavailable
        }
    }

    /// Tab 3 — reserves the single daily body-scan slot. The scan itself runs
    /// entirely on-device, so this is the only server involvement: it keeps the
    /// 24h cap authoritative instead of trusting a client the user can reinstall.
    /// Throws `.quotaReached` when today's scan is already spent.
    @discardableResult
    func claimBodyScan() async throws -> ScanClaimDTO {
        struct Body: Encodable {
            let deviceId: String
        }
        return try await post(path: "scan-quota/claim", body: Body(deviceId: LightBoltDevice.id))
    }

    /// Hands the slot back when the on-device solve couldn't produce a result.
    /// Best-effort by design — a failed refund must never surface to the user.
    func releaseBodyScan() async {
        struct Body: Encodable {
            let deviceId: String
        }
        struct Ack: Decodable {
            let released: Bool?
        }
        do {
            let _: Ack = try await post(path: "scan-quota/release", body: Body(deviceId: LightBoltDevice.id))
        } catch {
            print("[Backend] scan slot refund failed")
        }
    }

    /// Reads the authoritative remaining allowance so the UI can disable the
    /// scan buttons before the user spends a round trip discovering the cap.
    func scanQuota() async throws -> ScanQuotaDTO {
        var components = URLComponents(
            url: LightBoltBackend.baseURL.appendingPathComponent("scan-quota"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "deviceId", value: LightBoltDevice.id)]
        guard let url = components?.url else { throw BackendError.unexpected(-1) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return try await perform(request)
    }

    func createSubscription(
        customerId: String?,
        email: String?,
        plan: LightBoltPlan,
        userId: String
    ) async throws -> SubscriptionBootstrapDTO {
        struct Body: Encodable {
            let customerId: String?
            let email: String?
            let currency: String
            let amount: Int
            let plan: String
            let userId: String
        }
        let body = Body(
            customerId: customerId,
            email: email,
            currency: "usd",
            amount: plan.amountCents,
            plan: plan.rawValue,
            userId: userId
        )
        return try await post(path: "create-payment-intent", body: body)
    }

    // MARK: Identity

    /// Live uniqueness check — the same authority that later grants the name.
    func checkUsername(userId: String, username: String) async throws -> UsernameCheckDTO {
        struct Body: Encodable {
            let userId: String
            let username: String
        }
        return try await post(path: "username/check", body: Body(userId: userId, username: username))
    }

    /// Creates the account: a unique username and a password, in one call.
    /// The password is hashed server-side (PBKDF2-SHA256) and never stored here.
    func register(userId: String, username: String, password: String, authUserId: String?) async throws -> AuthAccountDTO {
        struct Body: Encodable {
            let userId: String
            let username: String
            let password: String
            let authUserId: String?
        }
        return try await post(
            path: "auth/register",
            body: Body(userId: userId, username: username, password: password, authUserId: authUserId)
        )
    }

    /// Signs back in on any device. Returns the original account id so the new
    /// install can adopt the existing identity instead of starting fresh.
    func login(username: String, password: String) async throws -> AuthAccountDTO {
        struct Body: Encodable {
            let username: String
            let password: String
        }
        return try await post(path: "auth/login", body: Body(username: username, password: password))
    }

    /// Reserves the username. Throws `.server` with a human message if taken.
    func claimUsername(userId: String, username: String, authUserId: String?) async throws -> UsernameClaimDTO {
        struct Body: Encodable {
            let userId: String
            let username: String
            let authUserId: String?
        }
        return try await post(
            path: "username/claim",
            body: Body(userId: userId, username: username, authUserId: authUserId)
        )
    }

    @discardableResult
    func uploadAvatar(userId: String, imageData: Data?) async throws -> AvatarAckDTO {
        struct Body: Encodable {
            let userId: String
            let imageBase64: String?
            let mimeType: String?
        }
        return try await post(
            path: "profile/avatar",
            body: Body(
                userId: userId,
                imageBase64: imageData?.base64EncodedString(),
                mimeType: imageData == nil ? nil : "image/jpeg"
            )
        )
    }

    /// Profile, plan, family roster and any waiting invitation in one call.
    func account(userId: String, customerId: String?) async throws -> AccountDTO {
        var items = [URLQueryItem(name: "userId", value: userId)]
        if let customerId { items.append(URLQueryItem(name: "customerId", value: customerId)) }
        return try await get(path: "account", query: items)
    }

    // MARK: Family plan

    func searchUser(username: String, requesterId: String) async throws -> UserSearchDTO {
        try await get(path: "user-search", query: [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "requesterId", value: requesterId)
        ])
    }

    @discardableResult
    func inviteToFamily(ownerId: String, targetUserId: String) async throws -> DirectoryAckDTO {
        struct Body: Encodable {
            let ownerId: String
            let targetUserId: String
        }
        return try await post(path: "family/invite", body: Body(ownerId: ownerId, targetUserId: targetUserId))
    }

    @discardableResult
    func respondToInvite(inviteId: String, userId: String, accept: Bool) async throws -> DirectoryAckDTO {
        struct Body: Encodable {
            let inviteId: String
            let userId: String
            let accept: Bool
        }
        return try await post(
            path: "family/invite/respond",
            body: Body(inviteId: inviteId, userId: userId, accept: accept)
        )
    }

    @discardableResult
    func removeFamilyMember(ownerId: String, memberId: String) async throws -> DirectoryAckDTO {
        struct Body: Encodable {
            let ownerId: String
            let memberId: String
        }
        return try await post(path: "family/remove", body: Body(ownerId: ownerId, memberId: memberId))
    }

    @discardableResult
    func leaveFamily(userId: String) async throws -> DirectoryAckDTO {
        struct Body: Encodable {
            let userId: String
        }
        return try await post(path: "family/leave", body: Body(userId: userId))
    }

    /// TEST MODE: grants (or revokes) a Family Plan with no payment behind it so
    /// the owner-only flows can be exercised end to end.
    @discardableResult
    func grantTestFamilyPlan(userId: String, revoke: Bool = false) async throws -> DirectoryAckDTO {
        struct Body: Encodable {
            let userId: String
            let revoke: Bool
        }
        return try await post(path: "testing/family-plan", body: Body(userId: userId, revoke: revoke))
    }

    /// Stops billing. Immediate by default — the user asked to stop paying, so
    /// the subscription is deleted at Stripe rather than left running to term.
    func cancelSubscription(customerId: String, atPeriodEnd: Bool = false) async throws -> CancelSubscriptionDTO {
        struct Body: Encodable {
            let customerId: String
            let atPeriodEnd: Bool
        }
        return try await post(
            path: "cancel-subscription",
            body: Body(customerId: customerId, atPeriodEnd: atPeriodEnd)
        )
    }

    /// Opens a SetupIntent so the user can attach a different card. No charge.
    func createSetupIntent(customerId: String) async throws -> SetupIntentDTO {
        struct Body: Encodable {
            let customerId: String
        }
        return try await post(path: "create-setup-intent", body: Body(customerId: customerId))
    }

    /// Promotes the newly saved card to the default for the customer and every
    /// live subscription, so the next renewal bills it.
    @discardableResult
    func updatePaymentMethod(customerId: String, setupIntentId: String) async throws -> CardDTO {
        struct Body: Encodable {
            let customerId: String
            let setupIntentId: String
        }
        return try await post(
            path: "update-payment-method",
            body: Body(customerId: customerId, setupIntentId: setupIntentId)
        )
    }

    func paymentMethod(customerId: String) async throws -> CardDTO {
        var components = URLComponents(
            url: LightBoltBackend.baseURL.appendingPathComponent("payment-method"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "customerId", value: customerId)]
        guard let url = components?.url else { throw BackendError.unexpected(-1) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return try await perform(request)
    }

    func subscriptionStatus(customerId: String) async throws -> SubscriptionStatusDTO {
        var components = URLComponents(
            url: LightBoltBackend.baseURL.appendingPathComponent("subscription-status"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "customerId", value: customerId)]
        guard let url = components?.url else { throw BackendError.unexpected(-1) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await perform(request)
    }

    // MARK: Plumbing

    private func get<Response: Decodable>(path: String, query: [URLQueryItem]) async throws -> Response {
        var components = URLComponents(
            url: LightBoltBackend.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query
        guard let url = components?.url else { throw BackendError.unexpected(-1) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return try await perform(request)
    }

    private func post<Body: Encodable, Response: Decodable>(path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: LightBoltBackend.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                throw BackendError.offline
            }
            throw BackendError.server(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw BackendError.decoding }

        if !(200..<300).contains(http.statusCode) {
            let dto = try? JSONDecoder().decode(ServerErrorDTO.self, from: data)
            let message = dto?.error ?? "Request failed (\(http.statusCode))."

            // Typed flags from the Worker so the UI can react precisely instead
            // of pattern-matching on prose.
            if dto?.quota == true {
                throw BackendError.quotaReached(message, resetAt: dto?.resetAt.map { Date(timeIntervalSince1970: $0) })
            }
            if dto?.aiDown == true { throw BackendError.aiUnavailable }
            throw BackendError.server(message)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw BackendError.decoding
        }
    }
}
