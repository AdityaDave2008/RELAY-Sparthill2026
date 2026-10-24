import SwiftUI
import RelayCore

@main
struct RelayApp: App {
    @StateObject private var model = RelayModel()
    var body: some Scene {
        WindowGroup { ContentView(model: model).tint(RelayTheme.accent).modifier(ReadingPreferences()) }
    }
}

final class RelayModel: ObservableObject {
    @Published var deviceID = "Opening SQLite…"
    @Published var displayName = ""
    @Published var role: TestRole = .relay
    @Published var forceRoute = false
    @Published var active = false
    @Published var networkState = "Stopped"
    @Published var discovered: [TransportPeer] = []
    @Published var connected: [Peer] = []
    @Published var known: [Peer] = []
    @Published var messages: [StoredMessage] = []
    @Published var paths: [String] = []
    @Published var logs: [String] = []
    @Published var error = ""
    @Published var storagePath = ""
    @Published var armed = false
    @Published var ready = false
    @Published var sending = false
    @Published var notice = ""
    @Published var chatDrafts: [String: String] = [:]
    @Published var shelters: [ShelterContact] = []
    @Published var removedShelters: [ShelterContact] = []
    @Published var helpDraft = HelpRequestDraft()
    @Published var draftSaveState = "Draft stays on this device"
    private let queue = DispatchQueue(label: "org.relay.engine")
    private var engine: RelayEngine?
    private var transport: NetworkTransport?
    private var refreshPending = false

