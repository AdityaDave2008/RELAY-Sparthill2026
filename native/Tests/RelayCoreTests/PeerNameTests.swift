import XCTest
import SQLite3
@testable import RelayCore

final class PeerNameTests: XCTestCase {
    let a = "00000000-0000-0000-0000-00000000000a"
    let b = "00000000-0000-0000-0000-00000000000b"
    let c = "00000000-0000-0000-0000-00000000000c"
    let now = Date(timeIntervalSince1970: 1800000000)

    func testNamedHelloAndLegacyHelloAreCompatible() throws {
        let named = Peer(deviceID: a, role: .relay, displayName: "Alex’s phone")
        var decoder = FrameDecoder()
        let packets = try decoder.append(FrameDecoder.frame(WirePacket(kind: .hello, peer: named)))
        XCTAssertEqual(packets.first?.peer, named)
        let legacy = Data("{\"device_id\":\"\(a)\",\"role\":\"Relay B\"}".utf8)
        let oldPeer = try WireCodec.decode(Peer.self, from: legacy)
        XCTAssertNil(oldPeer.displayName)
        XCTAssertEqual(oldPeer.title, "Device 00000000")
        try WirePacket(kind: .hello, peer: oldPeer).validate()
        struct LegacyPeer: Decodable { let device_id: String; let role: TestRole }
        XCTAssertEqual(try WireCodec.decode(LegacyPeer.self, from: WireCodec.encode(named)).device_id, a)
    }

    func testNameBoundsAndControlCharacters() throws {
        XCTAssertEqual(try Peer.normalizedName("  Alex  "), "Alex")
        for name in ["", "   ", "two\nlines", "hidden\u{202E}text", String(repeating: "a", count: 41)] {
            XCTAssertThrowsError(try WirePacket(kind: .hello, peer: Peer(deviceID: a, role: .relay, displayName: name)).validate())
        }
        XCTAssertThrowsError(try WirePacket(kind: .hello, peer: Peer(deviceID: a, role: .relay, displayName: " Alex ")).validate())
        try WirePacket(kind: .hello, peer: Peer(deviceID: a, role: .sender, displayName: String(repeating: "a", count: 40))).validate()
    }

    func testLegacyStoreMigrationRetainsMessagesIdentityAndPeerNamesAcrossRestart() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("relay-name-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("relay.sqlite").path
        let original = RelayMessage(originID: a, destinationID: b, payload: Payload(text: "SYNTHETIC migration"), createdAt: now)
        let body = String(decoding: try WireCodec.encode(original), as: UTF8.self).replacingOccurrences(of: "'", with: "''")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &handle), SQLITE_OK)
        let sql = """
        CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
        CREATE TABLE peers(id TEXT PRIMARY KEY,role TEXT NOT NULL);
        CREATE TABLE messages(id TEXT PRIMARY KEY,body TEXT NOT NULL,final_receipt TEXT);
        INSERT INTO metadata VALUES('device_id','\(a)');
        INSERT INTO peers VALUES('\(b)','Relay B');
        INSERT INTO messages VALUES('\(original.id)','\(body)',NULL);
        PRAGMA user_version=1;
        """
        XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
        var store: RelayStore? = try RelayStore.open(path: path)
        XCTAssertEqual(store!.deviceID, a)
        XCTAssertEqual(try store!.message(original.id), original)
        XCTAssertNil(try store!.knownPeers().first?.displayName)
        try store!.setSetting("display_name", "My phone")
        try store!.remember(Peer(deviceID: b, role: .relay, displayName: "Alex"))
        try store!.remember(Peer(deviceID: b, role: .sender, displayName: "Alex renamed"))
        try store!.remember(Peer(deviceID: b, role: .relay))
        store = nil
        let reopened = try RelayStore.open(path: path)
        XCTAssertEqual(reopened.deviceID, a)
        XCTAssertEqual(try reopened.setting("display_name"), "My phone")
        XCTAssertEqual(try reopened.knownPeers(), [Peer(deviceID: b, role: .relay, displayName: "Alex renamed")])
        XCTAssertEqual(try reopened.allMessages(), [original])
    }

    func testSameNamesAndRenameNeverChangeRoutingOrExposeRelayCopiesInChats() throws {
        let sender = RelayEngine(store: try RelayStore.open(path: ":memory:", deviceID: a), forceRelayRoute: false, displayName: "Alex")
        let relay = RelayEngine(store: try RelayStore.open(path: ":memory:", deviceID: b), forceRelayRoute: false, displayName: "Alex")
        let destination = RelayEngine(store: try RelayStore.open(path: ":memory:", deviceID: c), forceRelayRoute: false, displayName: "Alex")
        let request = try sender.compose(text: "SYNTHETIC for C only", destinationID: c, now: now)
        let first = SimulatedEncounter(sender, relay, now: now); try first.drain(); first.end()
        XCTAssertEqual(try relay.store.message(request.id)?.destinationID, c)
        XCTAssertTrue(RelayConversation.project(try relay.store.summaries(), deviceID: b).isEmpty)
        XCTAssertNil(try sender.store.summaries().first?.finalReceiptID)
        let second = SimulatedEncounter(relay, destination, now: now); try second.drain(); second.end()
        XCTAssertEqual(RelayConversation.project(try destination.store.summaries(), deviceID: c).first?.peerID, a)
        XCTAssertTrue(RelayConversation.project(try relay.store.summaries(), deviceID: b).isEmpty)
        relay.displayName = "Courier phone"
        let returned = SimulatedEncounter(relay, sender, now: now); try returned.drain(); returned.end()
        XCTAssertEqual(try sender.store.knownPeers().first?.displayName, "Courier phone")
        let chats = RelayConversation.project(try sender.store.summaries(), deviceID: a)
        XCTAssertEqual(chats.map(\.peerID), [c])
        XCTAssertEqual(chats.first?.messages.first?.id, request.id)
        XCTAssertNotNil(chats.first?.messages.first?.finalReceiptID)
        let toB = try sender.compose(text: "SYNTHETIC for B only", destinationID: b, now: now)
        let direct = SimulatedEncounter(sender, relay, now: now); try direct.drain(); direct.end()
        XCTAssertEqual(Set(RelayConversation.project(try sender.store.summaries(), deviceID: a).map(\.peerID)), Set([b,c]))
        XCTAssertEqual(RelayConversation.project(try relay.store.summaries(), deviceID: b).first?.messages.map(\.id), [toB.id])
    }
}
