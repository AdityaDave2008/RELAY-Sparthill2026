import SwiftUI
import AVFoundation
import RelayCore

@MainActor final class AnnouncementSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var speaking = false
    @Published var problem = ""
    private let synthesizer = AVSpeechSynthesizer()
    override init() { super.init(); synthesizer.delegate = self }
    func play(_ text: String) {
        stop(); problem = ""
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { problem = "Audio could not start. You can still read the announcement."; return }
        #endif
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance); speaking = true
    }
    func stop() { synthesizer.stopSpeaking(at: .immediate); speaking = false; releaseAudio() }
    private func releaseAudio() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = self.synthesizer.isSpeaking; if !self.speaking { self.releaseAudio() } }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = self.synthesizer.isSpeaking; if !self.speaking { self.releaseAudio() } }
    }
}

struct AnnouncementsView: View {
    @EnvironmentObject private var cloud: CloudModel
    @State private var composing = false
    @State private var showPrevious = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkflowHeader(eyebrow: "Community", title: "Alerts", subtitle: cloud.isDispatcher ? "Share updates with everyone in this incident." : "Announcements from your shelter dispatchers.")
                if cloud.profile == nil { AccountSignInView() }
                else {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            if let date = cloud.announcementFeed?.fetched_at { Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))") }
                            else { Text("No announcements downloaded yet") }
                            Text("Saved alerts work offline. New updates need a cloud connection.")
                        }.font(.caption).foregroundStyle(RelayTheme.secondary)
                        Spacer()
                        Button("Refresh") { Task { await cloud.refreshAnnouncements() } }.disabled(cloud.announcementsBusy || !cloud.canUseCloud)
                    }
                    if cloud.isDispatcher {
                        if let pending = cloud.pendingAnnouncement {
                            RelayCard {
                                Text("Publishing not confirmed").font(.headline)
                                Text(pending.title)
                                Text("Retry checks the same announcement; it will not publish a duplicate.").font(.caption)
                                Button("Retry publication") { Task { _ = await cloud.publishAnnouncement() } }.buttonStyle(WorkflowSecondaryButton()).disabled(cloud.announcementsBusy || !cloud.canUseCloud)
                                if pending.expires_at < Date() { Button("Clear expired publication") { Task { await cloud.discardExpiredAnnouncement() } }.disabled(cloud.announcementsBusy) }
                            }
                        } else {
                            Button("New announcement") { composing = true }.buttonStyle(PrimaryButton()).disabled(!cloud.canUseCloud)
                                .accessibilityIdentifier("newAnnouncement")
                        }
                    }
                    if !cloud.announcementsProblem.isEmpty { WorkflowNotice(text: cloud.announcementsProblem) }
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        let items = cloud.announcementFeed?.items ?? []
                        let active = items.filter { $0.active(at: context.date) }.sorted { rank($0) == rank($1) ? $0.created_at > $1.created_at : rank($0) > rank($1) }
                        if active.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No active alerts").font(.title2.bold())
                                Text("This only reflects your last download. It does not confirm that conditions are safe.").font(.subheadline).foregroundStyle(RelayTheme.secondary)
                            }.padding(.vertical, 24)
                        }
                        ForEach(active) { item in announcementRow(item) }
                        let previous = items.filter { !$0.active(at: context.date) }
                        if !previous.isEmpty {
                            DisclosureGroup("Expired & withdrawn (\(previous.count))", isExpanded: $showPrevious) {
                                VStack(spacing: 16) { ForEach(previous) { item in announcementRow(item) } }.padding(.top, 12)
                            }
                        }
                    }
                }
            }.padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }.background(RelayTheme.canvas).navigationTitle("")
            .task { await cloud.refreshAnnouncements() }
            .refreshable { await cloud.refreshAnnouncements() }
            .sheet(isPresented: $composing) { AnnouncementComposer() }
    }
    private func rank(_ value: CloudAnnouncement) -> Int { value.severity == "urgent" ? 2 : value.severity == "important" ? 1 : 0 }
    private func announcementRow(_ value: CloudAnnouncement) -> some View {
        NavigationLink { AnnouncementDetail(announcementID: value.id) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(value.withdrawn ? "WITHDRAWN" : !value.active() ? "EXPIRED" : value.severity.uppercased()).font(.caption.bold()).foregroundStyle(value.active() ? RelayTheme.accent : .secondary)
                    Spacer()
                    if value.active(), (cloud.announcementReads[value.id] ?? 0) < value.revision { Text("NEW").font(.caption.bold()) }
                }
                Text(value.title).font(.title3.bold()).foregroundStyle(.primary)
                Text(value.text).font(.body).lineLimit(3).foregroundStyle(.primary)
                HStack { Text(value.publisher); Spacer(); Text("Read →") }.font(.caption).foregroundStyle(RelayTheme.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(value.active() ? 0.7 : 0.2), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

struct AnnouncementDetail: View {
    @EnvironmentObject private var cloud: CloudModel
    @StateObject private var speaker = AnnouncementSpeaker()
    @State private var withdrawing = false
    let announcementID: String
    private var value: CloudAnnouncement? { cloud.announcementFeed?.items.first { $0.id == announcementID } }
    var body: some View {
        ScrollView {
            if let value {
                VStack(alignment: .leading, spacing: 20) {
                    Text(value.severity.uppercased()).font(.caption.bold()).foregroundStyle(RelayTheme.accent)
                    Text(value.title).font(.largeTitle.bold())
                    Text(value.publisher).font(.headline)
                    Text("Published \(value.created_at.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if !value.active(at: context.date) { WorkflowNotice(text: value.withdrawn ? "Withdrawn by the dispatcher. Do not rely on this announcement." : "This announcement has expired.") }
                        Text(value.text).font(.title3).textSelection(.enabled)
                        Text("Expires \(value.expires_at.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(RelayTheme.secondary)
                        Button(speaker.speaking ? "Stop reading" : "Listen to announcement") {
                            if speaker.speaking { speaker.stop() } else { speaker.play(value.spokenText) }
                        }.buttonStyle(WorkflowSecondaryButton()).disabled(!value.active(at: context.date) && !speaker.speaking)
                            .accessibilityIdentifier("listenAnnouncement")
                            .onChange(of: value.active(at: context.date)) { _, active in if !active { speaker.stop() } }
                    }
                    Text("Read aloud on this device using its installed system voice.").font(.caption).foregroundStyle(RelayTheme.secondary)
                    if !speaker.problem.isEmpty { WorkflowNotice(text: speaker.problem) }
                    if let shelter = cloud.directory.first(where: { $0.shelter_id == value.shelter_id }) {
                        NavigationLink("Shelter location & arrival instructions") { CloudShelterDetail(shelterID: shelter.shelter_id) }
                    }
                    if cloud.isDispatcher, cloud.profile?.shelter_ids.contains(value.shelter_id) == true, !value.withdrawn {
                        Divider()
                        Button("Withdraw announcement", role: .destructive) { withdrawing = true }.disabled(cloud.announcementsBusy || !cloud.canUseCloud)
                    }
                    if !cloud.announcementsProblem.isEmpty { WorkflowNotice(text: cloud.announcementsProblem) }
                }.padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
                    .task(id: value.revision) { await cloud.markAnnouncementRead(value) }
            } else { Text("This announcement is no longer in the current feed.").padding(24) }
        }.navigationTitle("Announcement").onDisappear { speaker.stop() }
            .confirmationDialog("Withdraw this announcement? Devices learn about the withdrawal on their next cloud refresh.", isPresented: $withdrawing, titleVisibility: .visible) {
                Button("Withdraw", role: .destructive) { if let value { Task { await cloud.withdrawAnnouncement(value) } } }
            }
    }
}

struct AnnouncementComposer: View {
    @EnvironmentObject private var cloud: CloudModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var severity = "info"
    @State private var shelter = ""
    @State private var hours = 6
    @State private var reviewing: AnnouncementCommand?
    @State private var problem = ""
    @FocusState private var editing: Bool
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(reviewing == nil ? "New announcement" : "Review announcement").font(.largeTitle.bold())
                    Text("Visible to every enrolled resident and dispatcher in this incident, including people who have not sent a request.").font(.subheadline).foregroundStyle(RelayTheme.secondary)
                    if let review = reviewing {
                        Text(review.severity.uppercased()).font(.caption.bold()).foregroundStyle(RelayTheme.accent)
                        Text(review.title).font(.title2.bold()); Text(review.text)
                        Text("Expires \(review.expires_at.formatted(date: .abbreviated, time: .shortened))")
                        Text("Devices receive it when the app refreshes online. Publication does not confirm that everyone has read it.").font(.caption)
                        Button(cloud.announcementsBusy ? "Publishing…" : "Publish to incident") {
                            Task { if await cloud.publishAnnouncement(review) { dismiss() } }
                        }.buttonStyle(PrimaryButton()).disabled(cloud.announcementsBusy || !cloud.canUseCloud)
                            .accessibilityIdentifier("publishAnnouncement")
                        if cloud.pendingAnnouncement == nil { Button("Edit announcement") { reviewing = nil } }
                        if !cloud.announcementsProblem.isEmpty { WorkflowNotice(text: cloud.announcementsProblem) }
                    } else {
                        Picker("Publish from", selection: $shelter) { ForEach(cloud.directory) { Text($0.display_name).tag($0.shelter_id) } }
                        TextField("Title", text: $title).textFieldStyle(WorkflowInput()).focused($editing).accessibilityIdentifier("announcementTitle")
                        TextField("What should residents know or do?", text: $text, axis: .vertical).lineLimit(5...10).textFieldStyle(WorkflowInput()).focused($editing).accessibilityIdentifier("announcementText")
                        Picker("Priority", selection: $severity) { Text("Information").tag("info"); Text("Important").tag("important"); Text("Urgent").tag("urgent") }
                        Picker("Expires after", selection: $hours) { Text("1 hour").tag(1); Text("6 hours").tag(6); Text("24 hours").tag(24) }
                        Text("Use confirmed facts and clear instructions. Include the place and time. Do not include private resident details.").font(.caption).foregroundStyle(RelayTheme.secondary)
                        if !problem.isEmpty { WorkflowNotice(text: problem) }
                        Button("Review announcement") {
                            editing = false
                            do { reviewing = try AnnouncementCommand(shelterID: shelter, title: title, text: text, severity: severity, expiresAt: Date().addingTimeInterval(Double(hours) * 3600)) }
                            catch { problem = error.localizedDescription }
                        }.buttonStyle(PrimaryButton()).accessibilityIdentifier("reviewAnnouncement")
                    }
                }.padding(24).frame(maxWidth: 660).frame(maxWidth: .infinity)
            }.toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(cloud.announcementsBusy) }
                ToolbarItem(placement: .primaryAction) { if editing { Button("Done") { editing = false } } }
            }.onAppear { shelter = cloud.staffShelterID.isEmpty ? cloud.directory.first?.shelter_id ?? "" : cloud.staffShelterID }
                .interactiveDismissDisabled(cloud.announcementsBusy)
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
        }
        #if os(macOS)
        .frame(minWidth: 580, minHeight: 650)
        #endif
    }
}

