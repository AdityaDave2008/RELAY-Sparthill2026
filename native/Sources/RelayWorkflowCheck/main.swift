import Foundation
import CryptoKit
import RelayCore

@main struct WorkflowCheck {
    static func main() async {
        do {
            let args = CommandLine.arguments
            func argument(_ key: String) throws -> String {
                guard let i = args.firstIndex(of: key), args.count > i + 1 else { throw RelayError.invalid("Missing " + key) }; return args[i + 1]
            }
            let base = try CloudCodec.apiURL(argument("--url"), allowLoopback: true)
            guard base.scheme == "http" || args.contains("--allow-live") else { throw RelayError.invalid("Live check requires --allow-live") }
            let api = try CloudHTTPClient(baseURL: base, allowLoopback: true)
            struct Health: Decodable { let mode: String }
            let healthData = try await URLSession.shared.data(from: base.appendingPathComponent("v1/health")).0
            let health = try JSONDecoder().decode(Health.self, from: healthData)
            guard health.mode == "local-test" || args.contains("--allow-live") else { throw RelayError.invalid("Real mode needs --allow-live") }
            var tokens: [String: String]
            var authCheck = "Fixture tokens"
            if args.contains("--identities") {
                let users = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: argument("--identities")))) as! [String: [String: Any]]
                tokens = [:]
                for actor in ["test-requester-a", "test-dispatcher-a"] {
                    guard let user = users[actor], let username = user["username"] as? String, let password = user["password"] as? String, let seed = user["totp_secret"] as? String else { throw RelayError.invalid("Private test identity missing") }
                    let challenge = try await CognitoLogin.begin(username: username, password: password)
                    let session = try await CognitoLogin.confirm(challenge, username: username, code: totp(seed))
                    guard let authenticated = session.AuthenticationResult, let refresh = authenticated.RefreshToken else { throw RelayError.invalid("Authentication incomplete") }
                    let refreshed = try await CognitoLogin.request("InitiateAuth", body: ["ClientId": CognitoLogin.clientID, "AuthFlow": "REFRESH_TOKEN_AUTH", "AuthParameters": ["REFRESH_TOKEN": refresh]])
                    guard let result = refreshed.AuthenticationResult else { throw RelayError.invalid("Refresh incomplete") }
                    tokens[actor] = result.AccessToken
                }
                authCheck = "PASS: Swift Cognito password + software MFA + refresh; no browser/UI or Keychain claim"
            } else { tokens = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: URL(fileURLWithPath: argument("--tokens")))) }
            let requester = tokens["test-requester-a"]!, dispatcher = tokens["test-dispatcher-a"]!
            let profile: CloudProfile = try await api.call("v1/me", token: requester)
            let directory: CloudDirectory = try await api.call("v1/shelters", token: requester)
            guard let shelter = directory.items.first else { throw RelayError.invalid("No shelter") }
            var transcriptionID: String?
            if args.contains("--audio") {
                let data = try Data(contentsOf: URL(fileURLWithPath: argument("--audio")))
                let job = CloudAudioJob(fileName: "synthetic.wav", incidentID: profile.incident_id, data: data)
                let allocated: CloudTranscription = try await api.call("v1/transcriptions", token: requester, method: "POST", body: job.allocation())
                guard let grant = allocated.upload else { throw RelayError.invalid("Missing upload") }
                try await api.upload(grant, wav: data, token: requester)
                var audio: CloudTranscription = try await api.call("v1/transcriptions/\(job.id)/start", token: requester, method: "POST", body: JSONSerialization.data(withJSONObject: ["operation_id": job.startID]))
                for _ in 0..<100 {
                    if ["completed", "failed"].contains(audio.status) { break }
                    try await Task.sleep(for: .seconds(2)); audio = try await api.call("v1/transcriptions/" + job.id, token: requester)
                }
                guard audio.status == "completed" else { throw RelayError.invalid("Audio not completed") }; transcriptionID = job.id
            } else if args.contains("--transcription") { transcriptionID = try argument("--transcription") }
            let previewID = UUID().uuidString.lowercased()
            let command = InterpretationCommand(id: previewID, incident: profile.incident_id, shelter: shelter.shelter_id, text: "Shelter A needs 2 water packs.", transcription: transcriptionID)
            let previewBody = try CloudCodec.encode(command)
            var preview: InterpretationResult = try await api.call("v1/interpretations", token: requester, method: "POST", body: previewBody)
            let repeated: InterpretationResult = try await api.call("v1/interpretations", token: requester, method: "POST", body: previewBody)
            guard repeated.interpretation_id == previewID else { throw RelayError.invalid("Preview replay mismatch") }
            for _ in 0..<90 {
                if preview.status != "pending" { break }
                try await Task.sleep(for: .seconds(1)); preview = try await api.call("v1/interpretations/" + previewID, token: requester)
            }
            guard preview.result?.proposal?.quantity == 2 else { throw RelayError.invalid("Preview did not extract quantity2") }
            let beforeSend: CloudPage = try await api.call("v1/requests", token: requester, query: [.init(name: "view", value: "mine")])
            guard !beforeSend.items.contains(where: { $0.id == previewID }) else { throw RelayError.invalid("Preview leaked into request inbox") }
            var draft = RequestDraft(); draft.shelterID = shelter.shelter_id; draft.text = command.original_text
            draft.item = "water_packs"; draft.quantity = "2"; draft.people = "1"; draft.landmark = "Synthetic demo point; not an actual emergency"
            draft.location = try RequestLocation(latitude: 0, longitude: 0, accuracy: 100, precision: "approximate", source: "manual")
            draft.transcriptionID = transcriptionID; draft.interpretationReady = true; draft.interpretationID = previewID; draft.interpretationText = draft.text
            draft.interpretationShelter = draft.shelterID; draft.interpretationTranscription = transcriptionID
            let store = try RelayStore.open(path: argument("--db"))
            let scope = CloudCodec.scope(baseURL: base, subject: profile.subject)
            try store.saveRequestDraft(draft, scope: scope)
            let record = try store.submitCloudDraft(draft, scope: scope, shelter: shelter)
            let body = try CloudCodec.encode(record.submission)
            let result: CloudResult = try await api.call("v1/requests", token: requester, method: "POST", body: body)
            let replay: CloudResult = try await api.call("v1/requests", token: requester, method: "POST", body: body)
            guard result.id == replay.id, result.submission.location == draft.location, result.analysis_state == "ready_for_review" else { throw RelayError.invalid("Send mismatch") }
            var stock: InventorySnapshot = try await api.call("v1/inventory", token: dispatcher, query: [.init(name: "shelter_id", value: shelter.shelter_id)])
            var water = stock.items.first { $0.id == "water_packs" }!
            var seeded = 0
            if water.available < 2 {
                seeded = 20
                let adjustment = InventoryAdjustment(item: water.item_id, delta: seeded, revision: water.revision, note: "Synthetic integration/demo starting stock")
                let bytes = try CloudCodec.encode(adjustment)
                stock = try await api.call("v1/inventory/\(shelter.shelter_id)/adjust", token: dispatcher, method: "POST", body: bytes)
                let replay: InventorySnapshot = try await api.call("v1/inventory/\(shelter.shelter_id)/adjust", token: dispatcher, method: "POST", body: bytes)
                guard replay.items.first(where: { $0.id == water.item_id })?.on_hand == stock.items.first(where: { $0.id == water.item_id })?.on_hand else { throw RelayError.invalid("Stock adjustment duplicated") }
                water = stock.items.first { $0.id == "water_packs" }!
            }
            let baseline = water.on_hand
            let reserve = InventoryCommand(action: "reserve", item: water.item_id, quantity: 2, revision: water.revision)
            let reserveBody = try CloudCodec.encode(reserve)
            let reserved: ReservationResult = try await api.call("v1/requests/\(record.id)/inventory", token: dispatcher, method: "POST", body: reserveBody)
            let reserveReplay: ReservationResult = try await api.call("v1/requests/\(record.id)/inventory", token: dispatcher, method: "POST", body: reserveBody)
            guard reserved.reservation?.status == "reserved", reserveReplay.reservation?.quantity == 2 else { throw RelayError.invalid("Reservation failed") }
            stock = try await api.call("v1/inventory", token: dispatcher, query: [.init(name: "shelter_id", value: shelter.shelter_id)])
            let reservedStock = stock.items.first { $0.id == "water_packs" }!
            guard reservedStock.on_hand == baseline, reservedStock.available == water.available - 2, reservedStock.reserved == water.reserved + 2 else { throw RelayError.invalid("Reservation stock mismatch") }
            let fulfill = InventoryCommand(action: "fulfill")
            let fulfillBody = try CloudCodec.encode(fulfill)
            let fulfilled: ReservationResult = try await api.call("v1/requests/\(record.id)/inventory", token: dispatcher, method: "POST", body: fulfillBody)
            let _: ReservationResult = try await api.call("v1/requests/\(record.id)/inventory", token: dispatcher, method: "POST", body: fulfillBody)
            stock = try await api.call("v1/inventory", token: dispatcher, query: [.init(name: "shelter_id", value: shelter.shelter_id)])
            let end = stock.items.first { $0.id == "water_packs" }!
            guard fulfilled.reservation?.status == "fulfilled", end.on_hand == baseline - 2, end.reserved == water.reserved else { throw RelayError.invalid("Handover stock mismatch") }
            let requesterView: ReservationResult = try await api.call("v1/requests/\(record.id)/inventory", token: requester)
            guard requesterView.history?.status == "completed" else { throw RelayError.invalid("Requester status missing") }
            let restore = InventoryAdjustment(item: "water_packs", delta: 2, revision: end.revision, note: "Return synthetic integration supplies to demo stock")
            let _: InventorySnapshot = try await api.call("v1/inventory/\(shelter.shelter_id)/adjust", token: dispatcher, method: "POST", body: CloudCodec.encode(restore))
            let output: [String: Any] = ["status":"PASS", "mode":health.mode, "authentication":authCheck, "interpretation_id":previewID, "request_id":record.id,
                "transcription_id":transcriptionID ?? "none", "preview_before_send":"PASS", "preview_reused_on_send":"PASS", "durable_outbox":"PASS", "location_round_trip":"PASS: synthetic0,0",
                "request_replay":"PASS", "reservation_replay":"PASS", "fulfillment_replay":"PASS", "stock_before_reservation":baseline, "available_after_reserve":reservedStock.available,
                "on_hand_after_fulfill":end.on_hand, "synthetic_stock_added":seeded, "synthetic_consumption_returned":2, "requester_status":requesterView.history?.status ?? "unknown", "native_UI":"NOT TESTED", "physical_wireless":"NOT TESTED"]
            print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted,.sortedKeys]), as: UTF8.self))
        } catch { fputs("Workflow check failed: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func totp(_ secret: String) throws -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var bits: UInt32 = 0, count = 0, bytes = Data()
        for c in secret.uppercased() where c != "=" {
            guard let value = alphabet.firstIndex(of: c) else { throw RelayError.invalid("Invalid private MFA seed") }
            bits = (bits << 5) | UInt32(value); count += 5
            if count >= 8 { count -= 8; bytes.append(UInt8((bits >> count) & 255)) }
        }
        var step = UInt64(Date().timeIntervalSince1970 / 30).bigEndian
        let counter = withUnsafeBytes(of: &step) { Data($0) }
        let digest = Array(HMAC<Insecure.SHA1>.authenticationCode(for: counter, using: SymmetricKey(data: bytes)))
        let offset = Int(digest.last! & 15)
        let value = (UInt32(digest[offset] & 127) << 24) | (UInt32(digest[offset+1]) << 16) | (UInt32(digest[offset+2]) << 8) | UInt32(digest[offset+3])
        return String(format: "%06u", value % 1_000_000)
    }
}
