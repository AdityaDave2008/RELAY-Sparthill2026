import Foundation
import SQLite3

public struct StoredMessage: Identifiable {
    public let message: RelayMessage
    public let finalReceiptID: String?
    public let attempts: Int
    public let acceptedBy: [String]
    public let destinationAccepted: Bool
    public var id: String { message.id }
    public func status(deviceID: String, now: Date = Date()) -> String {
        if finalReceiptID != nil { return "Final destination receipt received" }
        if message.destinationID == deviceID { return message.messageType == .receipt ? "Receipt persisted locally" : "Received at final destination" }
        if message.expiresAt <= now { return "Expired — retained, not forwarded" }
        if message.messageType == .receipt {
            if destinationAccepted { return "Receipt accepted by its recipient (storage ACK)" }
            if !acceptedBy.isEmpty { return "Receipt accepted by relay — queued for onward forwarding" }
        }
        if destinationAccepted { return "Destination storage ACK — awaiting return receipt" }
        if !acceptedBy.isEmpty { return "Accepted by relay — awaiting destination receipt" }
        return attempts > 0 ? "Queued — awaiting durable ACK (\(attempts) attempts)" : "Locally saved — queued"
    }
}
public struct ReceiveResult {
    public let duplicate: Bool
    public let generatedReceipt: RelayMessage?
    public let recognizedReceipt: Bool
}

/// Confined to the engine's serial queue. Transactions use WAL + synchronous FULL.
public final class RelayStore {
    public static let capacity = 1000
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public let deviceID: String
    public let path: String
    public private(set) var sealedIdentity: DeviceIdentity?
    public func enableSealedDelivery(_ identity: DeviceIdentity) throws {
        guard identity.deviceID == deviceID else { throw RelayError.invalid("Receiving key belongs to another device") }
        sealedIdentity = identity
    }
    public func nearbyRequests() throws -> [SignedNearbyRequest] {
        try rows("SELECT value FROM metadata WHERE key LIKE 'nearby_request:%' ORDER BY key").map {
            try CloudCodec.decode(SignedNearbyRequest.self, Data($0[0]!.utf8))
        }
    }

