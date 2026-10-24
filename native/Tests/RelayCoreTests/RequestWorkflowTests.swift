import XCTest
@testable import RelayCore

final class RequestWorkflowTests: XCTestCase {
    private let scope = String(repeating: "a", count: 64)
    private var shelter: CloudShelter { CloudShelter(shelter_id: "shelter-a", incident_id: "synthetic-demo-01", display_name: "Demo shelter") }
    private func draft() throws -> RequestDraft {
        var d = RequestDraft(); d.shelterID = shelter.shelter_id; d.text = "Shelter A needs 2 water packs."
        d.item = "water_packs"; d.quantity = "2"; d.landmark = "Synthetic test point"
        d.location = try RequestLocation(latitude: 0, longitude: 0, accuracy: 100, precision: "approximate", source: "manual")
        return d
    }
    func testLocationAndStructuredRequestSurviveRestartWithoutPlaintextPeerCopy() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("relay.sqlite").path
        var store: RelayStore? = try .open(path: path)
        let identity = store!.deviceID, d = try draft()
        try store!.saveRequestDraft(d, scope: scope)
        let saved = try store!.submitCloudDraft(d, scope: scope, shelter: shelter)
        store = nil; store = try .open(path: path)
        let record = try XCTUnwrap(store!.cloudRecords(scope: scope).first)
        XCTAssertEqual(record.submission, saved.submission)
        XCTAssertEqual(record.submission.location, d.location)
        XCTAssertEqual(record.submission.structured_fields?.quantity, 2)
        XCTAssertEqual(store!.deviceID, identity)
        XCTAssertNil(try store!.message(d.id), "Precise location must not enter the plaintext P2P store")
        XCTAssertNotEqual(try store!.requestDraft(scope: scope).id, d.id)
        XCTAssertTrue(try store!.cloudRecords(scope: String(repeating: "b", count: 64)).isEmpty)
    }
    func testExactReplayDoesNotDuplicateAndChangedContentIsRejected() throws {
        let store = try RelayStore.open(path: ":memory:")
        var d = try draft(); let first = try store.submitCloudDraft(d, scope: scope, shelter: shelter)
        let replay = try store.submitCloudDraft(d, scope: scope, shelter: shelter, now: Date().addingTimeInterval(40))
        XCTAssertEqual(first.submission, replay.submission); XCTAssertEqual(try store.cloudRecords(scope: scope).count, 1)
        d.quantity = "9"
        XCTAssertThrowsError(try store.submitCloudDraft(d, scope: scope, shelter: shelter))
        try store.saveRequestDraft(d, scope: scope)
        XCTAssertNotEqual(try store.requestDraft(scope: scope).id, d.id)
    }
    func testInvalidCloudSubmissionDoesNotClearDraft() throws {
        let store = try RelayStore.open(path: ":memory:"); var d = try draft(); d.quantity = "-2"
        try store.saveRequestDraft(d, scope: scope)
        XCTAssertThrowsError(try store.submitCloudDraft(d, scope: scope, shelter: shelter))
        XCTAssertEqual(try store.requestDraft(scope: scope).id, d.id)
        XCTAssertTrue(try store.cloudRecords(scope: scope).isEmpty)
    }
    func testLocationBoundsAndUnknownCounts() throws {
        XCTAssertThrowsError(try RequestLocation(latitude: .nan, longitude: 0, accuracy: 1))
        XCTAssertThrowsError(try RequestLocation(latitude: 91, longitude: 0, accuracy: 1))
        XCTAssertThrowsError(try RequestLocation(latitude: 0, longitude: 0, accuracy: -1))
        var d = try draft(); d.quantity = ""; d.people = ""
        XCTAssertNil(try d.fields().quantity); XCTAssertNil(try d.fields().people); XCTAssertNil(try d.fields().unit)
        d.quantity = "10001"; XCTAssertThrowsError(try d.fields())
    }
    func testEditedTextCannotReuseOldInterpretation() throws {
        var d = try draft(); d.interpretationReady = true; d.interpretationID = UUID().uuidString.lowercased()
        d.interpretationText = d.text; d.interpretationShelter = d.shelterID
        let device = UUID().uuidString.lowercased()
        XCTAssertEqual(try CloudSubmission(draft: d, shelter: shelter, deviceID: device).interpretation_id, d.interpretationID)
        d.text = "Now need food"
        XCTAssertNil(try CloudSubmission(draft: d, shelter: shelter, deviceID: device).interpretation_id)
    }
    func testInventoryOperationPersistsAcrossLostResponse() throws {
        let store = try RelayStore.open(path: ":memory:")
        var record = try store.submitCloudDraft(draft(), scope: scope, shelter: shelter)
        record.pendingInventory = InventoryCommand(action: "reserve", item: "water_packs", quantity: 2, revision: 1)
        record.failed("Connection lost after commit", retryable: true)
        try store.saveCloudRecord(record)
        let recovered = try XCTUnwrap(store.cloudRecords(scope: scope).first)
        XCTAssertEqual(recovered.pendingInventory, record.pendingInventory)
        XCTAssertEqual(recovered.submission, record.submission)
    }
    func testEndpointMigrationRetainsRequestsDraftAudioAndPendingInventoryWithoutOverwritingNewerState() throws {
        let store = try RelayStore.open(path: ":memory:"), target = String(repeating: "b", count: 64)
        var record = try store.submitCloudDraft(draft(), scope: scope, shelter: shelter)
        record.pendingInventory = InventoryCommand(action: "reserve", item: "water_packs", quantity: 2, revision: 1)
        record.attempts = 3; try store.saveCloudRecord(record)
        let next = try draft(); try store.saveRequestDraft(next, scope: scope)
        try store.setSetting("cloud_audio:" + scope, "retained-audio-reference")
        try store.setSetting("inventory_adjustment:" + scope + ":shelter-a", "pending-operation")
        try store.copyCloudScope(from: scope, to: target)
        var copy = try XCTUnwrap(store.cloudRecords(scope: target).first)
        XCTAssertEqual(copy.submission, record.submission); XCTAssertEqual(copy.pendingInventory, record.pendingInventory)
        XCTAssertEqual(copy.attempts, 3); XCTAssertEqual(try store.requestDraft(scope: target), next)
        XCTAssertEqual(try store.setting("cloud_audio:" + target), "retained-audio-reference")
        XCTAssertEqual(try store.setting("inventory_adjustment:" + target + ":shelter-a"), "pending-operation")
        copy.state = "accepted"; try store.saveCloudRecord(copy)
        try store.copyCloudScope(from: scope, to: target)
        XCTAssertEqual(try store.cloudRecords(scope: target).first?.state, "accepted")
        XCTAssertEqual(try store.cloudRecords(scope: scope).count, 1)
    }
    func testEndpointMigrationRejectsConflictingContentAtomically() throws {
        let store = try RelayStore.open(path: ":memory:"), target = String(repeating: "b", count: 64)
        var source = try draft(); _ = try store.submitCloudDraft(source, scope: scope, shelter: shelter)
        source.text = "Conflicting content"; _ = try store.submitCloudDraft(source, scope: target, shelter: shelter)
        try store.setSetting("cloud_audio:" + scope, "audio")
        XCTAssertThrowsError(try store.copyCloudScope(from: scope, to: target))
        XCTAssertNil(try store.setting("cloud_audio:" + target))
    }

    func testLegacyDraftAndFieldsDecodeWithoutNewKeys() throws {
        let original = try draft()
        let restored = try CloudCodec.decode(RequestDraft.self, CloudCodec.encode(original))
        XCTAssertNil(restored.urgency); XCTAssertNil(restored.medicineDetails); XCTAssertNil(restored.requestedUnit)
        let fields = try JSONSerialization.jsonObject(with: CloudCodec.encode(original.fields())) as! [String: Any]
        XCTAssertNil(fields["urgency"]); XCTAssertNil(fields["medicine_details"])
    }
    func testMedicineUrgencyAndUnitsSurviveDraftRestart() throws {
        let store = try RelayStore.open(path: ":memory:")
        var d = try draft(); d.item = "medicines"; d.medicineDetails = "Synthetic inhaler request"
        d.urgency = "urgent"; d.requestedUnit = "item"
        try store.saveRequestDraft(d, scope: scope)
        let recovered = try store.requestDraft(scope: scope)
        XCTAssertEqual(recovered.urgency, "urgent"); XCTAssertEqual(recovered.unit, "item")
        let record = try store.submitCloudDraft(recovered, scope: scope, shelter: shelter)
        XCTAssertEqual(record.submission.structured_fields?.medicine_details, d.medicineDetails)
        XCTAssertEqual(record.submission.structured_fields?.urgency, "urgent")
        d.urgency = "invented"; XCTAssertThrowsError(try d.fields())
    }
    func testLateSnapshotKeepsNewerReplyAndPendingOperation() throws {
        let store = try RelayStore.open(path: ":memory:")
        var record = try store.submitCloudDraft(draft(), scope: scope, shelter: shelter)
        let pending = CloudEventCommand(revision: 0, text: "Synthetic queued reply", status: nil)
        record.pendingEvent = pending; record.state = "needs_attention"; record.problem = "Pending conflict"
        try store.saveCloudRecord(record)
        func snapshot(_ revision: Int) throws -> CloudResult {
            let body = try JSONSerialization.jsonObject(with: CloudCodec.encode(record.submission))
            let value: [String: Any] = ["request_id": record.id, "submission": body, "cloud_state": "accepted", "analysis_state": "ready_for_review", "history": ["request_id": record.id, "revision": revision, "status": "accepted", "events": []]]
            return try CloudCodec.decode(CloudResult.self, JSONSerialization.data(withJSONObject: value))
        }
        try store.mergeCloudSnapshot(snapshot(2), scope: scope)
        try store.mergeCloudSnapshot(snapshot(1), scope: scope)
        let current = try XCTUnwrap(store.cloudRecords(scope: scope).first)
        XCTAssertEqual(current.history?.revision, 2)
        XCTAssertEqual(current.pendingEvent, pending); XCTAssertEqual(current.state, "needs_attention")
        XCTAssertEqual(current.problem, "Pending conflict"); XCTAssertEqual(current.submission, record.submission)
    }

    func testLegacyWholeSecondCacheAcceptsFractionalServerTimestampButNotChangedContent() throws {
        let store = try RelayStore.open(path: ":memory:")
        let record = try store.submitCloudDraft(draft(), scope: scope, shelter: shelter)
        var body = try JSONSerialization.jsonObject(with: CloudCodec.encode(record.submission)) as! [String: Any]
        let originalDate = body["created_at"] as! String
        body["created_at"] = originalDate.replacingOccurrences(of: "Z", with: ".250Z")
        func snapshot() throws -> CloudResult {
            let value: [String: Any] = ["request_id": record.id, "submission": body, "cloud_state": "accepted", "analysis_state": "pending"]
            return try CloudCodec.decode(CloudResult.self, JSONSerialization.data(withJSONObject: value))
        }
        try store.mergeCloudSnapshot(snapshot(), scope: scope)
        XCTAssertEqual(try store.cloudRecords(scope: scope).first?.submission, record.submission)
        body["original_text"] = "Changed immutable body"
        XCTAssertThrowsError(try store.mergeCloudSnapshot(snapshot(), scope: scope))
    }

}
