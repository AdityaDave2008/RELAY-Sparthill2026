import Foundation

/// Deterministic protocol state machine; all calls, including callbacks, use one serial queue.
/// The transport only carries framed packets. This class owns delivery semantics.
public final class RelayEngine {
    private struct Session {
        var peer: Peer?
        var remoteIDs = Set<String>()
        var receivedInventory = false
        var inFlight: [String: Date] = [:]
        var connectedAt: Date
    }
    public let store: RelayStore
    public var role: TestRole
    public var displayName: String?
    public var forceRelayRoute: Bool
    public var send: ((String, WirePacket) -> Void)?
    public var disconnect: ((String) -> Void)?
    public var onEvent: ((String) -> Void)?
    public var onChange: (() -> Void)?
    private var sessions: [String: Session] = [:]
    private var lastInventory = Date.distantPast
    public var connectedPeers: [String: Peer] { sessions.compactMapValues(\.peer) }
    public var localPeer: Peer { Peer(deviceID: store.deviceID, role: role, displayName: displayName) }

    public init(store: RelayStore, role: TestRole = .relay, forceRelayRoute: Bool = true, displayName: String? = nil) {
        self.store = store; self.role = role; self.forceRelayRoute = forceRelayRoute; self.displayName = displayName
    }
    public func event(_ detail: String, now: Date = Date()) {
        let line = "\(WireCodec.timestamp(now)) [\(store.deviceID)] \(detail)"
        do { try store.log(line) }
        catch { onEvent?("\(WireCodec.timestamp()) LOG_PERSIST_FAILURE \(error)") }
        onEvent?(line); onChange?()
    }
    public func connected(_ connectionID: String, now: Date = Date()) {
        sessions[connectionID] = Session(connectedAt: now)
        event("CONNECTION_READY session=\(connectionID)", now: now)
        send?(connectionID, WirePacket(kind: .hello, peer: localPeer))
    }
    public func disconnected(_ connectionID: String, now: Date = Date()) {
        guard let s = sessions.removeValue(forKey: connectionID) else { return }
        event("DISCONNECTED session=\(connectionID) unacked=\(s.inFlight.keys.sorted()) queued_for_retry", now: now)
    }
    @discardableResult public func compose(text: String, destinationID: String, now: Date = Date(), maxHops: Int = 5, ttl: TimeInterval = 86400) throws -> RelayMessage {
        guard destinationID != store.deviceID else { throw RelayError.invalid("choose another device") }
        let date = WireCodec.second(now)
        let m = RelayMessage(originID: store.deviceID, destinationID: destinationID, payload: Payload(text: text),
            createdAt: date, expiresAt: date.addingTimeInterval(ttl), maxHops: maxHops)
        try store.saveLocal(m, now: now)
        event("LOCALLY_SAVED id=\(m.id) destination=\(destinationID)", now: now)
        offerAll(now: now)
        return m
    }
    public func receive(_ packet: WirePacket, from connectionID: String, now: Date = Date()) {
        do {
            try packet.validate()
            guard var session = sessions[connectionID] else { throw RelayError.invalid("unknown session") }
            if packet.kind == .hello {
                let peer = packet.peer!
                guard session.peer == nil, peer.deviceID != store.deviceID else { throw RelayError.invalid("repeated/self hello") }
                if forceRelayRoute && Self.isBlocked(localPeer, peer) {
                    event("LOGICAL_ROUTE_BLOCK peer=\(peer.deviceID) A-C disabled; not evidence of physical separation", now: now)
                    disconnect?(connectionID); return
                }
                // Duplicate TCP sessions are harmless: immutable IDs + SQLite handle races on this queue.
                try store.remember(peer)
                session.peer = peer; sessions[connectionID] = session
                event("HELLO peer=\(peer.deviceID) role=\(peer.role.rawValue) identity=UNAUTHENTICATED", now: now)
                try sendInventory(connectionID, now: now)
                return
            }
            guard let peer = session.peer else { throw RelayError.invalid("hello required") }
            switch packet.kind {
            case .hello: break
            case .inventory:
                session.remoteIDs = Set(packet.inventory!); session.receivedInventory = true
                sessions[connectionID] = session
                event("INVENTORY peer=\(peer.deviceID) count=\(session.remoteIDs.count)", now: now)
                try offer(connectionID, now: now)
            case .message:
                let m = packet.message!
                // COMMIT precedes ACK, including request+receipt creation and receipt state updates.
                let result = try store.receive(m, now: now)
                event("\(result.duplicate ? "DUPLICATE_SUPPRESSED" : "PERSISTED") id=\(m.id) peer=\(peer.deviceID) hops=\(m.hopCount)", now: now)
                if let r = result.generatedReceipt { event("RECEIPT_CREATED id=\(r.id) original=\(m.id)", now: now) }
                if result.recognizedReceipt { event("FINAL_RECEIPT_RECOGNIZED id=\(m.id) original=\(m.payload.originalMessageID!)", now: now) }
                let kind: Acceptance = m.destinationID == store.deviceID ? .destinationStored : .relayStored
                send?(connectionID, WirePacket(kind: .ack, ack: StorageAck(messageID: m.id, acceptance: kind)))
                event("STORAGE_ACK_SENT id=\(m.id) kind=\(kind.rawValue)", now: now)
                // Mark only this encounter's knowledge, never global delivery.
                sessions[connectionID]?.remoteIDs.insert(m.id)
                offerAll(now: now)
            case .ack:
                let ack = packet.ack!
                guard let attemptedAt = session.inFlight[ack.messageID], let m = try store.message(ack.messageID) else {
                    event("UNSOLICITED_ACK_IGNORED id=\(ack.messageID)", now: now); return
                }
                let expected: Acceptance = m.destinationID == peer.deviceID ? .destinationStored : .relayStored
                guard ack.acceptance == expected else { throw RelayError.invalid("ACK kind mismatches peer destination") }
                try store.recordAck(ack, peer: peer.deviceID)
                sessions[connectionID]?.inFlight.removeValue(forKey: ack.messageID)
                sessions[connectionID]?.remoteIDs.insert(ack.messageID)
                event("STORAGE_ACK_RECEIVED id=\(ack.messageID) kind=\(ack.acceptance.rawValue) peer=\(peer.deviceID) ack_latency_ms=\(Int(now.timeIntervalSince(attemptedAt) * 1000))", now: now)
            }
        } catch {
            event("RECEIVE_REJECTED_OR_PERSIST_FAILURE session=\(connectionID) error=\(error); no ACK", now: now)
            disconnect?(connectionID)
        }
    }
    @discardableResult public func submitHelpRequest(_ draft: HelpRequestDraft, now: Date = Date()) throws -> RelayMessage {
        let message = try store.submitHelpDraft(draft, now: now)
        event("HELP_REQUEST_SAVED id=\(message.id) shelter=\(draft.shelterID) destination=\(message.destinationID)", now: now)
        offerAll(now: now)
        return message
    }
    public static func isBlocked(_ a: Peer, _ b: Peer) -> Bool {
        (a.role == .sender && b.role == .receiver) || (a.role == .receiver && b.role == .sender)
    }
    private func sendInventory(_ id: String, now: Date) throws {
        send?(id, WirePacket(kind: .inventory, inventory: try store.inventory(now: now)))
    }
    private func offer(_ id: String, now: Date) throws {
        guard let s = sessions[id], let peer = s.peer, s.receivedInventory else { return }
        for m in try store.allMessages() {
            guard m.expiresAt > now, m.hopCount < m.maxHops, m.destinationID != store.deviceID,
                  m.originID != peer.deviceID else { continue }
            let pending = try store.hasUnacknowledgedAttempt(m.id, peer: peer.deviceID)
            guard !s.remoteIDs.contains(m.id) || pending else { continue }
            if let last = sessions[id]?.inFlight[m.id], now.timeIntervalSince(last) < 8 { continue }
            var forwarded = m; forwarded.hopCount += 1
            try store.recordAttempt(m.id, peer: peer.deviceID)
            sessions[id]?.inFlight[m.id] = now
            event("TRANSFER_ATTEMPT id=\(m.id) peer=\(peer.deviceID) hops=\(forwarded.hopCount) pending_retry=\(pending)", now: now)
            send?(id, WirePacket(kind: .message, message: forwarded))
        }
    }
    private func offerAll(now: Date) {
        for id in Array(sessions.keys) {
            do { try offer(id, now: now) }
            catch { event("FORWARD_FAILURE session=\(id) error=\(error)", now: now) }
        }
    }
    public func tick(now: Date = Date()) {
        for (id, s) in sessions where s.peer == nil && now.timeIntervalSince(s.connectedAt) > 15 {
            event("HELLO_TIMEOUT session=\(id)", now: now); disconnect?(id)
        }
        if now.timeIntervalSince(lastInventory) >= 5 {
            lastInventory = now
            for (id, s) in sessions where s.peer != nil {
                do { try sendInventory(id, now: now) } catch { event("INVENTORY_FAILURE \(error)", now: now) }
            }
        }
        offerAll(now: now)
    }
    // Explicit test control: replay a stored request/receipt even if the peer already advertised it.
    public func retransmitForTest(_ messageID: String, now: Date = Date()) throws {
        guard let m = try store.message(messageID), m.expiresAt > now, m.hopCount < m.maxHops,
              m.destinationID != store.deviceID else { throw RelayError.invalid("not eligible for test retransmit") }
        for (id, s) in sessions {
            guard let p = s.peer else { continue }
            var copy = m; copy.hopCount += 1
            try store.recordAttempt(m.id, peer: p.deviceID); sessions[id]?.inFlight[m.id] = now
            event("FORCED_DUPLICATE_TEST id=\(m.id) peer=\(p.deviceID)", now: now)
            send?(id, WirePacket(kind: .message, message: copy))
        }
    }
}
