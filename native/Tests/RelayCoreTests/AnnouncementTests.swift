import XCTest
@testable import RelayCore

final class AnnouncementTests: XCTestCase {
    func testCachedFeedSurvivesRestartAndIsAccountScoped() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("relay.sqlite")
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let now = WireCodec.second(Date())
        let alert = CloudAnnouncement(announcement_id: UUID().uuidString, incident_id: "test", shelter_id: "a", title: "Synthetic", text: "A test announcement", severity: "important", publisher: "Test dispatcher", created_at: now, updated_at: now, expires_at: now.addingTimeInterval(3600), revision: 1, withdrawn: false)
        var store: RelayStore? = try .open(path: path.path)
        try store!.saveAnnouncementFeed(AnnouncementFeed(items: [alert], fetched_at: now), scope: "account-a")
        store = nil; store = try .open(path: path.path)
        XCTAssertEqual(try store!.announcementFeed(scope: "account-a")?.items, [alert])
        XCTAssertNil(try store!.announcementFeed(scope: "account-b"))
        XCTAssertTrue(alert.active(at: now)); XCTAssertFalse(alert.active(at: now.addingTimeInterval(3600)))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: CloudCodec.encode(alert)) as? [String: Any])
        object["withdrawn"] = true; object["revision"] = 2
        let withdrawn = try CloudCodec.decode(CloudAnnouncement.self, JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(withdrawn.active(at: now))
        try store!.saveAnnouncementFeed(AnnouncementFeed(items: [withdrawn], fetched_at: now), scope: "account-a")
        XCTAssertEqual(try store!.announcementFeed(scope: "account-a")?.items.first?.revision, 2)
    }
    func testPublishingCommandRetainsExactIDAndContentForRetry() throws {
        let command = try AnnouncementCommand(shelterID: "a", title: " Test ", text: " Synthetic ", severity: "info", expiresAt: Date().addingTimeInterval(3600))
        XCTAssertEqual(try CloudCodec.decode(AnnouncementCommand.self, CloudCodec.encode(command)), command)
        XCTAssertEqual(command.title, "Test"); XCTAssertNotNil(UUID(uuidString: command.announcement_id))
        XCTAssertThrowsError(try AnnouncementCommand(shelterID: "a", title: " ", text: "x", severity: "info", expiresAt: Date()))
    }
    func testDistanceHandlesSamePointDatelineAndNoCoordinates() throws {
        func details(_ lat: Double?, _ lon: Double?) -> ShelterDetails { ShelterDetails(address: "Test", instructions: "Test only", latitude: lat, longitude: lon, revision: 1, updated_at: Date()) }
        let location = try RequestLocation(latitude: 0, longitude: 0, accuracy: 10)
        XCTAssertEqual(try XCTUnwrap(details(0, 0).distance(from: location)), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(details(0, 1).distance(from: location)), 111194.9, accuracy: 1)
        let edge = try RequestLocation(latitude: 0, longitude: 179.9, accuracy: 10)
        XCTAssertEqual(try XCTUnwrap(details(0, -179.9).distance(from: edge)), 22238.99, accuracy: 1)
        XCTAssertNil(details(nil, nil).distance(from: location))
        XCTAssertThrowsError(try ShelterDetailsCommand(revision: 0, address: "", instructions: "", latitude: "1", longitude: ""))
        XCTAssertThrowsError(try ShelterDetailsCommand(revision: 0, address: "", instructions: "", latitude: "NaN", longitude: "1"))
    }
    func testLegacyDirectoryDecodesWithoutDetailsAndNewFieldsRoundTrip() throws {
        let old = Data(#"{"shelter_id":"a","incident_id":"demo","display_name":"Test shelter"}"#.utf8)
        var shelter = try CloudCodec.decode(CloudShelter.self, old)
        XCTAssertNil(shelter.details)
        shelter.details = ShelterDetails(address: "Test only", instructions: "East entrance", latitude: 0, longitude: 0, revision: 1, updated_at: WireCodec.second(Date()))
        XCTAssertEqual(try CloudCodec.decode(CloudShelter.self, CloudCodec.encode(shelter)), shelter)
    }
    func testNewRequestNeedsLocationOrLandmarkWithoutChangingHistoricalPayloads() throws {
        var draft = RequestDraft()
        XCTAssertThrowsError(try draft.validateLocationForNewRequest())
        draft.landmark = "  \n "; XCTAssertThrowsError(try draft.validateLocationForNewRequest())
        draft.landmark = "Fictional hall, room 12"; XCTAssertNoThrow(try draft.validateLocationForNewRequest())
        draft.landmark = ""; draft.location = try RequestLocation(latitude: 0, longitude: 0, accuracy: 1000, precision: "approximate")
        XCTAssertNoThrow(try draft.validateLocationForNewRequest())
        draft.location = nil
        XCTAssertNoThrow(try draft.fields(), "Legacy records and partial extraction do not acquire a new mandatory wire field")
    }
}