    init() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("RELAY", isDirectory: true)
                let store = try RelayStore.open(path: folder.appendingPathComponent("relay.sqlite").path)
                try store.enableSealedDelivery(DeviceIdentity.load(deviceID: store.deviceID, at: folder.appendingPathComponent("device-keys.json")))
                let role = try store.setting("role").flatMap(TestRole.init(rawValue:)) ?? .relay
                let forceRoute = try store.setting("force_route") == "true"
                #if targetEnvironment(simulator)
                let deviceKind = "Simulator"
                #elseif os(iOS)
                let deviceKind = "iPhone"
                #else
                let deviceKind = "Mac"
                #endif
                let displayName = try Peer.normalizedName(store.setting("display_name") ?? "\(deviceKind) \(store.deviceID.prefix(4).uppercased())")
                try store.setSetting("display_name", displayName)
                let engine = RelayEngine(store: store, role: role, forceRelayRoute: forceRoute, displayName: displayName)
                let helpDraft = try store.helpDraft() ?? HelpRequestDraft()
                self.engine = engine
                let transport = NetworkTransport(engine: engine, queue: self.queue); self.transport = transport
                engine.onEvent = { print($0) }
                engine.onChange = { [weak self] in self?.scheduleRefresh() }
                transport.onDiscovery = { [weak self] peers in DispatchQueue.main.async { self?.discovered = peers } }
                transport.onState = { [weak self] state in DispatchQueue.main.async { self?.networkState = state } }
                DispatchQueue.main.async {
                    self.deviceID = store.deviceID; self.displayName = displayName; self.role = role; self.forceRoute = forceRoute; self.storagePath = store.path; self.helpDraft = helpDraft; self.ready = true
                }
                engine.event("APP_OPEN device=\(store.deviceID) os=\(ProcessInfo.processInfo.operatingSystemVersionString) durable_store=\(store.path)")
                self.refresh()
            } catch { self.report(error) }
        }
    }
    private func report(_ error: Error) { DispatchQueue.main.async { self.error = String(describing: error) } }
    private func scheduleRefresh() {
        guard !refreshPending else { return }; refreshPending = true
        queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.refreshPending = false; self?.refresh() }
    }
    private func refresh() {
        guard let e = engine, let t = transport else { return }
        do {
            let messages = try e.store.summaries(), known = try e.store.knownPeers(), logs = try e.store.logs(limit: 300)
            let shelters = try e.store.shelters()
            let removed = try e.store.shelters(includeRemoved: true).filter { entry in !shelters.contains(where: { $0.id == entry.id }) }
            let connected = Array(Set(e.connectedPeers.values.map(\.deviceID))).sorted().compactMap { id in e.connectedPeers.values.first { $0.deviceID == id } }
            let paths = t.paths.values.sorted(), running = t.running, armed = t.interruptNextMessage
            DispatchQueue.main.async {
                self.messages = messages; self.known = known; self.logs = logs; self.connected = connected
                self.paths = paths; self.active = running; self.armed = armed
                self.shelters = shelters
                self.removedShelters = removed
            }
        } catch { report(error) }
    }
    func setNearby(active: Bool) {
        queue.async { [weak self] in
            guard let self, let transport = self.transport else { return }
            if active && !transport.running { transport.start() }
            else if !active && transport.running { transport.stop() }
            self.refresh()
        }
    }
    func configure() {
        let role = role, forceRoute = forceRoute
        queue.async { [weak self] in
            guard let self, let engine = self.engine else { return }
            let wasActive = self.transport?.running == true
            self.transport?.stop()
            do {
                try engine.store.setSetting("role", role.rawValue)
                try engine.store.setSetting("force_route", String(forceRoute))
                engine.role = role; engine.forceRelayRoute = forceRoute
                engine.event("CONFIG role=\(role.rawValue) force_logical_A_B_C=\(forceRoute)")
                if wasActive { self.transport?.start() }
            } catch { self.report(error) }
            self.refresh()
        }
    }
    func toggle() {
        queue.async { [weak self] in
            guard let self, let t = self.transport else { return }
            if t.running { t.stop() } else { t.start() }; self.refresh()
        }
    }
    func rename(_ proposed: String, onSaved: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self, let engine = self.engine else { return }
            do {
                let name = try Peer.normalizedName(proposed)
                try engine.store.setSetting("display_name", name)
                let wasActive = self.transport?.running == true
                self.transport?.stop()
                engine.displayName = name
                engine.event("DEVICE_NAME_UPDATED identity_unchanged=true")
                if wasActive { self.transport?.start() }
                DispatchQueue.main.async { self.displayName = name; onSaved() }
                self.refresh()
            } catch { self.report(error) }
        }
    }
    func addressLabel(_ id: String) -> String {
        "\(peerTitle(id)) · \(id.prefix(8))"
    }
    func peerTitle(_ id: String) -> String {
        if id == deviceID { return displayName.isEmpty ? "This device" : displayName }
        let connectedName = connected.first { $0.deviceID == id }?.displayName
        return connectedName ?? known.first { $0.deviceID == id }?.title ?? "Device \(id.prefix(8))"
    }
    func send(text: String, destination: String, onSaved: @escaping () -> Void) {
        guard !sending else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = destination.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        sending = true
        queue.async { [weak self] in
            guard let self else { return }
            do {
                guard let engine = self.engine else { throw RelayError.database("Store is not ready") }
                try engine.compose(text: text, destinationID: destination)
                self.refresh()
                DispatchQueue.main.async { self.sending = false; onSaved() }
            } catch {
                self.report(error)
                DispatchQueue.main.async { self.sending = false }
            }
        }
    }
    func retry(_ id: String) {
        queue.async { [weak self] in
            do { try self?.engine?.retransmitForTest(id) } catch { self?.report(error) }
            self?.refresh()
        }
    }
    func saveShelter(_ shelter: ShelterContact, done: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self, let engine = self.engine else { return }
            do {
                try engine.store.saveShelter(shelter)
                engine.event("SHELTER_SAVED id=\(shelter.id) receiver=\(shelter.receivingDeviceID) identity=UNVERIFIED")
                self.refresh(); DispatchQueue.main.async { done() }
            } catch { self.report(error) }
        }
    }
    func removeShelter(_ id: String, done: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self, let engine = self.engine else { return }
            do {
                try engine.store.removeShelter(id)
                engine.event("SHELTER_REMOVED_FROM_DIRECTORY id=\(id) history_preserved=true")
                self.refresh()
                DispatchQueue.main.async {
                    if self.helpDraft.shelterID == id { self.helpDraft.shelterID = "" }
                    done()
                }
            } catch { self.report(error) }
        }
    }
    func persistHelpDraft() {
        guard ready else { return }
        let draft = helpDraft
        draftSaveState = "Saving draft…"
        queue.async { [weak self] in
            guard let self, let engine = self.engine else { return }
            do {
                try engine.store.saveHelpDraft(draft)
                DispatchQueue.main.async {
                    if self.helpDraft == draft { self.draftSaveState = "Draft saved on this device" }
                }
            } catch {
                self.report(error)
                DispatchQueue.main.async { self.draftSaveState = "Draft could not be saved" }
            }
        }
    }
    func submitHelp(_ draft: HelpRequestDraft, done: @escaping (String) -> Void) {
        guard !sending else { return }; sending = true
        queue.async { [weak self] in
            guard let self else { return }
            do {
                guard let engine = self.engine else { throw RelayError.database("Store not ready") }
                let request = try engine.submitHelpRequest(draft)
                self.refresh()
                DispatchQueue.main.async {
                    self.sending = false
                    if self.helpDraft.requestID == draft.requestID { self.helpDraft = HelpRequestDraft() }
                    done(request.id)
                }
            } catch {
                self.report(error); DispatchQueue.main.async { self.sending = false }
            }
        }
    }
    func kickNearby() {
        queue.async { [weak self] in self?.engine?.tick(); self?.refresh() }
    }
    func withStore<T>(_ action: @escaping (RelayStore) throws -> T) async throws -> T {
        let workQueue = queue
        return try await withCheckedThrowingContinuation { continuation in
            workQueue.async {
                do {
                    guard let engine = self.engine else { throw RelayError.database("Store not ready") }
                    continuation.resume(returning: try action(engine.store))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func sendRequestUpdate(_ request: RelayMessage, text: String, progress: String?, done: @escaping () -> Void) {
        guard request.originID == deviceID || request.destinationID == deviceID else { return }
        do {
            let update = LocalRequestUpdate(requestID: request.id, text: text, progress: progress)
            try send(text: update.encode(), destination: request.originID == deviceID ? request.destinationID : request.originID, onSaved: done)
        } catch { self.error = String(describing: error) }
    }
    func armInterrupt() {
        queue.async { [weak self] in
            self?.transport?.interruptNextMessage = true
            self?.engine?.event("FAULT_ARMED next message will send half a frame then disconnect")
            self?.refresh()
        }
    }
    func export() {
        queue.async { [weak self] in
            guard let self, let e = self.engine else { return }
            do {
                let report = "RELAY diagnostics — path independence NOT certified by app\n" + (try e.store.logs(limit: 10000)).joined(separator: "\n")
                DispatchQueue.main.async {
                    #if os(iOS)
                    UIPasteboard.general.string = report
                    #else
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(report, forType: .string)
                    #endif
                    self.notice = "Diagnostic log copied."
                }
            } catch { self.report(error) }
        }
    }
}

enum RelayTheme {
    static let accent = Color(red: 0.55, green: 0.20, blue: 0.025)
    static let secondary = Color(red: 0.29, green: 0.29, blue: 0.29)
    static let action = Color.black
    static let onAction = Color.white
    static let incoming = Color.white
    static let canvas = Color.white
}

struct ReadingPreferences: ViewModifier {
    @AppStorage("relay.readingSize") private var readingSize = "Normal"
    @Environment(\.dynamicTypeSize) private var systemSize
    private var preferred: DynamicTypeSize {
        let selected: DynamicTypeSize = readingSize == "Largest" ? .accessibility1 : readingSize == "Large" ? .xxxLarge : .large
        return max(systemSize, selected)
    }
    func body(content: Content) -> some View {
        content.preferredColorScheme(.light).dynamicTypeSize(preferred)
    }
}

func copyText(_ value: String) {
    #if os(iOS)
    UIPasteboard.general.string = value
    #else
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    #endif
}

struct RelayCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 15) { content; Divider().padding(.top, 6) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
    }
}
struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.bold)).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.horizontal, 14).padding(.vertical, 17)
            .foregroundStyle(enabled ? RelayTheme.onAction : Color.secondary)
            .background(enabled ? RelayTheme.action : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.70 : 1)
    }
}

