import Foundation
import SwiftUI
import AuthenticationServices
import Security
import CryptoKit
import RelayCore

struct CloudTokens: Codable {
    var access: String
    var refresh: String?
    var expires: Date
    var profile: CloudProfile?
    var refreshMethod: String?
}
@MainActor final class CloudAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let login = URL(string: "https://relay-mvp-928489693154.auth.us-east-1.amazoncognito.com")!
    static let clientID = "dfulb5lau8283nlgil7ddu36i"
    private var tokens: CloudTokens?
    private var session: ASWebAuthenticationSession?
    private var passwordChallenge: CognitoChallenge?
    private var challengeUsername = ""
    private var refreshTask: Task<String, Error>?
    var hasSession: Bool { tokens != nil }
    var cachedProfile: CloudProfile? { tokens?.profile }
    func rememberProfile(_ profile: CloudProfile) throws { if var value = tokens { value.profile = profile; try save(value) } }
    private var key: [String: Any] {
        #if os(macOS) && DEBUG
        // Ad-hoc Mac binaries have changing code requirements. Keep each build's test session separate.
        let signature = Bundle.main.bundleURL.appendingPathComponent("Contents/_CodeSignature/CodeResources")
        let build = (try? Data(contentsOf: signature)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "unsigned"
        let service = (Bundle.main.bundleIdentifier ?? "relay") + ".cloud.native.debug." + build
        #elseif os(macOS)
        let service = (Bundle.main.bundleIdentifier ?? "relay") + ".cloud.native"
        #else
        let service = (Bundle.main.bundleIdentifier ?? "relay") + ".cloud"
        #endif
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "cognito-session"]
    }
    override init() {
        super.init()
        #if DEBUG
        // USB-only developer setup for owned test phones. Never compiled into distribution builds.
        // No credentials are embedded; the one-use file is removed after import.
        if let folder = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            let file = folder.appendingPathComponent("RELAY/developer-session.json")
            if let data = try? Data(contentsOf: file), data.count <= 32_768,
               let supplied = try? JSONDecoder().decode(CloudTokens.self, from: data),
               supplied.expires > Date(), supplied.refreshMethod == "sdk", supplied.refresh != nil {
                do { try save(supplied); try FileManager.default.removeItem(at: file) }
                catch { tokens = nil }
            }
        }
        #endif
        var query = key; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data { tokens = try? JSONDecoder().decode(CloudTokens.self, from: data) }
    }
    func signOut() {
        session?.cancel(); session = nil; refreshTask?.cancel(); refreshTask = nil
        passwordChallenge = nil; challengeUsername = ""
        tokens = nil; SecItemDelete(key as CFDictionary)
    }
    private func save(_ value: CloudTokens) throws {
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = key; query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw RelayError.invalid("Could not securely save sign-in") }
        } else if status != errSecSuccess { throw RelayError.invalid("Could not update secure sign-in") }
        tokens = value
    }
    func passwordSignIn(username: String, password: String) async throws -> Bool {
        let value = try await CognitoLogin.begin(username: username, password: password)
        if let token = value.AuthenticationResult { try saveSDK(token); return true }
        guard value.ChallengeName == "SOFTWARE_TOKEN_MFA" else { throw RelayError.invalid("This account needs setup by the demo organizer before signing in.") }
        passwordChallenge = value; challengeUsername = username; return false
    }
    func confirmCode(_ code: String) async throws {
        guard let challenge = passwordChallenge else { throw RelayError.invalid("Start sign-in again.") }
        let response = try await CognitoLogin.confirm(challenge, username: challengeUsername, code: code)
        guard let token = response.AuthenticationResult else { throw RelayError.invalid("Sign-in requires additional account setup.") }
        try saveSDK(token); passwordChallenge = nil; challengeUsername = ""
    }
    private func saveSDK(_ value: CognitoSessionData) throws {
        try save(CloudTokens(access: value.AccessToken, refresh: value.RefreshToken ?? tokens?.refresh,
            expires: Date().addingTimeInterval(value.ExpiresIn), profile: nil, refreshMethod: "sdk"))
    }
    func cancelSignIn() { session?.cancel(); session = nil; passwordChallenge = nil; challengeUsername = "" }
    func signIn() async throws {
        let pkce = OAuthPKCE()
        var url = URLComponents(url: Self.login.appendingPathComponent("oauth2/authorize"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "client_id", value: Self.clientID), .init(name: "response_type", value: "code"),
                         .init(name: "redirect_uri", value: "relay://oauth/callback"), .init(name: "scope", value: "openid email"),
                         .init(name: "state", value: pkce.state), .init(name: "code_challenge_method", value: "S256"), .init(name: "code_challenge", value: pkce.challenge)]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: "relay") { callback, error in
                if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: error ?? RelayError.invalid("Sign-in cancelled")) }
            }
            session.presentationContextProvider = self; session.prefersEphemeralWebBrowserSession = true
            self.session = session
            if !session.start() { continuation.resume(throwing: RelayError.invalid("Unable to open sign-in")) }
        }
        session = nil
        let code = try pkce.code(from: callback)
        try await exchange(["grant_type": "authorization_code", "code": code, "code_verifier": pkce.verifier, "redirect_uri": "relay://oauth/callback"])
    }
    func accessToken() async throws -> String {
        guard let tokens else { throw RelayError.invalid("Sign in to use cloud services") }
        if tokens.expires.timeIntervalSinceNow > 60 { return tokens.access }
        if let task = refreshTask { return try await task.value }
        guard let refresh = tokens.refresh else { throw RelayError.invalid("Sign in again to renew your session") }
        let task = Task { @MainActor in
            if self.tokens?.refreshMethod == "sdk" {
                let response = try await CognitoLogin.request("InitiateAuth", body: ["ClientId": Self.clientID, "AuthFlow": "REFRESH_TOKEN_AUTH", "AuthParameters": ["REFRESH_TOKEN": refresh]])
                guard let result = response.AuthenticationResult else { throw RelayError.invalid("Please sign in again.") }
                let profile = self.tokens?.profile
                try self.saveSDK(result)
                if let profile { try self.rememberProfile(profile) }
            } else { try await self.exchange(["grant_type": "refresh_token", "refresh_token": refresh]) }
            guard let value = self.tokens else { throw RelayError.invalid("Sign in again") }; return value.access
        }
        refreshTask = task; defer { refreshTask = nil }
        return try await task.value
    }
    private func exchange(_ fields: [String: String]) async throws {
        var query = URLComponents(); query.queryItems = (fields.merging(["client_id": Self.clientID]) { a, _ in a }).sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: Self.login.appendingPathComponent("oauth2/token"))
        request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((query.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw RelayError.invalid("Cloud sign-in expired or was declined. Sign in again.") }
        struct Response: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double }
        let value = try JSONDecoder().decode(Response.self, from: data)
        try save(CloudTokens(access: value.access_token, refresh: value.refresh_token ?? tokens?.refresh, expires: Date().addingTimeInterval(value.expires_in), profile: tokens?.profile))
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        #else
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #endif
    }
}
