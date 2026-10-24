import Foundation

/// A locally configured destination, not an authenticated organization membership.
public struct ShelterContact: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let area: String
    public let receivingDeviceID: String
    public let updatedAt: Date
    public init(id: String = UUID().uuidString.lowercased(), name: String, area: String,
                receivingDeviceID: String, updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.area = area
        self.receivingDeviceID = receivingDeviceID; self.updatedAt = WireCodec.second(updatedAt)
    }
    enum CodingKeys: String, CodingKey {
        case id, name, area, receivingDeviceID = "receiving_device_id", updatedAt = "updated_at"
    }
    public func validate() throws {
        guard Self.isID(id), Self.isID(receivingDeviceID), id != receivingDeviceID,
              (try? Peer.normalizedName(name)) == name,
              !area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, area.count <= 160,
              !area.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw RelayError.invalid("Use a shelter name, area and valid separate shelter/device IDs.") }
    }
    static func isID(_ value: String) -> Bool { UUID(uuidString: value) != nil && value == value.lowercased() }
    public func shareCode() throws -> String {
        try validate()
        // A one-line code survives smart-quote keyboards and messaging apps.
        return "RELAY-SHELTER-1:" + (try WireCodec.encode(self)).base64EncodedString()
    }
    public static func importCode(_ code: String) throws -> Self {
        let text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "RELAY-SHELTER-1:"
        guard text.hasPrefix(prefix), text.utf8.count <= 4096 else { throw RelayError.invalid("Paste a RELAY shelter code.") }
        let encoded = text.dropFirst(prefix.count).filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: String(encoded)) else { throw RelayError.invalid("Invalid shelter code. Share it from the other phone and paste the full code here.") }
        let entry = try WireCodec.decode(Self.self, from: data)
        try entry.validate(); return entry
    }
}

public enum HelpNeed: String, Codable, CaseIterable {
    case water, food, shelter, charging, other
    public var title: String { rawValue.capitalized }
    public var symbol: String {
        switch self { case .water: return "drop.fill"; case .food: return "fork.knife"
        case .shelter: return "house.fill"; case .charging: return "bolt.fill"; case .other: return "ellipsis.bubble.fill" }
    }
}

/// Editing is separate from the immutable sent envelope. One durable draft per device.
public struct HelpRequestDraft: Codable, Equatable, Identifiable {
    public var requestID: String = UUID().uuidString.lowercased()
    public var id: String { requestID }
    public var shelterID: String = ""
    public var need: HelpNeed = .water
    public var details = ""
    public var quantity = ""
    public var unit = ""
    public var people = ""
    public var location = ""
    public var cloudScope: String?
    public var cloudBinding: CloudBinding?
    public var transcriptionID: String?
    public var transcriptionSubject: String?
    public var transcriptionIncident: String?
    public init() {}
    public func request(to shelter: ShelterContact) throws -> ShelterRequest {
        guard shelterID == shelter.id else { throw RelayError.invalid("Choose a saved shelter.") }
        func count(_ text: String, label: String) throws -> Int? {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return nil }
            guard let n = Int(text), (1...1_000_000).contains(n) else { throw RelayError.invalid("\(label) must be a positive whole number, or leave it blank for unknown.") }
            return n
        }
        let value = ShelterRequest(requestID: requestID, shelter: shelter, need: need,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            quantity: try count(quantity, label: "Quantity"), unit: unit.trimmingCharacters(in: .whitespacesAndNewlines),
            people: try count(people, label: "People"), location: location.trimmingCharacters(in: .whitespacesAndNewlines))
        try value.validate(); return value
    }
}

public struct ShelterRequest: Codable, Equatable {
    public var schemaVersion = 1
    public let requestID: String
    public let shelter: ShelterContact
    public let need: HelpNeed
    public let details: String
    public let quantity: Int?
    public let unit: String
    public let people: Int?
    public let location: String
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", requestID = "request_id", shelter, need, details, quantity, unit, people, location
    }
    public func validate() throws {
        try shelter.validate()
        guard schemaVersion == 1, ShelterContact.isID(requestID), !details.isEmpty, details.utf8.count <= 4096,
              !location.isEmpty, location.count <= 240, unit.count <= 40,
              quantity.map({ (1...1_000_000).contains($0) }) ?? true,
              people.map({ (1...1_000_000).contains($0) }) ?? true,
              quantity == nil ? unit.isEmpty : !unit.isEmpty
        else { throw RelayError.invalid("Add details and a location or landmark. Quantity needs a unit; leave both blank when unknown.") }
    }
    public var amount: String { quantity.map { "\($0) \(unit)" } ?? "Quantity unknown" }
}

/// Application content stays inside payload.text so older relay engines preserve it
/// byte-for-byte. New optional JSON envelope fields would be dropped by older relays.
public enum ShelterRequestCodec {
    public static let prefix = "RELAY-HELP-1\n"
    public static func isRequest(_ message: RelayMessage) -> Bool {
        message.messageType == .request && message.payload.text.hasPrefix("RELAY-HELP-")
    }
    public static func encode(_ request: ShelterRequest) throws -> String {
        try request.validate()
        return prefix + String(decoding: try WireCodec.encode(request), as: UTF8.self)
    }
    public static func decode(_ message: RelayMessage) throws -> ShelterRequest {
        guard message.messageType == .request, message.payload.text.hasPrefix(prefix) else { throw RelayError.invalid("Unsupported help request format") }
        let value = try WireCodec.decode(ShelterRequest.self, from: Data(message.payload.text.dropFirst(prefix.count).utf8))
        try value.validate()
        guard value.requestID == message.id, value.shelter.receivingDeviceID == message.destinationID else { throw RelayError.invalid("Help request identity/destination mismatch") }
        return value
    }
}

public struct HelpRequestItem: Identifiable {
    public let stored: StoredMessage
    public let request: ShelterRequest
    public var id: String { stored.id }
    public static func project(_ rows: [StoredMessage], deviceID: String, inbox: Bool) -> [Self] {
        rows.compactMap { row in
            guard inbox ? row.message.destinationID == deviceID : row.message.originID == deviceID,
                  let request = try? ShelterRequestCodec.decode(row.message) else { return nil }
            return Self(stored: row, request: request)
        }.sorted { $0.stored.message.createdAt == $1.stored.message.createdAt ? $0.id < $1.id : $0.stored.message.createdAt > $1.stored.message.createdAt }
    }
}
