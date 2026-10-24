import SwiftUI
import RelayCore

@MainActor final class CloudModel: ObservableObject {
    @Published var endpoint = UserDefaults.standard.string(forKey: "relay.cloud.endpoint") ?? (Bundle.main.object(forInfoDictionaryKey: "RELAYCloudAPIURL") as? String ?? "")
    @Published var profile: CloudProfile?
    @Published private(set) var accountReady = false
    @Published var directory: [CloudShelter] = []
    @Published var records: [CloudQueueRecord] = []
    @Published var bindings: [CloudBinding] = []
    @Published var problem = ""
    @Published var status = "Cloud not configured"
    @Published var busy = false
    @Published var submitting = false
    @Published var audioBusy = false
    @Published var audioStatus = ""
    @Published var audioJob: CloudAudioJob?
    @Published var transcript = ""
    @Published var draft = RequestDraft()
    @Published var interpretation: InterpretationResult?
    @Published var interpreting = false
    @Published var signInNeedsCode = false
    @Published var inventory: InventorySnapshot?
    @Published var inventoryBusy = false
    @Published var staffShelterID = ""
    @Published var pendingAdjustment = false
    @Published var nearbyProblem = ""
    @Published var announcementFeed: AnnouncementFeed?
    @Published var announcementReads: [String: Int] = [:]
    @Published var pendingAnnouncement: AnnouncementCommand?
    @Published var announcementsBusy = false
    @Published var announcementsProblem = ""
    @Published private(set) var residentDetails = ResidentDetails()
    @Published private(set) var residentSetup = ResidentSetupState()
    @Published private(set) var residentContextScope: String?
    @Published private(set) var residentDetailsAvailable = false
    @Published var residentDetailsProblem = ""
    @Published private(set) var residentDetailsBusy = false
    private let residentVault = ResidentDetailsVault()
    #if DEBUG
    private var replayedResidentSetup = false
    #endif
    var residentContextID: String? { profile?.role == "requester" && residentContextScope == scope ? residentContextScope : nil }
    private var lastAlertsRefresh = Date.distantPast
    @Published var cloudPaused = UserDefaults.standard.bool(forKey: "relay.demo.cloudPaused") {
        didSet { UserDefaults.standard.set(cloudPaused, forKey: "relay.demo.cloudPaused") }
    }
    var pollingPaused = false
    var focusedRequestID: String?
    private var reconcilingNearby = false
    private var lastInboxRefresh = Date.distantPast
    private var lastDirectoryRefresh = Date.distantPast
    private var refreshingFocused = false
    private let auth = CloudAuth()
    private weak var model: RelayModel?
    private var api: CloudHTTPClient?
    private var scope: String?
    private var epoch = UUID()
    private var timer: Task<Void, Never>?
    var canUseCloud: Bool { !cloudPaused && profile != nil && api != nil && auth.hasSession }
    var isDispatcher: Bool { profile?.role == "dispatcher" }