private struct StatusPill: View {
    let text: String
    let symbol: String
    var color: Color = RelayTheme.accent
    var body: some View {
        Label(text, systemImage: symbol).font(.caption.weight(.semibold))
            .foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.10), in: Capsule())
    }
}

struct HideNativeTabBar: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.toolbar(.hidden, for: .tabBar)
        #else
        content
        #endif
    }
}

struct ContentView: View {
    @ObservedObject var model: RelayModel
    @StateObject private var cloud = CloudModel()
    @State private var selectedTab = 3
    @State private var requestPath: [String] = []
    @State private var residentWelcome = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
        if cloud.profile != nil {
            workspaceTabs
            #if os(iOS)
            .toolbar(.hidden, for: .tabBar)
            #endif
            #if os(iOS)
                HStack(spacing: 0) {
                    tabButton(cloud.isDispatcher ? "Inbox" : "Ask for help", symbol: cloud.isDispatcher ? "tray.fill" : "lifepreserver", tag: 3)
                    tabButton(cloud.isDispatcher ? "Inventory" : "Requests", symbol: cloud.isDispatcher ? "shippingbox.fill" : "tray.fill", tag: 4)
                    tabButton(cloud.unreadAnnouncementCount > 0 ? "Alerts (\(cloud.unreadAnnouncementCount))" : "Alerts", symbol: "megaphone", tag: 6)
                    tabButton("Settings", symbol: "gearshape.fill", tag: 5)
                }.padding(.top, 12).padding(.bottom, 4).background(.white)
                    .overlay(alignment: .top) { Rectangle().fill(.black).frame(height: 1.5) }
            #endif
        } else if cloud.accountReady {
            RelaySignInScreen()
        } else {
            ProgressView("Opening RELAY…").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        }.tint(RelayTheme.accent)
            .environmentObject(cloud)
        .task(id: model.ready) { if model.ready { model.setNearby(active: true); Task { await cloud.attach(model) } } }
        .onChange(of: nearbySnapshot) { _, _ in
            Task { await cloud.reconcileNearby() }
        }
        .onChange(of: cloud.profile?.role) { _, _ in selectedTab = 3; requestPath = [] }
        .onChange(of: cloud.residentContextID) { _, value in
            if value != nil, cloud.residentSetup.needsWelcome { residentWelcome = true }
            else if value == nil { residentWelcome = false }
        }
        .sheet(isPresented: $residentWelcome) { ResidentWelcomeView().environmentObject(cloud) }
            .alert("Couldn’t complete that action", isPresented: Binding(get: { !model.error.isEmpty }, set: { if !$0 { model.error = "" } })) {
                Button("OK") { model.error = "" }
            } message: { Text(model.error) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.setNearby(active: true) }
                else if phase == .background { model.setNearby(active: false) }
                #if os(iOS)
                UIApplication.shared.isIdleTimerDisabled = phase == .active
                #endif
            }
            #if os(macOS)
            .frame(minWidth: 540, minHeight: 650)
            #endif
    }
    private var nearbySnapshot: [String] {
        model.messages.map { row in "\(row.id):\(row.finalReceiptID ?? ""):\(row.acceptedBy.count)" }
    }
    private var workspaceTabs: some View {
        TabView(selection: $selectedTab) {
            if cloud.isDispatcher {
                NavigationStack { WorkflowRequestsView(model: model, staff: true) }
                    .tabItem { Label("Inbox", systemImage: "tray.fill") }.tag(3).modifier(HideNativeTabBar())
                NavigationStack { InventoryView(model: model) }
                    .tabItem { Label("Inventory", systemImage: "shippingbox.fill") }.tag(4).modifier(HideNativeTabBar())
            } else {
                NavigationStack { PublicHelpView(model: model) { id in selectedTab = 4; requestPath = [id] } }
                    .tabItem { Label("Ask for help", systemImage: "lifepreserver") }.tag(3).modifier(HideNativeTabBar())
                NavigationStack(path: $requestPath) {
                    WorkflowRequestsView(model: model, staff: false)
                        .navigationDestination(for: String.self) { id in WorkflowRequestDetail(id: id) }
                }.tabItem { Label("Requests", systemImage: "tray.fill") }.tag(4).modifier(HideNativeTabBar())
            }
            NavigationStack { AnnouncementsView() }
                .tabItem { Label("Alerts", systemImage: "megaphone") }.tag(6).modifier(HideNativeTabBar())
            NavigationStack { WorkflowSettings(model: model) }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(5).modifier(HideNativeTabBar())
        }
    }
    private func tabButton(_ title: String, symbol: String, tag: Int) -> some View {
        Button { selectedTab = tag } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 23, weight: .semibold)).accessibilityHidden(true)
                Text(title).font(.caption.bold()).multilineTextAlignment(.center)
            }.foregroundStyle(selectedTab == tag ? RelayTheme.accent : .black)
                .frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityIdentifier("workspaceTab" + String(tag))
            .accessibilityAddTraits(selectedTab == tag ? .isSelected : [])
    }

}

