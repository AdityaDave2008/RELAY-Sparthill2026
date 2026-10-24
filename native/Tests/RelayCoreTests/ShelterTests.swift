import XCTest
import SQLite3
@testable import RelayCore

final class ShelterTests: XCTestCase {
    let a = "00000000-0000-0000-0000-00000000000a"
    let b = "00000000-0000-0000-0000-00000000000b"
    let c = "00000000-0000-0000-0000-00000000000c"
    let shelterID = "00000000-0000-0000-0000-000000000001"
    let now = Date(timeIntervalSince1970: 1800000000)
    var shelter: ShelterContact { ShelterContact(id: shelterID, name: "Demo Shelter", area: "Synthetic Hall", receivingDeviceID: c, updatedAt: now) }
    func draft() -> HelpRequestDraft {
        var d = HelpRequestDraft(); d.shelterID = shelterID; d.details = "SYNTHETIC water request"
        d.quantity = "20"; d.unit = "packs"; d.location = "Demo Hall entrance"; return d
    }
    func store(_ id: String) throws -> RelayStore { try RelayStore.open(path: ":memory:", deviceID: id) }
    func temporaryPath() -> String { FileManager.default.temporaryDirectory.appendingPathComponent("shelter-tests-\(UUID().uuidString)/relay.sqlite").path }

    func testDirectoryCodeRoundTripAndConflictingRedirectionRejected() throws {
        let s = try store(a)
        let imported = try ShelterContact.importCode(shelter.shareCode())
        XCTAssertEqual(imported, shelter)
        try s.saveShelter(imported); try s.saveShelter(imported)
        XCTAssertEqual(try s.shelters().count, 1)
        let redirected = ShelterContact(id: shelterID, name: shelter.name, area: shelter.area, receivingDeviceID: b, updatedAt: now)
        XCTAssertThrowsError(try s.saveShelter(redirected))
        XCTAssertEqual(try s.shelters().first?.receivingDeviceID, c)
        XCTAssertThrowsError(try ShelterContact.importCode("not a code"))
    }

    func testRemovalIsReversibleAcrossRestartAndPreservesRequestsAndReceipts() throws {
        let path = temporaryPath(); defer { try? FileManager.default.removeItem(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path) }
        var s: RelayStore? = try RelayStore.open(path: path, deviceID: a)
        try s!.saveShelter(shelter)
        let request = try s!.submitHelpDraft(draft(), now: now)
        let receipt = RelayMessage(originID: c, destinationID: a, messageType: .receipt,
            payload: Payload(text: "Saved", originalMessageID: request.id), createdAt: now, hopCount: 1)
        _ = try s!.receive(receipt, now: now)
        var unsent = draft(); unsent.details = "SYNTHETIC draft remains"
        try s!.saveHelpDraft(unsent)
        try s!.removeShelter(shelter.id)
        XCTAssertTrue(try s!.shelters().isEmpty)
        XCTAssertEqual(try s!.helpDraft()?.shelterID, "")
        XCTAssertEqual(try s!.helpDraft()?.details, unsent.details)
        try s!.saveHelpDraft(unsent) // Delayed autosave cannot restore the old selection.
        XCTAssertEqual(try s!.helpDraft()?.shelterID, "")
        XCTAssertThrowsError(try s!.submitHelpDraft(unsent, now: now))
        s = nil; s = try RelayStore.open(path: path)
        XCTAssertEqual(s!.deviceID, a)
        XCTAssertTrue(try s!.shelters().isEmpty)
        XCTAssertEqual(try s!.shelters(includeRemoved: true), [shelter])
        XCTAssertEqual(try s!.message(request.id), request)
        XCTAssertEqual(try s!.summaries().first?.finalReceiptID, receipt.id)
        XCTAssertEqual(HelpRequestItem.project(try s!.summaries(), deviceID: a, inbox: false).map(\.id), [request.id])
        try s!.saveShelter(ShelterContact.importCode(shelter.shareCode()))
        XCTAssertEqual(try s!.shelters(), [shelter])
        XCTAssertEqual(try s!.allMessages().count, 2)
    }

    func testRemovedShelterCannotBeRedirectedByImport() throws {
        let s = try store(a); try s.saveShelter(shelter); try s.removeShelter(shelter.id)
        let redirected = ShelterContact(id: shelter.id, name: shelter.name, area: shelter.area, receivingDeviceID: b, updatedAt: now)
        XCTAssertThrowsError(try s.saveShelter(redirected))
        XCTAssertTrue(try s.shelters().isEmpty)
        XCTAssertEqual(try s.shelters(includeRemoved: true), [shelter])
        XCTAssertThrowsError(try s.removeShelter(UUID().uuidString.lowercased()))
    }

