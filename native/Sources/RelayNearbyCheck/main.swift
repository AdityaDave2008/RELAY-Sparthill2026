import Foundation
import RelayCore

@main struct RelayNearbyCheck {
    struct Fixture: Codable {
        let sender: [String: String]
        let receiver: [String: String]
        let signed: SignedNearbyRequest
        let submission: CloudSubmission
    }
    static func main() throws {
        guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--fixture" else {
            throw RelayError.invalid("Use --fixture /path/to/public-synthetic-fixture.json")
        }
        let sender = try DeviceIdentity(deviceID: UUID().uuidString.lowercased())
        let receiver = try DeviceIdentity(deviceID: UUID().uuidString.lowercased())
        let shelter = CloudShelter(shelter_id: "shelter-a", incident_id: "synthetic-demo-01", display_name: "Synthetic shelter")
        var draft = RequestDraft(); draft.shelterID = shelter.shelter_id
        draft.text = "SYNTHETIC native signature: two water packs at test point"
        draft.item = "water_packs"; draft.quantity = "2"
        draft.location = try RequestLocation(latitude: 0, longitude: 0, accuracy: 100, source: "manual")
        let submission = try CloudSubmission(draft: draft, shelter: shelter, deviceID: sender.deviceID)
        let wire = try SealedDelivery.seal(submission, identity: sender, receiver: receiver.address.forAccount("test-dispatcher-a"), subject: "test-requester-a")
        let signed = try SealedDelivery.open(wire, identity: receiver)
        func publicFields(_ identity: DeviceIdentity) -> [String: String] {
            ["device_id": identity.deviceID, "signing_key": identity.address.signing_key, "encryption_key": identity.address.encryption_key]
        }
        let fixture = Fixture(sender: publicFields(sender), receiver: publicFields(receiver), signed: signed, submission: submission)
        try CloudCodec.encode(fixture).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
        print("Synthetic public signature fixture created; no private keys exported. Request \(submission.request_id)")
    }
}
