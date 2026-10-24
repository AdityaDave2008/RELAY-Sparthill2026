import Foundation
import CryptoKit

/// A backend-enrolled device address. The HTTPS directory binds this key to a
/// shelter; a display name or Bonjour hello alone does not establish that trust.
public struct ShelterReceiver: Codable, Equatable {
    public let device_id: String
    public let signing_key: String
    public let encryption_key: String
    public let revision: Int
    public let account_subject: String?
    public init(deviceID: String, signingKey: String, encryptionKey: String, revision: Int = 0, subject: String? = nil) {
        device_id = deviceID; signing_key = signingKey; encryption_key = encryptionKey; self.revision = revision; account_subject = subject
    }
    public func forAccount(_ subject: String) -> ShelterReceiver {
        ShelterReceiver(deviceID: device_id, signingKey: signing_key, encryptionKey: encryption_key, revision: revision, subject: subject)
    }
    public func validate() throws {
        guard UUID(uuidString: device_id) != nil, device_id == device_id.lowercased(), revision >= 0,
              let signing = Data(base64Encoded: signing_key), let encryption = Data(base64Encoded: encryption_key) else { throw RelayError.invalid("Invalid receiving device") }
        _ = try P256.Signing.PublicKey(x963Representation: signing)
        _ = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: encryption)
    }
}

public struct DeviceIdentity {
    private struct Material: Codable { let deviceID: String; let signing: Data; let encryption: Data }
    public let deviceID: String
    private let signing: P256.Signing.PrivateKey
    private let encryption: Curve25519.KeyAgreement.PrivateKey
    public init(deviceID: String) throws {
        guard UUID(uuidString: deviceID) != nil, deviceID == deviceID.lowercased() else { throw RelayError.invalid("Invalid identity") }
        self.deviceID = deviceID; signing = .init(); encryption = .init()
    }
    private init(_ material: Material) throws {
        deviceID = material.deviceID
        signing = try .init(rawRepresentation: material.signing)
        encryption = try .init(rawRepresentation: material.encryption)
    }
    /// App-sandbox file protection for this prototype; not a Secure Enclave claim.
    /// Never replace an unreadable key file: queued encrypted messages depend on it.
    public static func load(deviceID: String, at url: URL) throws -> DeviceIdentity {
        if FileManager.default.fileExists(atPath: url.path) {
            let material = try JSONDecoder().decode(Material.self, from: Data(contentsOf: url))
            guard material.deviceID == deviceID else { throw RelayError.invalid("Saved cryptographic identity does not match this device") }
            return try DeviceIdentity(material)
        }
        let identity = try DeviceIdentity(deviceID: deviceID)
        let material = Material(deviceID: deviceID, signing: identity.signing.rawRepresentation, encryption: identity.encryption.rawRepresentation)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(material).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
        return identity
    }
    public var address: ShelterReceiver {
        ShelterReceiver(deviceID: deviceID, signingKey: signing.publicKey.x963Representation.base64EncodedString(), encryptionKey: encryption.publicKey.rawRepresentation.base64EncodedString())
    }
    fileprivate func sign(_ bytes: Data) throws -> String { try signing.signature(for: bytes).derRepresentation.base64EncodedString() }
    fileprivate func sharedKey(ephemeral: Data, salt: Data) throws -> SymmetricKey {
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeral)
        return try encryption.sharedSecretFromKeyAgreement(with: peer).hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("RELAY sealed request v1".utf8), outputByteCount: 32)
    }
}