    func testWrappedSharedCodeImportsButTruncatedAndForeignTextFail() throws {
        let code = try shelter.shareCode()
        let split = code.index(code.startIndex, offsetBy: 60)
        let wrapped = "  " + code[..<split] + "\n  " + code[split...] + "\n"
        XCTAssertEqual(try ShelterContact.importCode(wrapped), shelter)
        XCTAssertThrowsError(try ShelterContact.importCode(String(code.dropLast(17))))
        XCTAssertThrowsError(try ShelterContact.importCode("Hello " + code))
        XCTAssertThrowsError(try ShelterContact.importCode("RELAY-SHELTER-1:" + String(repeating: "A", count: 5000)))
    }

    func testDraftRecoveryAndAtomicIdempotentSubmission() throws {
        let path = temporaryPath(); defer { try? FileManager.default.removeItem(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path) }
        var s: RelayStore? = try RelayStore.open(path: path, deviceID: a)
        let d = draft(); try s!.saveShelter(shelter); try s!.saveHelpDraft(d); s = nil
        s = try RelayStore.open(path: path)
        XCTAssertEqual(s!.deviceID, a); XCTAssertEqual(try s!.helpDraft(), d)
        XCTAssertEqual(try s!.shelters(), [shelter])
        let m = try s!.submitHelpDraft(d, now: now)
        XCTAssertEqual(m.id, d.requestID); XCTAssertEqual(m.destinationID, c)
        XCTAssertNil(try s!.helpDraft())
        XCTAssertEqual(try s!.submitHelpDraft(d, now: now.addingTimeInterval(60)), m)
        try s!.saveHelpDraft(d) // Delayed autosave must not resurrect the submitted draft.
        XCTAssertNil(try s!.helpDraft()); XCTAssertEqual(try s!.allMessages().count, 1)
        var changed = d; changed.details = "Different request"
        XCTAssertThrowsError(try s!.submitHelpDraft(changed, now: now))
        s = nil; s = try RelayStore.open(path: path)
        XCTAssertEqual(try s!.message(m.id), m); XCTAssertNil(try s!.helpDraft())
    }

    func testFailedSubmissionRetainsDraftAndDoesNotCreateMessage() throws {
        let s = try store(a); var d = draft(); d.quantity = "-2"
        try s.saveShelter(shelter); try s.saveHelpDraft(d)
        XCTAssertThrowsError(try s.submitHelpDraft(d, now: now))
        XCTAssertEqual(try s.helpDraft(), d); XCTAssertTrue(try s.allMessages().isEmpty)
        d.quantity = ""; d.unit = ""; d.people = ""
        let request = try d.request(to: shelter)
        XCTAssertNil(request.quantity); XCTAssertNil(request.people)
        d.people = "0"; XCTAssertThrowsError(try d.request(to: shelter))
        d.people = "2"; d.quantity = "3.5"; XCTAssertThrowsError(try d.request(to: shelter))
    }

    func testStoreFailureRollsBackSubmitAndKeepsDraft() throws {
        let path = temporaryPath(); defer { try? FileManager.default.removeItem(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path) }
        let s = try RelayStore.open(path: path, deviceID: a); let d = draft()
        try s.saveShelter(shelter); try s.saveHelpDraft(d)
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TRIGGER fail_submit BEFORE INSERT ON messages BEGIN SELECT RAISE(ABORT,'synthetic failure'); END;", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try s.submitHelpDraft(d, now: now))
        XCTAssertEqual(try s.helpDraft(), d); XCTAssertNil(try s.message(d.requestID))
    }