struct NearbyMessagesView: View {
    @ObservedObject var model: RelayModel
    @State private var chatPath: [String] = []
    @State private var choosingPeer = false
    @State private var pendingPeer: String?
    private var conversations: [RelayConversation] { RelayConversation.project(model.messages, deviceID: model.deviceID) }
    var body: some View {
        NavigationStack(path: $chatPath) {
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Nearby").font(.largeTitle.weight(.bold))
                            Text("Direct device conversations").font(.subheadline).foregroundStyle(RelayTheme.secondary)
                        }
                        Spacer()
                        Button { choosingPeer = true } label: {
                            Text("New message").font(.subheadline.weight(.medium)).frame(minHeight: 44)
                        }.buttonStyle(.plain).disabled(!model.ready).accessibilityIdentifier("newChatButton")
                    }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
                    ConnectionCard(model: model).padding(.horizontal, 16).padding(.bottom, 12)
                    ScrollView {
                        if conversations.isEmpty {
                            VStack(spacing: 14) {
                                Text("Start a conversation").font(.title3.bold())
                                Text("Choose a nearby device, or enter its ID.\nYour messages stay saved between encounters.")
                                    .font(.subheadline).foregroundStyle(RelayTheme.secondary).multilineTextAlignment(.center)
                                Button("New chat") { choosingPeer = true }.buttonStyle(.borderedProminent).controlSize(.large)
                                    .disabled(!model.ready)
                            }.padding(.horizontal, 24).padding(.top, 70)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(conversations) { conversation in
                                    Button { chatPath = [conversation.peerID] } label: {
                                        ConversationRow(conversation: conversation, model: model)
                                    }.buttonStyle(.plain).accessibilityHint("Open conversation")
                                    Divider().padding(.leading, 76)
                                }
                            }.padding(.horizontal, 8)
                        }
                        Text("Shelter conversations are in Requests or Inbox. Devices carry eligible nearby messages automatically.")
                            .font(.caption2).foregroundStyle(RelayTheme.secondary).padding(20)
                    }
                }.background(RelayTheme.canvas)
                    .navigationDestination(for: String.self) { peerID in
                        ConversationView(model: model, peerID: peerID) { choosingPeer = true }
                    }
            }
        .sheet(isPresented: $choosingPeer, onDismiss: {
            if let id = pendingPeer { pendingPeer = nil; chatPath = [id] }
        }) { RecipientPicker(model: model) { id in pendingPeer = id; choosingPeer = false } }
    }
}

private struct PeerAvatar: View {
    let title: String
    var body: some View {
        Text(String(title.prefix(1))).font(.headline.weight(.semibold))
            .foregroundStyle(.primary).frame(width: 42, height: 42)
            .background(Color.primary.opacity(0.06), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct ConversationRow: View {
    let conversation: RelayConversation
    @ObservedObject var model: RelayModel
    var body: some View {
        let row = conversation.latest
        HStack(alignment: .center, spacing: 12) {
            PeerAvatar(title: model.peerTitle(conversation.peerID))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(model.peerTitle(conversation.peerID)).font(.headline).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(row.message.createdAt, style: .time).font(.caption2).foregroundStyle(RelayTheme.secondary)
                }
                Text((row.message.originID == model.deviceID ? "You: " : "") + row.message.payload.text)
                    .font(.subheadline).foregroundStyle(RelayTheme.secondary).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(String(conversation.peerID.prefix(8))).font(.system(.caption2, design: .monospaced))
                    Text("·")
                    Text(row.message.originID == model.deviceID ? row.chatStatus : "Received")
                }.font(.caption2).foregroundStyle(RelayTheme.secondary)
            }
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }.padding(.horizontal, 16).padding(.vertical, 16).contentShape(Rectangle())
    }
}

private extension StoredMessage {
    var chatStatus: String {
        if finalReceiptID != nil { return "Delivered" }
        if message.expiresAt <= Date() { return "Expired" }
        if destinationAccepted { return "Destination saved · awaiting receipt" }
        if !acceptedBy.isEmpty { return "Relay saved · awaiting delivery" }
        return "Queued"
    }
}

struct ConnectionCard: View {
    @ObservedObject var model: RelayModel
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(!model.active ? "Nearby paused" : model.connected.isEmpty ? "Looking for a connection" : "\(model.connected.count) nearby connection\(model.connected.count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.medium))
                Text("Messages remain saved between encounters").font(.caption).foregroundStyle(RelayTheme.secondary)
            }
            Spacer(minLength: 4)
            Button(model.active ? "Pause" : "Connect") { model.toggle() }.font(.subheadline).buttonStyle(.plain)
                .frame(minHeight: 44).disabled(!model.ready).accessibilityLabel(model.active ? "Pause connections" : "Start nearby connections")
        }.padding(.vertical, 14).overlay(alignment: .bottom) { Divider() }
    }
}

private struct RecipientPicker: View {
    @ObservedObject var model: RelayModel
    let select: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @FocusState private var addressFocused: Bool
    private var normalized: String { address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var valid: Bool { UUID(uuidString: normalized) != nil && normalized != model.deviceID }
    private var previous: [Peer] { model.known.filter { p in !model.connected.contains { $0.deviceID == p.deviceID } } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !model.connected.isEmpty {
                        Text("CONNECTED NOW").font(.caption.weight(.semibold)).foregroundStyle(RelayTheme.secondary)
                        ForEach(model.connected, id: \.deviceID) { peer in peerButton(peer) }
                    }
                    if !previous.isEmpty {
                        Text("PREVIOUSLY MET").font(.caption.weight(.semibold)).foregroundStyle(RelayTheme.secondary)
                        ForEach(previous, id: \.deviceID) { peer in peerButton(peer) }
                    }
                    if model.known.isEmpty {
                        Label("No devices met yet", systemImage: "person.2").font(.headline)
                        Text("Start connections on both devices, or paste the other device’s ID from Tools.")
                            .font(.subheadline).foregroundStyle(RelayTheme.secondary)
                        if !model.active { Button("Start nearby connections") { model.toggle() }.buttonStyle(.bordered) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Enter a device ID").font(.headline)
                        TextField("Destination UUID", text: $address).textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled().focused($addressFocused).submitLabel(.go)
                            .onSubmit { if valid { select(normalized) } }
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                        Text(normalized == model.deviceID ? "That is your own device ID. Choose another device." : "The destination can be offline. A relay can carry messages to it later.")
                            .font(.caption).foregroundStyle(RelayTheme.secondary)
                        Button("Open chat") { select(normalized) }.buttonStyle(PrimaryButton()).disabled(!valid)
                    }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 16))
                }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.background(RelayTheme.canvas).navigationTitle("New chat")
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { if addressFocused { Button("Done") { addressFocused = false } } }
                }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 500)
        #endif
    }
    private func peerButton(_ peer: Peer) -> some View {
        Button { select(peer.deviceID) } label: {
            HStack(spacing: 12) {
                PeerAvatar(title: model.peerTitle(peer.deviceID))
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.peerTitle(peer.deviceID)).font(.headline).foregroundStyle(.primary)
                    Text(String(peer.deviceID.prefix(8))).font(.system(.caption, design: .monospaced)).foregroundStyle(RelayTheme.secondary)
                }
                Spacer(); Image(systemName: "chevron.right").font(.caption)
            }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
}

