import XCTest
@testable import RelayCore

final class SealedDeliveryTests: XCTestCase {
    let a = "10000000-0000-0000-0000-00000000000a"
    let b = "10000000-0000-0000-0000-00000000000b"
    let c = "10000000-0000-0000-0000-00000000000c"
    let scope = String(repeating: "a", count: 64)
    let now = WireCodec.second(Date())
    var shelter: CloudShelter { .init(shelter_id: "shelter-a", incident_id: "synthetic-demo-01", display_name: "Synthetic shelter") }
    func draft() throws -> RequestDraft {
        var d = RequestDraft(); d.shelterID = shelter.shelter_id; d.text = "SYNTHETIC water at test point"; d.item = "water_packs"; d.quantity = "2"
        d.location = try RequestLocation(latitude: 0.12345, longitude: 0.54321, accuracy: 100, source: "manual")
        return d
    }
    func testSealingProtectsTextAndLocationAndBindsRoute() throws {
        let sender = try DeviceIdentity(deviceID: a), receiver = try DeviceIdentity(deviceID: c)
        let submission = try CloudSubmission(draft: draft(), shelter: shelter, deviceID: a, now: now)
        var m = try SealedDelivery.seal(submission, identity: sender, receiver: receiver.address.forAccount("test-dispatcher-a"), subject: "test-requester-a")
        XCTAssertFalse(m.payload.text.contains("SYNTHETIC water")); XCTAssertFalse(m.payload.text.contains("0.12345"))
        m.hopCount = 2
        XCTAssertEqual(try SealedDelivery.open(m, identity: receiver).verifiedBody().submission, submission)
        XCTAssertThrowsError(try SealedDelivery.open(m, identity: sender))
        let retargeted = RelayMessage(messageID: m.id, originID: b, destinationID: c, payload: m.payload, createdAt: m.createdAt, expiresAt: m.expiresAt, hopCount: 2)
        XCTAssertThrowsError(try SealedDelivery.open(retargeted, identity: receiver))
        let extended = RelayMessage(messageID: m.id, originID: a, destinationID: c, payload: m.payload, createdAt: m.createdAt, expiresAt: m.expiresAt.addingTimeInterval(1), hopCount: 2)
        XCTAssertThrowsError(try SealedDelivery.open(extended, identity: receiver))
    }
    func testEncryptedCarryRestartAndSignedReturnReceipt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let senderStore = try RelayStore.open(path: ":memory:", deviceID: a)
        let destinationStore = try RelayStore.open(path: ":memory:", deviceID: c)
        try senderStore.enableSealedDelivery(DeviceIdentity(deviceID: a))
        try destinationStore.enableSealedDelivery(DeviceIdentity(deviceID: c))
        var d = try draft()
        d.item = "medicines"; d.medicineDetails = "Synthetic inhaler request"; d.urgency = "urgent"; d.requestedUnit = "item"
        let saved = try senderStore.submitCloudDraft(d, scope: scope, shelter: shelter, receiver: destinationStore.sealedIdentity!.address.forAccount("test-dispatcher-a"), senderSubject: "test-requester-a", now: now)
        let sender = RelayEngine(store: senderStore), receiver = RelayEngine(store: destinationStore)
        var carrier: RelayEngine? = RelayEngine(store: try .open(path: folder.appendingPathComponent("carrier.sqlite").path, deviceID: b))
        var wire: SimulatedEncounter? = SimulatedEncounter(sender, carrier!, now: now)
        try wire!.drain(); wire!.end(); wire = nil; carrier = nil
        carrier = RelayEngine(store: try .open(path: folder.appendingPathComponent("carrier.sqlite").path))
        XCTAssertTrue(try carrier!.store.nearbyRequests().isEmpty, "Carriers do not decrypt application content")
        wire = SimulatedEncounter(carrier!, receiver, now: now.addingTimeInterval(5)); try wire!.drain()
        try carrier!.retransmitForTest(d.id, now: now.addingTimeInterval(6)); try wire!.drain(); wire!.end(); wire = nil; carrier = nil
        XCTAssertEqual(try destinationStore.nearbyRequests().count, 1)
        XCTAssertEqual(try XCTUnwrap(destinationStore.nearbyRequests().first).verifiedBody().submission, saved.submission)
        XCTAssertEqual(try destinationStore.allMessages().count, 2)
        carrier = RelayEngine(store: try .open(path: folder.appendingPathComponent("carrier.sqlite").path))
        wire = SimulatedEncounter(carrier!, sender, now: now.addingTimeInterval(10)); try wire!.drain(); wire!.end()
        let row = try XCTUnwrap(senderStore.summaries().first { $0.id == d.id })
        XCTAssertNotNil(row.finalReceiptID); XCTAssertEqual(row.message.id, saved.id)
        XCTAssertTrue(RelayConversation.project(try senderStore.summaries(), deviceID: a).isEmpty)
        XCTAssertTrue(RelayConversation.project(try destinationStore.summaries(), deviceID: c).isEmpty)
    }
    func testForgedPlainReceiptCannotMarkEncryptedRequestDelivered() throws {
        let sender = try RelayStore.open(path: ":memory:", deviceID: a), destination = try DeviceIdentity(deviceID: c)
        try sender.enableSealedDelivery(DeviceIdentity(deviceID: a))
        let saved = try sender.submitCloudDraft(draft(), scope: scope, shelter: shelter, receiver: destination.address.forAccount("test-dispatcher-a"), senderSubject: "test-requester-a", now: now)
        let forged = RelayMessage(originID: c, destinationID: a, messageType: .receipt,
            payload: Payload(text: "Final destination persisted request", originalMessageID: saved.id), createdAt: now, hopCount: 1)
        XCTAssertThrowsError(try sender.receive(forged, now: now))
        XCTAssertNil(try sender.summaries().first?.finalReceiptID)
        XCTAssertNil(try sender.message(forged.id))
        var receipt = try SealedDelivery.receipt(for: XCTUnwrap(sender.message(saved.id)), identity: destination, now: now)
        receipt.hopCount = 2
        XCTAssertTrue(try sender.receive(receipt, now: now).recognizedReceipt)
    }
    func testUnreadableRecipientNeverPersistsOrCreatesSuccessReceipt() throws {
        let sender = try DeviceIdentity(deviceID: a), correct = try DeviceIdentity(deviceID: c)
        let store = try RelayStore.open(path: ":memory:", deviceID: c)
        try store.enableSealedDelivery(DeviceIdentity(deviceID: c)) // Same UUID, wrong key.
        var m = try SealedDelivery.seal(CloudSubmission(draft: draft(), shelter: shelter, deviceID: a, now: now), identity: sender, receiver: correct.address.forAccount("test-dispatcher-a"), subject: "test-requester-a")
        m.hopCount = 1
        XCTAssertThrowsError(try store.receive(m, now: now)); XCTAssertTrue(try store.allMessages().isEmpty)
        XCTAssertTrue(try store.nearbyRequests().isEmpty)
    }
    func testOversizedNearbyCopyRollsBackCloudQueueAndKeepsDraft() throws {
        let store = try RelayStore.open(path: ":memory:", deviceID: a)
        try store.enableSealedDelivery(DeviceIdentity(deviceID: a))
        var d = try draft(); d.text = String(repeating: "🌊", count: 4096)
        try store.saveRequestDraft(d, scope: scope)
        XCTAssertThrowsError(try store.submitCloudDraft(d, scope: scope, shelter: shelter, receiver: DeviceIdentity(deviceID: c).address.forAccount("test-dispatcher-a"), senderSubject: "test-requester-a", now: now))
        XCTAssertTrue(try store.cloudRecords(scope: scope).isEmpty); XCTAssertTrue(try store.allMessages().isEmpty)
        XCTAssertEqual(try store.requestDraft(scope: scope), d)
    }
    func testKeyMaterialSurvivesRestartAndInvalidFileIsNeverOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("keys.json")
        let first = try DeviceIdentity.load(deviceID: c, at: file), second = try DeviceIdentity.load(deviceID: c, at: file)
        XCTAssertEqual(first.address, second.address)
        XCTAssertThrowsError(try DeviceIdentity.load(deviceID: a, at: file))
        let invalid = Data("broken".utf8); try invalid.write(to: file)
        XCTAssertThrowsError(try DeviceIdentity.load(deviceID: c, at: file)); XCTAssertEqual(try Data(contentsOf: file), invalid)
    }
    func testLateCloudWriteCannotRegressVerifiedNearbyDelivery() throws {
        let store = try RelayStore.open(path: ":memory:", deviceID: a), receiver = try DeviceIdentity(deviceID: c)
        try store.enableSealedDelivery(DeviceIdentity(deviceID: a))
        var stale = try store.submitCloudDraft(draft(), scope: scope, shelter: shelter, receiver: receiver.address.forAccount("test-dispatcher-a"), senderSubject: "test-requester-a", now: now)
        let original = try XCTUnwrap(store.message(stale.id))
        var receipt = try SealedDelivery.receipt(for: original, identity: receiver, now: now); receipt.hopCount = 1
        _ = try store.receive(receipt, now: now)
        stale.nearbyState = "queued"; stale.state = "accepted"
        try store.saveCloudRecord(stale)
        XCTAssertEqual(try store.cloudRecords(scope: scope).first?.nearbyState, "shelter_saved")
    }

}
