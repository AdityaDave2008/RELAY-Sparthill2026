import SwiftUI
import RelayCore

struct HelpHomeView: View {
    @ObservedObject var model: RelayModel
    let openChat: (String) -> Void
    let sent: (String) -> Void
    let chooseShelter: () -> Void
    @FocusState private var editing: Bool
    @State private var reviewedDraft: HelpRequestDraft?
    private var destinations: [ShelterContact] { model.shelters.filter { $0.receivingDeviceID != model.deviceID } }
    private var destination: ShelterContact? { destinations.first { $0.id == model.helpDraft.shelterID } }
    private var validation: String? {
        guard let destination else { return "Choose a saved shelter to receive this request." }
        do { _ = try model.helpDraft.request(to: destination); return nil }
        catch { return String(describing: error) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A request that stays with you").font(.title2.bold())
                    Text("Save it here. Nearby devices can carry it to your chosen shelter when they meet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ConnectionCard(model: model)
                HStack {
                    NavigationLink { NearbyView(model: model, compose: openChat) } label: {
                        Label("Nearby devices", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    Spacer()
                    Text("Test prototype").font(.caption).foregroundStyle(.secondary)
                }.font(.subheadline)
                RelayCard {
                    Text("Where should it go?").font(.headline)
                    if destinations.isEmpty {
                        Text("Add a shelter or import its code first. Its receiving device can be offline.").foregroundStyle(.secondary)
                        Button("Open shelters", action: chooseShelter).buttonStyle(.bordered)
                    } else {
                        Picker("Shelter", selection: $model.helpDraft.shelterID) {
                            Text("Choose a shelter").tag("")
                            ForEach(destinations) { s in Text("\(s.name) · \(s.area)").tag(s.id) }
                        }.pickerStyle(.menu).accessibilityIdentifier("requestShelter")
                    }
                    if let destination {
                        Text("Saved directory · \(destination.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                RelayCard {
                    Text("What do you need?").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 10) {
                        ForEach(HelpNeed.allCases, id: \.self) { need in
                            Button { model.helpDraft.need = need } label: {
                                Label(need.title, systemImage: need.symbol).font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background(model.helpDraft.need == need ? RelayTheme.accent.opacity(0.17) : RelayTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityAddTraits(model.helpDraft.need == need ? .isSelected : [])
                        }
                    }
                    TextField("Describe the need using synthetic test data", text: $model.helpDraft.details, axis: .vertical)
                        .lineLimit(3...6).textFieldStyle(.roundedBorder).focused($editing)
                        .accessibilityLabel("Request details").accessibilityIdentifier("requestDetails")
                    HStack(alignment: .top, spacing: 12) {
                        field("Quantity", placeholder: "Unknown", text: $model.helpDraft.quantity)
                        field("Unit", placeholder: "water packs", text: $model.helpDraft.unit)
                    }
                    field("People affected", placeholder: "Unknown", text: $model.helpDraft.people)
                    Text("Quantity and people are separate. Leave quantity and unit blank if you are unsure.")
                        .font(.caption).foregroundStyle(.secondary)
                    field("Location or landmark", placeholder: "e.g. Demo Hall, north entrance", text: $model.helpDraft.location)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label(model.draftSaveState, systemImage: "externaldrive").font(.caption).foregroundStyle(.secondary)
                    if let validation { Text(validation).font(.caption).foregroundStyle(.secondary) }
                    Button {
                        editing = false; reviewedDraft = model.helpDraft
                    } label: { Label("Review request", systemImage: "arrow.right") }
                        .buttonStyle(PrimaryButton()).disabled(validation != nil || !model.ready || model.sending)
                        .accessibilityIdentifier("reviewRequest")
                    Text("Synthetic data only. Cloud sign-in and voice input are available in the Cloud tab; nearby device identities remain unverified.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(RelayTheme.canvas).navigationTitle("Help")
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if editing { Button("Done") { editing = false } }
                    else { NavigationLink { ToolsView(model: model) } label: { Label("Settings and tools", systemImage: "gearshape") } }
                }
            }
            .onChange(of: model.helpDraft) { _, _ in model.persistHelpDraft() }
            .sheet(item: $reviewedDraft) { draft in
                RequestReviewView(model: model, draft: draft) { id in reviewedDraft = nil; sent(id) }
            }
    }
    private func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder).focused($editing).accessibilityLabel(title)
        }
    }
}

private struct RequestFacts: View {
    let request: ShelterRequest
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(request.need.title, systemImage: request.need.symbol).font(.title2.bold())
            Text(request.details).textSelection(.enabled)
            LabeledContent("To", value: request.shelter.name)
            LabeledContent("Area", value: request.shelter.area)
            LabeledContent("Amount", value: request.amount)
            LabeledContent("People", value: request.people.map(String.init) ?? "Unknown")
            VStack(alignment: .leading, spacing: 4) {
                Text("Location or landmark").font(.caption).foregroundStyle(.secondary)
                Text(request.location)
            }
        }
    }
}

private struct RequestReviewView: View {
    @EnvironmentObject private var cloud: CloudModel
    @State private var sendToCloud = false
    @ObservedObject var model: RelayModel
    let draft: HelpRequestDraft
    let sent: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    private var request: ShelterRequest? {
        guard let shelter = model.shelters.first(where: { $0.id == draft.shelterID }) else { return nil }
        return try? draft.request(to: shelter)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let request {
                        RequestFacts(request: request)
                        Text("This saves the request on your device and queues it for delivery. A delivery receipt means the receiving device saved it; it does not mean staff have acted.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if cloud.canUseCloud && cloud.bindings.contains(where: { $0.localID == draft.shelterID }) {
                            Toggle("Also queue for cloud", isOn: $sendToCloud)
                            Text("Uses the same request ID. Cloud acceptance stays separate from nearby delivery.").font(.caption).foregroundStyle(.secondary)
                        }
                        Button {
                            do {
                                let submission = try sendToCloud ? cloud.prepared(draft) : draft
                                model.submitHelp(submission) { id in
                                    // The cloud intent was committed atomically with the local message.
                                    Task { await cloud.sync() }; sent(id)
                                }
                            } catch { model.error = error.localizedDescription }
                        } label: {
                            Label(model.sending ? "Saving…" : "Save and send request", systemImage: "paperplane.fill")
                        }.buttonStyle(PrimaryButton()).disabled(model.sending)
                            .accessibilityIdentifier("submitRequest")
                    } else { Text("The destination or draft changed. Close this review and choose a shelter again.") }
                }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.navigationTitle("Review request")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() }.disabled(model.sending) } }
        }.interactiveDismissDisabled(model.sending)
            .alert("Request wasn’t saved", isPresented: Binding(get: { !model.error.isEmpty }, set: { if !$0 { model.error = "" } })) {
                Button("OK") { model.error = "" }
            } message: { Text(model.error) }
            #if os(macOS)
            .frame(minWidth: 560, minHeight: 600)
            #endif
    }
}

