import SwiftUI
import RelayCore

struct AccountSignInView: View {
    @EnvironmentObject private var cloud: CloudModel
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @FocusState private var editing: Bool
    var body: some View {
        RelayCard {
            Text("Sign in").font(.title2.weight(.medium))
            Text("Sign in once to send requests or coordinate your shelter. Your account opens the right workspace.").foregroundStyle(RelayTheme.secondary)
            if cloud.signInNeedsCode {
                TextField("Six-digit authenticator code", text: $code).textFieldStyle(WorkflowInput()).focused($editing)
                    .accessibilityIdentifier("loginCode")
                    #if os(iOS)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    #endif
            } else {
                TextField("Email", text: $email).textFieldStyle(WorkflowInput()).focused($editing).autocorrectionDisabled()
                    .accessibilityIdentifier("loginEmail")
                    #if os(iOS)
                    .textInputAutocapitalization(.never).keyboardType(.emailAddress).textContentType(.username)
                    #endif
                SecureField("Password", text: $password).textFieldStyle(WorkflowInput()).focused($editing).accessibilityIdentifier("loginPassword")
            }
            Button(cloud.busy ? "Signing in…" : cloud.signInNeedsCode ? "Verify and continue" : "Sign in") {
                editing = false
                Task { await cloud.login(username: email, password: password, code: code); password = ""; code = "" }
            }.buttonStyle(PrimaryButton()).disabled(cloud.busy || (cloud.signInNeedsCode ? code.count != 6 : email.isEmpty || password.isEmpty))
                .accessibilityIdentifier("accountSignIn")
            if cloud.signInNeedsCode { Button("Use another account") { cloud.cancelLogin(); code = "" } }
            if cloud.busy { ProgressView() }
            if !cloud.problem.isEmpty { Text(cloud.problem).font(.callout).foregroundStyle(.orange) }
            Text("Use your RELAY test account, not your Apple or AWS console login. The demo organizer provides accounts.").font(.caption).foregroundStyle(RelayTheme.secondary)
            if editing { Button("Done") { editing = false } }
        }
    }
}
struct WorkflowStatus: View {
    @EnvironmentObject private var cloud: CloudModel
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(.secondary).frame(width: 4, height: 4).accessibilityHidden(true)
            Text(cloud.cloudPaused ? "Demo: cloud delivery paused. Nearby remains active." : cloud.isDispatcher ? "Keep RELAY open to receive nearby requests." : cloud.selectedReceiver == nil ? "Saved on this device until cloud delivery is available." : "Saved first. Uses cloud or nearby phones to reach your shelter.")
                .font(.caption)
        }.foregroundStyle(RelayTheme.secondary).padding(.horizontal, 4)
    }
}
struct LocationFacts: View {
    let location: RequestLocation
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(location.precision == "approximate" ? "Approximate location" : "Location attached").font(.subheadline.weight(.medium))
            Text(String(format: "%.5f, %.5f · accuracy ±%.0f m", location.latitude, location.longitude, location.horizontal_accuracy)).font(.caption.monospaced())
            Text("Captured \(location.captured_at.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(RelayTheme.secondary)
            if Date().timeIntervalSince(location.captured_at) > 300 { Text("This is an earlier location snapshot. Refresh if you have moved.").font(.caption).foregroundStyle(.orange) }
            if let url = URL(string: "https://maps.apple.com/?ll=\(location.latitude),\(location.longitude)&q=Request%20location") { Link("Open location in Maps", destination: url).font(.subheadline) }
        }
    }
}
struct PublicHelpView: View {
    @ObservedObject var model: RelayModel
    @EnvironmentObject private var cloud: CloudModel
    @StateObject private var locator = RequestLocationModel()
    @State private var reviewing = false
    @State private var showingGuide = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var editing: Bool
    let sent: (String) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Text("Ask for help").font(.largeTitle.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { editing = false; showingGuide = true } label: { Image(systemName: "questionmark.circle").font(.system(size: 21)).frame(width: 44, height: 44) }
                        .accessibilityLabel("How RELAY works").accessibilityIdentifier("homeResidentGuide").help("How RELAY works")
                }.padding(.top, 8)
                Text("Tell your shelter what you need.").foregroundStyle(RelayTheme.secondary).padding(.bottom, 8)
                if cloud.profile == nil { AccountSignInView() }
                else {
                    HStack {
                        Text("Send to").font(.headline)
                        Spacer()
                        Picker("Shelter", selection: $cloud.draft.shelterID) {
                            Text("Choose shelter").tag("")
                            ForEach(cloud.directory) { Text($0.display_name).tag($0.shelter_id) }
                        }.labelsHidden().accessibilityLabel("Destination shelter").accessibilityIdentifier("destinationShelter")
                    }.padding(.vertical, 4)
                    if !cloud.draft.shelterID.isEmpty {
                        NavigationLink("Shelter location & arrival instructions") { CloudShelterDetail(shelterID: cloud.draft.shelterID) }.font(.subheadline)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("What do you need?", text: $cloud.draft.text, axis: .vertical)
                            .font(.body).lineLimit(3...6).textFieldStyle(WorkflowInput())
                            .focused($editing).accessibilityLabel("Describe your request").accessibilityIdentifier("requestText")
                        HStack {
                            NavigationLink { VoiceInputView() } label: { Label("Speak", systemImage: "mic.fill") }
                                .buttonStyle(WorkflowSecondaryButton()).disabled(cloud.audioBusy)
                            Spacer()
                            Button { editing = false; Task { await cloud.previewRequest() } } label: {
                                HStack(spacing: 7) { if cloud.interpreting { ProgressView().controlSize(.small) }; Text(cloud.interpreting ? "Reading request…" : "Extract details") }
                            }.font(.subheadline.weight(.medium)).buttonStyle(.plain).frame(minHeight: 44)
                                .disabled(cloud.interpreting || cloud.draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cloud.draft.shelterID.isEmpty)
                        }
                        if cloud.interpreting || cloud.draft.interpretationReady == false {
                            Button("Enter details myself") { cloud.skipPreview() }.font(.subheadline)
                        }
                        if let result = cloud.interpretation, cloud.draft.interpretationText == cloud.draft.text.trimmingCharacters(in: .whitespacesAndNewlines) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("AI suggestion — check the details below.").font(.caption.weight(.medium))
                                Text(result.result?.proposal?.summary ?? "Review your request details.").font(.subheadline).foregroundStyle(RelayTheme.secondary)
                                ForEach(result.result?.review_reasons ?? [], id: \.self) { WorkflowNotice(text: ExtractionReview.message($0)) }
                            }.padding(.vertical, 8)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 14) {
                        Text("What do you need?").font(.title2.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 280 : 150), spacing: 10)], spacing: 10) {
                            ForEach(["water_packs", "food_packs", "blankets", "medicines", "other"], id: \.self) { item in
                                Button { cloud.draft.item = item; cloud.draft.requestedUnit = nil } label: {
                                    HStack {
                                        Text(InventoryItem.emoji(item)).font(.title2).accessibilityHidden(true)
                                        Text(InventoryItem.title(item)).font(.body.bold())
                                        Spacer(minLength: 4)
                                        if cloud.draft.item == item { Text("✓").font(.subheadline.weight(.medium)) }
                                    }.padding(.horizontal, 13).padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 72)
                                        .foregroundStyle(cloud.draft.item == item ? RelayTheme.onAction : .primary)
                                        .background(cloud.draft.item == item ? RelayTheme.action : .clear, in: RoundedRectangle(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.black, lineWidth: 2))
                                }.buttonStyle(.plain).accessibilityAddTraits(cloud.draft.item == item ? .isSelected : [])
                            }
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 14) { quantity; people }
                            VStack(alignment: .leading, spacing: 14) { quantity; people }
                        }
                    }
                    HStack {
                        Text("Requested unit").font(.subheadline)
                        Spacer()
                        Picker("Requested unit", selection: Binding(get: { cloud.draft.unit }, set: { cloud.draft.requestedUnit = $0 })) {
                            ForEach(RequestDraft.units, id: \.self) { Text($0.capitalized).tag($0) }
                        }.labelsHidden()
                    }
                    if cloud.draft.item == "medicines" {
                        TextField("Medicine name and details, if known", text: Binding(get: { cloud.draft.medicineDetails ?? "" }, set: { cloud.draft.medicineDetails = $0 }), axis: .vertical)
                            .lineLimit(2...4).textFieldStyle(WorkflowInput()).focused($editing)
                        Text("Share what you need. Shelter staff confirm availability; this app does not recommend medicines or doses.").font(.caption).foregroundStyle(RelayTheme.secondary)
                    }
                    Divider()
                    UrgencySelection(value: $cloud.draft.urgency)
                    Divider().padding(.top, 4)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Location").font(.title2.bold())
                            Spacer()
                            Button(locator.busy ? "Locating…" : cloud.draft.location == nil ? "Use my location" : "Update") {
                                editing = false; locator.capture { cloud.draft.location = $0; cloud.persistDraft() }
                            }.font(.subheadline).frame(minHeight: 44).disabled(locator.busy)
                        }
                        Text("Add a location snapshot or type where you are. GPS permission is optional.").font(.subheadline).foregroundStyle(RelayTheme.secondary)
                        TextField("Address, landmark, entrance or room", text: $cloud.draft.landmark, axis: .vertical)
                            .lineLimit(1...3).textFieldStyle(WorkflowInput()).focused($editing)
                        if let location = cloud.draft.location {
                            LocationFacts(location: location)
                            Button("Remove location") { cloud.draft.location = nil }.font(.caption)
                        }
                        if !locator.problem.isEmpty { WorkflowNotice(text: locator.problem) }
                    }
                    if !cloud.problem.isEmpty { WorkflowNotice(text: cloud.problem) }
                }
            }.padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: 660).frame(maxWidth: .infinity)
        }.background(RelayTheme.canvas).navigationTitle("")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if cloud.profile != nil {
                    VStack(spacing: 0) {
                        Divider()
                        Button { editing = false; reviewing = true } label: {
                            HStack { Text("Review request"); Spacer(); Text("→") }.padding(.horizontal, 18)
                        }.buttonStyle(PrimaryButton()).disabled(cloud.submitting || cloud.interpreting || locator.busy || cloud.draft.shelterID.isEmpty || cloud.draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .padding(.horizontal, 24).padding(.vertical, 12)
                    }.frame(maxWidth: 660).frame(maxWidth: .infinity).background(RelayTheme.canvas)
                }
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { if editing { Button("Done") { editing = false } } } }
            .onChange(of: cloud.draft) { _, _ in cloud.persistDraft() }
            .sheet(isPresented: $reviewing) { WorkflowReview { id in reviewing = false; sent(id) } }
            .sheet(isPresented: $showingGuide) { ResidentGuideView() }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            #endif
    }
    private var quantity: some View { WorkflowField(title: "Quantity (\(cloud.draft.unit))", placeholder: "Unknown", text: $cloud.draft.quantity, focus: $editing).frame(minWidth: 115) }
    private var people: some View { WorkflowField(title: "People", placeholder: "Unknown", text: $cloud.draft.people, focus: $editing).frame(minWidth: 115) }
}
struct WorkflowReview: View {
    @EnvironmentObject private var cloud: CloudModel
    @Environment(\.dismiss) private var dismiss
    let sent: (String) -> Void
    @State private var sharePersonal = false
    @State private var shareHealth = false
    @State private var shareSupport = false
    @State private var editingProfile = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Review request").font(.largeTitle.bold())
                    Text(cloud.draft.text)
                    WorkflowFact("Shelter", value: cloud.directory.first(where: { $0.shelter_id == cloud.draft.shelterID })?.display_name ?? "Unknown")
                    WorkflowFact("Item", value: InventoryItem.title(cloud.draft.item))
                    WorkflowFact("Amount", value: cloud.draft.quantity.isEmpty ? "Unknown" : "\(cloud.draft.quantity) \(cloud.draft.unit)")
                    WorkflowFact("People", value: cloud.draft.people.isEmpty ? "Unknown" : cloud.draft.people)
                    WorkflowFact("Reported urgency", value: cloud.draft.urgency.flatMap(RequestUrgency.init(rawValue:))?.title ?? "Not specified")
                    if cloud.draft.item == "medicines", let details = cloud.draft.medicineDetails, !details.isEmpty { Text("Medicine: " + details) }
                    if !cloud.draft.landmark.isEmpty { Text("Landmark: " + cloud.draft.landmark) }
                    if let location = cloud.draft.location { LocationFacts(location: location) }
                    else { Text("No device location attached").foregroundStyle(RelayTheme.secondary) }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Share personal details with this shelter", isOn: $sharePersonal).accessibilityIdentifier("sharePersonalDetails")
                            .disabled(!cloud.residentDetailsAvailable)
                        Text("Optional. Name and preferred language are included when enabled. Your photo stays on this device.").font(.caption).foregroundStyle(RelayTheme.secondary)
                        if sharePersonal {
                            Toggle("Include health details", isOn: $shareHealth).accessibilityIdentifier("shareHealthDetails")
                            Text("Age, height, weight, blood group, allergies, conditions and medications you saved.").font(.caption).foregroundStyle(RelayTheme.secondary)
                            Toggle("Include accessibility & support needs", isOn: $shareSupport)
                            if let details = try? selectedPersonalDetails() { SharedResidentSummary(details: details) }
                            Text("The details shown above will be saved with this request and visible to authorized shelter staff. They are excluded from AI extraction. Editing your profile later does not change a sent request.").font(.caption).foregroundStyle(RelayTheme.secondary)
                        }
                        Button("Edit profile in Settings") { editingProfile = true }.font(.subheadline)
                    }
                    if let error = validation { Text(error).foregroundStyle(.orange) }
                    Text(cloud.selectedReceiver == nil ? "Your request stays saved until the cloud is reachable. This shelter has no nearby receiver configured yet." : "Your request stays saved. Nearby phones can carry an encrypted copy to this shelter when internet is unavailable.")
                    Text("Shelter receipt and staff approval are separate. Staff review supplies before approving.").font(.subheadline).foregroundStyle(RelayTheme.secondary)
                    Button(cloud.submitting ? "Saving…" : "Send request") {
                        Task {
                            do { if let id = await cloud.submitRequest(sharedDetails: try selectedPersonalDetails()) { sent(id) } }
                            catch { cloud.problem = error.localizedDescription }
                        }
                    }.buttonStyle(PrimaryButton()).disabled(cloud.submitting || validation != nil).accessibilityIdentifier("sendReviewedRequest")
                    if !cloud.problem.isEmpty { Text(cloud.problem).foregroundStyle(.orange) }
                }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.navigationTitle("")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Edit") { dismiss() }.disabled(cloud.submitting) } }
        }.interactiveDismissDisabled(cloud.submitting)
            .sheet(isPresented: $editingProfile) { ResidentDetailsEditor() }
            #if os(macOS)
            .frame(minWidth: 550, minHeight: 600)
            #endif
    }
    private func selectedPersonalDetails() throws -> SharedResidentDetails? {
        guard sharePersonal else { return nil }
        return try SharedResidentDetails(profile: cloud.residentDetails, includeHealth: shareHealth, includeSupport: shareSupport)
    }
    private var validation: String? { do { _ = try cloud.draft.fields(); try cloud.draft.validateLocationForNewRequest(); _ = try selectedPersonalDetails(); return nil } catch { return error.localizedDescription } }
}
struct WorkflowRequestsView: View {
    @ObservedObject var model: RelayModel
    @EnvironmentObject private var cloud: CloudModel
    let staff: Bool
    @State private var filter = "Open"
    private var rows: [CloudQueueRecord] {
        cloud.records.filter { !staff || $0.submission.destination_shelter_id == cloud.staffShelterID }.sorted { $0.submission.created_at > $1.submission.created_at }
    }
    private var visibleRows: [CloudQueueRecord] { rows.filter { filter == "All" || (filter == "Closed") == ["completed", "cancelled", "rejected"].contains($0.history?.status ?? "new") } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WorkflowHeader(eyebrow: staff ? "Coordinator" : "Your requests", title: staff ? "Inbox" : "Requests", subtitle: staff ? "Requests awaiting your attention." : "Updates from your shelter.")
                if cloud.profile == nil { AccountSignInView() }
                else {
                    HStack {
                        if staff {
                            Picker("Shelter", selection: $cloud.staffShelterID) { ForEach(cloud.directory) { Text($0.display_name).tag($0.shelter_id) } }
                                .onChange(of: cloud.staffShelterID) { _, value in Task { await cloud.loadInbox(shelterID: value) } }
                        } else { Text("\(rows.count) saved request\(rows.count == 1 ? "" : "s")").font(.subheadline).foregroundStyle(RelayTheme.secondary) }
                        Spacer()
                        Button { Task { await cloud.loadInbox(shelterID: staff ? cloud.staffShelterID : nil) } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                            .buttonStyle(.plain).disabled(cloud.busy).accessibilityLabel("Refresh requests")
                    }
                    WorkflowFilter(selection: $filter, options: ["Open", "All", "Closed"])
                    if visibleRows.isEmpty { ContentUnavailableView(filter == "Open" ? "No open requests" : "No requests here", systemImage: "tray", description: Text(staff ? "New requests appear here when they reach RELAY." : "Create a request in Help. Your shelter's replies will appear here.")) }
                    ForEach(visibleRows) { record in
                        NavigationLink { WorkflowRequestDetail(id: record.id) } label: {
                            WorkflowRequestCard(record: record, shelter: cloud.directory.first(where: { $0.shelter_id == record.submission.destination_shelter_id })?.display_name ?? "Shelter")
                        }.buttonStyle(.plain)
                    }
                    WorkflowStatus()
                    if !cloud.problem.isEmpty { WorkflowNotice(text: cloud.problem) }
                }
            }.padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: 780).frame(maxWidth: .infinity)
        }.background(RelayTheme.canvas).navigationTitle("")
            .toolbar { ToolbarItem(placement: .primaryAction) { NavigationLink("Settings") { WorkflowSettings(model: model) }.font(.caption) } }
            .task { if cloud.canUseCloud { await cloud.loadInbox(shelterID: staff ? cloud.staffShelterID : nil) } }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }
    static func progress(_ record: CloudQueueRecord) -> String {
        switch record.history?.status {
        case "accepted": return record.reservation?.status == "reserved" ? "Approved · supplies reserved" : "Accepted by staff"
        case "in_progress": return "In progress"
        case "completed": return record.reservation?.status == "fulfilled" ? "Supplies marked handed over" : "Reported completed"
        case "cancelled": return "Cancelled"
        case "rejected": return "Unable to fulfill"
        default:
            if record.result != nil { return "Waiting for coordinator" }
            if record.nearbyState == "received" { return "Received nearby · identity check pending" }
            if record.nearbyState == "shelter_saved" { return "Shelter received · awaiting staff" }
            if record.nearbyState == "relay_saved" { return "Nearby relay saved · awaiting shelter" }
            return "Queued"
        }
    }
}
struct WorkflowRequestDetail: View {
    @EnvironmentObject private var cloud: CloudModel
    let id: String
    @State private var reply = ""
    @State private var item = "water_packs"
    @State private var amount = ""
    @State private var confirmingHandover = false
    @FocusState private var editing: Bool
    private var record: CloudQueueRecord? { cloud.records.first { $0.id == id } }
    var body: some View {
        ScrollView {
            if let record {
                VStack(alignment: .leading, spacing: 18) {
                    RelayCard {
                        WorkflowBadge(text: WorkflowRequestsView.progress(record), symbol: ["accepted", "in_progress", "completed"].contains(record.history?.status ?? "") ? "checkmark.circle" : "clock")
                        Text(InventoryItem.title(record.submission.structured_fields?.item_id ?? record.result?.result?.proposal?.item_id ?? "other")).font(.title2.bold())
                        Text(record.submission.original_text)
                        if let details = record.submission.requester_details { Divider(); SharedResidentSummary(details: details) }
                        if let fields = record.submission.structured_fields {
                            WorkflowFact("Item", value: InventoryItem.title(fields.item_id ?? "other"))
                            WorkflowFact("Amount", value: fields.quantity.map { "\($0) \(fields.unit ?? "")" } ?? "Unknown")
                            WorkflowFact("People", value: fields.people.map(String.init) ?? "Unknown")
                            WorkflowFact("Reported urgency", value: fields.urgency.flatMap(RequestUrgency.init(rawValue:))?.title ?? "Not specified")
                            if let medicine = fields.medicine_details, !medicine.isEmpty { Text("Medicine: " + medicine) }
                            if !fields.landmark.isEmpty { Text("Landmark: " + fields.landmark) }
                        }
                        if let location = record.submission.location { LocationFacts(location: location) }
                        DisclosureGroup("Request reference") { Text(record.id).font(.caption.monospaced()).foregroundStyle(RelayTheme.secondary).textSelection(.enabled) }.font(.caption)
                        Button("Refresh / retry") { Task { await cloud.retry(id); if cloud.isDispatcher { await cloud.refreshInventory() } } }.buttonStyle(WorkflowSecondaryButton()).disabled(cloud.busy)
                    }
                    if let nearby = record.nearbyState {
                        RelayCard {
                            Text("Delivery").font(.headline)
                            Text(nearby == "received" ? "Saved on this shelter device" : nearby == "shelter_saved" ? "Shelter receipt verified" : nearby == "relay_saved" ? "A nearby phone saved a copy" : "Nearby copy queued")
                            Text(record.result == nil ? "Cloud acceptance pending" : "Cloud accepted this request").font(.subheadline)
                            if nearby == "received", record.result == nil {
                                Text("Sender identity is checked when the cloud reconnects. Inventory approval becomes available after that check.").font(.subheadline).foregroundStyle(RelayTheme.secondary)
                            }
                        }
                    }
                    if let proposal = record.result?.result?.proposal {
                        RelayCard {
                            WorkflowSection(title: "AI interpretation", symbol: "sparkles", subtitle: "A suggestion for staff to review")
                            Text(proposal.summary)
                            Text("\(InventoryItem.title(proposal.item_id ?? "other")) · \(proposal.quantity.map(String.init) ?? "Unknown") \(proposal.unit ?? "")")
                            ForEach(record.result?.result?.review_reasons ?? [], id: \.self) { Text(ExtractionReview.message($0)).font(.caption).foregroundStyle(.orange) }
                            Text("Staff approval controls inventory. AI cannot allocate supplies.").font(.caption).foregroundStyle(RelayTheme.secondary)
                        }
                    }
                    if cloud.isDispatcher, record.result != nil {
                        if record.submission.structured_fields?.item_id == "medicines" || record.result?.result?.proposal?.item_id == "medicines" {
                            RelayCard {
                                Text("Medicine request · staff review").font(.headline)
                                Text("Check the named medicine and confirm availability in a reply. Medicines are not interchangeable stock; automatic reservation is unavailable.").font(.subheadline)
                            }
                        } else { approval(record) }
                    }
                    if let reservation = record.reservation {
                        RelayCard {
                            Text("Supplies: \(reservation.status)").font(.headline)
                            Text("\(reservation.quantity) \(reservation.unit) · \(InventoryItem.title(reservation.item_id))")
                        }
                    }
                    RelayCard {
                        WorkflowSection(title: "Updates & replies", symbol: "bubble.left.and.bubble.right.fill")
                        ForEach(record.history?.events ?? []) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.author_role == "dispatcher" ? "Shelter coordinator" : "Requester").font(.caption.bold())
                                if !event.text.isEmpty { Text(event.text) }
                                if let status = event.status { Text(status.replacingOccurrences(of: "_", with: " ")).font(.caption).foregroundStyle(RelayTheme.secondary) }
                            }.padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).overlay(alignment: .bottom) { Divider() }
                        }
                        TextField("Write a reply…", text: $reply, axis: .vertical).lineLimit(2...5).textFieldStyle(WorkflowInput()).focused($editing)
                        Button("Send reply") { let text = reply; editing = false; Task { await cloud.sendEvent(id, text: text, status: nil); if cloud.problem.isEmpty { reply = "" } } }.buttonStyle(WorkflowSecondaryButton()).disabled(cloud.busy || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || record.result == nil || record.pendingEvent != nil)
                        if !cloud.isDispatcher, !["completed", "cancelled", "rejected"].contains(record.history?.status ?? "new") {
                            Button("Cancel request", role: .destructive) { Task { await cloud.sendEvent(id, text: "Requester cancelled this request.", status: "cancelled") } }.disabled(cloud.busy || record.result == nil)
                        }
                    }
                    if let problem = record.problem { Text(problem).foregroundStyle(.orange) }
                    if record.pendingInventory != nil {
                        Text("An inventory action is queued. Retry uses the same operation and cannot reserve stock twice.").font(.caption)
                        if record.state == "needs_attention" { Button("Clear declined action and refresh") { Task { await cloud.discardInventoryConflict(id) } } }
                    }
                    if !cloud.problem.isEmpty { Text(cloud.problem).foregroundStyle(.orange) }
                }.padding(20).frame(maxWidth: 730).frame(maxWidth: .infinity)
            } else { ContentUnavailableView("Request unavailable", systemImage: "tray") }
        }.background(RelayTheme.canvas).navigationTitle("Request")
            .toolbar { ToolbarItem(placement: .primaryAction) { if editing { Button("Done") { editing = false } } } }
            .onDisappear { cloud.focusedRequestID = nil }
            .task {
                cloud.focusedRequestID = id
                if let record {
                    item = record.submission.structured_fields?.item_id ?? record.result?.result?.proposal?.item_id ?? "water_packs"
                    let requestedUnit = record.submission.structured_fields?.unit ?? record.result?.result?.proposal?.unit
                    let stockUnit = item == "blankets" ? "piece" : "pack"
                    amount = requestedUnit == stockUnit ? (record.submission.structured_fields?.quantity ?? record.result?.result?.proposal?.quantity).map(String.init) ?? "" : ""
                    if cloud.isDispatcher { cloud.staffShelterID = record.submission.destination_shelter_id; await cloud.refreshInventory() }
                    await cloud.refreshFocusedRequest()
                }
            }
            .confirmationDialog("Confirm the supplies were handed over?", isPresented: $confirmingHandover, titleVisibility: .visible) {
                Button("Confirm handover") { Task { await cloud.inventoryAction(id, action: "fulfill") } }
                Button("Cancel", role: .cancel) {}
            }
    }
    @ViewBuilder private func approval(_ record: CloudQueueRecord) -> some View {
        if record.reservation?.status == "reserved" {
            RelayCard {
                WorkflowSection(title: "Supplies reserved", symbol: "shippingbox.fill", subtitle: "Record the next step when it happens.")
                Button("Mark supplies handed over") { confirmingHandover = true }.buttonStyle(PrimaryButton()).disabled(cloud.cloudPaused || cloud.busy || record.pendingInventory != nil)
                Button("Release reservation", role: .destructive) { Task { await cloud.inventoryAction(id, action: "release") } }.disabled(cloud.cloudPaused || cloud.busy || record.pendingInventory != nil)
            }
        } else if !["completed", "cancelled", "rejected"].contains(record.history?.status ?? "new") {
            RelayCard {
                WorkflowSection(title: "Approve supplies", symbol: "checkmark.seal.fill")
                Picker("Item", selection: $item) { ForEach(["water_packs", "food_packs", "blankets"], id: \.self) { Text(InventoryItem.title($0)).tag($0) } }
                TextField("Quantity to reserve", text: $amount).textFieldStyle(WorkflowInput()).focused($editing)
                if let stock = cloud.inventory?.items.first(where: { $0.id == item }) { Text("Available: \(stock.available) \(stock.unit) · already reserved: \(stock.reserved)").font(.subheadline) }
                Button("Approve and reserve") { editing = false; Task { await cloud.inventoryAction(id, action: "reserve", item: item, quantity: Int(amount)) } }
                    .buttonStyle(PrimaryButton()).disabled(cloud.cloudPaused || cloud.busy || cloud.inventoryBusy || record.pendingInventory != nil || (Int(amount) ?? 0) <= 0 || cloud.inventory == nil)
                Text("Approval reserves stock. Handover deducts it. Concurrent approvals cannot overbook available supplies.").font(.caption).foregroundStyle(RelayTheme.secondary)
            }
        }
    }
}
struct InventoryView: View {
    @ObservedObject var model: RelayModel
    @EnvironmentObject private var cloud: CloudModel
    @State private var item = "water_packs"
    @State private var amount = ""
    @State private var note = "Synthetic demo stock"
    @State private var editingStock = false
    @FocusState private var editing: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WorkflowHeader(eyebrow: "Coordinator", title: "Inventory", subtitle: "Available stock at your shelter.")
                HStack {
                    Picker("Shelter", selection: $cloud.staffShelterID) { ForEach(cloud.directory) { Text($0.display_name).tag($0.shelter_id) } }
                        .onChange(of: cloud.staffShelterID) { _, _ in Task { await cloud.refreshInventory() } }
                    Spacer()
                    Button { Task { await cloud.refreshInventory() } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).disabled(cloud.inventoryBusy).accessibilityLabel("Refresh stock")
                }
                if cloud.inventory == nil && !cloud.inventoryBusy { ContentUnavailableView("Stock not loaded", systemImage: "shippingbox", description: Text("Refresh when your connection is available.")) }
                ForEach((cloud.inventory?.items ?? []).sorted { $0.available == $1.available ? $0.id < $1.id : $0.available > $1.available }) { row in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(InventoryItem.emoji(row.item_id)).accessibilityHidden(true)
                            Text(row.title).font(.title3.weight(.medium))
                            Spacer()
                            Text(row.unit.uppercased()).font(.system(.caption2, design: .monospaced)).foregroundStyle(RelayTheme.secondary)
                        }
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(row.available)").font(.system(.largeTitle, design: .monospaced).weight(.regular)).monospacedDigit()
                                Text("Available").font(.caption).foregroundStyle(RelayTheme.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(row.reserved)").font(.system(.title3, design: .monospaced)).monospacedDigit()
                                Text("Reserved").font(.caption).foregroundStyle(RelayTheme.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(row.on_hand)").font(.system(.title3, design: .monospaced)).monospacedDigit()
                                Text("On hand").font(.caption).foregroundStyle(RelayTheme.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider()
                    }.padding(.vertical, 12)
                }
                Text("Approval reserves supplies. Handover deducts stock.").font(.caption).foregroundStyle(RelayTheme.secondary).padding(.horizontal, 4)
                RelayCard {
                    DisclosureGroup(isExpanded: $editingStock) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Item", selection: $item) { ForEach(["water_packs", "food_packs", "blankets"], id: \.self) { Text(InventoryItem.title($0)).tag($0) } }
                            WorkflowField(title: "Stock change", placeholder: "Add amount, or use − to remove", text: $amount, focus: $editing)
                            WorkflowField(title: "Reason", placeholder: "Why is stock changing?", text: $note, focus: $editing)
                            Button(cloud.pendingAdjustment ? "Retry saved stock change" : "Save stock change") {
                                editing = false; Task { await cloud.adjustInventory(item: item, amount: Int(amount) ?? 0, note: note); if !cloud.pendingAdjustment && cloud.problem.isEmpty { amount = "" } }
                            }.buttonStyle(PrimaryButton()).disabled(cloud.inventoryBusy || (!cloud.pendingAdjustment && (Int(amount) ?? 0) == 0))
                            Text("Use synthetic stock for this demonstration.").font(.caption).foregroundStyle(RelayTheme.secondary)
                        }.padding(.top, 12)
                    } label: { Text("Adjust stock").font(.headline) }
                }
                if cloud.inventoryBusy { ProgressView("Updating stock…").frame(maxWidth: .infinity) }
                if !cloud.problem.isEmpty { WorkflowNotice(text: cloud.problem) }
            }.padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }.background(RelayTheme.canvas).navigationTitle("")
            .toolbar { ToolbarItem(placement: .primaryAction) { if editing { Button("Done") { editing = false } } } }
            .task { await cloud.refreshInventory(); if cloud.pendingAdjustment { editingStock = true } }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            #endif
    }
    private func stat(_ title: String, value: Int) -> some View { HStack(spacing: 7) { Text(title).font(.caption).foregroundStyle(RelayTheme.secondary); Text("\(value)").font(.subheadline.bold()).monospacedDigit() } }
}
struct WorkflowSettings: View {
    @ObservedObject var model: RelayModel
    @EnvironmentObject private var cloud: CloudModel
    @AppStorage("relay.readingSize") private var readingSize = "Normal"
    @AppStorage("relay.highContrast") private var highContrast = false
    @State private var assigningReceiver = false
    @State private var showingDetails = false
    @State private var showingGuide = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                WorkflowHeader(eyebrow: "Preferences", title: "Settings", subtitle: "")
                VStack(alignment: .leading, spacing: 18) {
                    Text("Text size").font(.title2.bold())
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { sizeChoices }
                        VStack(spacing: 10) { sizeChoices }
                    }
                }
                Toggle(isOn: $highContrast) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("High contrast").font(.title3.bold())
                        Text("Black text on white, with thicker outlines.").font(.body)
                    }
                }.toggleStyle(.switch).tint(.black).padding(18)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: highContrast ? 3 : 1.5))
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your workspace").font(.title2.bold())
                    if let profile = cloud.profile {
                        Text(profile.role == "dispatcher" ? "Shelter coordinator" : "Public requester").font(.headline)
                        if profile.role == "requester" {
                            Button { showingDetails = true } label: {
                                HStack(spacing: 14) {
                                    ResidentAvatar(data: cloud.residentDetails.photoJPEG, size: 48)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(cloud.residentDetails.name.isEmpty ? "Your profile" : cloud.residentDetails.name).font(.headline)
                                        Text("Photo & personal details").font(.caption).foregroundStyle(RelayTheme.secondary)
                                    }
                                    Spacer(); Image(systemName: "chevron.right").accessibilityHidden(true)
                                }
                            }.buttonStyle(WorkflowSecondaryButton()).accessibilityLabel("Edit profile and personal details").accessibilityIdentifier("settingsResidentDetails")
                            Button("How RELAY works") { showingGuide = true }.buttonStyle(WorkflowSecondaryButton()).accessibilityIdentifier("settingsResidentGuide")
                        }
                        Text("Account: " + String(profile.subject.prefix(8)) + "…").font(.caption.monospaced())
                        Text("Device: " + String(model.deviceID.prefix(8)) + "…").font(.caption.monospaced())
                        Text("Your account controls access to requests. This device has its own nearby delivery ID. Use a separate account for each resident.").font(.caption).foregroundStyle(RelayTheme.secondary)
                        ForEach(cloud.directory) { shelter in
                            NavigationLink(shelter.display_name + " · information") { CloudShelterDetail(shelterID: shelter.shelter_id) }
                        }
                        if cloud.isDispatcher {
                            Text(cloud.receivesHere ? "This device receives nearby shelter requests." : "Nearby requests go to the shelter's selected receiving device.").font(.subheadline)
                            if !cloud.receivesHere {
                                Button("Receive shelter requests here") { assigningReceiver = true }.buttonStyle(WorkflowSecondaryButton()).disabled(cloud.busy)
                            }
                        }
                        if !cloud.nearbyProblem.isEmpty { WorkflowNotice(text: cloud.nearbyProblem) }
                        Button("Sign out / switch account") { cloud.signOut() }
                            .buttonStyle(WorkflowSecondaryButton()).disabled(cloud.busy || cloud.audioBusy || cloud.interpreting || cloud.submitting)
                    } else { AccountSignInView() }
                }
                Divider()
                NavigationLink { NearbyMessagesView(model: model) } label: {
                    HStack { Text("Nearby messages").font(.headline); Spacer(); Image(systemName: "chevron.right") }
                        .padding(.vertical, 12)
                }.foregroundStyle(.primary)
                Text("Phones can carry requests while RELAY is open. Wi-Fi radios must stay enabled.")
                    .font(.subheadline).foregroundStyle(RelayTheme.secondary)
                DisclosureGroup("Demo tools") {
                    VStack(alignment: .leading, spacing: 20) {
                        Toggle("Pause cloud delivery (demo)", isOn: $cloud.cloudPaused)
                            .disabled(cloud.busy || cloud.audioBusy || cloud.submitting || cloud.interpreting)
                            .onChange(of: cloud.cloudPaused) { _, paused in if !paused { Task { await cloud.connect(signIn: false) } } }
                        Text("This isolates the nearby request path in software. It does not prove that the radios are disconnected from a router.").font(.caption).foregroundStyle(RelayTheme.secondary)
                        NavigationLink("Diagnostics and test routes") { ToolsView(model: model) }
                        NavigationLink("Offline shelter directory") { ShelterDirectoryView(model: model, choose: { _ in }) }
                        NavigationLink("Saved offline requests") { HelpRequestsView(model: model) }
                        NavigationLink("Offline request form") { HelpHomeView(model: model, openChat: { _ in }, sent: { _ in }, chooseShelter: {}) }
                        NavigationLink("Cloud configuration") { CloudView(model: model) }
                        Text("Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")").font(.caption)
                    }.padding(.vertical, 16)
                }.font(.headline)
            }.padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }.navigationTitle("").background(RelayTheme.canvas)
            .sheet(isPresented: $showingDetails) { ResidentDetailsEditor() }
            .sheet(isPresented: $showingGuide) { ResidentGuideView() }
            .confirmationDialog("Use this device as the shelter's nearby inbox? New requests will be addressed here after their directory refreshes.", isPresented: $assigningReceiver, titleVisibility: .visible) {
                Button("Use this device") { Task { await cloud.useThisDeviceForShelter() } }
                Button("Cancel", role: .cancel) {}
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }
    private var sizeChoices: some View {
        ForEach(["Normal", "Large", "Largest"], id: \.self) { value in
            Button { readingSize = value } label: {
                VStack(spacing: 12) {
                    Text("Aa").font(.system(size: value == "Normal" ? 26 : value == "Large" ? 32 : 38, weight: .bold))
                    Text(value).font(.body.bold()).fixedSize()
                }.frame(maxWidth: .infinity, minHeight: 112).padding(.horizontal, 10)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: readingSize == value ? 4 : highContrast ? 3 : 1.5))
            }.buttonStyle(.plain).accessibilityAddTraits(readingSize == value ? .isSelected : [])
        }
    }
}

struct UrgencySelection: View {
    @Binding var value: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("How urgent is it?").font(.title2.bold()); Spacer(); if value != nil { Button("Clear") { value = nil }.font(.caption) } }
            Text("Choose or correct your reported urgency. Staff review the request.").font(.caption).foregroundStyle(RelayTheme.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 10)], spacing: 10) {
                ForEach(RequestUrgency.allCases, id: \.rawValue) { level in
                    Button { value = level.rawValue } label: {
                        Text(level.title).font(.body.bold()).frame(maxWidth: .infinity, minHeight: 46)
                            .foregroundStyle(value == level.rawValue ? RelayTheme.onAction : .primary)
                            .background(value == level.rawValue ? RelayTheme.action : .clear, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
                    }.buttonStyle(.plain).accessibilityAddTraits(value == level.rawValue ? .isSelected : [])
                }
            }
            if let level = value.flatMap(RequestUrgency.init(rawValue:)) { Text(level.explanation).font(.caption) }
            else { Text("Not specified").font(.caption).foregroundStyle(RelayTheme.secondary) }
        }
    }
}
