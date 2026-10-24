import Foundation

public struct CognitoSessionData: Decodable {
    public let AccessToken: String
    public let RefreshToken: String?
    public let ExpiresIn: Double
}
public struct CognitoChallenge: Decodable {
    public let AuthenticationResult: CognitoSessionData?
    public let ChallengeName: String?
    public let Session: String?
    public let ChallengeParameters: [String: String]?
}
public enum CognitoLogin {
    public static let clientID = "dfulb5lau8283nlgil7ddu36i"
    public static func request(_ operation: String, body: [String: Any]) async throws -> CognitoChallenge {
        var request = URLRequest(url: URL(string: "https://cognito-idp.us-east-1.amazonaws.com/")!)
        request.httpMethod = "POST"; request.timeoutInterval = 25
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("AWSCognitoIdentityProviderService." + operation, forHTTPHeaderField: "X-Amz-Target")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RelayError.invalid("Sign-in was declined. Check your account and current authenticator code, then try again.")
        }
        return try JSONDecoder().decode(CognitoChallenge.self, from: data)
    }
    public static func begin(username: String, password: String) async throws -> CognitoChallenge {
        try await request("InitiateAuth", body: ["ClientId": clientID, "AuthFlow": "USER_PASSWORD_AUTH", "AuthParameters": ["USERNAME": username, "PASSWORD": password]])
    }
    public static func confirm(_ challenge: CognitoChallenge, username: String, code: String) async throws -> CognitoChallenge {
        guard challenge.ChallengeName == "SOFTWARE_TOKEN_MFA", let session = challenge.Session,
              code.count == 6, code.allSatisfy(\.isNumber) else { throw RelayError.invalid("Enter the current six-digit authenticator code.") }
        let user = challenge.ChallengeParameters?["USER_ID_FOR_SRP"] ?? challenge.ChallengeParameters?["USERNAME"] ?? username
        return try await request("RespondToAuthChallenge", body: ["ClientId": clientID, "ChallengeName": "SOFTWARE_TOKEN_MFA", "Session": session,
            "ChallengeResponses": ["USERNAME": user, "SOFTWARE_TOKEN_MFA_CODE": code]])
    }
}
