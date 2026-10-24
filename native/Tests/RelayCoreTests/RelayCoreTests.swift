import XCTest
@testable import RelayCore

final class RelayCoreTests: XCTestCase {
    let a = "00000000-0000-0000-0000-00000000000a"
    let b = "00000000-0000-0000-0000-00000000000b"
    let c = "00000000-0000-0000-0000-00000000000c"
    let now = Date(timeIntervalSince1970: 1800000000)
    func store(_ id: String, path: String = ":memory:") throws -> RelayStore { try RelayStore.open(path: path, deviceID: id) }
    func message(hop: Int = 1, max: Int = 5, destination: String? = nil) -> RelayMessage {
        RelayMessage(originID: a, destinationID: destination ?? c, payload: Payload(text: "SYNTHETIC water request"), createdAt: now, hopCount: hop, maxHops: max)
    }
    func tempPath() -> String { FileManager.default.temporaryDirectory.appendingPathComponent("relay-tests-\(UUID().uuidString)/relay.sqlite").path }
    func cleanup(_ path: String) { try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent()) }

    func testJSONRoundTripAndWireNames() throws {
        let m = message(); let data = try WireCodec.encode(m)
        XCTAssertEqual(try WireCodec.decode(RelayMessage.self, from: data), m)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["protocol_version"] as? Int, 1)
        XCTAssertEqual(json["message_type"] as? String, "RESOURCE_REQUEST")
        XCTAssertEqual(json["created_at"] as? String, "2027-01-15T08:00:00Z")
    }
    func testFramingFragmentationAndCoalescing() throws {
        let p = WirePacket(kind: .message, message: message())
        let bytes = try FrameDecoder.frame(p)
        for split in 0...bytes.count {
            var decoder = FrameDecoder()
            let one = try decoder.append(Data(bytes.prefix(split)))
            let two = try decoder.append(Data(bytes.dropFirst(split)))
            XCTAssertEqual((one + two).count, 1)
            XCTAssertEqual((one + two).first?.message, p.message)
            XCTAssertFalse(decoder.hasPartialFrame)
        }
        var decoder = FrameDecoder()
        XCTAssertEqual(try decoder.append(bytes + bytes + bytes).count, 3)
    }
    func testMalformedFramesAndVersionRejected() throws {
        var d = FrameDecoder(); XCTAssertThrowsError(try d.append(Data([255,255,255,255])))
        d = FrameDecoder(); XCTAssertThrowsError(try d.append(Data([0,0,0,0])))
        var p = WirePacket(kind: .inventory, inventory: []); p.protocolVersion = 2
        d = FrameDecoder(); XCTAssertThrowsError(try d.append(FrameDecoder.frame(p)))
        XCTAssertThrowsError(try WirePacket(kind: .hello, inventory: []).validate())
    }
    func testDurableIdentityMessagesAndAcknowledgementsAfterRestart() throws {
        let path = tempPath(); defer { cleanup(path) }
        var s: RelayStore? = try store(b, path: path)
        let m = message(); _ = try s!.receive(m, now: now)
        try s!.recordAttempt(m.id, peer: c)
        try s!.recordAck(StorageAck(messageID: m.id, acceptance: .destinationStored), peer: c)
        try s!.setSetting("role", TestRole.relay.rawValue); s = nil
        let reopened = try RelayStore.open(path: path)
        XCTAssertEqual(reopened.deviceID, b)
        XCTAssertEqual(try reopened.message(m.id), m)
        XCTAssertEqual(try reopened.summaries().first?.attempts, 1)
        XCTAssertEqual(try reopened.summaries().first?.destinationAccepted, true)
        XCTAssertEqual(try reopened.setting("role"), TestRole.relay.rawValue)
    }
    func testDuplicatesDoNotRepeatActionOrReceiptAndCollisionRejected() throws {
        let s = try store(c), m = message()
        let first = try s.receive(m, now: now)
        XCTAssertNotNil(first.generatedReceipt)
        for _ in 0..<20 {
            let r = try s.receive(m, now: now)
            XCTAssertTrue(r.duplicate); XCTAssertNil(r.generatedReceipt)
        }
        XCTAssertEqual(try s.allMessages().count, 2)
        let collision = RelayMessage(messageID: m.id, originID: a, destinationID: c, payload: Payload(text: "different"), createdAt: now, hopCount: 1)
        XCTAssertThrowsError(try s.receive(collision, now: now))
        XCTAssertEqual(try s.message(m.id)?.payload.text, m.payload.text)
    }
    func testExpirationAndHopBoundary() throws {
        let s = try store(b), m = message(hop: 5, max: 5)
        _ = try s.receive(m, now: now)
        XCTAssertEqual(try s.inventory(now: now).count, 1)
        XCTAssertTrue(try s.inventory(now: now.addingTimeInterval(86401)).isEmpty)
        XCTAssertThrowsError(try s.receive(m, now: now.addingTimeInterval(86401)))
        XCTAssertThrowsError(try s.receive(message(hop: 6), now: now))
        let engine = RelayEngine(store: s), remote = try RelayEngine(store: store(c), role: .receiver)
        let wire = SimulatedEncounter(engine, remote, now: now); try wire.drain()
        XCTAssertNil(try remote.store.message(m.id))
        // A destination may receive a message on its final permitted hop.
        XCTAssertNotNil(try remote.store.receive(m, now: now).generatedReceipt)
    }
    func testInventoryOnlyOffersMissingAndDoesNotIncreaseHopOnRetries() throws {
        let left = RelayEngine(store: try store(a), role: .sender)
        let right = RelayEngine(store: try store(b))
        let m = try left.compose(text: "SYNTHETIC", destinationID: c, now: now)
        let wire = SimulatedEncounter(left, right, now: now); try wire.drain()
        XCTAssertEqual(try right.store.message(m.id)?.hopCount, 1)
        let attempts = try left.store.summaries()[0].attempts
        left.tick(now: now.addingTimeInterval(6)); right.tick(now: now.addingTimeInterval(6)); try wire.drain()
        XCTAssertEqual(try left.store.summaries()[0].attempts, attempts)
        try left.retransmitForTest(m.id, now: now); try wire.drain()
        XCTAssertEqual(try right.store.message(m.id)?.hopCount, 1)
        XCTAssertEqual(try right.store.allMessages().count, 1)
        XCTAssertEqual(try left.store.summaries()[0].attempts, attempts + 1)
    }
    func testThreeDeviceCarryRestartReturnReceipt() throws {
        let path = tempPath(); defer { cleanup(path) }
        let sender = RelayEngine(store: try store(a), role: .sender)
        var relay: RelayEngine? = RelayEngine(store: try store(b, path: path))
        let receiver = RelayEngine(store: try store(c), role: .receiver)
        let m = try sender.compose(text: "SYNTHETIC M001", destinationID: c, now: now)
        var wire: SimulatedEncounter? = SimulatedEncounter(sender, relay!, now: now)
        try wire!.drain(); wire!.end(); wire = nil
        XCTAssertNil(try sender.store.summaries()[0].finalReceiptID)
        XCTAssertEqual(try sender.store.summaries()[0].acceptedBy, [b])
        relay = nil // Close database and destroy all sessions.
        relay = RelayEngine(store: try RelayStore.open(path: path))
        XCTAssertNotNil(try relay!.store.message(m.id))
        wire = SimulatedEncounter(relay!, receiver, now: now.addingTimeInterval(60))
        try wire!.drain(); wire!.end(); wire = nil
        XCTAssertEqual(try receiver.store.message(m.id)?.hopCount, 2)
        XCTAssertEqual(try receiver.store.allMessages().count, 2)
        XCTAssertEqual(try relay!.store.allMessages().count, 2)
        XCTAssertNil(try sender.store.summaries()[0].finalReceiptID)
        wire = SimulatedEncounter(relay!, sender, now: now.addingTimeInterval(120))
        try wire!.drain(); wire!.end()
        XCTAssertNotNil(try sender.store.summaries()[0].finalReceiptID)
        XCTAssertEqual(try sender.store.allMessages().filter { $0.messageType == .receipt }.first?.hopCount, 2)
    }
    func testDroppedAckRetriedAfterReconnectDespiteInventory() throws {
        let sender = RelayEngine(store: try store(a), role: .sender), relay = RelayEngine(store: try store(b))
        let m = try sender.compose(text: "SYNTHETIC", destinationID: c, now: now)
        let first = SimulatedEncounter(sender, relay, now: now); first.dropAcks = true
        try first.drain(); first.end()
        XCTAssertNotNil(try relay.store.message(m.id))
        XCTAssertTrue(try sender.store.summaries()[0].acceptedBy.isEmpty)
        let second = SimulatedEncounter(sender, relay, now: now.addingTimeInterval(20))
        try second.drain(); second.end()
        XCTAssertEqual(try relay.store.allMessages().count, 1)
        XCTAssertEqual(try sender.store.summaries()[0].acceptedBy, [b])
        XCTAssertEqual(try sender.store.summaries()[0].attempts, 2)
    }
    func testPartialFrameDisconnectAndRepeatedRetry() throws {
        let sender = RelayEngine(store: try store(a), role: .sender), relay = RelayEngine(store: try store(b))
        let m = try sender.compose(text: "SYNTHETIC", destinationID: c, now: now)
        for attempt in 0..<30 {
            let wire = SimulatedEncounter(sender, relay, now: now.addingTimeInterval(Double(attempt * 20)))
            wire.cutMessages = true; try wire.drain(); wire.end()
            XCTAssertNil(try relay.store.message(m.id))
            XCTAssertNil(try sender.store.summaries()[0].finalReceiptID)
            XCTAssertTrue(try sender.store.summaries()[0].acceptedBy.isEmpty)
        }
        let wire = SimulatedEncounter(sender, relay, now: now.addingTimeInterval(620)); try wire.drain(); wire.end()
        XCTAssertEqual(try relay.store.allMessages().count, 1)
        XCTAssertEqual(try sender.store.summaries()[0].attempts, 31)
    }
    func testReceiptCannotMarkWrongDestinationAsDelivered() throws {
        let s = try store(a), m = message(hop: 0)
        try s.saveLocal(m, now: now)
        let receipt = RelayMessage(originID: b, destinationID: a, messageType: .receipt,
            payload: Payload(text: "wrong claimed destination", originalMessageID: m.id), createdAt: now, hopCount: 1)
        XCTAssertFalse(try s.receive(receipt, now: now).recognizedReceipt)
        XCTAssertNil(try s.summaries()[0].finalReceiptID)
    }
    func testRouteBlockAndUnsolicitedAck() throws {
        let sender = RelayEngine(store: try store(a), role: .sender), receiver = RelayEngine(store: try store(c), role: .receiver)
        let m = try sender.compose(text: "SYNTHETIC", destinationID: c, now: now)
        let wire = SimulatedEncounter(sender, receiver, now: now); try wire.drain()
        XCTAssertNil(try receiver.store.message(m.id))
        let relay = RelayEngine(store: try store(b)); let other = SimulatedEncounter(sender, relay, now: now); try other.drain()
        sender.receive(WirePacket(kind: .ack, ack: StorageAck(messageID: m.id, acceptance: .destinationStored)), from: "link", now: now)
        XCTAssertNil(try sender.store.summaries()[0].finalReceiptID)
    }
    func testShorterDuplicateRouteUpdatesHopsButPreservesFinalState() throws {
        let s = try store(b), longer = message(hop: 4)
        _ = try s.receive(longer, now: now)
        var shorter = longer; shorter.hopCount = 1
        XCTAssertTrue(try s.receive(shorter, now: now).duplicate)
        XCTAssertEqual(try s.message(longer.id)?.hopCount, 1)
        _ = try s.receive(longer, now: now)
        XCTAssertEqual(try s.message(longer.id)?.hopCount, 1)
    }
    func testExpiredMessagesNeverOffered() throws {
        let sender = RelayEngine(store: try store(a), role: .sender), relay = RelayEngine(store: try store(b))
        let m = try sender.compose(text: "SYNTHETIC expired", destinationID: c, now: now, ttl: 2)
        let wire = SimulatedEncounter(sender, relay, now: now.addingTimeInterval(3)); try wire.drain()
        XCTAssertNil(try relay.store.message(m.id))
        XCTAssertEqual(try sender.store.summaries()[0].attempts, 0)
    }
    func testRetryWithoutDisconnectAfterMissingAck() throws {
        let sender = RelayEngine(store: try store(a), role: .sender), relay = RelayEngine(store: try store(b))
        let m = try sender.compose(text: "SYNTHETIC", destinationID: c, now: now)
        let wire = SimulatedEncounter(sender, relay, now: now); wire.dropAcks = true; try wire.drain()
        XCTAssertTrue(try sender.store.summaries()[0].acceptedBy.isEmpty)
        wire.dropAcks = false
        sender.tick(now: now.addingTimeInterval(9)); try wire.drain()
        XCTAssertEqual(try sender.store.summaries()[0].attempts, 2)
        XCTAssertEqual(try sender.store.summaries()[0].acceptedBy, [b])
        XCTAssertEqual(try relay.store.allMessages().count, 1)
        XCTAssertNil(try sender.store.summaries()[0].finalReceiptID)
        XCTAssertNotNil(try relay.store.message(m.id))
    }
    func testReceiptStateSurvivesSenderRestartAndDuplicateReceipt() throws {
        let path = tempPath(); defer { cleanup(path) }
        var sender: RelayStore? = try store(a, path: path)
        let m = message(hop: 0); try sender!.saveLocal(m, now: now)
        var receipt = try XCTUnwrap(try store(c).receive(messageCopy(m, hop: 2), now: now).generatedReceipt)
        receipt.hopCount = 2
        XCTAssertTrue(try sender!.receive(receipt, now: now).recognizedReceipt)
        sender = nil
        let reopened = try RelayStore.open(path: path)
        XCTAssertEqual(try reopened.summaries()[0].finalReceiptID, receipt.id)
        XCTAssertTrue(try reopened.receive(receipt, now: now).duplicate)
        XCTAssertEqual(try reopened.summaries()[0].finalReceiptID, receipt.id)
        XCTAssertEqual(try reopened.allMessages().count, 2)
    }
    private func messageCopy(_ m: RelayMessage, hop: Int) -> RelayMessage { var n = m; n.hopCount = hop; return n }
    func testPersistenceFailureSendsNoAcknowledgement() throws {
        let s = try store(c)
        // Exhaust quota, leaving one slot. Destination request+receipt needs TWO slots and must roll back.
        for _ in 0..<(RelayStore.capacity - 1) { try s.saveLocal(RelayMessage(originID: c, destinationID: a, payload: Payload(text: "quota test"), createdAt: now), now: now) }
        let engine = RelayEngine(store: s, role: .receiver, forceRelayRoute: false)
        var packets: [WirePacket] = []; engine.send = { _, p in packets.append(p) }
        engine.connected("link", now: now)
        engine.receive(WirePacket(kind: .hello, peer: Peer(deviceID: b, role: .relay)), from: "link", now: now)
        let m = message(); engine.receive(WirePacket(kind: .message, message: m), from: "link", now: now)
        XCTAssertFalse(packets.contains { $0.kind == .ack })
        XCTAssertNil(try s.message(m.id))
        XCTAssertEqual(try s.allMessages().count, RelayStore.capacity - 1)
    }
}