private struct ConversationView: View {
    @ObservedObject var model: RelayModel
    let peerID: String
    let newChat: () -> Void
    @State private var selectedMessage: StoredMessage?
    @FocusState private var composerFocused: Bool
    private var messages: [StoredMessage] { RelayConversation.project(model.messages, deviceID: model.deviceID).first { $0.peerID == peerID }?.messages ?? [] }
    private var draft: Binding<String> { Binding(get: { model.chatDrafts[peerID] ?? "" }, set: { model.chatDrafts[peerID] = $0 }) }
    private var valid: Bool { !(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && draft.wrappedValue.utf8.count <= 16_384 }
    private var direct: Bool { model.connected.contains { $0.deviceID == peerID } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(direct ? RelayTheme.accent : Color.secondary).frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(direct ? "Connected now" : "Messages stay queued between encounters")
                    Text("To: \(model.peerTitle(peerID)) · \(peerID.prefix(8))").lineLimit(1)
                }.font(.caption).foregroundStyle(RelayTheme.secondary)
                Spacer(minLength: 0)
                if !model.active { Button("Connect") { model.toggle() }.font(.caption.weight(.semibold)).frame(minHeight: 36) }
            }.padding(.horizontal, 16).padding(.vertical, 5)
            Divider()
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            Text("Nearby conversation · synthetic demo").font(.caption2)
                                .foregroundStyle(RelayTheme.secondary).padding(.vertical, 12)
                            if messages.isEmpty {
                                Text("Send your first message.\nIt will be saved even when this device isn’t nearby.")
                                    .font(.subheadline).foregroundStyle(RelayTheme.secondary).multilineTextAlignment(.center).padding(.vertical, 30)
                            }
                            ForEach(messages) { row in
                                ChatBubble(row: row, outgoing: row.message.originID == model.deviceID,
                                           maxWidth: min(480, geometry.size.width * 0.78)) { selectedMessage = row }
                            }
                            Color.clear.frame(height: 1).id("chat-bottom")
                        }.padding(.horizontal, 14).padding(.bottom, 10).frame(maxWidth: 760).frame(maxWidth: .infinity)
                    }
                    .defaultScrollAnchor(.bottom)
                    #if os(iOS)
                    .scrollDismissesKeyboard(.interactively)
                    #endif
                    .onChange(of: messages.map(\.id)) { _, _ in proxy.scrollTo("chat-bottom", anchor: .bottom) }
                    .onChange(of: composerFocused) { _, focused in if focused { proxy.scrollTo("chat-bottom", anchor: .bottom) } }
                }
            }
        }.background(RelayTheme.canvas)
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle(model.peerTitle(peerID))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: newChat) { Label("New chat", systemImage: "square.and.pencil") }
                }
            }
            .sheet(item: $selectedMessage) { row in
                MessageDetailView(model: model, messageID: row.id) { _ in selectedMessage = nil }
            }
            .alert("Message wasn’t saved", isPresented: Binding(get: { !model.error.isEmpty }, set: { if !$0 { model.error = "" } })) {
                Button("OK") { model.error = "" }
            } message: { Text(model.error) }
    }
    private var composer: some View {
        VStack(spacing: 8) {
            Divider()
            HStack {
                Menu {
                    Button("Hello") { draft.wrappedValue = "SYNTHETIC: Hello from RELAY." }
                    Button("Water request") { draft.wrappedValue = "SYNTHETIC: Shelter A needs 20 water packs." }
                    Button("Check-in") { draft.wrappedValue = "SYNTHETIC: Team check-in. Please confirm receipt." }
                } label: { Label("Test templates", systemImage: "text.badge.plus").font(.caption) }
                Spacer()
                if composerFocused {
                    Button { composerFocused = false } label: { Label("Done", systemImage: "keyboard.chevron.compact.down") }
                        .font(.subheadline.weight(.semibold)).accessibilityIdentifier("dismissChatKeyboard")
                }
            }.padding(.horizontal, 18)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message", text: draft, axis: .vertical).font(.body).lineLimit(1...5)
                    .textFieldStyle(.plain).focused($composerFocused)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(RelayTheme.canvas, in: RoundedRectangle(cornerRadius: 23))
                    .accessibilityIdentifier("chatComposer")
                Button {
                    let text = draft.wrappedValue
                    model.send(text: text, destination: peerID) {
                        if draft.wrappedValue == text { draft.wrappedValue = "" }
                    }
                } label: {
                    Image(systemName: model.sending ? "hourglass" : "arrow.up")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(RelayTheme.onAction).frame(width: 44, height: 44)
                        .background(valid && !model.sending ? RelayTheme.action : Color.gray, in: Circle())
                }.buttonStyle(.plain).disabled(!valid || model.sending || !model.ready)
                    .accessibilityLabel("Send message").accessibilityIdentifier("sendChatMessage")
            }.padding(.horizontal, 12)
            if draft.wrappedValue.utf8.count > 16_384 {
                Text("Message too long. Keep it under 16 KB.").font(.caption).foregroundStyle(.red)
            }
        }.padding(.bottom, 10).background(.background)
    }
}

