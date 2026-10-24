import Foundation

/// A presentation-only projection. Carried messages and receipt envelopes never
/// become personal chat bubbles; they remain available in the durable relay queue.
public struct RelayConversation: Identifiable {
    public let peerID: String
    public let messages: [StoredMessage]
    public var id: String { peerID }
    public var latest: StoredMessage { messages[messages.count - 1] }

    public static func project(_ rows: [StoredMessage], deviceID: String) -> [RelayConversation] {
        var groups: [String: [StoredMessage]] = [:]
        for row in rows where row.message.messageType == .request {
            let m = row.message
            if SealedDelivery.isSealed(m) || ShelterRequestCodec.isRequest(m) || LocalRequestUpdate.isUpdate(m) { continue }
            let peer: String
            if m.originID == deviceID && m.destinationID != deviceID { peer = m.destinationID }
            else if m.destinationID == deviceID && m.originID != deviceID { peer = m.originID }
            else { continue }
            groups[peer, default: []].append(row)
        }
        return groups.map { peer, messages in
            RelayConversation(peerID: peer, messages: messages.sorted {
                $0.message.createdAt == $1.message.createdAt ? $0.id < $1.id : $0.message.createdAt < $1.message.createdAt
            })
        }.sorted {
            $0.latest.message.createdAt == $1.latest.message.createdAt ? $0.peerID < $1.peerID : $0.latest.message.createdAt > $1.latest.message.createdAt
        }
    }
}