/// Simulated byte transport. No radios or Network.framework; explicitly not a physical test.
final class SimulatedEncounter {
    let left: RelayEngine, right: RelayEngine
    let now: Date
    var pending: [(Bool, WirePacket)] = []
    var dropAcks = false, cutMessages = false
    var closed = false
    init(_ left: RelayEngine, _ right: RelayEngine, now: Date) {
        self.left = left; self.right = right; self.now = now
        left.send = { [weak self] _, p in self?.pending.append((true, p)) }
        right.send = { [weak self] _, p in self?.pending.append((false, p)) }
        left.disconnect = { [weak self] _ in self?.end() }; right.disconnect = { [weak self] _ in self?.end() }
        left.connected("link", now: now); right.connected("link", now: now)
    }
    func drain() throws {
        var count = 0
        while !pending.isEmpty && !closed {
            count += 1; if count > 10000 { throw RelayError.invalid("simulation runaway") }
            let (fromLeft, p) = pending.removeFirst()
            if dropAcks && p.kind == .ack { continue }
            let frame = try FrameDecoder.frame(p)
            var decoder = FrameDecoder()
            if cutMessages && p.kind == .message {
                XCTAssertTrue(try decoder.append(Data(frame.prefix(frame.count / 2))).isEmpty)
                end(); continue
            }
            // Exercise a fragmented stream for every packet.
            for chunk in [Data(frame.prefix(3)), Data(frame.dropFirst(3))] {
                for packet in try decoder.append(chunk) { (fromLeft ? right : left).receive(packet, from: "link", now: now) }
            }
        }
    }
    func end() {
        if closed { return }; closed = true
        left.disconnected("link", now: now); right.disconnected("link", now: now)
        left.send = nil; right.send = nil; left.disconnect = nil; right.disconnect = nil
        pending.removeAll()
    }
}