private struct ChatBubble: View {
    let row: StoredMessage
    let outgoing: Bool
    let maxWidth: CGFloat
    let details: () -> Void
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if outgoing { Spacer(minLength: 24) }
            VStack(alignment: outgoing ? .trailing : .leading, spacing: 5) {
                Button(action: details) {
                    Text(row.message.payload.text).font(.body).multilineTextAlignment(.leading)
                        .foregroundStyle(outgoing ? RelayTheme.onAction : Color.primary)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(outgoing ? RelayTheme.action : RelayTheme.incoming, in: RoundedRectangle(cornerRadius: 19))
                }.buttonStyle(.plain).accessibilityHint("Show delivery details")
                    .contextMenu {
                        Button("Copy message", systemImage: "doc.on.doc") { copyText(row.message.payload.text) }
                        Button("Delivery details", systemImage: "info.circle", action: details)
                    }
                HStack(spacing: 5) {
                    Text(row.message.createdAt, style: .time)
                    if outgoing {
                        Image(systemName: row.finalReceiptID != nil ? "checkmark.circle.fill" : "clock")
                        Text(row.chatStatus)
                    }
                }.font(.caption2).foregroundStyle(RelayTheme.secondary).padding(.horizontal, 4)
            }.frame(maxWidth: maxWidth, alignment: outgoing ? .trailing : .leading)
            if !outgoing { Spacer(minLength: 24) }
        }.frame(maxWidth: .infinity)
    }
}

private struct DeliveryBadge: View {
    let row: StoredMessage
    let deviceID: String
    var body: some View {
        if row.finalReceiptID != nil { StatusPill(text: "Delivery confirmed", symbol: "checkmark.seal.fill") }
        else if row.message.destinationID == deviceID { StatusPill(text: row.message.messageType == .receipt ? "Receipt saved" : "Received", symbol: "tray.and.arrow.down.fill") }
        else if row.message.expiresAt <= Date() { StatusPill(text: "Expired", symbol: "clock.badge.xmark", color: .secondary) }
        else if row.destinationAccepted { StatusPill(text: "Destination saved", symbol: "checkmark.circle", color: .orange) }
        else if !row.acceptedBy.isEmpty { StatusPill(text: "Relay accepted", symbol: "arrow.triangle.branch", color: .orange) }
        else { StatusPill(text: "Queued on device", symbol: "externaldrive", color: .secondary) }
    }
}

struct NearbyView: View {
    @ObservedObject var model: RelayModel
    let compose: (String) -> Void
    private var remembered: [Peer] { model.known.filter { p in !model.connected.contains { $0.deviceID == p.deviceID } } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ConnectionCard(model: model)
                HStack { Text("Connected devices").font(.title2.bold()); Spacer(); Text("\(model.connected.count)").foregroundStyle(RelayTheme.secondary) }
                if model.connected.isEmpty {
                    RelayCard {
                        Label("Bring another device nearby", systemImage: "iphone.radiowaves.left.and.right").font(.headline)
                        Text("Open RELAY on both devices and start nearby connections. Keep Wi-Fi and Bluetooth on, and allow Local Network access.")
                            .font(.subheadline).foregroundStyle(RelayTheme.secondary)
                        if model.forceRoute { Label("Forced relay route is on. Sender A and Receiver C cannot connect directly.", systemImage: "arrow.triangle.branch").font(.caption).foregroundStyle(.orange) }
                    }
                }
                ForEach(model.connected, id: \.deviceID) { peer in peerCard(peer, online: true) }
                if !remembered.isEmpty {
                    Text("Previously met").font(.title2.bold())
                    Text("Queue a message now. It can travel when you meet again, or through a relay.").font(.subheadline).foregroundStyle(RelayTheme.secondary)
                    ForEach(remembered, id: \.deviceID) { peer in peerCard(peer, online: false) }
                }
                RelayCard {
                    Label("For a real offline test", systemImage: "wifi.slash").font(.headline)
                    Text("Turn off cellular and disconnect from Wi-Fi networks and hotspots. Leave the Wi-Fi and Bluetooth radios on. Unplug USB and keep both apps open.")
                        .font(.subheadline).foregroundStyle(RelayTheme.secondary)
                    Text("Peer-to-peer path: not yet verified.").font(.caption).foregroundStyle(.orange)
                }
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(RelayTheme.canvas).navigationTitle("Nearby")
    }
    private func peerCard(_ peer: Peer, online: Bool) -> some View {
        RelayCard {
            HStack {
                PeerAvatar(title: model.peerTitle(peer.deviceID))
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.addressLabel(peer.deviceID)).font(.headline)
                    Text(online ? "Connected now" : "Currently disconnected").font(.caption).foregroundStyle(RelayTheme.secondary)
                }
                Spacer()
                if online { Image(systemName: "circle.fill").font(.caption2).foregroundStyle(RelayTheme.accent) }
            }
            Button { compose(peer.deviceID) } label: { Label(online ? "Message this device" : "Queue a message", systemImage: "paperplane") }
                .buttonStyle(.bordered).controlSize(.large)
        }
    }
}

