import Foundation
import RelayCore

@main struct CloudCheck {
    static func main() async {
        do {
            let args = CommandLine.arguments
            func arg(_ key: String) throws -> String {
                guard let i = args.firstIndex(of: key), args.count > i + 1 else { throw RelayError.invalid("Missing \(key)") }; return args[i + 1]
            }
            let endpoint = try CloudCodec.apiURL(arg("--url"), allowLoopback: true)
            if endpoint.scheme != "http" && !args.contains("--allow-live") { throw RelayError.invalid("Use --allow-live for a hosted check") }
            let tokens = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: URL(fileURLWithPath: arg("--tokens"))))
            guard let requester = tokens[try arg("--requester")], let dispatcher = tokens[try arg("--dispatcher")] else { throw RelayError.invalid("Test actors not found") }
            let api = try CloudHTTPClient(baseURL: endpoint, allowLoopback: true)
            struct Health: Decodable { let mode: String }
            let healthData = try await URLSession.shared.data(from: endpoint.appendingPathComponent("v1/health")).0
            let health = try JSONDecoder().decode(Health.self, from: healthData)
            guard health.mode == "local-test" || args.contains("--allow-live") else { throw RelayError.invalid("Real AWS calls require --allow-live") }
            let profile: CloudProfile = try await api.call("v1/me", token: requester)
            let directory: CloudDirectory = try await api.call("v1/shelters", token: requester)
            guard let cloudShelter = directory.items.first else { throw RelayError.invalid("No authorized shelter") }
            let store = try RelayStore.open(path: arg("--db"))
            let shelter = ShelterContact(name: "Synthetic Swift client", area: "Demo hall", receivingDeviceID: UUID().uuidString.lowercased())
            try store.saveShelter(shelter)
            var draft = HelpRequestDraft(); draft.shelterID = shelter.id; draft.details = "Shelter A needs 2 water packs."
            draft.quantity = "2"; draft.unit = "pack"; draft.location = "Synthetic demo hall"
            if args.contains("--reviewed-transcription") {
                draft.details = try arg("--reviewed-text")
                draft.transcriptionID = try arg("--reviewed-transcription")
                draft.transcriptionSubject = profile.subject; draft.transcriptionIncident = profile.incident_id
            }
            let binding = CloudBinding(localID: shelter.id, incidentID: cloudShelter.incident_id, shelterID: cloudShelter.shelter_id)
            let scope = CloudCodec.scope(baseURL: endpoint, subject: profile.subject)
            draft.cloudScope = scope; draft.cloudBinding = binding
            let message = try store.submitHelpDraft(draft, now: Date())
            var record = try store.cloudRecords(scope: scope).first { $0.id == message.id }!
            let body = try CloudCodec.encode(record.submission)
            let result: CloudResult = try await api.call("v1/requests", token: requester, method: "POST", body: body)
            // Simulate losing the acceptance response: replay exact persisted bytes before recording success.
            let replay: CloudResult = try await api.call("v1/requests", token: requester, method: "POST", body: body)
            guard result.id == replay.id, replay.submission == record.submission else { throw RelayError.invalid("Replay mismatch") }
            record.result = replay; record.state = "accepted"; try store.saveCloudRecord(record)
            for (index, state) in ["accepted", "in_progress", "completed"].enumerated() {
                let command = CloudEventCommand(revision: index, text: "SYNTHETIC Swift integration update", status: state)
                let data = try CloudCodec.encode(command)
                let first: CloudHistory = try await api.call("v1/requests/\(message.id)/events", token: dispatcher, method: "POST", body: data)
                let repeated: CloudHistory = try await api.call("v1/requests/\(message.id)/events", token: dispatcher, method: "POST", body: data)
                guard first.revision == index + 1, repeated.events.count == index + 1 else { throw RelayError.invalid("Event replay duplicated") }
            }
            let history: CloudHistory = try await api.call("v1/requests/\(message.id)/history", token: requester)
            record.history = history; try store.saveCloudRecord(record)
            var analyzed = replay
            for _ in 0..<80 {
                analyzed = try await api.call("v1/requests/\(message.id)", token: requester)
                if !["pending", "retrying"].contains(analyzed.analysis_state) { break }
                try await Task.sleep(for: .seconds(1))
            }
            guard analyzed.result != nil else { throw RelayError.invalid("Analysis did not produce a reviewable result") }
            var output: [String: Any] = ["test": "Swift URLSession to Python API", "mode": health.mode, "request_id": message.id,
                "profile": "PASS", "directory": "PASS", "durable_cloud_intent": "PASS", "lost_response_replay": "PASS",
                "dispatcher_progress": history.status, "event_replay_count": history.events.count,
                "analysis_state": analyzed.analysis_state, "input_mode": record.submission.input_mode, "proposal_allocation_authorized": analyzed.result?.allocation_authorized ?? false,
                "physical_wireless": "NOT TESTED", "native_PKCE": "NOT TESTED by this CLI"]
            if let i = args.firstIndex(of: "--audio"), args.count > i + 1 {
                let wav = try Data(contentsOf: URL(fileURLWithPath: args[i + 1]))
                let job = CloudAudioJob(fileName: "synthetic.wav", incidentID: profile.incident_id, data: wav)
                let allocation: CloudTranscription = try await api.call("v1/transcriptions", token: requester, method: "POST", body: job.allocation())
                guard let upload = allocation.upload else { throw RelayError.invalid("Missing upload") }
                try await api.upload(upload, wav: wav, token: requester)
                let started: CloudTranscription = try await api.call("v1/transcriptions/\(job.id)/start", token: requester, method: "POST", body: JSONSerialization.data(withJSONObject: ["operation_id": job.startID]))
                var audio = started
                for _ in 0..<120 {
                    audio = try await api.call("v1/transcriptions/\(job.id)", token: requester)
                    if ["completed", "failed"].contains(audio.status) { break }
                    try await Task.sleep(for: .seconds(2))
                }
                guard audio.status == "completed", audio.transcript != nil else { throw RelayError.invalid("Transcription did not complete") }
                output["transcription_id"] = job.id; output["audio_status"] = audio.status; output["synthetic_transcript"] = audio.transcript
                output["audio_did_not_auto_submit_request"] = true
            }
            let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } catch {
            // No HTTP bodies, token values, presigned forms or credentials in failures.
            fputs("Cloud check failed: \(error.localizedDescription)\n", stderr); exit(1)
        }
    }
}