public struct NearbyRequestBody: Codable {
    public let schema_version: Int
    public let submission: CloudSubmission
    public let sender_subject: String
    public let receiver_subject: String
    public let receiving_device_id: String
    public let sender_encryption_key: String
    public let receiver_signing_key: String
}
/// Signature covers the exact bytes, avoiding JSON canonicalization differences
/// between Swift and Python. There are no bearer tokens in this object.
public struct SignedNearbyRequest: Codable {
    public let body: String
    public let signature: String
    public let signing_key: String
    public func verifiedBody() throws -> NearbyRequestBody {
        guard let data = Data(base64Encoded: body), data.count <= 24_000 else { throw RelayError.invalid("Invalid signed request size") }
        try SealedDelivery.verify(signature: signature, data: data, publicKey: signing_key)
        let value = try CloudCodec.decode(NearbyRequestBody.self, data)
        guard value.schema_version == 1, value.submission.schema_version == 1,
              value.submission.operation_id == value.submission.request_id,
              !value.sender_subject.isEmpty, value.sender_subject.utf8.count <= 128,
              !value.receiver_subject.isEmpty, value.receiver_subject.utf8.count <= 128,
              UUID(uuidString: value.submission.request_id) != nil,
              UUID(uuidString: value.receiving_device_id) != nil,
              !value.submission.original_text.isEmpty, value.submission.original_text.count <= 4096,
              let senderKey = Data(base64Encoded: value.sender_encryption_key) else { throw RelayError.invalid("Invalid signed request") }
        _ = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderKey)
        try value.submission.location?.validate()
        try value.submission.requester_details?.validate()
        if let fields = value.submission.structured_fields {
            guard fields.item_id == nil || ["water_packs", "food_packs", "blankets", "medicines", "other"].contains(fields.item_id!),
                  fields.quantity.map({ (1...10000).contains($0) }) ?? true,
                  fields.people.map({ (1...1_000_000).contains($0) }) ?? true,
                  fields.unit == nil || RequestDraft.units.contains(fields.unit!), fields.landmark.count <= 240,
                  fields.urgency == nil || RequestUrgency(rawValue: fields.urgency!) != nil, (fields.medicine_details?.count ?? 0) <= 240 else {
                throw RelayError.invalid("Invalid structured nearby request")
            }
        }
        guard value.submission.revision == 1, UUID(uuidString: value.submission.origin_device_id) != nil,
              ["text", "reviewed_transcript"].contains(value.submission.input_mode) else { throw RelayError.invalid("Invalid nearby request version or input mode") }
        return value
    }
}