    func testVersionTwoUpgradePreservesOldIdentityMessagesReceiptsAndPeers() throws {
        let path = temporaryPath(); defer { try? FileManager.default.removeItem(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path) }
        var s: RelayStore? = try RelayStore.open(path: path, deviceID: a)
        let old = RelayMessage(originID: a, destinationID: c, payload: Payload(text: "SYNTHETIC legacy chat"), createdAt: now)
        try s!.saveLocal(old, now: now)
        let receipt = RelayMessage(originID: c, destinationID: a, messageType: .receipt,
            payload: Payload(text: "Saved", originalMessageID: old.id), createdAt: now, hopCount: 1)
        _ = try s!.receive(receipt, now: now); try s!.remember(Peer(deviceID: b, role: .relay, displayName: "Courier"))
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "DROP TABLE shelters; PRAGMA user_version=2;", nil, nil, nil), SQLITE_OK); sqlite3_close(db)
        s = nil
        let reopened = try RelayStore.open(path: path)
        XCTAssertEqual(reopened.deviceID, a); XCTAssertEqual(try reopened.message(old.id), old)
        XCTAssertEqual(try reopened.summaries().first?.finalReceiptID, receipt.id)
        XCTAssertEqual(try reopened.knownPeers().first?.displayName, "Courier")
        try reopened.saveShelter(shelter); XCTAssertEqual(try reopened.shelters(), [shelter])
    }

    func testStructuredPayloadIsPreservedByLegacyJSONCodecAndBoundToDestination() throws {
        let s = try store(a); try s.saveShelter(shelter)
        let m = try s.submitHelpDraft(draft(), now: now)
        struct OldPayload: Codable { let text: String; let original_message_id: String? }
        struct OldMessage: Codable {
            let protocol_version: Int; let message_id: String; let origin_id: String; let destination_id: String
            let message_type: String; let payload: OldPayload; let created_at: String; let expires_at: String
            let hop_count: Int; let max_hops: Int
        }
        let legacy = try JSONDecoder().decode(OldMessage.self, from: WireCodec.encode(m))
        let returned = try WireCodec.decode(RelayMessage.self, from: JSONEncoder().encode(legacy))
        XCTAssertEqual(returned, m)
        XCTAssertEqual(try ShelterRequestCodec.decode(returned).shelter.id, shelterID)
        let misrouted = RelayMessage(messageID: m.id, originID: a, destinationID: b, payload: m.payload, createdAt: now, hopCount: 1)
        XCTAssertThrowsError(try store(b).receive(misrouted, now: now))
        let future = RelayMessage(originID: a, destinationID: c, payload: Payload(text: "RELAY-HELP-2\n{}"), createdAt: now, hopCount: 1)
        XCTAssertThrowsError(try store(c).receive(future, now: now))
    }

    func testShelterRequestCarryRestartRetryReceiptAndInboxIsolation() throws {
        let path = temporaryPath(); defer { try? FileManager.default.removeItem(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path) }
        let sender = RelayEngine(store: try store(a), role: .sender)
        var carrier: RelayEngine? = RelayEngine(store: try RelayStore.open(path: path, deviceID: b), role: .relay)
        let receiver = RelayEngine(store: try store(c), role: .receiver)
        try sender.store.saveShelter(shelter)
        let d = draft(); try sender.store.saveHelpDraft(d)
        let m = try sender.submitHelpRequest(d, now: now)
        var wire: SimulatedEncounter? = SimulatedEncounter(sender, carrier!, now: now)
        wire!.cutMessages = true; try wire!.drain(); wire!.end(); wire = nil
        XCTAssertNil(try carrier!.store.message(m.id)); XCTAssertNil(try sender.store.summaries().first?.finalReceiptID)
        wire = SimulatedEncounter(sender, carrier!, now: now.addingTimeInterval(20))
        try wire!.drain(); wire!.end(); wire = nil
        XCTAssertTrue(HelpRequestItem.project(try carrier!.store.summaries(), deviceID: b, inbox: true).isEmpty)
        carrier = nil
        carrier = RelayEngine(store: try RelayStore.open(path: path), role: .relay)
        XCTAssertEqual(try ShelterRequestCodec.decode(XCTUnwrap(carrier!.store.message(m.id))).quantity, 20)
        wire = SimulatedEncounter(carrier!, receiver, now: now.addingTimeInterval(40))
        try wire!.drain()
        for _ in 0..<3 { try carrier!.retransmitForTest(m.id, now: now.addingTimeInterval(41)); try wire!.drain() }
        wire!.end(); wire = nil
        XCTAssertEqual(try receiver.store.allMessages().count, 2)
        XCTAssertEqual(HelpRequestItem.project(try receiver.store.summaries(), deviceID: c, inbox: true).map(\.id), [m.id])
        XCTAssertTrue(RelayConversation.project(try receiver.store.summaries(), deviceID: c).isEmpty)
        carrier = nil
        carrier = RelayEngine(store: try RelayStore.open(path: path), role: .relay)
        wire = SimulatedEncounter(carrier!, sender, now: now.addingTimeInterval(60)); try wire!.drain(); wire!.end()
        XCTAssertNotNil(HelpRequestItem.project(try sender.store.summaries(), deviceID: a, inbox: false).first?.stored.finalReceiptID)
        XCTAssertTrue(HelpRequestItem.project(try carrier!.store.summaries(), deviceID: b, inbox: false).isEmpty)
        XCTAssertTrue(RelayConversation.project(try sender.store.summaries(), deviceID: a).isEmpty)
    }
}