private struct MessageDetailView: View {
    @ObservedObject var model: RelayModel
    let messageID: String
    let reply: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    private var row: StoredMessage? { model.messages.first { $0.id == messageID } }
    var body: some View {
        NavigationStack {
            ScrollView {
                if let row {
                    VStack(alignment: .leading, spacing: 20) {
                        RelayCard {
                            DeliveryBadge(row: row, deviceID: model.deviceID)
                            Text(row.message.payload.text).font(.title3).textSelection(.enabled)
                            Text(row.message.createdAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(RelayTheme.secondary)
                            if row.message.destinationID == model.deviceID && row.message.originID != model.deviceID && row.message.messageType == .request {
                                Button { reply(row.message.originID) } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }.buttonStyle(PrimaryButton())
                            }
                        }
                        RelayCard {
                            Text("Delivery progress").font(.headline)
                            progress("Saved on this device", detail: "The message is in durable local storage.", done: true)
                            if row.message.destinationID == model.deviceID {
                                progress("Received at its destination", detail: row.message.messageType == .receipt ? "Return receipt persisted." : "A return receipt is saved automatically.", done: true)
                            } else {
                                progress("Accepted by a peer", detail: "A storage acknowledgement confirms that another device saved it.", done: !row.acceptedBy.isEmpty || row.destinationAccepted)
                                if row.message.messageType == .request {
                                    progress("Final delivery receipt", detail: "A separate receipt must travel back from the destination.", done: row.finalReceiptID != nil)
                                }
                            }
                            Text(row.status(deviceID: model.deviceID)).font(.caption).foregroundStyle(RelayTheme.secondary)
                        }
                        RelayCard {
                            Text("Message details").font(.headline)
                            detail("From · \(model.peerTitle(row.message.originID))", row.message.originID)
                            detail("To · \(model.peerTitle(row.message.destinationID))", row.message.destinationID)
                            detail("Message ID", row.id)
                            if let original = row.message.payload.originalMessageID { detail("Receipt for", original) }
                            if let receipt = row.finalReceiptID { detail("Final receipt", receipt) }
                            HStack { Label("\(row.message.hopCount) / \(row.message.maxHops) hops", systemImage: "arrow.triangle.branch"); Spacer(); Text("\(row.attempts) attempts") }.font(.caption)
                            Text("Expires \(row.message.expiresAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(RelayTheme.secondary)
                            Button { copyText(row.id); copied = true } label: { Label(copied ? "Message ID copied" : "Copy message ID", systemImage: copied ? "checkmark" : "doc.on.doc") }
                        }
                    }.padding(20).frame(maxWidth: 660).frame(maxWidth: .infinity)
                }
            }.background(RelayTheme.canvas).navigationTitle("Message")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 580, minHeight: 650)
        #endif
    }
    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(RelayTheme.secondary)
            Text(value).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
    }
    private func progress(_ title: String, detail: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dotted").foregroundStyle(done ? RelayTheme.accent : .secondary).font(.title3)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline.bold()); Text(detail).font(.caption).foregroundStyle(RelayTheme.secondary) }
        }
    }
}

private struct DeviceNameView: View {
    @ObservedObject var model: RelayModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var saving = false
    @FocusState private var focused: Bool
    private var valid: Bool { (try? Peer.normalizedName(name)) != nil }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("What should nearby devices call you?").font(.title3.bold())
                TextField("Your name or device name", text: $name).textFieldStyle(.roundedBorder)
                    .focused($focused).submitLabel(.done).onSubmit { if valid { save() } }
                    .accessibilityIdentifier("deviceNameField")
                Text("Use up to 40 characters. Your name is shared when peers connect. Renaming keeps your messages and device ID.")
                    .font(.subheadline).foregroundStyle(RelayTheme.secondary)
                Text("Names can be duplicated. The small ID below each name identifies the exact device.")
                    .font(.caption).foregroundStyle(RelayTheme.secondary)
                Button(saving ? "Saving…" : "Save name", action: save).buttonStyle(PrimaryButton())
                    .disabled(!valid || saving).accessibilityIdentifier("saveDeviceName")
                Spacer()
            }.padding(24).navigationTitle("Your name")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.onAppear { name = model.displayName }
            .alert("Name wasn’t saved", isPresented: Binding(get: { !model.error.isEmpty }, set: { if !$0 { model.error = ""; saving = false } })) {
                Button("OK") { model.error = ""; saving = false }
            } message: { Text(model.error) }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 340)
        #endif
    }
    private func save() {
        guard valid, !saving else { return }
        saving = true
        model.rename(name) { focused = false; dismiss() }
    }
}

