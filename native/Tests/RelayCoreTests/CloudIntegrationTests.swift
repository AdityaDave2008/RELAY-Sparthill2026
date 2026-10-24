import XCTest
@testable import RelayCore

final class CloudIntegrationTests: XCTestCase {
    private let a = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private let b = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private func fixture(_ store: RelayStore) throws -> (HelpRequestDraft, CloudBinding) {
        let shelter = ShelterContact(name: "Synthetic A", area: "Demo hall", receivingDeviceID: b)
        try store.saveShelter(shelter)
        var draft = HelpRequestDraft(); draft.shelterID = shelter.id; draft.details = "Need 2 water packs"
        draft.quantity = "2"; draft.unit = "packs"; draft.location = "Demo hall"
        return (draft, CloudBinding(localID: shelter.id, incidentID: "synthetic-demo-01", shelterID: "shelter-a"))
    }
    func testAtomicCloudIntentSurvivesRestartAndPreservesLocalIdentity() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var store: RelayStore? = try .open(path: folder.appendingPathComponent("relay.sqlite").path, deviceID: a)
        var (draft, binding) = try fixture(store!)
        let scope = CloudCodec.scope(baseURL: URL(string: "https://relay.example")!, subject: "one")
        draft.cloudScope = scope; draft.cloudBinding = binding
        let message = try store!.submitHelpDraft(draft, now: Date())
        store = nil; store = try .open(path: folder.appendingPathComponent("relay.sqlite").path)
        let record = try XCTUnwrap(store!.cloudRecords(scope: scope).first)
        XCTAssertEqual(record.id, message.id); XCTAssertEqual(record.submission.operation_id, message.id)
        XCTAssertEqual(record.submission.origin_device_id, a); XCTAssertEqual(record.state, "queued")
        XCTAssertEqual(try store!.message(message.id), message)
        XCTAssertEqual(store!.deviceID, a)
        XCTAssertTrue(try store!.cloudRecords(scope: CloudCodec.scope(baseURL: URL(string: "https://relay.example")!, subject: "two")).isEmpty)
    }
    func testInvalidCloudIntentRollsBackMessageAndKeepsDraft() throws {
        let store = try RelayStore.open(path: ":memory:", deviceID: a)
        var (draft, binding) = try fixture(store); draft.cloudScope = "bad-scope"; draft.cloudBinding = binding
        try store.saveHelpDraft(draft)
        XCTAssertThrowsError(try store.submitHelpDraft(draft, now: Date()))
        XCTAssertNil(try store.message(draft.requestID)); XCTAssertEqual(try store.helpDraft()?.requestID, draft.requestID)
    }
    func testCarrierCannotUploadUnderItsOwnIdentityAndContentCannotChange() throws {
        let store = try RelayStore.open(path: ":memory:", deviceID: a)
        let (draft, binding) = try fixture(store); let message = try store.submitHelpDraft(draft, now: Date())
        XCTAssertThrowsError(try CloudSubmission(message: message, binding: binding, localDeviceID: b))
        let submission = try CloudSubmission(message: message, binding: binding, localDeviceID: a)
        let scope = CloudCodec.scope(baseURL: URL(string: "https://relay.example")!, subject: "one")
        try store.saveCloudRecord(CloudQueueRecord(scope: scope, submission: submission))
        let different = CloudBinding(localID: binding.localID, incidentID: binding.incidentID, shelterID: "different")
        let changed = try CloudSubmission(message: message, binding: different, localDeviceID: a)
        XCTAssertThrowsError(try store.saveCloudRecord(CloudQueueRecord(scope: scope, submission: changed)))
    }
    func testInterruptedCloudAttemptPreservesExactSubmission() throws {
        let store = try RelayStore.open(path: ":memory:", deviceID: a)
        let (draft, binding) = try fixture(store); let message = try store.submitHelpDraft(draft, now: Date())
        let scope = String(repeating: "a", count: 64)
        var record = CloudQueueRecord(scope: scope, submission: try CloudSubmission(message: message, binding: binding, localDeviceID: a))
        let original = try CloudCodec.encode(record.submission)
        record.failed("Connection lost after server commit", retryable: true)
        try store.saveCloudRecord(record)
        let recovered = try XCTUnwrap(store.cloudRecords(scope: scope).first)
        XCTAssertEqual(try CloudCodec.encode(recovered.submission), original)
        XCTAssertNil(recovered.result); XCTAssertEqual(recovered.state, "queued"); XCTAssertGreaterThan(recovered.retryAt, Date())
    }
    func testPKCECallbackRejectsWrongStateHostAndDuplicates() throws {
        let flow = OAuthPKCE()
        XCTAssertEqual(flow.challenge.count, 43)
        XCTAssertEqual(try flow.code(from: URL(string: "relay://oauth/callback?code=abc&state=\(flow.state)")!), "abc")
        for u in ["relay://oauth/callback?code=abc&state=wrong", "relay://evil/callback?code=abc&state=\(flow.state)", "relay://oauth/callback?code=abc&code=xyz&state=\(flow.state)"] {
            XCTAssertThrowsError(try flow.code(from: URL(string: u)!))
        }
    }
    func testEndpointRejectsInsecureAndCredentialBearingAddresses() throws {
        for u in ["http://relay.example", "https://name:secret@relay.example", "https://relay.example?token=secret"] { XCTAssertThrowsError(try CloudCodec.apiURL(u)) }
        XCTAssertThrowsError(try CloudCodec.apiURL("http://127.0.0.1:8787"))
        XCTAssertNoThrow(try CloudCodec.apiURL("http://127.0.0.1:8787", allowLoopback: true))
        XCTAssertThrowsError(try CloudCodec.apiURL("http://192.168.1.2:8787", allowLoopback: true))
    }
    func testLocalRequestRepliesStayOutOfChatsAndDeduplicate() throws {
        let store = try RelayStore.open(path: ":memory:", deviceID: a)
        let (draft, _) = try fixture(store); let request = try store.submitHelpDraft(draft, now: Date())
        let note = LocalRequestUpdate(requestID: request.id, text: "SYNTHETIC acknowledged", progress: "accepted")
        let reply = RelayMessage(originID: b, destinationID: a, payload: Payload(text: try note.encode()), createdAt: WireCodec.second(Date()), hopCount: 1)
        _ = try store.receive(reply, now: Date()); let duplicate = try store.receive(reply, now: Date())
        XCTAssertTrue(duplicate.duplicate)
        XCTAssertEqual(LocalRequestUpdate.thread(try store.summaries(), request: request).count, 1)
        XCTAssertTrue(RelayConversation.project(try store.summaries(), deviceID: a).isEmpty)
        let alien = RelayMessage(originID: UUID().uuidString.lowercased(), destinationID: a, payload: Payload(text: try note.encode()), createdAt: WireCodec.second(Date()), hopCount: 1)
        _ = try store.receive(alien, now: Date())
        XCTAssertEqual(LocalRequestUpdate.thread(try store.summaries(), request: request).count, 1)
    }
    func testLegacyDraftDecodeAndCloudTimestampVariants() throws {
        let draft = HelpRequestDraft(); var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
        object.removeValue(forKey: "transcriptionID"); object.removeValue(forKey: "cloudScope")
        XCTAssertEqual(try JSONDecoder().decode(HelpRequestDraft.self, from: JSONSerialization.data(withJSONObject: object)).requestID, draft.requestID)
        struct Stamp: Decodable { let date: Date }
        XCTAssertNoThrow(try CloudCodec.decode(Stamp.self, Data("{\"date\":\"2026-10-24T06:20:10.123456+00:00\"}".utf8)))
        XCTAssertNoThrow(try CloudCodec.decode(Stamp.self, Data("{\"date\":\"2026-10-24T06:20:10Z\"}".utf8)))
    }
}
