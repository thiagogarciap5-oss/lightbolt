import AuthenticationServices
import CryptoKit
import Observation
import SwiftUI

/// Account creation and sign-in with Apple or Google. Tokens live in the
/// Keychain; the account exists so a subscription and profile survive a new
/// phone instead of being tied to one install.
@Observable
final class AuthManager {
    struct User: Codable, Equatable, Sendable {
        let id: String
        let email: String
        let name: String?
        let picture: String?

        var displayName: String {
            if let name, !name.isEmpty { return name }
            if !email.isEmpty { return email }
            return "LightBolt athlete"
        }

        /// Two-letter monogram for the avatar tile.
        var initials: String {
            let source = (name?.isEmpty == false ? name! : email)
            let parts = source.split(separator: " ").prefix(2)
            let letters = parts.compactMap { $0.first }.map(String.init)
            if letters.isEmpty { return "LB" }
            return letters.joined().uppercased()
        }
    }

    var user: User?
    var isLoading = true
    var isSigningIn = false
    var showError = false
    var errorMessage = ""

    private let authURL = Config.EXPO_PUBLIC_RORK_AUTH_URL
    private let appKey = Config.EXPO_PUBLIC_RORK_APP_KEY
    private let projectID = Config.EXPO_PUBLIC_PROJECT_ID
    private var codeVerifier: String?
    private var webAuthSession: ASWebAuthenticationSession?

    private var developerHint: String? {
        UserDefaults.standard.string(forKey: "RORK_DEVELOPER_HINT")
    }

    var isSignedIn: Bool { user != nil }

    /// True when the project has auth configured — used to hide the UI rather
    /// than show a button that can only fail.
    var isConfigured: Bool { !authURL.isEmpty && !appKey.isEmpty }

    init() {
        Task { await checkAuth() }
    }

    // MARK: PKCE

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private var authEnv: String {
        #if targetEnvironment(simulator)
        return "simulator"
        #else
        return "native"
        #endif
    }

