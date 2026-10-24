import Foundation
import CryptoKit

public struct CloudHTTPError: Error, LocalizedError {
    public let status: Int
    public let code: String
    public let message: String
    public let retryable: Bool
    public var errorDescription: String? { message }
}
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
public final class CloudHTTPClient {
    public let baseURL: URL
    private let session: URLSession
    private let allowLoopback: Bool
    public init(baseURL: URL, allowLoopback: Bool = false, session: URLSession? = nil) throws {
        self.baseURL = try CloudCodec.apiURL(baseURL.absoluteString, allowLoopback: allowLoopback)
        self.allowLoopback = allowLoopback
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 60
        self.session = session ?? URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }
    public func call<T: Decodable>(_ path: String, token: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = []) async throws -> T {
        guard !path.contains(".."), !path.hasPrefix("/"), !token.isEmpty else { throw RelayError.invalid("Invalid API request") }
        var parts = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query }
        var request = URLRequest(url: parts.url!)
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let data = try await send(request)
        return try CloudCodec.decode(T.self, data)
    }
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count <= 2_097_152 else { throw RelayError.invalid("Invalid or oversized cloud response") }
        if !(200..<300).contains(http.statusCode) {
            struct Envelope: Decodable { let error: CloudErrorDetail }
            let error = try? CloudCodec.decode(Envelope.self, data).error
            throw CloudHTTPError(status: http.statusCode, code: error?.code ?? "http_\(http.statusCode)",
                                 message: error?.message ?? "Cloud request failed (\(http.statusCode)).",
                                 retryable: error?.retryable ?? ([408, 425, 429].contains(http.statusCode) || http.statusCode >= 500))
        }
        return data
    }
    public func upload(_ grant: CloudUpload, wav: Data, token: String) async throws {
        let url = try CloudCodec.apiURL(grant.url, allowLoopback: allowLoopback)
        var request = URLRequest(url: url); request.httpMethod = grant.method
        if grant.requires_bearer_token {
            guard allowLoopback, url.scheme == "http", url.host == baseURL.host, url.port == baseURL.port, grant.method == "PUT" else { throw RelayError.invalid("Refused token forwarding to an upload host") }
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.httpBody = wav; request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        } else {
            guard grant.method == "POST", url.scheme == "https" else { throw RelayError.invalid("Unsupported upload grant") }
            let boundary = "relay-" + UUID().uuidString
            var body = Data()
            func append(_ text: String) { body.append(Data(text.utf8)) }
            for (key, value) in grant.fields.sorted(by: { $0.key < $1.key }) {
                guard !key.contains("\""), !key.contains("\r"), !key.contains("\n") else { throw RelayError.invalid("Invalid upload field") }
                append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")
            }
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
            body.append(wav); append("\r\n--\(boundary)--\r\n")
            request.httpBody = body
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        }
        _ = try await send(request)
    }
}
public struct CloudUpload: Codable {
    public let method: String; public let url: String; public let fields: [String: String]
    public let requires_bearer_token: Bool
}
public struct CloudTranscription: Codable {
    public let transcription_id: String; public let status: String; public let transcript: String?
    public let error: CloudErrorDetail?; public let upload: CloudUpload?
}
public struct CloudAudioJob: Codable {
    public let id: String
    public let allocationID: String
    public let startID: String
    public let incidentID: String
    public let fileName: String
    public let sha256: String
    public let byteLength: Int
    public var transcript: String?
    public var source: String?
    public init(fileName: String, incidentID: String, data: Data, id: String? = nil, source: String? = nil) {
        self.source = source
        self.id = id ?? UUID().uuidString.lowercased(); allocationID = UUID().uuidString.lowercased(); startID = UUID().uuidString.lowercased()
        self.fileName = fileName; self.incidentID = incidentID; byteLength = data.count
        sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public func allocation() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schema_version": 1, "operation_id": allocationID,
            "transcription_id": id, "incident_id": incidentID, "content_type": "audio/wav",
            "byte_length": byteLength, "sha256": sha256, "language_code": "en-US"], options: [.sortedKeys])
    }
}
public struct OAuthPKCE {
    public let verifier: String
    public let state: String
    public init() {
        verifier = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        state = UUID().uuidString
    }
    public var challenge: String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    public func code(from url: URL) throws -> String {
        guard url.scheme == "relay", url.host == "oauth", url.path == "/callback", url.fragment == nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state,
              items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty,
              !items.contains(where: { $0.name == "error" }) else { throw RelayError.invalid("Sign-in callback could not be verified") }
        return code
    }
}