struct HelpRequestsView: View {
    @ObservedObject var model: RelayModel
    @State private var inbox = false
    private var items: [HelpRequestItem] { HelpRequestItem.project(model.messages, deviceID: model.deviceID, inbox: inbox) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Request list", selection: $inbox) {
                    Text("My requests").tag(false)
                    Text("Device inbox").tag(true)
                }.pickerStyle(.segmented)
                Text(inbox ? "Requests addressed to this receiving device. This is a local test inbox, not an authenticated staff role." : "Your saved help requests and their delivery progress.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if items.isEmpty {
                    ContentUnavailableView(inbox ? "No received requests" : "No requests yet", systemImage: "tray", description: Text(inbox ? "Share a shelter code from Shelters, then receive its requests here." : "Use Help to create a request for a saved shelter."))
                }
                ForEach(items) { item in
                    NavigationLink { HelpRequestDetail(model: model, requestID: item.id) } label: {
                        RelayCard {
                            HStack {
                                Label(item.request.need.title, systemImage: item.request.need.symbol).font(.headline)
                                Spacer(); Image(systemName: "chevron.right").font(.caption)
                            }
                            Text(item.request.shelter.name).font(.subheadline.weight(.medium))
                            Text(item.request.details).lineLimit(2).foregroundStyle(.secondary)
                            Text(item.stored.status(deviceID: model.deviceID)).font(.caption).foregroundStyle(RelayTheme.accent)
                            Text(item.stored.message.createdAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }.multilineTextAlignment(.leading)
                    }.buttonStyle(.plain)
                }
            }.padding(20).frame(maxWidth: 740).frame(maxWidth: .infinity)
        }.background(RelayTheme.canvas).navigationTitle("Requests")
    }
}

