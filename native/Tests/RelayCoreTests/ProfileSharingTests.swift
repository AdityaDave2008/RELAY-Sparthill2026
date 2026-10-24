import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import RelayCore

final class ProfileSharingTests: XCTestCase {
    func profile() -> ResidentDetails {
        var p = ResidentDetails(); p.name = "Synthetic Resident"; p.preferredLanguage = "English"
        p.age = 24; p.heightCM = 172.5; p.weightKG = 68.25; p.bloodGroup = "O−"
        p.allergies = "SYNTHETIC ALLERGY"; p.healthConditions = "SYNTHETIC CONDITION"
        p.medications = "SYNTHETIC MEDICATION"; p.accessibilityNeeds = "SYNTHETIC SUPPORT"
        p.photoJPEG = Data([0xff, 0xd8, 0xff, 0xd9]); return p
    }
    func testNewProfileSaveRequiresNameAndLanguageButNotHealthOrPhoto() throws {
        var d = ResidentDetailsDraft()
        XCTAssertThrowsError(try d.validated(requireBasics: true))
        d.name = "Test resident"; XCTAssertThrowsError(try d.validated(requireBasics: true))
        d.preferredLanguage = "English"
        let p = try d.validated(requireBasics: true)
        XCTAssertNil(p.age); XCTAssertNil(p.photoJPEG); XCTAssertTrue(p.healthConditions.isEmpty)
    }
    func testBuild21ProfileDecodesWithoutNewPhotoOrLanguage() throws {
        let old = Data(#"{"name":"Legacy","age":24,"allergies":"","healthConditions":"","medications":"","accessibilityNeeds":"","bloodGroup":""}"#.utf8)
        let value = try CloudCodec.decode(ResidentDetails.self, old)
        XCTAssertNil(value.preferredLanguage); XCTAssertNil(value.photoJPEG); XCTAssertEqual(value.name, "Legacy")
    }
    func testSharingSelectionExcludesPhotoAndUnselectedSensitiveFields() throws {
        let p = profile()
        let basic = try SharedResidentDetails(profile: p, includeHealth: false, includeSupport: false)
        XCTAssertEqual(basic.display_name, p.name); XCTAssertNil(basic.age); XCTAssertNil(basic.allergies); XCTAssertNil(basic.accessibility_needs)
        let json = String(decoding: try CloudCodec.encode(basic), as: UTF8.self)
        XCTAssertFalse(json.contains("photo")); XCTAssertFalse(json.contains("SYNTHETIC ALLERGY"))
        let health = try SharedResidentDetails(profile: p, includeHealth: true, includeSupport: false)
        XCTAssertEqual(health.allergies, p.allergies); XCTAssertNil(health.accessibility_needs)
        let support = try SharedResidentDetails(profile: p, includeHealth: false, includeSupport: true)
        XCTAssertNil(support.age); XCTAssertEqual(support.accessibility_needs, p.accessibilityNeeds)
    }
    func testSharedSnapshotSurvivesQueueRestartAndRejectsChangedRetry() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("relay.sqlite").path
        var store: RelayStore? = try .open(path: path)
        let shelter = CloudShelter(shelter_id: "shelter-a", incident_id: "test", display_name: "Test shelter")
        var draft = RequestDraft(); draft.shelterID = "shelter-a"; draft.text = "SYNTHETIC: two water packs"; draft.landmark = "Test hall"
        let absent = try CloudSubmission(draft: draft, shelter: shelter, deviceID: store!.deviceID)
        XCTAssertNil(absent.requester_details)
        XCTAssertFalse(String(decoding: try CloudCodec.encode(absent), as: UTF8.self).contains("requester_details"))
        draft.requesterDetails = try SharedResidentDetails(profile: profile(), includeHealth: true, includeSupport: true)
        let saved = try store!.submitCloudDraft(draft, scope: String(repeating: "a", count: 64), shelter: shelter)
        store = nil; store = try .open(path: path)
        XCTAssertEqual(try store!.cloudRecords(scope: String(repeating: "a", count: 64)).first?.submission.requester_details, draft.requesterDetails)
        var changed = profile(); changed.name = "Changed later"
        draft.requesterDetails = try SharedResidentDetails(profile: changed, includeHealth: true, includeSupport: true)
        XCTAssertThrowsError(try store!.submitCloudDraft(draft, scope: String(repeating: "a", count: 64), shelter: shelter))
        XCTAssertEqual(try store!.cloudRecords(scope: String(repeating: "a", count: 64)).first?.submission, saved.submission)
    }
    func testNearbyEnvelopeEncryptsAndRestoresSharedProfile() throws {
        let sender = try DeviceIdentity(deviceID: UUID().uuidString.lowercased()), receiver = try DeviceIdentity(deviceID: UUID().uuidString.lowercased())
        let shelter = CloudShelter(shelter_id: "shelter-a", incident_id: "test", display_name: "Test shelter")
        var draft = RequestDraft(); draft.shelterID = shelter.shelter_id; draft.text = "SYNTHETIC request"
        draft.requesterDetails = try SharedResidentDetails(profile: profile(), includeHealth: true, includeSupport: true)
        let submission = try CloudSubmission(draft: draft, shelter: shelter, deviceID: sender.deviceID)
        let sealed = try SealedDelivery.seal(submission, identity: sender, receiver: receiver.address.forAccount("staff"), subject: "resident")
        XCTAssertFalse(sealed.payload.text.contains("SYNTHETIC ALLERGY")); XCTAssertFalse(sealed.payload.text.contains("Synthetic Resident"))
        XCTAssertEqual(try SealedDelivery.open(sealed, identity: receiver).verifiedBody().submission.requester_details, draft.requesterDetails)
    }
    func testPhotoThumbnailIsBoundedAndDropsLocationMetadata() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        let pixels = try XCTUnwrap(context.makeImage()), original = NSMutableData()
        let writer = try XCTUnwrap(CGImageDestinationCreateWithData(original, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, pixels, [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 1.23, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 2.34, kCGImagePropertyGPSLongitudeRef: "E"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        let small = try ResidentPhoto.thumbnail(original as Data)
        XCTAssertLessThanOrEqual(small.count, 24000)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(small as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertLessThanOrEqual(properties[kCGImagePropertyPixelWidth] as? Int ?? Int.max, 256)
        var p = profile(); p.photoJPEG = small
        XCTAssertEqual(try CloudCodec.decode(ResidentDetails.self, CloudCodec.encode(p)).photoJPEG, small)
        XCTAssertThrowsError(try ResidentPhoto.thumbnail(Data("not an image".utf8)))
    }
}
