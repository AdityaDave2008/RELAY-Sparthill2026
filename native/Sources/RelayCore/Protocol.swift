import Foundation

public enum RelayError: Error, CustomStringConvertible, LocalizedError {
    public var errorDescription: String? { switch self { case .invalid(let text), .database(let text): return text } }
    case invalid(String), database(String)
    public var description: String {
        switch self { case .invalid(let s): return "Protocol: \(s)"; case .database(let s): return "SQLite: \(s)" }
    }
}
public enum TestRole: String, Codable, CaseIterable {
    case sender = "Sender A", relay = "Relay B", receiver = "Receiver C"
}
public struct Peer: Codable, Equatable {
    public let deviceID: String
    public let role: TestRole
    /// A user-chosen label, never a routing address or authenticated identity.
    public let displayName: String?
    public var title: String { displayName ?? "Device \(deviceID.prefix(8))" }
    public init(deviceID: String, role: TestRole, displayName: String? = nil) {
        self.deviceID = deviceID; self.role = role; self.displayName = displayName
    }
    public static func normalizedName(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 40, value.utf8.count <= 160,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) })
        else { throw RelayError.invalid("Use a single-line device name of 1–40 characters (up to 160 bytes).") }
        return value
    }
    enum CodingKeys: String, CodingKey { case deviceID = "device_id", role, displayName = "display_name" }
}
public enum MessageType: String, Codable { case request = "RESOURCE_REQUEST", receipt = "DELIVERY_RECEIPT" }
public struct Payload: Codable, Equatable {
    public var text: String
    public var originalMessageID: String?
    public init(text: String, originalMessageID: String? = nil) {
        self.text = text; self.originalMessageID = originalMessageID
    }
    enum CodingKeys: String, CodingKey { case text, originalMessageID = "original_message_id" }
}
public struct RelayMessage: Codable, Equatable, Identifiable {
    public var protocolVersion: Int = 1
    public let messageID: String
    public let originID: String
    public let destinationID: String
    public let messageType: MessageType
    public let payload: Payload
    public let createdAt: Date
    public let expiresAt: Date
    public var hopCount: Int
    public let maxHops: Int
    public var id: String { messageID }
    public init(messageID: String = UUID().uuidString.lowercased(), originID: String,
                destinationID: String, messageType: MessageType = .request,
                payload: Payload, createdAt: Date = Date(), expiresAt: Date? = nil,
                hopCount: Int = 0, maxHops: Int = 5) {
        self.messageID = messageID; self.originID = originID; self.destinationID = destinationID
        self.messageType = messageType; self.payload = payload; self.createdAt = createdAt
        self.expiresAt = expiresAt ?? createdAt.addingTimeInterval(86400)
        self.hopCount = hopCount; self.maxHops = maxHops
    }
    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version", messageID = "message_id", originID = "origin_id"
        case destinationID = "destination_id", messageType = "message_type", payload
        case createdAt = "created_at", expiresAt = "expires_at", hopCount = "hop_count", maxHops = "max_hops"
    }
    public func validate(now: Date) throws {
        guard protocolVersion == 1, UUID(uuidString: messageID) != nil,
              UUID(uuidString: originID) != nil, UUID(uuidString: destinationID) != nil,
              messageID == messageID.lowercased(), originID == originID.lowercased(),
              destinationID == destinationID.lowercased() else { throw RelayError.invalid("version/UUID") }
        guard maxHops > 0, maxHops <= 16, hopCount >= 0, hopCount <= maxHops else { throw RelayError.invalid("hop limit") }
        guard expiresAt > now, expiresAt > createdAt,
              expiresAt.timeIntervalSince(createdAt) <= 7 * 86400,
              createdAt <= now.addingTimeInterval(300) else { throw RelayError.invalid("expired/invalid clock or TTL") }
        guard !payload.text.isEmpty, payload.text.utf8.count <= 16_384 else { throw RelayError.invalid("text size") }
        if messageType == .receipt {
            guard let original = payload.originalMessageID, UUID(uuidString: original) != nil,
                  original == original.lowercased(), original != messageID else { throw RelayError.invalid("receipt reference") }
        } else if payload.originalMessageID != nil { throw RelayError.invalid("request has receipt reference") }
    }
    public func sameContent(as other: Self) -> Bool {
        var a = self, b = other; a.hopCount = 0; b.hopCount = 0
        return a == b
    }
}
public enum WireKind: String, Codable { case hello, inventory, message, ack }
public enum Acceptance: String, Codable { case relayStored = "RELAY_STORED", destinationStored = "DESTINATION_STORED" }
public struct StorageAck: Codable {
    public let messageID: String
    public let acceptance: Acceptance
    public init(messageID: String, acceptance: Acceptance) { self.messageID = messageID; self.acceptance = acceptance }
    enum CodingKeys: String, CodingKey { case messageID = "message_id", acceptance }
}
public struct WirePacket: Codable {
    public var protocolVersion = 1
    public let kind: WireKind
    public var peer: Peer?
    public var inventory: [String]?
    public var message: RelayMessage?
    public var ack: StorageAck?
    public init(kind: WireKind, peer: Peer? = nil, inventory: [String]? = nil,
                message: RelayMessage? = nil, ack: StorageAck? = nil) {
        self.kind = kind; self.peer = peer; self.inventory = inventory; self.message = message; self.ack = ack
    }
    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version", kind, peer, inventory, message, ack
    }
    public func validate() throws {
        guard protocolVersion == 1 else { throw RelayError.invalid("wire version") }
        switch kind {
        case .hello:
            guard let p = peer, UUID(uuidString: p.deviceID) != nil,
                  p.deviceID == p.deviceID.lowercased(), inventory == nil, message == nil, ack == nil else { throw RelayError.invalid("hello") }
            if let name = p.displayName, try Peer.normalizedName(name) != name { throw RelayError.invalid("noncanonical device name") }
        case .inventory:
            guard let ids = inventory, ids.count <= RelayStore.capacity, ids.allSatisfy({ UUID(uuidString: $0) != nil }),
                  peer == nil, message == nil, ack == nil else { throw RelayError.invalid("inventory") }
        case .message:
            guard message != nil, peer == nil, inventory == nil, ack == nil else { throw RelayError.invalid("message envelope") }
        case .ack:
            guard let a = ack, UUID(uuidString: a.messageID) != nil, peer == nil, inventory == nil, message == nil else { throw RelayError.invalid("ack") }
        }
    }
}
public enum WireCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; e.dateEncodingStrategy = .iso8601
        return try e.encode(value)
    }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try d.decode(type, from: data)
    }
    public static func timestamp(_ date: Date = Date()) -> String { ISO8601DateFormatter().string(from: date) }
    // Wire dates have whole-second precision. Normalize before storing or comparing immutable content.
    public static func second(_ date: Date) -> Date { Date(timeIntervalSince1970: floor(date.timeIntervalSince1970)) }
}
public struct FrameDecoder {
    public static let maximumLength = 262_144
    private var buffer = Data()
    public init() {}
    public var hasPartialFrame: Bool { !buffer.isEmpty }
    public static func frame(_ packet: WirePacket) throws -> Data {
        let body = try WireCodec.encode(packet)
        guard !body.isEmpty, body.count <= maximumLength else { throw RelayError.invalid("frame too large") }
        let n = UInt32(body.count)
        return Data([UInt8((n >> 24) & 255), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)]) + body
    }
    public mutating func append(_ chunk: Data) throws -> [WirePacket] {
        // Network adapter reads <=64 KiB. Bound buffering even for a malicious length prefix.
        guard chunk.count <= Self.maximumLength + 4 else { throw RelayError.invalid("oversize read") }
        buffer.append(chunk)
        var packets: [WirePacket] = []
        while buffer.count >= 4 {
            let n = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard n > 0, n <= Self.maximumLength else { throw RelayError.invalid("frame length \(n)") }
            guard buffer.count >= n + 4 else { break }
            let body = Data(buffer.dropFirst(4).prefix(n))
            buffer = Data(buffer.dropFirst(n + 4))
            let p = try WireCodec.decode(WirePacket.self, from: body); try p.validate(); packets.append(p)
        }
        return packets
    }
}
