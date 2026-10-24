import Foundation

public struct SpeechStreamEvent: Codable, Equatable {
    public var type: String
    public var transcription_id: String?
    public var result_id: String?
    public var text: String?
    public var is_partial: Bool?
    public var start_time: Double?
    public var sample_rate: Int?
    public var max_seconds: Int?
    public var code: String?
    public var message: String?
    public var retryable: Bool?
    public var cached: Bool?
    public init(type: String, resultID: String? = nil, text: String? = nil, partial: Bool? = nil, start: Double? = nil) {
        self.type = type; result_id = resultID; self.text = text; is_partial = partial; start_time = start
    }
}

public struct LiveTranscript {
    private var segments: [String: SpeechStreamEvent] = [:]
    public private(set) var completed = false
    private var finalText: String?
    public init() {}
    public var text: String {
        finalText ?? segments.values.sorted { ($0.start_time ?? 0, $0.result_id ?? "") < ($1.start_time ?? 0, $1.result_id ?? "") }
            .compactMap(\.text).joined(separator: " ")
    }
    public mutating func apply(_ event: SpeechStreamEvent) throws {
        guard !completed else { return }
        guard (event.text?.count ?? 0) <= 4096 else { throw RelayError.invalid("Speech response is too large") }
        if event.type == "complete" {
            guard let text = event.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RelayError.invalid("No speech was recognized") }
            finalText = text; completed = true
        } else if event.type == "transcript" {
            guard let id = event.result_id, id.count <= 128, let partial = event.is_partial,
                  let start = event.start_time, start.isFinite, start >= 0, event.text != nil else { throw RelayError.invalid("Invalid speech segment") }
            if let old = segments[id], old.is_partial == false { return }
            segments[id] = event
            guard segments.count <= 256, text.count <= 4096 else { throw RelayError.invalid("Speech response is too large") }
            // A finalized segment is not the same as successful completion of the recording.
            _ = partial
        }
    }
}

private final class SpeechNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public actor SpeechStreamClient {
    public nonisolated let id: String
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var finished = false
    private var bytesSent = 0
    public init(id: String = UUID().uuidString.lowercased()) { self.id = id }
    public func connect(baseURL: URL, token: String, allowLoopback: Bool = false) async throws -> SpeechStreamEvent {
        guard socket == nil, UUID(uuidString: id) != nil, !token.isEmpty else { throw RelayError.invalid("Invalid speech session") }
        let base = try CloudCodec.apiURL(baseURL.absoluteString, allowLoopback: allowLoopback)
        var parts = URLComponents(url: base.appendingPathComponent("v1/speech/" + id), resolvingAgainstBaseURL: false)!
        parts.scheme = base.scheme == "https" ? "wss" : "ws"
        var request = URLRequest(url: parts.url!); request.timeoutInterval = 15
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 90
        let session = URLSession(configuration: config, delegate: SpeechNoRedirect(), delegateQueue: nil)
        self.session = session
        let socket = session.webSocketTask(with: request); socket.maximumMessageSize = 65536
        self.socket = socket; socket.resume()
        let event = try await next()
        if event.type == "error" { throw CloudHTTPError(status: 503, code: event.code ?? "speech_unavailable", message: event.message ?? "Live speech is unavailable", retryable: event.retryable ?? false) }
        guard (event.type == "ready" && event.sample_rate == 16000 && (1...60).contains(event.max_seconds ?? 0)) || event.type == "complete" else {
            throw RelayError.invalid("Speech service did not start a session")
        }
        return event
    }
    public func send(_ pcm: Data) async throws {
        guard let socket, !finished, !pcm.isEmpty, pcm.count <= 8192, pcm.count % 2 == 0,
              bytesSent + pcm.count <= 60 * 32000 else { throw RelayError.invalid("Invalid or oversized audio chunk") }
        bytesSent += pcm.count
        try await socket.send(.data(pcm))
    }
    public func finish() async throws {
        guard let socket, !finished else { return }; finished = true
        try await socket.send(.string("{\"type\":\"finish\"}"))
    }
    public func next() async throws -> SpeechStreamEvent {
        guard let socket else { throw RelayError.invalid("Speech connection is closed") }
        let value = try await socket.receive()
        let data: Data
        switch value { case .string(let text): data = Data(text.utf8); case .data(let bytes): data = bytes; @unknown default: throw RelayError.invalid("Invalid speech response") }
        guard data.count <= 65536 else { throw RelayError.invalid("Speech response is too large") }
        let event = try JSONDecoder().decode(SpeechStreamEvent.self, from: data)
        guard ["ready", "transcript", "complete", "error"].contains(event.type), (event.text?.count ?? 0) <= 4096,
              event.transcription_id == nil || event.transcription_id == id else { throw RelayError.invalid("Speech response does not match this session") }
        if ["ready", "complete"].contains(event.type), event.transcription_id != id { throw RelayError.invalid("Missing speech session identity") }
        return event
    }
    public func cancel() {
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil; finished = true
    }
}

public enum PCM16WAV {
    public static func encode(_ pcm: Data, sampleRate: UInt32 = 16000) throws -> Data {
        guard !pcm.isEmpty, pcm.count % 2 == 0, pcm.count <= 1_920_000, sampleRate == 16000 else { throw RelayError.invalid("Invalid live audio") }
        var data = Data()
        func word<T: FixedWidthInteger>(_ value: T) { var n = value.littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } }
        data.append(Data("RIFF".utf8)); word(UInt32(pcm.count + 36)); data.append(Data("WAVEfmt ".utf8))
        word(UInt32(16)); word(UInt16(1)); word(UInt16(1)); word(sampleRate); word(sampleRate * 2); word(UInt16(2)); word(UInt16(16))
        data.append(Data("data".utf8)); word(UInt32(pcm.count)); data.append(pcm); return data
    }
    public static func decode(_ wav: Data) throws -> Data {
        let bytes = [UInt8](wav)
        func number(_ offset: Int, _ size: Int) -> UInt32 { (0..<size).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) } }
        guard bytes.count >= 44, bytes.count <= 2_097_152,
              Data(bytes[0..<4]) == Data("RIFF".utf8), Data(bytes[8..<12]) == Data("WAVE".utf8),
              number(4, 4) == bytes.count - 8 else { throw RelayError.invalid("Invalid WAV file") }
        var offset = 12, validFormat = false, pcm: Data?
        while offset + 8 <= bytes.count {
            let tag = String(decoding: bytes[offset..<offset+4], as: UTF8.self), count = Int(number(offset+4, 4)); offset += 8
            guard count <= bytes.count - offset else { throw RelayError.invalid("Truncated WAV file") }
            if tag == "fmt " {
                guard count >= 16, number(offset,2) == 1, number(offset+2,2) == 1,
                      number(offset+4,4) == 16000, number(offset+14,2) == 16 else { throw RelayError.invalid("Live speech needs mono PCM16 at 16 kHz") }
                validFormat = true
            } else if tag == "data" { guard pcm == nil else { throw RelayError.invalid("Duplicate WAV data") }; pcm = Data(bytes[offset..<offset+count]) }
            offset += count + count % 2
        }
        guard validFormat, let pcm, !pcm.isEmpty, pcm.count % 2 == 0, pcm.count <= 1_920_000 else { throw RelayError.invalid("Invalid live audio") }
        return pcm
    }
}