    private init(openPath: String, requestedID: String?) throws {
        path = openPath
        if openPath != ":memory:" {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: openPath).deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(openPath, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let reason = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle); throw RelayError.database(reason)
        }
        // Close failed initialization handles as well as successful ones.
        do { deviceID = try Self.bootstrap(handle: handle!, requestedID: requestedID) }
        catch { sqlite3_close(handle); throw error }
        db = handle
    }
    public static func open(path: String, deviceID: String? = nil) throws -> RelayStore {
        try RelayStore(openPath: path, requestedID: deviceID)
    }
    private static func bootstrap(handle: OpaquePointer, requestedID: String?) throws -> String {
        let schema = """
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=FULL;
        PRAGMA busy_timeout=3000;
        CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY, body TEXT NOT NULL, final_receipt TEXT);
        CREATE TABLE IF NOT EXISTS transfers(message_id TEXT NOT NULL, peer_id TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0, acceptance TEXT, PRIMARY KEY(message_id,peer_id));
        CREATE TABLE IF NOT EXISTS events(seq INTEGER PRIMARY KEY AUTOINCREMENT, line TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS peers(id TEXT PRIMARY KEY, role TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS shelters(id TEXT PRIMARY KEY, body TEXT NOT NULL);
        """
        guard sqlite3_exec(handle, schema, nil, nil, nil) == SQLITE_OK else {
            throw RelayError.database("schema initialization")
        }
        // Existing installations keep their UUIDs, messages and receipt state.
        var columns: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA table_info(peers)", -1, &columns, nil) == SQLITE_OK else { throw RelayError.database("peer schema query") }
        var hasName = false
        while sqlite3_step(columns) == SQLITE_ROW {
            if let p = sqlite3_column_text(columns, 1), String(cString: p) == "display_name" { hasName = true }
        }
        sqlite3_finalize(columns)
        let migration = hasName ? "PRAGMA user_version=3;" : "BEGIN IMMEDIATE; ALTER TABLE peers ADD COLUMN display_name TEXT; PRAGMA user_version=3; COMMIT;"
        guard sqlite3_exec(handle, migration, nil, nil, nil) == SQLITE_OK else { throw RelayError.database("peer name migration") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT value FROM metadata WHERE key='device_id'", -1, &stmt, nil) == SQLITE_OK else { throw RelayError.database("identity query") }
        var stored: String?
        if sqlite3_step(stmt) == SQLITE_ROW, let p = sqlite3_column_text(stmt, 0) { stored = String(cString: p) }
        sqlite3_finalize(stmt)
        let id = stored ?? requestedID ?? UUID().uuidString.lowercased()
        guard UUID(uuidString: id) != nil, id == id.lowercased(), requestedID == nil || requestedID == id else { throw RelayError.invalid("persistent device identity mismatch") }
        if stored == nil {
            // UUID is validated; no user-provided SQL enters this statement.
            guard sqlite3_exec(handle, "INSERT INTO metadata VALUES('device_id','\(id)')", nil, nil, nil) == SQLITE_OK else { throw RelayError.database("identity insert") }
        }
        return id
    }
    deinit { sqlite3_close(db) }

    private func statement(_ sql: String, _ values: [String] = []) throws -> OpaquePointer {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else { throw error() }
        for (i, value) in values.enumerated() {
            guard sqlite3_bind_text(s, Int32(i + 1), value, -1, transient) == SQLITE_OK else { sqlite3_finalize(s); throw error() }
        }
        return s
    }
    private func error() -> RelayError { .database(String(cString: sqlite3_errmsg(db))) }
    private func execute(_ sql: String, _ values: [String] = []) throws {
        let s = try statement(sql, values); defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_DONE else { throw error() }
    }
    private func rows(_ sql: String, _ values: [String] = []) throws -> [[String?]] {
        let s = try statement(sql, values); defer { sqlite3_finalize(s) }
        var output: [[String?]] = []
        while true {
            let result = sqlite3_step(s)
            if result == SQLITE_DONE { return output }
            guard result == SQLITE_ROW else { throw error() }
            output.append((0..<sqlite3_column_count(s)).map { col in
                sqlite3_column_text(s, col).map { String(cString: $0) }
            })
        }
    }
    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let result = try body(); try execute("COMMIT"); return result }
        catch { try? execute("ROLLBACK"); throw error }
    }
    public func setting(_ key: String) throws -> String? { try rows("SELECT value FROM metadata WHERE key=?", [key]).first?.first ?? nil }
    public func setSetting(_ key: String, _ value: String) throws {
        try execute("INSERT INTO metadata(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [key, value])
    }
    public func shelters(includeRemoved: Bool = false) throws -> [ShelterContact] {
        let filter = includeRemoved ? "" : " WHERE NOT EXISTS (SELECT 1 FROM metadata WHERE key='removed_shelter:' || shelters.id AND value='true')"
        return try rows("SELECT body FROM shelters" + filter + " ORDER BY id").map {
            try WireCodec.decode(ShelterContact.self, from: Data($0[0]!.utf8))
        }.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
    }
    public func saveShelter(_ entry: ShelterContact) throws {
        try entry.validate()
        if let existing = try shelters(includeRemoved: true).first(where: { $0.id == entry.id }) {
            // A pasted code must not silently redirect an existing organizational inbox.
            guard existing == entry else { throw RelayError.invalid("This shelter ID already has different details. Device replacement needs an explicit directory migration.") }
            try execute("DELETE FROM metadata WHERE key=?", ["removed_shelter:" + entry.id])
            return
        }
        guard try shelters(includeRemoved: true).count < 100 else { throw RelayError.invalid("Prototype directory limit is 100 shelters, including removed entries.") }
        try execute("INSERT INTO shelters(id,body) VALUES(?,?)", [entry.id, String(decoding: try WireCodec.encode(entry), as: UTF8.self)])
    }
    /// Reversible directory removal. Request snapshots, queued envelopes and receipts stay intact.
    public func removeShelter(_ id: String) throws {
        guard try shelters(includeRemoved: true).contains(where: { $0.id == id }) else { throw RelayError.invalid("Shelter not found") }
        try transaction {
            try setSetting("removed_shelter:" + id, "true")
            if var draft = try helpDraft(), draft.shelterID == id {
                draft.shelterID = ""; try saveHelpDraft(draft)
            }
        }
    }
    public func helpDraft() throws -> HelpRequestDraft? {
        guard let body = try setting("help_draft") else { return nil }
        return try WireCodec.decode(HelpRequestDraft.self, from: Data(body.utf8))
    }
    public func saveHelpDraft(_ draft: HelpRequestDraft) throws {
        guard ShelterContact.isID(draft.requestID) else { throw RelayError.invalid("Draft identity") }
        // A queued autosave from the old form cannot resurrect a submitted draft.
        guard try message(draft.requestID) == nil else { return }
        var draft = draft
        // An autosave queued before removal must not select the removed entry again.
        if !draft.shelterID.isEmpty, try !shelters().contains(where: { $0.id == draft.shelterID }) { draft.shelterID = "" }
        let body = try WireCodec.encode(draft)
        guard body.count <= 24_000 else { throw RelayError.invalid("Draft is too large") }
        try setSetting("help_draft", String(decoding: body, as: UTF8.self))
    }
    public func submitHelpDraft(_ draft: HelpRequestDraft, now: Date) throws -> RelayMessage {
        guard let shelter = try shelters().first(where: { $0.id == draft.shelterID }), shelter.receivingDeviceID != deviceID else {
            throw RelayError.invalid("Choose a shelter received by another device.")
        }
        let request = try draft.request(to: shelter)
        let text = try ShelterRequestCodec.encode(request)
        return try transaction {
            if let existing = try message(draft.requestID) {
                guard existing.originID == deviceID, existing.payload.text == text else { throw RelayError.invalid("Request ID content conflict") }
                return existing
            }
            let message = RelayMessage(messageID: draft.requestID, originID: deviceID,
                destinationID: shelter.receivingDeviceID, payload: Payload(text: text), createdAt: WireCodec.second(now))
            try message.validate(now: now)
            try insert(message)
            if let scope = draft.cloudScope, let binding = draft.cloudBinding {
                let submission = try CloudSubmission(message: message, binding: binding, localDeviceID: deviceID,
                    transcriptionID: draft.transcriptionID)
                try saveCloudRecord(CloudQueueRecord(scope: scope, submission: submission))
            }
            if let id = draft.transcriptionID, let subject = draft.transcriptionSubject, let incident = draft.transcriptionIncident {
                let reference = try JSONSerialization.data(withJSONObject: ["id": id, "subject": subject, "incident": incident])
                try setSetting("request_audio:" + message.id, String(decoding: reference, as: UTF8.self))
            }
            if try helpDraft()?.requestID == draft.requestID { try execute("DELETE FROM metadata WHERE key='help_draft'") }
            return message
        }
    }
    public func remember(_ peer: Peer) throws {
        if let name = peer.displayName { _ = try Peer.normalizedName(name) }
        try execute("INSERT INTO peers(id,role,display_name) VALUES(?,?,NULLIF(?,'')) ON CONFLICT(id) DO UPDATE SET role=excluded.role,display_name=COALESCE(excluded.display_name,peers.display_name)", [peer.deviceID, peer.role.rawValue, peer.displayName ?? ""])
    }
    public func knownPeers() throws -> [Peer] {
        try rows("SELECT id,role,display_name FROM peers ORDER BY COALESCE(display_name,id),id").compactMap {
            guard let id = $0[0], let r = $0[1], let role = TestRole(rawValue: r) else { return nil }
            return Peer(deviceID: id, role: role, displayName: $0[2])
        }
    }
    public func message(_ id: String) throws -> RelayMessage? {
        guard let body = try rows("SELECT body FROM messages WHERE id=?", [id]).first?[0] else { return nil }
        return try WireCodec.decode(RelayMessage.self, from: Data(body.utf8))
    }
    public func allMessages() throws -> [RelayMessage] {
        try rows("SELECT body FROM messages ORDER BY rowid").map { try WireCodec.decode(RelayMessage.self, from: Data($0[0]!.utf8)) }
    }
    private func insert(_ message: RelayMessage) throws {
        guard let n = try rows("SELECT COUNT(*) FROM messages").first?[0], Int(n)! < Self.capacity else { throw RelayError.database("1000-message prototype quota reached; no ACK issued") }
        let body = String(decoding: try WireCodec.encode(message), as: UTF8.self)
        try execute("INSERT INTO messages(id,body) VALUES(?,?)", [message.id, body])
    }
    public func saveLocal(_ message: RelayMessage, now: Date) throws {
        try message.validate(now: now)
        guard message.originID == deviceID, message.hopCount == 0 else { throw RelayError.invalid("local origin") }
        try transaction { try insert(message) }
    }
    public func receive(_ message: RelayMessage, now: Date) throws -> ReceiveResult {
        try message.validate(now: now)
        if ShelterRequestCodec.isRequest(message) { _ = try ShelterRequestCodec.decode(message) }
        guard message.hopCount > 0 else { throw RelayError.invalid("received hop must be positive") }
        var nearby: SignedNearbyRequest?
        if SealedDelivery.isSealed(message), message.destinationID == deviceID {
            guard let identity = sealedIdentity else { throw RelayError.invalid("This receiving device has no saved decryption key") }
            nearby = try SealedDelivery.open(message, identity: identity)
        }
        if message.messageType == .receipt, message.destinationID == deviceID,
           let originalID = message.payload.originalMessageID, let original = try self.message(originalID), SealedDelivery.isSealed(original) {
            try SealedDelivery.verifyReceipt(message, original: original)
        }
        return try transaction {
            let previous = try self.message(message.id)
            if let previous, !previous.sameContent(as: message) { throw RelayError.invalid("UUID content collision \(message.id)") }
            if previous == nil { try insert(message) }
            else if message.hopCount < previous!.hopCount {
                try execute("UPDATE messages SET body=? WHERE id=?", [String(decoding: try WireCodec.encode(message), as: UTF8.self), message.id])
            }
            if let nearby {
                try setSetting("nearby_request:" + message.id, String(decoding: try CloudCodec.encode(nearby), as: UTF8.self))
            }
            var generated: RelayMessage?
            var recognized = false
            if message.destinationID == deviceID && message.messageType == .request {
                // Insert request and its receipt atomically. A duplicate never repeats the application action.
                let receipts = try allMessages().filter { $0.messageType == .receipt && $0.originID == deviceID && $0.payload.originalMessageID == message.id }
                if receipts.isEmpty {
                    let receipt: RelayMessage
                    if SealedDelivery.isSealed(message) {
                        receipt = try SealedDelivery.receipt(for: message, identity: sealedIdentity!, now: now)
                    } else {
                        receipt = RelayMessage(originID: deviceID, destinationID: message.originID,
                            messageType: .receipt, payload: Payload(text: "Final destination persisted request", originalMessageID: message.id),
                            createdAt: WireCodec.second(now), maxHops: message.maxHops)
                    }
                    try insert(receipt); generated = receipt
                }
            }
            if message.messageType == .receipt, message.destinationID == deviceID,
               let originalID = message.payload.originalMessageID,
               let original = try self.message(originalID), original.messageType == .request,
               original.originID == deviceID, message.originID == original.destinationID {
                try execute("UPDATE messages SET final_receipt=COALESCE(final_receipt,?) WHERE id=?", [message.id, originalID])
                recognized = true
            }
            return ReceiveResult(duplicate: previous != nil, generatedReceipt: generated, recognizedReceipt: recognized)
        }
    }
    public func inventory(now: Date) throws -> [String] { try allMessages().filter { $0.expiresAt > now }.map(\.id) }
    public func recordAttempt(_ id: String, peer: String) throws {
        try execute("INSERT INTO transfers(message_id,peer_id,attempts) VALUES(?,?,1) ON CONFLICT(message_id,peer_id) DO UPDATE SET attempts=attempts+1", [id, peer])
    }
    public func recordAck(_ ack: StorageAck, peer: String) throws {
        try execute("UPDATE transfers SET acceptance=COALESCE(acceptance,?) WHERE message_id=? AND peer_id=?", [ack.acceptance.rawValue, ack.messageID, peer])
    }
    public func hasUnacknowledgedAttempt(_ id: String, peer: String) throws -> Bool {
        !(try rows("SELECT 1 FROM transfers WHERE message_id=? AND peer_id=? AND acceptance IS NULL", [id, peer])).isEmpty
    }
    public func summaries() throws -> [StoredMessage] {
        try allMessages().map { m in
            let transfers = try rows("SELECT peer_id,attempts,acceptance FROM transfers WHERE message_id=?", [m.id])
            return StoredMessage(message: m, finalReceiptID: try rows("SELECT final_receipt FROM messages WHERE id=?", [m.id]).first?[0],
                attempts: transfers.reduce(0) { $0 + (Int($1[1] ?? "0") ?? 0) },
                acceptedBy: transfers.compactMap { $0[2] == nil ? nil : $0[0] },
                destinationAccepted: transfers.contains { $0[0] == m.destinationID && $0[2] == Acceptance.destinationStored.rawValue })
        }
    }
    public func log(_ line: String) throws {
        try transaction {
            try execute("INSERT INTO events(line) VALUES(?)", [line])
            try execute("DELETE FROM events WHERE seq <= (SELECT COALESCE(MAX(seq),0)-10000 FROM events)")
        }
    }
    public func logs(limit: Int = 500) throws -> [String] {
        try rows("SELECT line FROM (SELECT seq,line FROM events ORDER BY seq DESC LIMIT ?) ORDER BY seq", [String(limit)]).compactMap { $0[0] }
    }
}

