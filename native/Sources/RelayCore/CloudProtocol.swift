import Foundation
import CryptoKit

public struct CloudProfile: Codable, Equatable {
    public let subject: String
    public let role: String
    public let incident_id: String
    public let shelter_ids: [String]
}
public struct CloudShelter: Codable, Identifiable, Equatable {
    public let shelter_id: String
    public let incident_id: String
    public let display_name: String
    public var receiver: ShelterReceiver? = nil
    public var details: ShelterDetails? = nil
    public init(shelter_id: String, incident_id: String, display_name: String, receiver: ShelterReceiver? = nil) {
        self.shelter_id = shelter_id; self.incident_id = incident_id; self.display_name = display_name; self.receiver = receiver
    }
    public var id: String { incident_id + ":" + shelter_id }
}
public struct CloudDirectory: Codable { public let items: [CloudShelter] }
public struct CloudBinding: Codable, Equatable {
    public let localID: String
    public let incidentID: String
    public let shelterID: String
    public init(localID: String, incidentID: String, shelterID: String) {
        self.localID = localID; self.incidentID = incidentID; self.shelterID = shelterID
    }
}
public struct CloudSubmission: Codable, Equatable {
    public var schema_version = 1
    public let operation_id: String
    public let request_id: String
    public let incident_id: String
    public let destination_shelter_id: String
    public let origin_device_id: String
    public let original_text: String
    public let input_mode: String
    public let transcription_id: String?
    public let created_at: Date
    public let expires_at: Date
    public var revision = 1
    public var location: RequestLocation?
    public var structured_fields: RequestFields?
    public var interpretation_id: String?
    public var requester_details: SharedResidentDetails?
    public init(draft: RequestDraft, shelter: CloudShelter, deviceID: String, now: Date = Date()) throws {
        guard UUID(uuidString: draft.id) != nil, UUID(uuidString: deviceID) != nil,
              draft.shelterID == shelter.shelter_id, !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.text.count <= 4096 else { throw RelayError.invalid("Choose a shelter and describe your request.") }
        try draft.location?.validate()
        try draft.requesterDetails?.validate()
        requester_details = draft.requesterDetails
        operation_id = draft.id; request_id = draft.id; incident_id = shelter.incident_id
        destination_shelter_id = shelter.shelter_id; origin_device_id = deviceID
        original_text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        transcription_id = draft.transcriptionID; input_mode = draft.transcriptionID == nil ? "text" : "reviewed_transcript"
        created_at = WireCodec.second(now); expires_at = created_at.addingTimeInterval(86400)
        location = draft.location; structured_fields = try draft.fields()
        let matchesPreview = draft.interpretationID != nil && draft.interpretationText == original_text && draft.interpretationShelter == shelter.shelter_id && draft.interpretationTranscription == draft.transcriptionID
        guard !matchesPreview || draft.interpretationReady == true else { throw RelayError.invalid("Finish the AI preview before sending. Retry Prepare structured request to resume.") }
        interpretation_id = draft.interpretationText == original_text && draft.interpretationShelter == shelter.shelter_id && draft.interpretationTranscription == draft.transcriptionID ? draft.interpretationID : nil
    }
    public init(message: RelayMessage, binding: CloudBinding, localDeviceID: String,
                transcriptionID: String? = nil) throws {
        guard message.originID == localDeviceID else { throw RelayError.invalid("Only your own requests can be uploaded with your account. Carrier uploads need separate sender verification.") }
        let request = try ShelterRequestCodec.decode(message)
        guard request.shelter.id == binding.localID else { throw RelayError.invalid("Shelter mapping does not match this request") }
        operation_id = message.id; request_id = message.id; origin_device_id = message.originID
        incident_id = binding.incidentID; destination_shelter_id = binding.shelterID
        original_text = "\(request.details)\nNeed: \(request.need.title)\nQuantity: \(request.amount)\nPeople: \(request.people.map(String.init) ?? "Unknown")\nLocation: \(request.location)"
        guard original_text.count <= 4096 else { throw RelayError.invalid("Cloud text limit is 4096 characters; this existing request stays available over nearby delivery.") }
        input_mode = transcriptionID == nil ? "text" : "reviewed_transcript"; transcription_id = transcriptionID
        created_at = message.createdAt; expires_at = message.expiresAt
    }
}
public struct CloudProposal: Codable {
    public let item_id: String?
    public let quantity: Int?
    public let unit: String?
    public let shelter_id: String?
    public let negated: Bool
    public let missing_fields: [String]
    public let people: Int?
    public let landmark: String?
    public let medicine_details: String?
    public let urgency: String?
    public let urgency_evidence: String?
    public let summary: String
}
public struct CloudValidatedResult: Codable {
    public let status: String
    public let proposal: CloudProposal?
    public let review_reasons: [String]
    public let allocation_authorized: Bool
}
public struct CloudErrorDetail: Codable { public let code: String; public let message: String; public let retryable: Bool }
public struct CloudResult: Codable, Identifiable {
    public let request_id: String
    public let submission: CloudSubmission
    public let cloud_state: String
    public let analysis_state: String
    public let result: CloudValidatedResult?
    public let error: CloudErrorDetail?
    public let history: CloudHistory?
    public let reservation: RequestReservation?
    public var id: String { request_id }
}
public struct CloudPage: Codable { public let items: [CloudResult]; public let next_cursor: String? }
public struct CloudEvent: Codable, Identifiable {
    public let event_id: String
    public let revision: Int
    public let author_role: String
    public let text: String
    public let status: String?
    public let created_at: Date
    public var id: String { event_id }
}
public struct CloudHistory: Codable {
    public let request_id: String
    public let revision: Int
    public let status: String
    public let events: [CloudEvent]
}
public struct CloudEventCommand: Codable, Equatable {
    public let operation_id: String
    public let expected_revision: Int
    public let text: String
    public let status: String?
    public init(revision: Int, text: String, status: String?) {
        operation_id = UUID().uuidString.lowercased(); expected_revision = revision
        self.text = text; self.status = status
    }
}
public struct CloudQueueRecord: Codable, Identifiable {
    public let scope: String
    public let submission: CloudSubmission
    public var state = "queued"
    public var attempts = 0
    public var retryAt = Date.distantPast
    public var problem: String?
    public var result: CloudResult?
    public var history: CloudHistory?
    public var pendingEvent: CloudEventCommand?
    public var pendingInventory: InventoryCommand?
    public var reservation: RequestReservation?
    public var nearbyState: String?
    public var id: String { submission.request_id }
    public init(scope: String, submission: CloudSubmission) { self.scope = scope; self.submission = submission }
    public mutating func failed(_ message: String, retryable: Bool, now: Date = Date()) {
        attempts += 1; problem = message; state = retryable ? "queued" : "needs_attention"
        retryAt = now.addingTimeInterval(min(60, pow(2, Double(min(attempts, 6)))))
    }
}
public enum CloudCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    public static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: text) { return d }
            f.formatOptions = [.withInternetDateTime]
            guard let d = f.date(from: text) else { throw RelayError.invalid("Invalid cloud timestamp") }; return d
        }
        return try decoder.decode(type, from: data)
    }
    public static func scope(baseURL: URL, subject: String) -> String {
        SHA256.hash(data: Data((baseURL.absoluteString + "|" + subject).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public static func apiURL(_ text: String, allowLoopback: Bool = false) throws -> URL {
        guard let u = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              u.user == nil, u.password == nil, u.query == nil, u.fragment == nil,
              let host = u.host, !host.isEmpty,
              u.scheme == "https" || (allowLoopback && u.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host))
        else { throw RelayError.invalid("Enter an HTTPS API address. Credentials and query parameters are not allowed.") }
        return u
    }
}
