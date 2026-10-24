import Foundation

/// Device-addressed, unauthenticated progress notes. Cloud staff events use a separate authenticated API.
public struct LocalRequestUpdate: Codable, Identifiable {
    public let id: String
    public let requestID: String
    public let text: String
    public let progress: String?
    public init(requestID: String, text: String, progress: String?) {
        id = UUID().uuidString.lowercased(); self.requestID = requestID; self.text = text; self.progress = progress
    }
    public static let prefix = "RELAY-UPDATE-1\n"
    public static func isUpdate(_ message: RelayMessage) -> Bool { message.payload.text.hasPrefix("RELAY-UPDATE-") }
    public func encode() throws -> String {
        guard UUID(uuidString: requestID) != nil, text.count <= 2000,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || progress != nil,
              progress == nil || ["accepted", "in_progress", "completed", "rejected", "cancelled"].contains(progress!)
        else { throw RelayError.invalid("Add a reply or valid progress update") }
        return Self.prefix + String(decoding: try WireCodec.encode(self), as: UTF8.self)
    }
    public static func thread(_ messages: [StoredMessage], request: RelayMessage) -> [(StoredMessage, Self)] {
        messages.compactMap { row in
            let m = row.message
            guard m.messageType == .request, m.payload.text.hasPrefix(prefix),
                  (m.originID == request.originID && m.destinationID == request.destinationID) ||
                  (m.originID == request.destinationID && m.destinationID == request.originID),
                  let update = try? WireCodec.decode(Self.self, from: Data(m.payload.text.dropFirst(prefix.count).utf8)),
                  update.requestID == request.id, (try? update.encode()) != nil else { return nil }
            return (row, update)
        }.sorted { $0.0.message.createdAt == $1.0.message.createdAt ? $0.0.id < $1.0.id : $0.0.message.createdAt < $1.0.message.createdAt }
    }
}