struct ToolsView: View {
    @ObservedObject var model: RelayModel
    @State private var copiedID = false
    @State private var showDiagnostics = false
    @State private var showQueue = false
    @State private var editingName = false
    private var version: String { "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "5"))" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                RelayCard {
                    HStack {
                        Image(systemName: "person.crop.square.filled.and.at.rectangle").font(.title).foregroundStyle(RelayTheme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.displayName).font(.title3.bold())
                            Text("Your name on nearby devices").font(.caption).foregroundStyle(RelayTheme.secondary)
                        }
                        Spacer()
                        Button("Edit name") { editingName = true }.buttonStyle(.bordered).disabled(!model.ready)
                    }
                    Text(model.deviceID).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    HStack {
                        Button { copyText(model.deviceID); copiedID = true } label: { Label(copiedID ? "Copied" : "Copy ID", systemImage: copiedID ? "checkmark" : "doc.on.doc") }
                        Spacer()
                        ShareLink(item: model.deviceID) { Label("Share ID", systemImage: "square.and.arrow.up") }
                    }.buttonStyle(.bordered).disabled(!model.ready)
                }
                RelayCard {
                    Label("How messaging works", systemImage: "bubble.left.and.bubble.right").font(.headline)
                    Text("Choose a name in Nearby or New chat. Every device can send and receive. Another device can carry a copy until it meets the recipient.").font(.subheadline).foregroundStyle(RelayTheme.secondary)
                    Text("Your sent copy and the recipient’s received copy appear in Chats. Copies for other people only appear in the forwarding queue.").font(.caption).foregroundStyle(RelayTheme.secondary)
                    Text("This prototype is not encrypted. A name is a label, not verified identity.").font(.caption).foregroundStyle(RelayTheme.secondary)
                    if model.forceRoute {
                        Label("Advanced relay test is active", systemImage: "arrow.triangle.branch").font(.subheadline).foregroundStyle(.orange)
                        Button("Use normal messaging") { model.forceRoute = false; model.configure() }.buttonStyle(.bordered)
                    }
                    DisclosureGroup("Advanced relay test") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Test role", selection: $model.role) {
                                ForEach(TestRole.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.menu).onChange(of: model.role) { _, _ in model.configure() }
                            Toggle("Force A → B → C", isOn: Binding(get: { model.forceRoute }, set: { model.forceRoute = $0; model.configure() }))
                            Text("Roles only control this lab test: A and C cannot connect directly when forced routing is on. They do not determine who can send or receive. Changing setup reconnects active peers.")
                                .font(.caption).foregroundStyle(RelayTheme.secondary)
                        }.padding(.top, 10)
                    }
                }
                RelayCard {
                    Text("Quick offline test").font(.title3.bold())
                    instruction("1", "Prepare", "Cellular off. No Wi-Fi network or hotspot. Wi-Fi and Bluetooth radios on. USB unplugged.")
                    instruction("2", "Connect", "Open RELAY on both phones. Tap Start nearby connections and allow Local Network access.")
                    instruction("3", "Send", "In Nearby, choose the other phone. Send a synthetic message and check its delivery progress.")
                    Text("For two phones, use normal messaging on both.").font(.caption.bold()).foregroundStyle(RelayTheme.accent)
                }
                RelayCard {
                    Label("Forwarding & receipts", systemImage: "tray.2").font(.headline)
                    Text("Engineering view of all saved envelopes, including copies addressed to someone else. A forwarding copy is not a message to you.").font(.subheadline).foregroundStyle(RelayTheme.secondary)
                    Button("Open durable queue (\(model.messages.count))") { showQueue = true }.buttonStyle(.bordered)
                }
                RelayCard {
                    Label("Engineering tools", systemImage: "waveform.path.ecg").font(.title3.bold())
                    Text("Inspect paths, logs, receipt messages, and repeat or interrupt a transfer.").font(.subheadline).foregroundStyle(RelayTheme.secondary)
                    Button { showDiagnostics = true } label: { Label("Open diagnostics", systemImage: "terminal") }.buttonStyle(.bordered)
                }
                Text("RELAY \(version) · Engineering preview\nSynthetic data only. Messages are not encrypted or authenticated. Keep RELAY foreground during encounters. Infrastructure-independent delivery remains unverified.")
                    .font(.caption).foregroundStyle(RelayTheme.secondary)
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(RelayTheme.canvas).navigationTitle("Tools")
            .sheet(isPresented: $showDiagnostics) { DiagnosticsView(model: model) }
            .sheet(isPresented: $showQueue) { DurableQueueView(model: model) }
            .sheet(isPresented: $editingName) { DeviceNameView(model: model) }
    }
    private func instruction(_ number: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.caption.bold()).frame(width: 28, height: 28).background(RelayTheme.accent.opacity(0.10), in: Circle()).foregroundStyle(RelayTheme.accent)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline.bold()); Text(text).font(.caption).foregroundStyle(RelayTheme.secondary) }
        }
    }
}

private struct DiagnosticsView: View {
    @ObservedObject var model: RelayModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Transport") {
                    Text(model.networkState)
                    Text("Discovered: \(model.discovered.count) · Connected: \(model.connected.count)")
                    Text("Peer-to-peer enabled · Path independence unverified").foregroundStyle(.orange)
                    ForEach(model.discovered) { Text($0.details).font(.caption).textSelection(.enabled) }
                    ForEach(model.paths, id: \.self) { Text($0).font(.system(.caption2, design: .monospaced)).textSelection(.enabled) }
                }
                Section("Failure testing") {
                    Button(model.armed ? "Interruption armed" : "Interrupt next transfer midway") { model.armInterrupt() }.disabled(model.armed)
                    ForEach(model.messages.filter { $0.message.destinationID != model.deviceID && $0.message.expiresAt > Date() }.reversed()) { row in
                        Button("Retransmit \(row.id.prefix(8)) · \(row.message.messageType == .receipt ? "receipt" : "message")") { model.retry(row.id) }
                    }
                }
                Section("Persistent log") {
                    Button("Copy complete diagnostic log") { model.export() }
                    ShareLink(item: "RELAY diagnostics — path independence unverified\n" + model.logs.joined(separator: "\n")) { Text("Share recent diagnostic log") }
                    Text(model.storagePath).font(.caption2).textSelection(.enabled)
                    ForEach(Array(model.logs.suffix(100).reversed().enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }.formStyle(.grouped).navigationTitle("Diagnostics")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 650)
        #endif
    }
}

private struct DurableQueueView: View {
    @ObservedObject var model: RelayModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Text("Forwarding copies are addressed to someone else. They are excluded from your chats; their text is hidden in this view. Storage and transport are still unencrypted.")
                    .font(.caption).foregroundStyle(RelayTheme.secondary)
                ForEach(model.messages.reversed()) { row in
                    let carried = row.message.originID != model.deviceID && row.message.destinationID != model.deviceID
                    DisclosureGroup {
                        if !carried { Text(row.message.payload.text).textSelection(.enabled) }
                        Text(row.status(deviceID: model.deviceID)).font(.caption)
                        Text("From \(row.message.originID)\nTo \(row.message.destinationID)\nID \(row.id)")
                            .font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                        if let original = row.message.payload.originalMessageID { Text("Receipt for \(original)").font(.caption2).textSelection(.enabled) }
                        Text("Hops \(row.message.hopCount)/\(row.message.maxHops) · Attempts \(row.attempts)").font(.caption)
                        Text("Expires \(row.message.expiresAt.formatted())").font(.caption2)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(carried ? "Forwarding copy · not addressed to you" : row.message.messageType == .receipt ? "Delivery receipt" : row.message.originID == model.deviceID ? "Sent by you" : "Received by you").font(.subheadline.bold())
                            Text("\(model.peerTitle(row.message.originID)) → \(model.peerTitle(row.message.destinationID))").font(.caption).foregroundStyle(RelayTheme.secondary).lineLimit(2)
                            DeliveryBadge(row: row, deviceID: model.deviceID)
                        }.padding(.vertical, 4)
                    }
                }
            }.navigationTitle("Durable queue")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 600)
        #endif
    }
}