    func attach(_ model: RelayModel) async {
        guard self.model == nil else { return }; self.model = model
        defer { accountReady = true }
        if auth.hasSession, let cached = auth.cachedProfile, let url = try? CloudCodec.apiURL(endpoint) {
            busy = true
            api = try? CloudHTTPClient(baseURL: url); scope = CloudCodec.scope(baseURL: url, subject: cached.subject)
            profile = cached
            if let scope {
                do {
                    let cachedData = try await model.withStore { store in
                        (try store.setting("cloud_bindings:" + scope), try store.setting("cloud_directory:" + scope))
                    }
                    if let value = cachedData.0 { bindings = try CloudCodec.decode([CloudBinding].self, Data(value.utf8)) }
                    if let value = cachedData.1 { directory = try CloudCodec.decode([CloudShelter].self, Data(value.utf8)) }
                    draft = try await model.withStore { try $0.requestDraft(scope: scope) }
                    await reload(); status = "Saved account · connecting…"
                    await loadAnnouncementCache()
                    await loadResidentContext()
                } catch { problem = error.localizedDescription }
            }
            staffShelterID = directory.first?.shelter_id ?? ""
            busy = false
            await reconcileNearby()
            if !cloudPaused { await connect(signIn: false) }
        }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                if self?.pollingPaused == true { continue }
                await self?.reconcileNearby()
                await self?.sync()
                await self?.refreshFocusedRequest()
                if let self, Date().timeIntervalSince(self.lastAlertsRefresh) > 12 { await self.refreshAnnouncements() }
                if let self, self.canUseCloud, self.focusedRequestID == nil, Date().timeIntervalSince(self.lastInboxRefresh) > 8 {
                    self.lastInboxRefresh = Date()
                    if Date().timeIntervalSince(self.lastDirectoryRefresh) > 60 { self.lastDirectoryRefresh = Date(); await self.refreshDirectory() }
                    await self.loadInbox(shelterID: self.isDispatcher ? self.staffShelterID : nil)
                }
            }
        }
    }
    func connect(signIn: Bool) async {
        guard !busy, let model else { return }
        guard !cloudPaused else { problem = "Resume cloud delivery in Settings before signing in or refreshing setup."; return }
        busy = true; defer { busy = false }; problem = ""
        do {
            let originalURL = try CloudCodec.apiURL(endpoint)
            let oldDemoURL = "https://resumes-investigated-striking-mba.trycloudflare.com"
            let url = try CloudCodec.apiURL(originalURL.absoluteString == oldDemoURL ? "https://relay.stepcheck.app" : originalURL.absoluteString)
            let client = try CloudHTTPClient(baseURL: url)
            if signIn { try await auth.signIn() }
            let token = try await auth.accessToken()
            let verified: CloudProfile = try await client.call("v1/me", token: token)
            var shelters: CloudDirectory = try await client.call("v1/shelters", token: token)
            nearbyProblem = ""
            do {
                let address = try await model.withStore { store -> ShelterReceiver in
                    guard let identity = store.sealedIdentity else { throw RelayError.invalid("Device keys are not ready") }
                    return identity.address
                }
                let registration = ["device_id": address.device_id, "signing_key": address.signing_key, "encryption_key": address.encryption_key]
                let _: [String: String] = try await client.call("v1/devices", token: token, method: "POST", body: CloudCodec.encode(registration))
                #if os(macOS)
                if verified.role == "dispatcher", let shelter = shelters.items.first, shelter.receiver == nil {
                    let command = ReceiverCommand(device_id: address.device_id, expected_revision: 0)
                    let _: ShelterReceiver = try await client.call("v1/shelters/\(shelter.shelter_id)/receiver", token: token, method: "PUT", body: CloudCodec.encode(command))
                    shelters = try await client.call("v1/shelters", token: token)
                }
                #endif
            } catch { nearbyProblem = "Nearby setup: " + error.localizedDescription }
            let key = CloudCodec.scope(baseURL: url, subject: verified.subject)
            if originalURL != url {
                let previous = CloudCodec.scope(baseURL: originalURL, subject: verified.subject)
                try await model.withStore { try $0.copyCloudScope(from: previous, to: key) }
            }
            try auth.rememberProfile(verified)
            let directoryData = try CloudCodec.encode(shelters.items)
            try await model.withStore { try $0.setSetting("cloud_directory:" + key, String(decoding: directoryData, as: UTF8.self)) }
            let saved = try await model.withStore { store -> ([CloudQueueRecord], [CloudBinding], CloudAudioJob?) in
                let bindings = try store.setting("cloud_bindings:" + key).map { try CloudCodec.decode([CloudBinding].self, Data($0.utf8)) } ?? []
                let audio = try store.setting("cloud_audio:" + key).flatMap { try CloudCodec.decode(CloudAudioJob?.self, Data($0.utf8)) }
                return (try store.cloudRecords(scope: key), bindings, audio)
            }
            epoch = UUID(); api = client; scope = key; profile = verified; directory = shelters.items
            records = saved.0; bindings = saved.1; audioJob = saved.2; transcript = saved.2?.transcript ?? ""
            draft = try await model.withStore { try $0.requestDraft(scope: key) }
            if draft.shelterID.isEmpty { draft.shelterID = shelters.items.first?.shelter_id ?? "" }
            staffShelterID = shelters.items.first?.shelter_id ?? ""
            endpoint = url.absoluteString
            UserDefaults.standard.set(url.absoluteString, forKey: "relay.cloud.endpoint")
            status = "Signed in · \(verified.role.capitalized)"
            await loadAnnouncementCache()
            await loadResidentContext()
            await refreshAnnouncements()
        } catch { problem = error.localizedDescription; status = "Cloud unavailable; nearby delivery still works" }
    }
    func signOut() {
        cloudPaused = false; nearbyProblem = ""
        epoch = UUID(); auth.signOut(); profile = nil; api = nil; scope = nil
        records = []; directory = []; bindings = []; audioJob = nil; transcript = ""; draft = RequestDraft(); interpretation = nil; inventory = nil; signInNeedsCode = false; status = "Signed out"
        announcementFeed = nil; announcementReads = [:]; pendingAnnouncement = nil; announcementsProblem = ""
        residentDetails = ResidentDetails(); residentSetup = ResidentSetupState(); residentContextScope = nil; residentDetailsAvailable = false; residentDetailsProblem = ""
    }
    func bind(localID: String, cloudID: String) async {
        guard let destination = directory.first(where: { $0.id == cloudID }), let scope, let model else { return }
        var updated = bindings.filter { $0.localID != localID }
        updated.append(CloudBinding(localID: localID, incidentID: destination.incident_id, shelterID: destination.shelter_id))
        do {
            let data = try CloudCodec.encode(updated)
            try await model.withStore { try $0.setSetting("cloud_bindings:" + scope, String(decoding: data, as: UTF8.self)) }
            bindings = updated
        } catch { problem = error.localizedDescription }
    }
    func prepared(_ draft: HelpRequestDraft) throws -> HelpRequestDraft {
        guard let scope, let profile, let binding = bindings.first(where: { $0.localID == draft.shelterID }) else { throw RelayError.invalid("Sign in and link this shelter first") }
        var copy = draft; copy.cloudScope = scope; copy.cloudBinding = binding
        if copy.transcriptionSubject != profile.subject || copy.transcriptionIncident != binding.incidentID { copy.transcriptionID = nil }
        return copy
    }
    func queue(_ message: RelayMessage, draft: HelpRequestDraft? = nil) async {
        guard let scope, let profile, let model else { problem = "Sign in and map this shelter first"; return }
        do {
            let request = try ShelterRequestCodec.decode(message)
            guard let binding = bindings.first(where: { $0.localID == request.shelter.id }),
                  directory.contains(where: { $0.shelter_id == binding.shelterID && $0.incident_id == binding.incidentID }) else { throw RelayError.invalid("Map this local shelter to an authorized cloud shelter first") }
            if records.contains(where: { $0.id == message.id }) { await sync(); return }
            let savedAudio = try await model.withStore { try $0.setting("request_audio:" + message.id) }
            let reference = savedAudio.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: String] }
            let transcription = reference?["subject"] == profile.subject && reference?["incident"] == binding.incidentID ? reference?["id"] : nil
            let submission = try CloudSubmission(message: message, binding: binding, localDeviceID: model.deviceID, transcriptionID: transcription)
            let record = CloudQueueRecord(scope: scope, submission: submission)
            try await model.withStore { try $0.saveCloudRecord(record) }
            await reload(); await sync()
        } catch { problem = error.localizedDescription }
    }
    func sync() async {
        guard !cloudPaused, !busy, let api, let scope, let model, profile != nil else { return }
        busy = true; defer { busy = false }
        let generation = epoch
        do {
            let token = try await auth.accessToken()
            let pending = try await model.withStore { try $0.cloudRecords(scope: scope) }
            for var record in pending.filter({ row in
                return row.retryAt <= Date() && row.state != "needs_attention" && (row.state == "queued" || row.pendingEvent != nil || row.pendingInventory != nil || row.retryAt == .distantPast)
            }).sorted { ($0.pendingInventory != nil || $0.pendingEvent != nil || $0.state == "queued" ? 0 : 1, $0.retryAt) < ($1.pendingInventory != nil || $1.pendingEvent != nil || $1.state == "queued" ? 0 : 1, $1.retryAt) }.prefix(5) {
                guard generation == epoch else { return }
                do {
                    let result: CloudResult
                    if record.state == "queued" {
                        if record.nearbyState == "received" {
                            let id = record.id
                            let signed = try await model.withStore { store -> SignedNearbyRequest in
                                guard let value = try store.nearbyRequests().first(where: { try $0.verifiedBody().submission.request_id == id }) else { throw RelayError.invalid("Carried request proof is unavailable") }
                                return value
                            }
                            result = try await api.call("v1/relay/requests", token: token, method: "POST", body: CloudCodec.encode(signed))
                        } else {
                            result = try await api.call("v1/requests", token: token, method: "POST", body: CloudCodec.encode(record.submission))
                        }
                    } else if let saved = record.result { result = saved }
                    else { result = try await api.call("v1/requests/" + record.id, token: token) }
                    guard result.request_id == record.id, result.submission == record.submission, result.cloud_state == "accepted" else { throw RelayError.invalid("Cloud response does not match the saved request") }
                    record.result = result; record.state = "accepted"; record.problem = nil
                    if let command = record.pendingInventory {
                        let result: ReservationResult = try await api.call("v1/requests/\(record.id)/inventory", token: token, method: "POST", body: CloudCodec.encode(command))
                        record.reservation = result.reservation; record.history = result.history; record.pendingInventory = nil
                    }
                    if let event = record.pendingEvent {
                        record.history = try await api.call("v1/requests/\(record.id)/events", token: token, method: "POST", body: CloudCodec.encode(event))
                        record.pendingEvent = nil
                    }
                    let snapshot: CloudResult = try await api.call("v1/requests/\(record.id)/snapshot", token: token)
                    record.result = snapshot
                    if let history = snapshot.history, history.revision >= (record.history?.revision ?? -1) { record.history = history; record.reservation = snapshot.reservation }
                    record.retryAt = Date().addingTimeInterval(20)
                } catch {
                    let http = error as? CloudHTTPError
                    let retryable = http?.retryable ?? !(error is RelayError)
                    if record.state == "queued" { record.failed(error.localizedDescription, retryable: retryable) }
                    else { record.problem = error.localizedDescription; record.retryAt = Date().addingTimeInterval(30) }
                    if let http, !http.retryable { record.state = "needs_attention" }
                }
                guard generation == epoch else { return }
                try await model.withStore { try $0.saveCloudRecord(record) }
                await reload()
            }
            await reload(); if problem == "cancelled" { problem = "" }; status = "Cloud checked \(Date().formatted(date: .omitted, time: .shortened))"
        } catch { problem = error.localizedDescription; status = "Cloud unavailable · queued requests retained" }
    }
    func refreshFocusedRequest() async {
        guard !cloudPaused, !busy, !refreshingFocused, let id = focusedRequestID,
              let api, let scope, let model, records.contains(where: { $0.id == id && $0.result != nil }) else { return }
        refreshingFocused = true; defer { refreshingFocused = false }; let generation = epoch
        do {
            let token = try await auth.accessToken()
            let snapshot: CloudResult = try await api.call("v1/requests/" + id + "/snapshot", token: token)
            guard generation == epoch else { return }
            try await model.withStore { try $0.mergeCloudSnapshot(snapshot, scope: scope) }
            await reload()
        } catch { /* Saved content stays visible; explicit Refresh shows actionable errors. */ }
    }

    func loadInbox(shelterID: String? = nil) async {
        guard !cloudPaused, !busy, let api, let scope, let model else { return }
        busy = true; defer { busy = false }; let generation = epoch
        let previousProblem = problem
        do {
            let token = try await auth.accessToken()
            var cursor: String?
            repeat {
                var query = [URLQueryItem(name: "view", value: shelterID == nil ? "mine" : "shelter"), .init(name: "limit", value: "50")]
                if let shelterID { query.append(.init(name: "shelter_id", value: shelterID)) }
                if let cursor { query.append(.init(name: "cursor", value: cursor)) }
                let page: CloudPage = try await api.call("v1/requests", token: token, query: query)
                guard generation == epoch else { return }
                for result in page.items.sorted(by: { $0.submission.created_at > $1.submission.created_at }) {
                    try await model.withStore { try $0.mergeCloudSnapshot(result, scope: scope) }
                }
                cursor = page.next_cursor
                await reload()
            } while cursor != nil && records.count < 1000
            // A successful inbox refresh resolves its old connection error. Keep
            // a newer error raised by another task while this request was in flight.
            if generation == epoch && problem == previousProblem { problem = "" }
        } catch { problem = error.localizedDescription }
    }
    func sendEvent(_ id: String, text: String, status: String?) async {
        guard !busy, var record = records.first(where: { $0.id == id }), let model else { return }
        guard record.pendingEvent == nil else { problem = "The previous update is still queued. Retry it before adding another."; return }
        busy = true; problem = ""
        record.pendingEvent = CloudEventCommand(revision: record.history?.revision ?? 0, text: text, status: status)
        record.retryAt = .distantPast
        do { try await model.withStore { try $0.saveCloudRecord(record) }; await reload(); busy = false; await sync() }
        catch { busy = false; problem = error.localizedDescription }
    }
    func retry(_ id: String) async {
        guard !busy, var record = records.first(where: { $0.id == id }), let model else { return }
        busy = true
        record.state = record.result == nil ? "queued" : "accepted"; record.retryAt = .distantPast
        do { try await model.withStore { try $0.saveCloudRecord(record) }; busy = false; await sync() } catch { busy = false; problem = error.localizedDescription }
    }
    func discardConflictingEvent(_ id: String) async {
        guard var record = records.first(where: { $0.id == id }), let model else { return }
        record.pendingEvent = nil; record.state = "accepted"; record.retryAt = .distantPast
        do { try await model.withStore { try $0.saveCloudRecord(record) }; await sync() } catch { problem = error.localizedDescription }
    }
    private func reload() async {
        guard let scope, let model else { return }
        do { records = try await model.withStore { try $0.cloudRecords(scope: scope) } } catch { problem = error.localizedDescription }
    }
    func login(username: String, password: String, code: String) async {
        guard !busy else { return }; busy = true; problem = ""
        do {
            if signInNeedsCode { try await auth.confirmCode(code); signInNeedsCode = false }
            else {
                let complete = try await auth.passwordSignIn(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                signInNeedsCode = !complete
                if !complete { busy = false; return }
            }
            busy = false; await connect(signIn: false)
            if profile != nil { await loadInbox(shelterID: isDispatcher ? staffShelterID : nil) }
        } catch { problem = error.localizedDescription; busy = false }
    }
    func cancelLogin() { auth.cancelSignIn(); signInNeedsCode = false; busy = false; problem = "" }
    func persistDraft() {
        guard let model, let scope else { return }; let value = draft
        Task {
            do { try await model.withStore { try $0.saveRequestDraft(value, scope: scope) } }
            catch { problem = error.localizedDescription }
        }
    }
    func previewRequest() async {
        guard !cloudPaused else { problem = "Cloud delivery is paused for this demo. Enter the request details manually."; return }
        guard !interpreting, let api, let scope, let model,
              let shelter = directory.first(where: { $0.shelter_id == draft.shelterID }) else { problem = "Choose a shelter first."; return }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { problem = "Describe your request first."; return }
        interpreting = true; problem = ""; let generation = epoch
        if draft.interpretationText != text || draft.interpretationShelter != shelter.shelter_id || draft.interpretationID == nil || draft.interpretationTranscription != draft.transcriptionID || interpretation?.status == "failed" {
            draft.interpretationReady = false; draft.interpretationID = UUID().uuidString.lowercased(); draft.interpretationText = text; draft.interpretationShelter = shelter.shelter_id; draft.interpretationTranscription = draft.transcriptionID
        }
        let id = draft.interpretationID!, snapshot = draft
        defer { if draft.interpretationID == id { interpreting = false } }
        do {
            try await model.withStore { try $0.saveRequestDraft(snapshot, scope: scope) }
            let token = try await auth.accessToken()
            let command = InterpretationCommand(id: id, incident: shelter.incident_id, shelter: shelter.shelter_id, text: text, transcription: snapshot.transcriptionID)
            var value: InterpretationResult = try await api.call("v1/interpretations", token: token, method: "POST", body: CloudCodec.encode(command))
            for _ in 0..<40 {
                guard generation == epoch, draft.interpretationID == id, !cloudPaused else { return }
                if value.status != "pending" { break }
                try await Task.sleep(for: .milliseconds(500))
                value = try await api.call("v1/interpretations/" + id, token: token)
            }
            guard generation == epoch, draft.interpretationID == id, draft.text.trimmingCharacters(in: .whitespacesAndNewlines) == text, draft.shelterID == shelter.shelter_id else { return }
            interpretation = value
            draft.interpretationReady = ["ready_for_review", "needs_review"].contains(value.status) && value.result != nil
            persistDraft()
            if let proposal = value.result?.proposal {
                if let item = proposal.item_id, draft.item == snapshot.item { draft.item = item }
                if draft.requestedUnit == snapshot.requestedUnit { draft.requestedUnit = proposal.unit }
                if draft.people == snapshot.people { draft.people = proposal.people.map(String.init) ?? snapshot.people }
                if draft.landmark == snapshot.landmark, let landmark = proposal.landmark { draft.landmark = landmark }
                if draft.urgency == snapshot.urgency, let urgency = proposal.urgency { draft.urgency = urgency }
                if draft.medicineDetails == snapshot.medicineDetails, let details = proposal.medicine_details { draft.medicineDetails = details }
                if draft.quantity == snapshot.quantity { draft.quantity = proposal.quantity.map(String.init) ?? "" }
                persistDraft()
            }
            if value.status == "pending" { problem = "Still extracting details. You can retry the same preview or enter the details yourself." }
            if let error = value.error { problem = error.message }
        } catch { if generation == epoch && draft.interpretationID == id { problem = error.localizedDescription } }
    }
    func skipPreview() {
        draft.interpretationID = nil; draft.interpretationReady = nil; draft.interpretationText = nil
        draft.interpretationShelter = nil; draft.interpretationTranscription = nil
        interpreting = false; interpretation = nil; problem = ""; persistDraft()
    }
    func submitRequest(sharedDetails: SharedResidentDetails? = nil) async -> String? {
        guard !submitting, let scope, let model, let shelter = directory.first(where: { $0.shelter_id == draft.shelterID }) else { return nil }
        submitting = true; defer { submitting = false }; problem = ""
        do {
            try draft.validateLocationForNewRequest()
            var snapshot = draft
            try sharedDetails?.validate()
            snapshot.requesterDetails = sharedDetails
            let subject = profile?.subject
            let record = try await model.withStore { store -> CloudQueueRecord in
                var record = try store.submitCloudDraft(snapshot, scope: scope, shelter: shelter, receiver: shelter.receiver, senderSubject: subject)
                if shelter.receiver != nil { record.nearbyState = "queued"; try store.saveCloudRecord(record) }
                return record
            }
            model.kickNearby()
            draft = RequestDraft(); draft.shelterID = shelter.shelter_id; interpretation = nil
            await reload(); Task { await self.sync() }; return record.id
        } catch { problem = error.localizedDescription; return nil }
    }
    func refreshInventory() async {
        guard !cloudPaused, isDispatcher, !staffShelterID.isEmpty, !inventoryBusy, let api, let model, let scope else { return }
        inventoryBusy = true; defer { inventoryBusy = false }
        let generation = epoch, shelter = staffShelterID
        do {
            let token = try await auth.accessToken()
            let value: InventorySnapshot = try await api.call("v1/inventory", token: token, query: [.init(name: "shelter_id", value: shelter)])
            guard generation == epoch else { return }; inventory = value
            pendingAdjustment = try await model.withStore { try $0.setting("inventory_adjustment:" + scope + ":" + shelter).map { $0 != "null" } ?? false }
        } catch { problem = error.localizedDescription }
    }
    func adjustInventory(item: String, amount: Int, note: String) async {
        guard !cloudPaused, isDispatcher, !inventoryBusy, let api, let scope, let model else { return }
        inventoryBusy = true; defer { inventoryBusy = false }; problem = ""
        let generation = epoch, shelter = staffShelterID, key = "inventory_adjustment:" + scope + ":" + staffShelterID
        do {
            let saved = try await model.withStore { try $0.setting(key) }
            let command: InventoryAdjustment
            if let saved, saved != "null" { command = try CloudCodec.decode(InventoryAdjustment.self, Data(saved.utf8)) }
            else {
                guard let row = inventory?.items.first(where: { $0.id == item }), amount != 0 else { throw RelayError.invalid("Refresh stock and enter a nonzero amount.") }
                command = InventoryAdjustment(item: item, delta: amount, revision: row.revision, note: note)
                let data = try CloudCodec.encode(command)
                try await model.withStore { try $0.setSetting(key, String(decoding: data, as: UTF8.self)) }; pendingAdjustment = true
            }
            let token = try await auth.accessToken()
            let value: InventorySnapshot = try await api.call("v1/inventory/" + shelter + "/adjust", token: token, method: "POST", body: CloudCodec.encode(command))
            try await model.withStore { try $0.setSetting(key, "null") }
            guard generation == epoch else { return }; inventory = value; pendingAdjustment = false
        } catch {
            problem = error.localizedDescription
            if let e = error as? CloudHTTPError, !e.retryable { try? await model.withStore { try $0.setSetting(key, "null") }; pendingAdjustment = false }
        }
    }
    func inventoryAction(_ id: String, action: String, item: String? = nil, quantity: Int? = nil) async {
        guard !cloudPaused else { problem = "Inventory approval requires a cloud connection."; return }
        guard !busy, var record = records.first(where: { $0.id == id }), let model else { return }
        guard record.pendingInventory == nil else { await retry(id); return }
        busy = true
        let revision = inventory?.shelter_id == record.submission.destination_shelter_id ? inventory?.items.first(where: { $0.id == (item ?? record.reservation?.item_id) })?.revision : nil
        record.pendingInventory = InventoryCommand(action: action, item: item, quantity: quantity, revision: revision)
        record.retryAt = .distantPast
        do { try await model.withStore { try $0.saveCloudRecord(record) }; await reload(); busy = false; await sync(); await refreshInventory() }
        catch { busy = false; problem = error.localizedDescription }
    }
    func discardInventoryConflict(_ id: String) async {
        guard var record = records.first(where: { $0.id == id }), record.state == "needs_attention", let model else { return }
        record.pendingInventory = nil; record.state = "accepted"; record.problem = nil; record.retryAt = .distantPast
        do { try await model.withStore { try $0.saveCloudRecord(record) }; await sync(); await refreshInventory() }
        catch { problem = error.localizedDescription }
    }
    func saveRecording(url: URL) async {
        guard let profile else { problem = "Sign in before cloud transcription"; return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count > 44 && data.count <= 2_097_152 else { throw RelayError.invalid("Record up to 60 seconds of audio") }
            let job = CloudAudioJob(fileName: url.lastPathComponent, incidentID: profile.incident_id, data: data)
            try await persistAudio(job); audioJob = job; transcript = ""; audioStatus = "Recording saved on this device"
        } catch { problem = error.localizedDescription }
    }
    private func persistAudio(_ job: CloudAudioJob) async throws {
        guard let model, let scope else { throw RelayError.invalid("Sign in first") }
        let data = try CloudCodec.encode(job)
        try await model.withStore { try $0.setSetting("cloud_audio:" + scope, String(decoding: data, as: UTF8.self)) }
    }
    func transcribe() async {
        guard !cloudPaused else { problem = "Resume cloud delivery before transcribing. The recording stays saved."; return }
        guard !audioBusy, var job = audioJob, let api else { return }
        audioBusy = true; defer { audioBusy = false }; let generation = epoch
        do {
            let token = try await auth.accessToken()
            let url = try VoiceRecorder.folder().appendingPathComponent(job.fileName)
            let data = try Data(contentsOf: url)
            if job.source == "streaming" {
                let live: CloudTranscription = try await api.call("v1/transcriptions/\(job.id)", token: token)
                if live.status == "completed", let text = live.transcript {
                    job.transcript = text; try await persistAudio(job); audioJob = job; transcript = text; audioStatus = "Review the recovered live transcript"; return
                }
                guard live.status == "failed" else { throw RelayError.invalid("The live session is still finishing. Try again shortly.") }
                job = CloudAudioJob(fileName: job.fileName, incidentID: job.incidentID, data: data)
                try await persistAudio(job); audioJob = job
            }
            audioStatus = "Preparing private upload…"
            var result: CloudTranscription = try await api.call("v1/transcriptions", token: token, method: "POST", body: job.allocation())
            if let grant = result.upload { try await api.upload(grant, wav: data, token: token) }
            if result.status != "completed" {
                result = try await api.call("v1/transcriptions/\(job.id)/start", token: token, method: "POST", body: JSONSerialization.data(withJSONObject: ["operation_id": job.startID]))
            }
            for _ in 0..<80 {
                guard generation == epoch else { return }
                if result.status == "completed" { break }
                if result.status == "failed" { throw RelayError.invalid(result.error?.message ?? "Transcription failed") }
                audioStatus = "Transcribing… You can continue using nearby messaging."
                try await Task.sleep(for: .seconds(3))
                result = try await api.call("v1/transcriptions/\(job.id)", token: token)
            }
            guard generation == epoch else { return }
            guard result.status == "completed", let text = result.transcript else { throw RelayError.invalid("Still processing. Retry later; the same job will be reused.") }
            job.transcript = text; try await persistAudio(job)
            audioJob = job; transcript = text; audioStatus = "Review and correct the transcript before using it"
        } catch { audioStatus = "Recording retained for retry"; problem = error.localizedDescription }
    }
    func applyTranscript() {
        guard let job = audioJob, job.transcript != nil, let profile, let model, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft.text = transcript; draft.transcriptionID = job.id; draft.interpretationID = nil
        persistDraft()
        model.helpDraft.details = transcript
        model.helpDraft.transcriptionID = job.id; model.helpDraft.transcriptionSubject = profile.subject
        model.helpDraft.transcriptionIncident = job.incidentID
        model.persistHelpDraft(); audioStatus = "Copied to Help. Choose a shelter, complete the fields, then review and submit."
    }
    func refreshDirectory() async {
        guard !cloudPaused, !busy, let api, let model, let scope else { return }
        busy = true; defer { busy = false }; let generation = epoch
        do {
            let token = try await auth.accessToken()
            let value: CloudDirectory = try await api.call("v1/shelters", token: token)
            guard generation == epoch else { return }
            if value.items != directory {
                directory = value.items
                try await model.withStore { try $0.setSetting("cloud_directory:" + scope, String(decoding: try CloudCodec.encode(value.items), as: UTF8.self)) }
            }
        } catch { /* Cached receiving addresses remain usable during an outage. */ }
    }
    private struct ReceiverCommand: Codable { let device_id: String; let expected_revision: Int }
    var selectedReceiver: ShelterReceiver? { directory.first { $0.shelter_id == (isDispatcher ? staffShelterID : draft.shelterID) }?.receiver }
    var receivesHere: Bool { selectedReceiver?.device_id == model?.deviceID && selectedReceiver?.account_subject == profile?.subject }
    func useThisDeviceForShelter() async {
        guard !busy, isDispatcher, let api, let model, let scope, !staffShelterID.isEmpty else { return }
        busy = true; defer { busy = false }
        let generation = epoch
        do {
            let token = try await auth.accessToken()
            let command = ReceiverCommand(device_id: model.deviceID, expected_revision: selectedReceiver?.revision ?? 0)
            let _: ShelterReceiver = try await api.call("v1/shelters/\(staffShelterID)/receiver", token: token, method: "PUT", body: CloudCodec.encode(command))
            let value: CloudDirectory = try await api.call("v1/shelters", token: token)
            guard generation == epoch else { return }
            directory = value.items
            try await model.withStore { try $0.setSetting("cloud_directory:" + scope, String(decoding: try CloudCodec.encode(value.items), as: UTF8.self)) }
            nearbyProblem = ""
        } catch { nearbyProblem = error.localizedDescription }
    }
    /// Application projection follows the durable receipt transaction. Unknown
    /// offline sender identities remain pending backend verification, never staff approval.
    func reconcileNearby() async {
        guard !reconcilingNearby, let model, let scope, let profile else { return }
        reconcilingNearby = true; defer { reconcilingNearby = false }
        let generation = epoch
        do {
            try await model.withStore { store in
                var rows = try store.cloudRecords(scope: scope)
                if profile.role == "dispatcher" {
                    for signed in try store.nearbyRequests() {
                        let value = try signed.verifiedBody(), submission = value.submission
                        guard value.receiver_subject == profile.subject,
                              submission.incident_id == profile.incident_id,
                              profile.shelter_ids.contains(submission.destination_shelter_id) else { continue }
                        if let existing = rows.first(where: { $0.id == submission.request_id }) {
                            guard existing.submission == submission else { throw RelayError.invalid("Nearby/cloud content conflict") }
                            continue
                        }
                        var record = CloudQueueRecord(scope: scope, submission: submission)
                        record.nearbyState = "received"
                        try store.saveCloudRecord(record); rows.append(record)
                    }
                }
                let summaries = try store.summaries()
                for var record in rows where record.submission.origin_device_id == store.deviceID {
                    guard let nearby = summaries.first(where: { $0.id == record.id && SealedDelivery.isSealed($0.message) }) else { continue }
                    let state = nearby.finalReceiptID != nil ? "shelter_saved" : !nearby.acceptedBy.isEmpty ? "relay_saved" : "queued"
                    if record.nearbyState != state { record.nearbyState = state; try store.saveCloudRecord(record) }
                }
            }
            guard generation == epoch else { return }; await reload()
        } catch { nearbyProblem = error.localizedDescription }
    }

    func liveSpeechContext() async throws -> LiveSpeechContext {
        guard !cloudPaused else { throw RelayError.invalid("Resume cloud delivery before using live transcription. You can still type an offline request.") }
        guard let api, let profile, let scope else { throw RelayError.invalid("Sign in before live transcription") }
        let generation = epoch, token = try await auth.accessToken()
        guard generation == epoch else { throw RelayError.invalid("Account changed; start again") }
        return LiveSpeechContext(baseURL: api.baseURL, token: token, subject: profile.subject,
                                 incident: profile.incident_id, scope: scope, generation: generation)
    }
    func retainLiveSpeech(context: LiveSpeechContext, identifier: String, text: String?, url: URL) async throws {
        guard context.generation == epoch, context.scope == scope, context.subject == profile?.subject else { return }
        let data = try Data(contentsOf: url)
        var job = CloudAudioJob(fileName: url.lastPathComponent, incidentID: context.incident, data: data, id: identifier, source: "streaming")
        job.transcript = text; try await persistAudio(job)
        audioJob = job; transcript = text ?? ""
        audioStatus = text == nil ? "Recording retained. Retry checks the original live session first." : "Live transcript saved. Review names and quantities before sending."
    }

    var unreadAnnouncementCount: Int {
        (announcementFeed?.items ?? []).filter { $0.active() && (announcementReads[$0.id] ?? 0) < $0.revision }.count
    }
    private func loadAnnouncementCache() async {
        guard let scope, let model else { return }; let generation = epoch
        do {
            let saved = try await model.withStore { store in
                (try store.announcementFeed(scope: scope),
                 try store.setting("announcement_reads:" + scope),
                 try store.setting("announcement_pending:" + scope))
            }
            guard generation == epoch else { return }
            announcementFeed = saved.0
            announcementReads = try saved.1.map { try CloudCodec.decode([String: Int].self, Data($0.utf8)) } ?? [:]
            pendingAnnouncement = try saved.2.flatMap { try CloudCodec.decode(AnnouncementCommand?.self, Data($0.utf8)) }
        } catch { announcementsProblem = error.localizedDescription }
    }
    func refreshAnnouncements() async {
        guard canUseCloud, !announcementsBusy, let api, let model, let scope, let incident = profile?.incident_id else { return }
        announcementsBusy = true; lastAlertsRefresh = Date(); defer { announcementsBusy = false }
        let generation = epoch
        do {
            let token = try await auth.accessToken()
            let feed: AnnouncementFeed = try await api.call("v1/announcements", token: token)
            guard generation == epoch else { return }
            guard feed.items.allSatisfy({ $0.incident_id == incident }) else { throw RelayError.invalid("Announcement incident does not match this account") }
            try await model.withStore { try $0.saveAnnouncementFeed(feed, scope: scope) }
            guard generation == epoch else { return }
            announcementFeed = feed; announcementsProblem = ""
        } catch { if generation == epoch { announcementsProblem = "Could not refresh. Showing saved announcements. " + error.localizedDescription } }
    }
    func markAnnouncementRead(_ value: CloudAnnouncement) async {
        guard let scope, let model else { return }; let generation = epoch
        var reads = announcementReads; reads[value.id] = value.revision
        do {
            try await model.withStore { try $0.setSetting("announcement_reads:" + scope, String(decoding: CloudCodec.encode(reads), as: UTF8.self)) }
            if generation == epoch { announcementReads = reads }
        } catch { announcementsProblem = error.localizedDescription }
    }
    /// Save the immutable publishing command before HTTP. A lost-response retry uses the same ID and text.
    func publishAnnouncement(_ command: AnnouncementCommand? = nil) async -> Bool {
        guard !announcementsBusy, isDispatcher, let api, let scope, let model else { return false }
        guard !cloudPaused else { announcementsProblem = "Resume cloud delivery to publish announcements."; return false }
        announcementsBusy = true; announcementsProblem = ""; let generation = epoch
        do {
            guard let value = pendingAnnouncement ?? command else { throw RelayError.invalid("Create an announcement first") }
            if pendingAnnouncement == nil {
                try await model.withStore { try $0.setSetting("announcement_pending:" + scope, String(decoding: CloudCodec.encode(value), as: UTF8.self)) }
                guard generation == epoch else { announcementsBusy = false; return false }
                pendingAnnouncement = value
            }
            let token = try await auth.accessToken()
            let _: CloudAnnouncement = try await api.call("v1/announcements", token: token, method: "POST", body: CloudCodec.encode(value))
            try await model.withStore { try $0.setSetting("announcement_pending:" + scope, "null") }
            guard generation == epoch else { announcementsBusy = false; return false }
            pendingAnnouncement = nil; announcementsBusy = false
            await refreshAnnouncements(); return true
        } catch {
            if generation == epoch { announcementsProblem = "Publishing not confirmed. Retry the saved announcement: " + error.localizedDescription }
            announcementsBusy = false; return false
        }
    }
    /// Used only after the server has definitively rejected an expired, never-published draft.
    func discardExpiredAnnouncement() async {
        guard let value = pendingAnnouncement, value.expires_at < Date(), !announcementsBusy, let api, let model, let scope, canUseCloud else { return }
        announcementsBusy = true; defer { announcementsBusy = false }; let generation = epoch
        do {
            let token = try await auth.accessToken()
            let feed: AnnouncementFeed = try await api.call("v1/announcements", token: token)
            // An expired publication is inactive regardless of whether its previous response was lost.
            try await model.withStore { try $0.saveAnnouncementFeed(feed, scope: scope); try $0.setSetting("announcement_pending:" + scope, "null") }
            guard generation == epoch else { return }; pendingAnnouncement = nil; announcementFeed = feed; announcementsProblem = ""
        } catch { announcementsProblem = error.localizedDescription }
    }
    func withdrawAnnouncement(_ value: CloudAnnouncement) async {
        guard canUseCloud, isDispatcher, !announcementsBusy, let api else { return }
        announcementsBusy = true; let generation = epoch
        do {
            let token = try await auth.accessToken()
            let _: CloudAnnouncement = try await api.call("v1/announcements/\(value.id)/withdraw", token: token, method: "POST", body: CloudCodec.encode(["expected_revision": value.revision]))
            announcementsBusy = false
            if generation == epoch { await refreshAnnouncements() }
        } catch { announcementsBusy = false; if generation == epoch { announcementsProblem = error.localizedDescription } }
    }
    func updateShelterDetails(shelterID: String, command: ShelterDetailsCommand) async throws {
        guard canUseCloud, isDispatcher, let api, let scope, let model else { throw RelayError.invalid("Connect to the cloud as a dispatcher to update shelter information") }
        let generation = epoch, token = try await auth.accessToken()
        let _: ShelterDetails = try await api.call("v1/shelters/\(shelterID)/details", token: token, method: "PUT", body: CloudCodec.encode(command))
        let updated: CloudDirectory = try await api.call("v1/shelters", token: token)
        guard generation == epoch else { return }
        try await model.withStore { try $0.setSetting("cloud_directory:" + scope, String(decoding: CloudCodec.encode(updated.items), as: UTF8.self)) }
        if generation == epoch { directory = updated.items }
    }

    func loadResidentContext(force: Bool = false) async {
        guard profile?.role == "requester", let scope, let model else { return }
        guard force || residentContextScope != scope else { return }
        residentContextScope = nil; residentDetails = ResidentDetails(); residentDetailsAvailable = false; residentDetailsProblem = ""
        do {
            var state = try await model.withStore { try $0.residentSetup(scope: scope) }
            guard self.scope == scope, profile?.role == "requester" else { return }
            #if DEBUG
            // Explicit development launch only. Preserve profile, account and request data.
            if !replayedResidentSetup && ProcessInfo.processInfo.arguments.contains("--relay-replay-resident-setup") {
                try await model.withStore { try $0.saveResidentSetup(ResidentSetupState(), scope: scope) }
                guard self.scope == scope, profile?.role == "requester" else { return }
                replayedResidentSetup = true
                state = ResidentSetupState()
            }
            #endif
            residentSetup = state
            do { residentDetails = try residentVault.read(scope: scope); residentDetailsAvailable = true }
            catch { residentDetailsProblem = error.localizedDescription }
            residentContextScope = scope
        } catch { residentDetailsProblem = error.localizedDescription }
    }
    func saveResidentDetails(_ value: ResidentDetails) async -> Bool {
        guard !residentDetailsBusy, residentDetailsAvailable, let scope = residentContextID, let model else { return false }
        residentDetailsBusy = true; defer { residentDetailsBusy = false }; residentDetailsProblem = ""
        do {
            let validated = try ResidentDetailsDraft(value).validated(decimalSeparator: ".", requireBasics: true)
            try residentVault.save(validated, scope: scope)
            var updated = residentSetup; updated.profileOffered = true
            try await model.withStore { try $0.saveResidentSetup(updated, scope: scope) }
            guard residentContextID == scope else { return false }
            residentDetails = validated; residentSetup = updated; return true
        } catch { if residentContextID == scope { residentDetailsProblem = error.localizedDescription }; return false }
    }
    func completeResidentStep(profile: Bool = false, guide: Bool = false) async -> Bool {
        guard !residentDetailsBusy, let scope = residentContextID, let model else { return false }
        residentDetailsBusy = true; defer { residentDetailsBusy = false }
        do {
            var updated = residentSetup
            if profile { updated.profileOffered = true }
            if guide { updated.guideSeen = true }
            try await model.withStore { try $0.saveResidentSetup(updated, scope: scope) }
            guard residentContextID == scope else { return false }; residentSetup = updated; return true
        } catch { if residentContextID == scope { residentDetailsProblem = error.localizedDescription }; return false }
    }
    func clearResidentDetails() -> Bool {
        guard !residentDetailsBusy, let scope = residentContextID else { return false }
        do { try residentVault.clear(scope: scope); residentDetails = ResidentDetails(); residentDetailsAvailable = true; residentDetailsProblem = ""; return true }
        catch { residentDetailsProblem = error.localizedDescription; return false }
    }

}
