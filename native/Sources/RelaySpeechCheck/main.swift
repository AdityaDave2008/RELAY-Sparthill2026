import Foundation
import RelayCore

@main struct RelaySpeechCheck {
    static func main() async {
        let args = CommandLine.arguments
        func option(_ key: String) throws -> String {
            guard let at = args.firstIndex(of: key), at + 1 < args.count else { throw RelayError.invalid("Supply --base-url, --session-file, --wav and --output. Synthetic audio only.") }
            return args[at + 1]
        }
        var evidence: [String: Any] = ["scope": "Native Swift WebSocket client with synthetic WAV chunks; not microphone or physical wireless verification"]
        var client: SpeechStreamClient?
        do {
            let base = try CloudCodec.apiURL(option("--base-url"), allowLoopback: true)
            let login = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: option("--session-file")))) as! [String: Any]
            var token = login["access"] as! String
            if let expires = login["expires"] as? Double, expires + 978307200 < Date().timeIntervalSince1970 + 60, let refresh = login["refresh"] as? String {
                let response = try await CognitoLogin.request("InitiateAuth", body: ["ClientId": "dfulb5lau8283nlgil7ddu36i", "AuthFlow": "REFRESH_TOKEN_AUTH", "AuthParameters": ["REFRESH_TOKEN": refresh]])
                guard let session = response.AuthenticationResult else { throw RelayError.invalid("Session refresh failed") }
                token = session.AccessToken
            }
            let pcm = try PCM16WAV.decode(Data(contentsOf: URL(fileURLWithPath: option("--wav"))))
            guard pcm.count <= 15 * 32000 else { throw RelayError.invalid("This smoke test only accepts up to 15 seconds of synthetic audio") }
            let active = SpeechStreamClient(); client = active
            let start = ContinuousClock.now
            func elapsed() -> Int { let d = start.duration(to: .now).components; return Int(d.seconds * 1000 + d.attoseconds / 1_000_000_000_000_000) }
            let timeout = Task { try? await Task.sleep(for: .seconds(35)); if !Task.isCancelled { await active.cancel() } }
            defer { timeout.cancel() }
            let ready = try await active.connect(baseURL: base, token: token, allowLoopback: true)
            guard ready.type == "ready" else { throw RelayError.invalid("Unexpected cached test session") }
            evidence["ready_ms"] = elapsed(); evidence["transcription_id"] = active.id; evidence["audio_seconds"] = Double(pcm.count) / 32000
            let feed = Task {
                for offset in stride(from: 0, to: pcm.count, by: 3200) {
                    try await active.send(pcm.subdata(in: offset..<min(pcm.count, offset + 3200)))
                    try await Task.sleep(for: .milliseconds(100))
                }
                try await active.finish()
            }
            var transcript = LiveTranscript(), events: [[String: Any]] = []
            while !transcript.completed {
                let event = try await active.next()
                if event.type == "error" { throw RelayError.invalid(event.message ?? "Streaming failed") }
                try transcript.apply(event)
                events.append(["type": event.type, "partial": event.is_partial as Any? ?? NSNull(), "elapsed_ms": elapsed(), "text": event.text ?? ""])
            }
            try await feed.value
            await active.cancel()
            let http = try CloudHTTPClient(baseURL: base, allowLoopback: true)
            let saved: CloudTranscription = try await http.call("v1/transcriptions/" + active.id, token: token)
            guard saved.status == "completed", saved.transcript == transcript.text else { throw RelayError.invalid("Final transcript was not durable") }
            let replay = SpeechStreamClient(id: active.id)
            let cached = try await replay.connect(baseURL: base, token: token, allowLoopback: true)
            await replay.cancel()
            guard cached.type == "complete", cached.cached == true, cached.text == transcript.text else { throw RelayError.invalid("Completed transcript replay failed") }
            evidence["events"] = events; evidence["transcript"] = transcript.text; evidence["durable_result"] = "PASS"; evidence["replay_without_new_AWS_stream"] = "PASS"; evidence["status"] = "PASS"
        } catch {
            evidence["status"] = "FAIL"; evidence["error_type"] = String(describing: type(of: error)); evidence["message"] = error.localizedDescription
        }
        await client?.cancel()
        let data = try! JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
        if let path = try? option("--output") { try? data.write(to: URL(fileURLWithPath: path)) }
        print(String(decoding: data, as: UTF8.self))
        if evidence["status"] as? String != "PASS" { exit(1) }
    }
}