    /// Decodes the locally stored JWT to recover the profile and check expiry.
    private func userFromToken(_ token: String) -> User? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }

        guard let data = Data(base64Encoded: base64) else { return nil }

        struct JWTPayload: Codable {
            let sub: String
            let email: String?
            let name: String?
            let picture: String?
            let exp: TimeInterval?
        }

        guard let payload = try? JSONDecoder().decode(JWTPayload.self, from: data) else { return nil }
        if let exp = payload.exp, Date(timeIntervalSince1970: exp) < Date() { return nil }

        return User(id: payload.sub, email: payload.email ?? "", name: payload.name, picture: payload.picture)
    }

    private func storedRefreshToken() -> String? {
        #if targetEnvironment(simulator)
        if let injected = UserDefaults.standard.string(forKey: "RORK_AUTH_REFRESH_TOKEN") {
            return injected
        }
        #endif
        return KeychainHelper.get("refresh_token")
    }

    // MARK: Lifecycle

    func checkAuth() async {
        defer { isLoading = false }
        guard isConfigured else { return }

        if let accessToken = KeychainHelper.get("access_token"),
           let user = userFromToken(accessToken) {
            self.user = user
            return
        }
        if storedRefreshToken() != nil {
            await refreshToken()
        }
    }

    func signIn(provider: String) async {
        guard isConfigured else {
            setError("Accounts aren't configured for this build yet.")
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let verifier = generateCodeVerifier()
            let challenge = generateCodeChallenge(from: verifier)
            codeVerifier = verifier

            guard let url = URL(string: "\(authURL)/oauth/initiate") else {
                setError("Sign in is unavailable right now.")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var initiateBody: [String: String] = [
                "app_key": appKey,
                "provider": provider,
                "code_challenge": challenge,
                "target": "swift",
                "env": authEnv
            ]
            if authEnv == "simulator", let hint = developerHint {
                initiateBody["developer_hint"] = hint
            }
            request.httpBody = try JSONEncoder().encode(initiateBody)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if let failure = try? JSONDecoder().decode(AuthErrorResponse.self, from: data) {
                    setError(failure.error)
                } else {
                    setError("Sign in failed (\(status)).")
                }
                return
            }
            let initiate = try JSONDecoder().decode(AuthInitiateResponse.self, from: data)

            let code: String
            if initiate.flow == "popup" {
                do {
                    code = try await pollForCode(state: initiate.state)
                } catch AuthError.cancelledByUser {
                    code = try await runWebAuthSession(authURL: initiate.auth_url)
                }
            } else {
                code = try await runWebAuthSession(authURL: initiate.auth_url)
            }

            await exchangeCode(code)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            setError(error.localizedDescription)
        }
    }

    private func pollForCode(state: String) async throws -> String {
        guard let url = URL(string: "\(authURL)/oauth/poll-code") else { throw AuthError.invalidURL }

        let deadline = Date().addingTimeInterval(5 * 60)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(1_500))

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["app_key": appKey, "state": state])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            guard let poll = try? JSONDecoder().decode(AuthPollResponse.self, from: data) else { continue }

            if poll.status == "cancelled" { throw AuthError.cancelledByUser }
            if poll.status == "ready", let code = poll.code { return code }
        }
        throw AuthError.popupTimeout
    }

    private func runWebAuthSession(authURL authURLString: String) async throws -> String {
        let callbackScheme = "rork-\(projectID)"
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            guard let url = URL(string: authURLString) else {
                continuation.resume(throwing: AuthError.invalidURL)
                return
            }

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                self?.webAuthSession = nil

                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url = callbackURL,
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: AuthError.noCode)
                    return
                }
                continuation.resume(returning: code)
            }

            self.webAuthSession = session
            session.presentationContextProvider = WebAuthPresentationContext.shared
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    private func exchangeCode(_ code: String) async {
        guard let verifier = codeVerifier else { return }
        codeVerifier = nil

        guard let url = URL(string: "\(authURL)/oauth/token") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode([
            "app_key": appKey,
            "code": code,
            "code_verifier": verifier
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if let failure = try? JSONDecoder().decode(AuthErrorResponse.self, from: data) {
                    setError(failure.error)
                } else {
                    setError("Sign in failed (\(status)).")
                }
                return
            }
            let tokens = try JSONDecoder().decode(AuthTokenResponse.self, from: data)

            KeychainHelper.set("access_token", value: tokens.access_token)
            KeychainHelper.set("refresh_token", value: tokens.refresh_token)

            user = tokens.user
            Haptics.success()
        } catch {
            setError("Sign in failed: \(error.localizedDescription)")
        }
    }

    private func refreshToken() async {
        guard let refresh = storedRefreshToken() else {
            user = nil
            return
        }
        guard let url = URL(string: "\(authURL)/oauth/refresh") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode([
            "app_key": appKey,
            "refresh_token": refresh
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                await signOut()
                return
            }
            let refreshed = try JSONDecoder().decode(AuthRefreshResponse.self, from: data)
            KeychainHelper.set("access_token", value: refreshed.access_token)
            user = userFromToken(refreshed.access_token)
        } catch {
            await signOut()
        }
    }

    func signOut() async {
        KeychainHelper.delete("access_token")
        KeychainHelper.delete("refresh_token")
        UserDefaults.standard.removeObject(forKey: "RORK_AUTH_REFRESH_TOKEN")
        user = nil
    }

    private func setError(_ message: String) {
        errorMessage = message
        showError = true
        Haptics.failure()
    }
}

// MARK: - Wire types

nonisolated private struct AuthInitiateResponse: Codable {
    let auth_url: String
    let state: String
    let flow: String?
}

nonisolated private struct AuthPollResponse: Codable {
    let status: String
    let code: String?
}

nonisolated private struct AuthTokenResponse: Codable {
    let access_token: String
    let refresh_token: String
    let user: AuthManager.User
}

nonisolated private struct AuthRefreshResponse: Codable {
    let access_token: String
    let expires_in: Int
}

nonisolated private struct AuthErrorResponse: Codable {
    let error: String
}

nonisolated enum AuthError: LocalizedError {
    case noCode
    case invalidURL
    case serverError(statusCode: Int)
    case popupTimeout
    case cancelledByUser

    var errorDescription: String? {
        switch self {
        case .noCode: "No authorization code was returned."
        case .invalidURL: "Sign in is unavailable right now."
        case .serverError(let code): "Server error (\(code))."
        case .popupTimeout: "Sign-in timed out — please try again."
        case .cancelledByUser: "Sign-in cancelled."
        }
    }
}

final class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