public enum SealedDelivery {
    public static let requestPrefix = "RELAY-SEALED-1:"
    public static let receiptPrefix = "RELAY-RECEIPT-1:"
    private struct Envelope: Codable {
        let version: Int
        let ephemeral_key: String
        let ciphertext: String
        let receiver_signing_key: String
    }
    private struct ReceiptProof: Codable { let version: Int; let signature: String }
    private struct Binding: Codable {
        let version: Int
        let message_id: String
        let origin_id: String
        let destination_id: String
        let original_message_id: String?
        let created_at: Date
        let expires_at: Date
        let max_hops: Int
        let receiver_signing_key: String
    }
    public static func isSealed(_ message: RelayMessage) -> Bool { message.messageType == .request && message.payload.text.hasPrefix(requestPrefix) }
    private static func binding(_ m: RelayMessage, key: String) throws -> Data {
        try CloudCodec.encode(Binding(version: 1, message_id: m.id, origin_id: m.originID, destination_id: m.destinationID,
            original_message_id: m.payload.originalMessageID, created_at: m.createdAt, expires_at: m.expiresAt, max_hops: m.maxHops, receiver_signing_key: key))
    }
    private static func envelope(_ m: RelayMessage) throws -> Envelope {
        guard isSealed(m), m.payload.text.utf8.count <= 16_384 else { throw RelayError.invalid("Invalid encrypted envelope") }
        let e = try CloudCodec.decode(Envelope.self, Data(m.payload.text.dropFirst(requestPrefix.count).utf8))
        guard e.version == 1, let ephemeral = Data(base64Encoded: e.ephemeral_key), ephemeral.count == 32,
              let cipher = Data(base64Encoded: e.ciphertext), cipher.count >= 28,
              let key = Data(base64Encoded: e.receiver_signing_key) else { throw RelayError.invalid("Invalid encrypted envelope fields") }
        _ = try P256.Signing.PublicKey(x963Representation: key)
        return e
    }
    public static func seal(_ submission: CloudSubmission, identity: DeviceIdentity, receiver: ShelterReceiver, subject: String) throws -> RelayMessage {
        try receiver.validate()
        guard submission.origin_device_id == identity.deviceID, receiver.device_id != identity.deviceID,
              !subject.isEmpty, subject.utf8.count <= 128, let receiverSubject = receiver.account_subject,
              !receiverSubject.isEmpty, receiverSubject.utf8.count <= 128 else { throw RelayError.invalid("Invalid nearby sender or destination") }
        let value = NearbyRequestBody(schema_version: 1, submission: submission, sender_subject: subject, receiver_subject: receiverSubject, receiving_device_id: receiver.device_id,
            sender_encryption_key: identity.address.encryption_key, receiver_signing_key: receiver.signing_key)
        let body = try CloudCodec.encode(value)
        let signed = SignedNearbyRequest(body: body.base64EncodedString(), signature: try identity.sign(body), signing_key: identity.address.signing_key)
        let shell = RelayMessage(messageID: submission.request_id, originID: identity.deviceID, destinationID: receiver.device_id,
            payload: Payload(text: "pending"), createdAt: submission.created_at, expiresAt: submission.expires_at)
        let aad = try binding(shell, key: receiver.signing_key)
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: Data(base64Encoded: receiver.encryption_key)!)
        let secret = try ephemeral.sharedSecretFromKeyAgreement(with: publicKey)
        let key = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: aad, sharedInfo: Data("RELAY sealed request v1".utf8), outputByteCount: 32)
        let box = try ChaChaPoly.seal(CloudCodec.encode(signed), using: key, authenticating: aad)
        let envelope = Envelope(version: 1, ephemeral_key: ephemeral.publicKey.rawRepresentation.base64EncodedString(),
            ciphertext: box.combined.base64EncodedString(), receiver_signing_key: receiver.signing_key)
        let text = requestPrefix + String(decoding: try CloudCodec.encode(envelope), as: UTF8.self)
        guard text.utf8.count <= 16_384 else { throw RelayError.invalid("Shorten this request so its encrypted nearby copy fits the relay limit") }
        return RelayMessage(messageID: shell.id, originID: shell.originID, destinationID: shell.destinationID,
            payload: Payload(text: text), createdAt: shell.createdAt, expiresAt: shell.expiresAt)
    }
    public static func open(_ message: RelayMessage, identity: DeviceIdentity) throws -> SignedNearbyRequest {
        let e = try envelope(message)
        guard message.destinationID == identity.deviceID, e.receiver_signing_key == identity.address.signing_key else { throw RelayError.invalid("Request addressed to another receiving key") }
        let aad = try binding(message, key: e.receiver_signing_key)
        let key = try identity.sharedKey(ephemeral: Data(base64Encoded: e.ephemeral_key)!, salt: aad)
        let data = try ChaChaPoly.open(.init(combined: Data(base64Encoded: e.ciphertext)!), using: key, authenticating: aad)
        let signed = try CloudCodec.decode(SignedNearbyRequest.self, data), value = try signed.verifiedBody()
        guard value.receiving_device_id == message.destinationID, value.receiver_signing_key == e.receiver_signing_key,
              value.submission.request_id == message.id, value.submission.origin_device_id == message.originID,
              value.submission.created_at == message.createdAt, value.submission.expires_at == message.expiresAt else { throw RelayError.invalid("Signed request does not match its route") }
        return signed
    }
    public static func receipt(for original: RelayMessage, identity: DeviceIdentity, now: Date) throws -> RelayMessage {
        let e = try envelope(original)
        guard identity.deviceID == original.destinationID, identity.address.signing_key == e.receiver_signing_key else { throw RelayError.invalid("Wrong shelter receipt key") }
        let shell = RelayMessage(originID: identity.deviceID, destinationID: original.originID, messageType: .receipt,
            payload: Payload(text: "pending", originalMessageID: original.id), createdAt: WireCodec.second(now), maxHops: original.maxHops)
        let proof = ReceiptProof(version: 1, signature: try identity.sign(binding(shell, key: e.receiver_signing_key)))
        return RelayMessage(messageID: shell.id, originID: shell.originID, destinationID: shell.destinationID, messageType: .receipt,
            payload: Payload(text: receiptPrefix + String(decoding: try CloudCodec.encode(proof), as: UTF8.self), originalMessageID: original.id),
            createdAt: shell.createdAt, expiresAt: shell.expiresAt, maxHops: shell.maxHops)
    }
    public static func verifyReceipt(_ message: RelayMessage, original: RelayMessage) throws {
        guard message.messageType == .receipt, message.originID == original.destinationID,
              message.destinationID == original.originID, message.payload.originalMessageID == original.id,
              message.payload.text.hasPrefix(receiptPrefix) else { throw RelayError.invalid("An authenticated shelter receipt is required") }
        let e = try envelope(original)
        let proof = try CloudCodec.decode(ReceiptProof.self, Data(message.payload.text.dropFirst(receiptPrefix.count).utf8))
        guard proof.version == 1 else { throw RelayError.invalid("Unsupported receipt proof") }
        try verify(signature: proof.signature, data: binding(message, key: e.receiver_signing_key), publicKey: e.receiver_signing_key)
    }
    fileprivate static func verify(signature: String, data: Data, publicKey: String) throws {
        guard let keyData = Data(base64Encoded: publicKey), let signatureData = Data(base64Encoded: signature), signatureData.count <= 80 else { throw RelayError.invalid("Malformed signature") }
        let key = try P256.Signing.PublicKey(x963Representation: keyData)
        guard key.isValidSignature(try .init(derRepresentation: signatureData), for: data) else { throw RelayError.invalid("Signature does not match") }
    }
}