struct CloudShelterDetail: View {
    @EnvironmentObject private var cloud: CloudModel
    @StateObject private var locator = RequestLocationModel()
    @State private var distanceLocation: RequestLocation?
    @State private var editing = false
    let shelterID: String
    private var shelter: CloudShelter? { cloud.directory.first { $0.shelter_id == shelterID } }
    var body: some View {
        ScrollView {
            if let shelter {
                VStack(alignment: .leading, spacing: 20) {
                    WorkflowHeader(eyebrow: "Shelter", title: shelter.display_name, subtitle: "Location & arrival instructions")
                    if let details = shelter.details {
                        if !details.address.isEmpty { Text(details.address).font(.title3).textSelection(.enabled) }
                        if let latitude = details.latitude, let longitude = details.longitude {
                            if let location = distanceLocation ?? cloud.draft.location, let meters = details.distance(from: location) {
                                Text(meters < 1000 ? String(format: "About %.0f m away", (meters / 10).rounded() * 10) : String(format: "About %.1f km away", meters / 1000)).font(.title2.bold())
                                Text("Straight-line distance, not a walking route. Your location: ±\(Int(location.horizontal_accuracy)) m, captured \(location.captured_at.formatted(date: .abbreviated, time: .shortened)).").font(.caption).foregroundStyle(RelayTheme.secondary)
                            } else { Text("Add a location to estimate how far away this shelter is.").foregroundStyle(RelayTheme.secondary) }
                            Button(locator.busy ? "Locating…" : "Use my location for distance") { locator.capture { distanceLocation = $0 } }.disabled(locator.busy)
                            if let url = URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=Shelter") { Link("Open shelter location in Maps", destination: url) }
                            Text("Maps may need internet. Check current conditions with shelter staff before travelling.").font(.caption).foregroundStyle(RelayTheme.secondary)
                        } else { Text("Shelter coordinates have not been provided.").font(.subheadline).foregroundStyle(RelayTheme.secondary) }
                        Divider()
                        Text("Arrival instructions").font(.title2.bold())
                        Text(details.instructions.isEmpty ? "No arrival instructions have been published." : details.instructions).textSelection(.enabled)
                        Text("Updated by shelter staff \(details.updated_at.formatted(date: .abbreviated, time: .shortened)). Cached information can be out of date during an outage.").font(.caption).foregroundStyle(RelayTheme.secondary)
                    } else { Text("Shelter staff have not published an address or arrival instructions yet.") }
                    if !locator.problem.isEmpty { WorkflowNotice(text: locator.problem) }
                    if cloud.isDispatcher { Button("Edit shelter information") { editing = true }.buttonStyle(WorkflowSecondaryButton()).disabled(!cloud.canUseCloud) }
                }.padding(24).frame(maxWidth: 660).frame(maxWidth: .infinity)
            }
        }.navigationTitle("Shelter information").task { await cloud.refreshDirectory() }
            .sheet(isPresented: $editing) { if let shelter { ShelterInformationEditor(shelter: shelter) } }
    }
}

