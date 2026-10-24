import XCTest
@testable import RelayCore

final class ResidentDetailsTests: XCTestCase {
    func testAllPersonalFieldsAreOptional() throws {
        let value = try ResidentDetailsDraft().validated()
        XCTAssertTrue(value.isEmpty)
        XCTAssertNil(value.age); XCTAssertNil(value.heightCM); XCTAssertNil(value.weightKG)
        XCTAssertEqual(value.bloodGroup, "")
    }
    func testSelfReportedFieldsRoundTripWithoutDroppingNotes() throws {
        var draft = ResidentDetailsDraft()
        draft.name = "  Synthetic Test Resident  "; draft.age = "24"
        draft.height = "172.5"; draft.weight = "68.25"; draft.bloodGroup = "O−"
        draft.allergies = "Synthetic note"; draft.healthConditions = "Test condition — not real"
        draft.medications = "Test medicine"; draft.accessibilityNeeds = "Test communication preference"
        let value = try draft.validated()
        XCTAssertEqual(value.name, "Synthetic Test Resident"); XCTAssertEqual(value.heightCM, 172.5)
        XCTAssertEqual(try CloudCodec.decode(ResidentDetails.self, CloudCodec.encode(value)), value)
        XCTAssertEqual(try ResidentDetailsDraft(value).validated(), value)
    }
    func testNumericInputRejectsNonfiniteUnitsSuffixAndOutOfRangeValues() throws {
        for text in ["-1", "0", "301", "nan", "inf", "175 cm", "175abc", "1e2", "1,750"] {
            var draft = ResidentDetailsDraft(); draft.height = text
            XCTAssertThrowsError(try draft.validated(decimalSeparator: "."), text)
        }
        var draft = ResidentDetailsDraft(); draft.weight = "1001"
        XCTAssertThrowsError(try draft.validated())
        draft.weight = "0.5"; draft.height = "25"; draft.age = "0"
        XCTAssertNoThrow(try draft.validated())
        for age in ["-1", "24.5", "131", "twenty", "999999999999999999999"] {
            draft.age = age; XCTAssertThrowsError(try draft.validated())
        }
    }
    func testDecimalCommaWorksOnlyWhenChosenLocaleUsesIt() throws {
        var draft = ResidentDetailsDraft(); draft.weight = "68,5"
        XCTAssertEqual(try draft.validated(decimalSeparator: ",").weightKG, 68.5)
        XCTAssertThrowsError(try draft.validated(decimalSeparator: "."))
        draft.weight = "68.5"; XCTAssertEqual(try draft.validated(decimalSeparator: ",").weightKG, 68.5)
    }
    func testBloodGroupAndNoteBoundsPreserveUnknownInsteadOfGuessing() throws {
        var draft = ResidentDetailsDraft(); draft.bloodGroup = "probably O"
        XCTAssertThrowsError(try draft.validated())
        draft.bloodGroup = ""; draft.healthConditions = String(repeating: "a", count: 501)
        XCTAssertThrowsError(try draft.validated())
        draft.healthConditions = "   "; XCTAssertTrue(try draft.validated().isEmpty)
    }
    func testFirstRunFlagsPersistPerAccountAcrossRestartWithoutProfileData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("relay.sqlite").path
        var store: RelayStore? = try .open(path: path)
        let first = try store!.residentSetup(scope: "resident-a")
        XCTAssertTrue(first.needsWelcome)
        var skipped = first; skipped.profileOffered = true
        try store!.saveResidentSetup(skipped, scope: "resident-a")
        store = nil; store = try .open(path: path)
        var recovered = try store!.residentSetup(scope: "resident-a")
        XCTAssertTrue(recovered.needsWelcome); XCTAssertFalse(recovered.guideSeen)
        recovered.guideSeen = true; try store!.saveResidentSetup(recovered, scope: "resident-a")
        XCTAssertFalse(try store!.residentSetup(scope: "resident-a").needsWelcome)
        XCTAssertTrue(try store!.residentSetup(scope: "resident-b").needsWelcome)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: CloudCodec.encode(recovered)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["profileOffered", "guideSeen"], "Onboarding metadata must not hold medical/profile fields")
    }
    func testSupplyEmojiDoesNotChangeProtocolIdentifiersOrTitles() {
        XCTAssertEqual(InventoryItem.title("water_packs"), "Water packs")
        XCTAssertEqual(InventoryItem.emoji("water_packs"), "💧")
        XCTAssertEqual(InventoryItem.emoji("food_packs"), "🥫")
        XCTAssertEqual(InventoryItem.emoji("medicines"), "💊")
    }
}