struct HelpRequestDetail: View {
    @ObservedObject var model: RelayModel
    let requestID: String
    private var item: HelpRequestItem? {
        (HelpRequestItem.project(model.messages, deviceID: model.deviceID, inbox: false) +
         HelpRequestItem.project(model.messages, deviceID: model.deviceID, inbox: true)).first { $0.id == requestID }
    }
    var body: some View {
        ScrollView {
            if let item {
                VStack(alignment: .leading, spacing: 20) {
                    RelayCard { RequestFacts(request: item.request) }
                    RelayCard {
                        Label("Delivery", systemImage: "paperplane").font(.headline)
                        Text(item.stored.status(deviceID: model.deviceID))
                        Text("Created \(item.stored.message.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        if let receipt = item.stored.finalReceiptID {
                            Text("Return receipt: \(receipt)").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                        Text("Delivery does not confirm assignment or fulfillment.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    LocalRequestThread(model: model, request: item.stored.message)
                    if item.stored.message.originID == model.deviceID { CloudRequestPanel(message: item.stored.message) }
                    RelayCard {
                        Text("Request identity").font(.headline)
                        Text(item.id).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Text("Shelter: \(item.request.shelter.id)\nReceiving device: \(item.stored.message.destinationID)")
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        Button("Copy request ID") { copyText(item.id) }
                        Text("The saved destination is a local directory entry, not a verified organizational identity.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
            } else { ContentUnavailableView("Request unavailable", systemImage: "tray") }
        }.background(RelayTheme.canvas).navigationTitle("Request")
    }
}

struct ShelterDirectoryView: View {
    @ObservedObject var model: RelayModel
    let choose: (String) -> Void
    private enum Setup: String, Identifiable { case local, code; var id: String { rawValue } }
    @State private var setup: Setup?
    @State private var savedName = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Saved destinations").font(.title2.bold())
                Text("A shelter keeps its own ID. For this prototype, one phone or Mac receives its requests. Add or import it before going offline.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button { setup = .code } label: { Label("Import shelter", systemImage: "square.and.arrow.down") }
                    .buttonStyle(PrimaryButton()).disabled(!model.ready).accessibilityIdentifier("importShelter")
                Button { setup = .local } label: { Label("Create shelter on this device", systemImage: "plus") }
                    .buttonStyle(.bordered).controlSize(.large).disabled(!model.ready).accessibilityIdentifier("addShelter")
                Text("Connect is not needed to save shelters. Copy stays on the source phone: share its code to this phone, then import it here.")
                    .font(.caption).foregroundStyle(.secondary)
                if !savedName.isEmpty { Label("\(savedName) saved on this device", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(RelayTheme.accent) }
                if model.shelters.isEmpty {
                    ContentUnavailableView("No shelters saved", systemImage: "house", description: Text("Create a test shelter on its receiving device, then share its code with the sender."))
                }
                ForEach(model.shelters) { shelter in
                    NavigationLink {
                        ShelterDetailView(model: model, shelter: shelter, choose: choose)
                    } label: {
                        RelayCard {
                            HStack { Label(shelter.name, systemImage: "house.fill").font(.headline); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                            Text(shelter.area).font(.subheadline).foregroundStyle(.secondary)
                            Text(shelter.receivingDeviceID == model.deviceID ? "Receives on this device" : "Saved for later encounters")
                                .font(.caption).foregroundStyle(RelayTheme.accent)
                            Text("Local entry · unverified").font(.caption2).foregroundStyle(.secondary)
                        }.multilineTextAlignment(.leading)
                    }.buttonStyle(.plain)
                }
                if !model.removedShelters.isEmpty {
                    DisclosureGroup("Removed shelters (\(model.removedShelters.count))") {
                        ForEach(model.removedShelters) { shelter in
                            HStack {
                                VStack(alignment: .leading) { Text(shelter.name); Text(shelter.area).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Button("Restore") { model.saveShelter(shelter) { savedName = shelter.name } }
                            }.padding(.vertical, 10)
                        }
                    }.font(.subheadline)
                }
            }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }.background(RelayTheme.canvas).navigationTitle("Shelters")
            .sheet(item: $setup) { choice in
                AddShelterView(model: model, initialMode: choice == .code ? "import" : "local") { savedName = $0 }
            }
    }
}

private struct ShelterDetailView: View {
    @ObservedObject var model: RelayModel
    let shelter: ShelterContact
    let choose: (String) -> Void
    @State private var copied = false
    @State private var confirmingRemoval = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label(shelter.name, systemImage: "house.fill").font(.title.bold())
                Text(shelter.area).font(.title3).foregroundStyle(.secondary)
                Text("Saved \(shelter.updatedAt.formatted(date: .abbreviated, time: .shortened)). Capacity and services have not been verified.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if shelter.receivingDeviceID != model.deviceID {
                    Button("Request help here") { choose(shelter.id) }.buttonStyle(PrimaryButton())
                } else {
                    Label("This device receives requests", systemImage: "tray.and.arrow.down.fill").font(.headline)
                    Text("Keep RELAY open and connect nearby. Received requests appear in Requests → Device inbox.").foregroundStyle(.secondary)
                }
                if let code = try? shelter.shareCode() {
                    Button(copied ? "Shelter code copied" : "Copy shelter code") { copyText(code); copied = true }.buttonStyle(.bordered)
                    ShareLink("Share shelter code", item: code)
                    Text("Copy only affects this phone’s clipboard. Use Share to send the code to the other phone (for example through Messages), then Shelters → Import shelter there. Do this setup before your offline test.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Shelter ID\n\(shelter.id)\n\nReceiving device\n\(shelter.receivingDeviceID)")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Text("Local test configuration only. Creating or importing this entry does not grant staff permissions.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Remove shelter", role: .destructive) { confirmingRemoval = true }
                    .buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("removeShelter")
            }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.navigationTitle("Shelter")
            .confirmationDialog("Remove \(shelter.name) from this device?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button("Remove shelter", role: .destructive) { model.removeShelter(shelter.id) { dismiss() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Existing requests, messages and receipts stay saved and queued delivery continues. Restore this entry from Removed shelters at any time.")
            }
    }
}

private struct AddShelterView: View {
    @ObservedObject var model: RelayModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: String
    let onSaved: (String) -> Void
    @State private var name = ""
    @State private var area = ""
    @State private var deviceID = ""
    @State private var code = ""
    @State private var shelterID = UUID().uuidString.lowercased()
    @State private var saving = false
    @FocusState private var editing: Bool
    init(model: RelayModel, initialMode: String, onSaved: @escaping (String) -> Void) {
        self.model = model; _mode = State(initialValue: initialMode); self.onSaved = onSaved
    }
    private var imported: ShelterContact? { try? ShelterContact.importCode(code) }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Setup", selection: $mode) {
                    Text("Receive here").tag("local")
                    Text("Another device").tag("manual")
                    Text("Import code").tag("import")
                }.pickerStyle(.menu)
                if mode == "import" {
                    Text("On the other phone, open its shelter and use Share shelter code. Paste that code below; Connect is not required.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    PasteButton(payloadType: String.self) { strings in if let text = strings.first { code = text } }
                    TextField("Paste RELAY shelter code", text: $code, axis: .vertical).lineLimit(4...8).focused($editing)
                        .autocorrectionDisabled().accessibilityIdentifier("shelterCode")
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    if let imported {
                        Section("Shelter to import") {
                            Text(imported.name).font(.headline)
                            Text(imported.area)
                            Text("Receiving device: \(imported.receivingDeviceID.prefix(8))").font(.caption)
                            if imported.receivingDeviceID == model.deviceID {
                                Text("This code belongs to this phone. It will appear in Shelters, but Help only offers destinations on another device.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    } else if !code.isEmpty {
                        Text("Code not recognized. Paste the complete code starting with RELAY-SHELTER-1:.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                } else {
                    TextField("Shelter name", text: $name).focused($editing).accessibilityIdentifier("shelterName")
                    TextField("Area or address", text: $area).focused($editing).accessibilityIdentifier("shelterArea")
                    if mode == "manual" {
                        TextField("Receiving device UUID", text: $deviceID).focused($editing).autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                        if !model.known.isEmpty {
                            Picker("Previously met", selection: $deviceID) {
                                Text("Enter manually").tag("")
                                ForEach(model.known, id: \.deviceID) { peer in Text(model.addressLabel(peer.deviceID)).tag(peer.deviceID) }
                            }
                        }
                    }
                    Text(mode == "local" ? "This device will receive the shelter's messages. Share the saved code with requesters." : "Use the same shared code on all devices. Creating another entry generates a different shelter ID.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Use a synthetic shelter. This local setup is not identity verification or staff enrollment.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(saving ? "Saving…" : mode == "import" ? "Import shelter" : "Save shelter", action: save)
                    .disabled(saving || !model.ready || (mode == "import" && imported == nil))
                    .accessibilityIdentifier("saveShelter")
            }.navigationTitle(mode == "import" ? "Import shelter" : "Create shelter")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .primaryAction) { if editing { Button("Done") { editing = false } } }
                }
                .alert("Shelter wasn’t saved", isPresented: Binding(get: { !model.error.isEmpty }, set: { if !$0 { model.error = ""; saving = false } })) {
                    Button("OK") { model.error = ""; saving = false }
                } message: { Text(model.error) }
        }.interactiveDismissDisabled(saving)
            #if os(macOS)
            .frame(minWidth: 560, minHeight: 480)
            #endif
    }
    private func save() {
        do {
            let shelter = try mode == "import" ? ShelterContact.importCode(code) : ShelterContact(id: shelterID,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines), area: area.trimmingCharacters(in: .whitespacesAndNewlines),
                receivingDeviceID: mode == "local" ? model.deviceID : deviceID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            try shelter.validate(); saving = true
            model.saveShelter(shelter) { saving = false; onSaved(shelter.name); dismiss() }
        } catch { model.error = String(describing: error) }
    }
}