struct ShelterInformationEditor: View {
    @EnvironmentObject private var cloud: CloudModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locator = RequestLocationModel()
    @State private var address = ""
    @State private var instructions = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var saving = false
    @State private var problem = ""
    @FocusState private var editing: Bool
    let shelter: CloudShelter
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(shelter.display_name).font(.largeTitle.bold())
                    Text("Publish the shelter's address and staff-confirmed arrival instructions.")
                    TextField("Shelter address", text: $address, axis: .vertical).lineLimit(2...3).textFieldStyle(WorkflowInput()).focused($editing)
                    TextField("Latitude (optional)", text: $latitude).textFieldStyle(WorkflowInput()).focused($editing)
                    TextField("Longitude (optional)", text: $longitude).textFieldStyle(WorkflowInput()).focused($editing)
                    Button(locator.busy ? "Locating…" : "Use this device's location") { editing = false; locator.capture { latitude = String($0.latitude); longitude = String($0.longitude) } }.disabled(locator.busy)
                    Text("Only use this device's location if you are at the shelter.").font(.caption).foregroundStyle(RelayTheme.secondary)
                    TextField("Entrance, access instructions and landmarks", text: $instructions, axis: .vertical).lineLimit(4...8).textFieldStyle(WorkflowInput()).focused($editing)
                    if !problem.isEmpty { WorkflowNotice(text: problem) }
                    if !locator.problem.isEmpty { WorkflowNotice(text: locator.problem) }
                    Button(saving ? "Saving…" : "Publish shelter information") {
                        editing = false; saving = true
                        Task {
                            do {
                                let command = try ShelterDetailsCommand(revision: shelter.details?.revision ?? 0, address: address, instructions: instructions, latitude: latitude, longitude: longitude)
                                try await cloud.updateShelterDetails(shelterID: shelter.shelter_id, command: command); dismiss()
                            } catch { problem = error.localizedDescription }
                            saving = false
                        }
                    }.buttonStyle(PrimaryButton()).disabled(saving || locator.busy)
                }.padding(24).frame(maxWidth: 660).frame(maxWidth: .infinity)
            }.toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .primaryAction) { if editing { Button("Done") { editing = false } } }
            }.onAppear {
                address = shelter.details?.address ?? ""; instructions = shelter.details?.instructions ?? ""
                latitude = shelter.details?.latitude.map { String($0) } ?? ""; longitude = shelter.details?.longitude.map { String($0) } ?? ""
            }.interactiveDismissDisabled(saving)
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
        }
        #if os(macOS)
        .frame(minWidth: 580, minHeight: 680)
        #endif
    }
}