extension RelayStore {
    /// Called only after the app verifies the same enrolled account on an explicitly
    /// configured replacement endpoint. Preserve the source as an upgrade backup.
    public func copyCloudScope(from old: String, to new: String) throws {
        guard old != new, [old, new].allSatisfy({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) else {
            throw RelayError.invalid("Invalid cloud scope migration")
        }
        try transaction {
            let marker = "cloud_scope_copied:" + old + ":" + new
            guard try setting(marker) == nil else { return }
            let existing = try cloudRecords(scope: new)
            for record in try cloudRecords(scope: old) {
                if let target = existing.first(where: { $0.id == record.id }) {
                    guard target.submission == record.submission else { throw RelayError.invalid("Conflicting saved request during server migration") }
                    continue // Never overwrite newer delivery or inventory state.
                }
                var object = try JSONSerialization.jsonObject(with: CloudCodec.encode(record)) as! [String: Any]
                object["scope"] = new
                try saveCloudRecord(CloudCodec.decode(CloudQueueRecord.self, JSONSerialization.data(withJSONObject: object)))
            }
            for prefix in ["request_compose:", "cloud_audio:", "cloud_directory:", "cloud_bindings:"] {
                if try setting(prefix + new) == nil, let value = try setting(prefix + old) { try setSetting(prefix + new, value) }
            }
            for row in try rows("SELECT key,value FROM metadata WHERE key LIKE ?", ["inventory_adjustment:" + old + ":%"] ) {
                let name = row[0]!.replacingOccurrences(of: old, with: new)
                if try setting(name) == nil { try setSetting(name, row[1]!) }
            }
            try setSetting(marker, "complete")
        }
    }
    public func cloudRecords(scope: String) throws -> [CloudQueueRecord] {
        try rows("SELECT value FROM metadata WHERE key LIKE ? ORDER BY key", ["cloud_record:" + scope + ":%"]).map {
            try CloudCodec.decode(CloudQueueRecord.self, Data($0[0]!.utf8))
        }
    }
    public func saveRequestDraft(_ draft: RequestDraft, scope: String) throws {
        guard !(try cloudRecords(scope: scope)).contains(where: { $0.id == draft.id }) else { return }
        let data = try CloudCodec.encode(draft)
        guard data.count < 32_000 else { throw RelayError.invalid("Draft too large") }
        try setSetting("request_compose:" + scope, String(decoding: data, as: UTF8.self))
    }
    public func requestDraft(scope: String) throws -> RequestDraft {
        guard let text = try setting("request_compose:" + scope) else { return RequestDraft() }
        return try CloudCodec.decode(RequestDraft.self, Data(text.utf8))
    }
    public func submitCloudDraft(_ draft: RequestDraft, scope: String, shelter: CloudShelter, receiver: ShelterReceiver? = nil, senderSubject: String? = nil, now: Date = Date()) throws -> CloudQueueRecord {
        try transaction {
            if let existing = try cloudRecords(scope: scope).first(where: { $0.id == draft.id }) {
                let replay = try CloudSubmission(draft: draft, shelter: shelter, deviceID: deviceID, now: existing.submission.created_at)
                guard replay == existing.submission else { throw RelayError.invalid("Request ID content conflict") }
                return existing
            }
            let record = CloudQueueRecord(scope: scope, submission: try CloudSubmission(draft: draft, shelter: shelter, deviceID: deviceID, now: now))
            try saveCloudRecord(record)
            if let receiver {
                guard let identity = sealedIdentity, let senderSubject else { throw RelayError.invalid("Nearby delivery keys and account are not ready") }
                try insert(SealedDelivery.seal(record.submission, identity: identity, receiver: receiver, subject: senderSubject))
            }
            if try requestDraft(scope: scope).id == draft.id { try execute("DELETE FROM metadata WHERE key=?", ["request_compose:" + scope]) }
            return record
        }
    }
    /// Merge a read response without losing a concurrently queued action or newer reply.
    public func mergeCloudSnapshot(_ result: CloudResult, scope: String) throws {
        var record = try cloudRecords(scope: scope).first { $0.id == result.id } ?? CloudQueueRecord(scope: scope, submission: result.submission)
        // Legacy caches serialize dates at whole-second precision. Compare that
        // persisted representation so a server's fractional timestamp does not
        // block all inbox updates; retain the original local submission unchanged.
        guard try CloudCodec.encode(record.submission) == CloudCodec.encode(result.submission) else { throw RelayError.invalid("Cloud response changed the saved request") }
        if !(["ready_for_review", "needs_review"].contains(record.result?.analysis_state ?? "") && ["pending", "retrying"].contains(result.analysis_state)) { record.result = result }
        if let history = result.history, history.revision >= (record.history?.revision ?? -1) {
            record.history = history; record.reservation = result.reservation
        }
        if record.pendingEvent == nil && record.pendingInventory == nil { record.state = "accepted"; record.problem = nil }
        try saveCloudRecord(record)
    }

    public func saveCloudRecord(_ value: CloudQueueRecord) throws {
        var record = value
        // Network responses may have been in flight when a nearby receipt arrived.
        // Derive delivery projection from durable transport state on every save.
        if let message = try message(record.id), SealedDelivery.isSealed(message) {
            if message.originID == deviceID {
                let receipt = try rows("SELECT final_receipt FROM messages WHERE id=?", [record.id]).first?[0]
                let acceptance = try rows("SELECT 1 FROM transfers WHERE message_id=? AND acceptance IS NOT NULL LIMIT 1", [record.id])
                record.nearbyState = receipt != nil ? "shelter_saved" : !acceptance.isEmpty ? "relay_saved" : "queued"
            } else if message.destinationID == deviceID, try setting("nearby_request:" + record.id) != nil {
                record.nearbyState = "received"
            }
        }
        guard record.scope.count == 64, record.scope.allSatisfy({ $0.isHexDigit }), UUID(uuidString: record.id) != nil else { throw RelayError.invalid("Invalid cloud queue key") }
        let key = "cloud_record:" + record.scope + ":" + record.id
        if let old = try setting(key) {
            let existing = try CloudCodec.decode(CloudQueueRecord.self, Data(old.utf8))
            guard existing.submission == record.submission else { throw RelayError.invalid("Cloud request ID content conflict") }
        } else if try cloudRecords(scope: record.scope).count >= 1000 { throw RelayError.invalid("Cloud queue limit reached") }
        let data = try CloudCodec.encode(record)
        guard data.count <= 512_000 else { throw RelayError.invalid("Cloud record exceeds local limit") }
        try setSetting(key, String(decoding: data, as: UTF8.self))
    }
}
