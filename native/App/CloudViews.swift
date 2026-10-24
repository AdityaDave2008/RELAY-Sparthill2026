import SwiftUI
import UniformTypeIdentifiers
import RelayCore

struct CloudView: View {
    @ObservedObject var model: RelayModel
    @EnvironmentObject private var cloud: CloudModel
    @FocusState private var editing: Bool
    @State private var localID = ""
    @State private var cloudID = ""
    @State private var inboxID = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RelayCard {
                    Label("Cloud connection", systemImage: "cloud").font(.headline)
                    Text(cloud.status).font(.subheadline)
                    if cloud.profile == nil {
                        TextField("HTTPS API address", text: $cloud.endpoint).textFieldStyle(.roundedBorder).focused($editing)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never).keyboardType(.URL)
                            #endif
                        Button("Sign in securely") { Task { await cloud.connect(signIn: true) } }.buttonStyle(.borderedProminent).disabled(cloud.busy || cloud.endpoint.isEmpty)
                        Text("An enrolled account and hosted API are required. Nearby messages and saved requests work without signing in.").font(.caption).foregroundStyle(RelayTheme.secondary)
                    } else {
                        Text("\(cloud.profile!.role.capitalized) · \(cloud.profile!.incident_id)").font(.caption)
                        HStack {
                            Button("Sync now") { Task { await cloud.sync() } }.disabled(cloud.busy)
                            Button("Sign out") { cloud.signOut() }.disabled(cloud.busy || cloud.audioBusy)
                        }.buttonStyle(.bordered)
                    }
                    if cloud.busy { ProgressView() }
                    if !cloud.problem.isEmpty { Text(cloud.problem).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                }
                if cloud.profile != nil {
                    RelayCard {
                        Text("Link a saved shelter").font(.headline)
                        Text("Choose which authorized cloud inbox corresponds to a shelter saved on this device. Existing peer addresses stay the same.").font(.subheadline).foregroundStyle(RelayTheme.secondary)
                        Picker("Saved on this device", selection: $localID) {
                            Text("Choose local shelter").tag("")
                            ForEach(model.shelters) { Text($0.name).tag($0.id) }
                        }
                        Picker("Cloud inbox", selection: $cloudID) {
                            Text("Choose cloud shelter").tag("")
                            ForEach(cloud.directory) { Text($0.display_name).tag($0.id) }
                        }
                        Button("Link destination") { Task { await cloud.bind(localID: localID, cloudID: cloudID) } }.disabled(localID.isEmpty || cloudID.isEmpty)
                        ForEach(cloud.bindings, id: \.localID) { binding in
                            Text("\(model.shelters.first { $0.id == binding.localID }?.name ?? String(binding.localID.prefix(8))) → \(cloud.directory.first { $0.shelter_id == binding.shelterID }?.display_name ?? binding.shelterID)").font(.caption)
                        }
                    }
                    NavigationLink { VoiceInputView() } label: { Label("Record a request", systemImage: "mic.fill") }.buttonStyle(.borderedProminent)
                    RelayCard {
                        Text(cloud.isDispatcher ? "Operations inbox" : "Cloud requests").font(.headline)
                        if cloud.isDispatcher {
                            Picker("Shelter", selection: $inboxID) {
                                Text("Choose a shelter").tag("")
                                ForEach(cloud.directory) { Text($0.display_name).tag($0.shelter_id) }
                            }
                            Button("Load shelter requests") { Task { await cloud.loadInbox(shelterID: inboxID) } }.disabled(inboxID.isEmpty || cloud.busy)
                        }
                        Button("Load my cloud requests") { Task { await cloud.loadInbox() } }.disabled(cloud.busy)
                        Text("Local requests can be queued from Requests → request → Cloud delivery. Future requests offer cloud delivery during review.").font(.caption).foregroundStyle(RelayTheme.secondary)
                    }
                    ForEach(cloud.records.sorted { $0.submission.created_at > $1.submission.created_at }) { record in
                        NavigationLink { CloudRequestDetail(id: record.id) } label: {
                            RelayCard {
                                Text(record.submission.original_text).lineLimit(3)
                                Text(record.result == nil ? "Saved locally for cloud · \(record.state)" : "Cloud accepted · \(record.result!.analysis_state.replacingOccurrences(of: "_", with: " "))").font(.caption).foregroundStyle(RelayTheme.accent)
                                if let problem = record.problem { Text(problem).font(.caption).foregroundStyle(.orange) }
                            }.multilineTextAlignment(.leading)
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(RelayTheme.canvas).navigationTitle("Cloud")
            .toolbar { ToolbarItem(placement: .primaryAction) { if editing { Button("Done") { editing = false } } } }
    }
}
struct CloudRequestPanel: View {
    @EnvironmentObject private var cloud: CloudModel
    let message: RelayMessage
    var body: some View {
        RelayCard {
            Label("Cloud delivery", systemImage: "cloud").font(.headline)
            if let record = cloud.records.first(where: { $0.id == message.id }) {
                Text(record.result == nil ? "Queued on this device" : "Accepted by cloud")
                NavigationLink("Open analysis and replies") { CloudRequestDetail(id: message.id) }
            } else {
                Text("Nearby delivery and cloud acceptance are tracked separately.").font(.caption).foregroundStyle(RelayTheme.secondary)
                Button("Queue this request for cloud") { Task { await cloud.queue(message) } }.disabled(!cloud.canUseCloud)
            }
            if !cloud.problem.isEmpty { Text(cloud.problem).font(.caption).foregroundStyle(.orange) }
        }
    }
}
struct CloudRequestDetail: View {
    @EnvironmentObject private var cloud: CloudModel
    let id: String
    @FocusState private var editing: Bool
    @State private var reply = ""
    @State private var progress = ""
    private var record: CloudQueueRecord? { cloud.records.first { $0.id == id } }
    var body: some View {
        ScrollView {
            if let record {
                VStack(alignment: .leading, spacing: 20) {
                    RelayCard {
                        Text("Original request").font(.headline); Text(record.submission.original_text)
                        Text(record.id).font(.caption.monospaced()).textSelection(.enabled)
                        Text(record.result == nil ? "Queued for cloud" : "Cloud accepted").foregroundStyle(RelayTheme.accent)
                        if let problem = record.problem { Text(problem).foregroundStyle(.orange) }
                        Button("Refresh / retry") { Task { await cloud.retry(id) } }.disabled(cloud.busy)
                    }
                    if let result = record.result {
                        RelayCard {
                            Text("AI proposal · review required").font(.headline)
                            Text(result.analysis_state.replacingOccurrences(of: "_", with: " "))
                            if let proposal = result.result?.proposal {
                                Text(proposal.summary)
                                Text("Item: \(proposal.item_id ?? "Unknown") · Amount: \(proposal.quantity.map(String.init) ?? "Unknown") \(proposal.unit ?? "")").font(.subheadline)
                            }
                            ForEach(result.result?.review_reasons ?? [], id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                            if let error = result.error { Text(error.message).font(.caption) }
                            Text("A proposal does not reserve supplies or authorize an assignment.").font(.caption).foregroundStyle(RelayTheme.secondary)
                        }
                        RelayCard {
                            Text("Request conversation").font(.headline)
                            Text("Progress: \(record.history?.status.replacingOccurrences(of: "_", with: " ") ?? "new")")
                            ForEach(record.history?.events ?? []) { event in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(event.author_role.capitalized).font(.caption.bold())
                                    if let status = event.status { Text(status.replacingOccurrences(of: "_", with: " ")).font(.subheadline.bold()) }
                                    if !event.text.isEmpty { Text(event.text) }
                                    Text(event.created_at, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(RelayTheme.secondary)
                                }.padding(.vertical, 6)
                            }
                            TextField("Reply about this request", text: $reply, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder).focused($editing)
                            Picker("Progress update", selection: $progress) {
                                Text("Reply only").tag("")
                                if cloud.isDispatcher {
                                    Text("Accepted by staff").tag("accepted")
                                    Text("In progress").tag("in_progress")
                                    Text("Reported completed").tag("completed")
                                    Text("Unable to help").tag("rejected")
                                } else { Text("Cancel request").tag("cancelled") }
                            }
                            Button("Queue update") { Task {
                                await cloud.sendEvent(id, text: reply, status: progress.isEmpty ? nil : progress)
                                if cloud.records.first(where: { $0.id == id })?.pendingEvent != nil || cloud.problem.isEmpty { reply = ""; progress = "" }
                            } }.disabled(cloud.busy || record.pendingEvent != nil || (reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && progress.isEmpty))
                            if record.pendingEvent != nil {
                                Text("An update is queued. Its ID stays the same on retry.").font(.caption)
                                if record.state == "needs_attention" {
                                    Button("Discard unsent update and refresh") { Task { await cloud.discardConflictingEvent(id) } }
                                }
                            }
                            Text("Progress is reported by people. Inventory allocation and independent fulfillment verification are not implemented.").font(.caption).foregroundStyle(RelayTheme.secondary)
                        }
                    }
                }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
        }.background(RelayTheme.canvas).navigationTitle("Cloud request")
            .toolbar { ToolbarItem(placement: .primaryAction) { if editing { Button("Done") { editing = false } } } }
    }
}
struct VoiceInputView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cloud: CloudModel
    @FocusState private var editing: Bool
    @StateObject private var live = LiveSpeechRecorder()
    @State private var importingWAV = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WorkflowHeader(eyebrow: "Voice", title: "Record a request", subtitle: "Words appear while you speak. Review them before sending.")
                RelayCard {
                    Text("Live transcription").font(.title3.bold())
                    Text("English · up to 60 seconds · internet required").font(.subheadline).foregroundStyle(RelayTheme.secondary)
                    Button {
                        if live.recording { live.stop() }
                        else { Task { await live.start(cloud: cloud) } }
                    } label: {
                        Text(live.recording ? "Stop recording" : live.state == "connecting" ? "Connecting…" : live.state == "finishing" ? "Finishing transcript…" : "Start recording")
                    }.buttonStyle(PrimaryButton()).disabled((cloud.audioBusy || live.working) && !live.recording)
                    if live.working {
                        Text(String(format: "%.1f / 60 seconds", live.seconds)).font(.body.monospacedDigit())
                        if !live.text.isEmpty { Text(live.text).font(.title3).frame(maxWidth: .infinity, alignment: .leading) }
                        Text(live.state == "finishing" ? "Waiting for the final words…" : "Live text may change as you speak.").font(.caption).foregroundStyle(RelayTheme.secondary)
                    }
                    if !live.problem.isEmpty { WorkflowNotice(text: live.problem) }
                    if live.state == "failed", !live.text.isEmpty {
                        Text("Incomplete transcript").font(.headline)
                        Text(live.text).foregroundStyle(RelayTheme.secondary)
                    }
                    Button("Import a saved WAV") { importingWAV = true }.buttonStyle(WorkflowSecondaryButton()).disabled(cloud.audioBusy || live.working)
                }
                if let job = cloud.audioJob, !live.working, live.state == "idle" || live.state == "completed" || live.seconds > 0 {
                    RelayCard {
                        Text(job.transcript == nil ? "Saved recording" : "Review the transcript").font(.title3.bold())
                        if job.transcript == nil {
                            Button(cloud.audioBusy ? "Transcribing…" : "Transcribe / resume") { Task { await cloud.transcribe() } }
                                .buttonStyle(WorkflowSecondaryButton()).disabled(cloud.audioBusy)
                            if cloud.audioBusy { ProgressView() }
                        } else {
                            TextField("Review transcript", text: $cloud.transcript, axis: .vertical).lineLimit(5...12).textFieldStyle(WorkflowInput()).focused($editing)
                            Text("Check names, quantities and locations.").font(.subheadline).foregroundStyle(RelayTheme.secondary)
                            Button("Use this text") { cloud.applyTranscript(); dismiss(); Task { await cloud.previewRequest() } }
                                .buttonStyle(PrimaryButton()).disabled(cloud.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Text(cloud.audioStatus).font(.caption).foregroundStyle(RelayTheme.secondary)
                    }
                }
                if !cloud.problem.isEmpty { WorkflowNotice(text: cloud.problem) }
                Text("Recording never sends a shelter request. You review and send separately.").font(.caption).foregroundStyle(RelayTheme.secondary)
            }.padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(RelayTheme.canvas).navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .fileImporter(isPresented: $importingWAV, allowedContentTypes: [.audio]) { result in
                do {
                    let source = try result.get(), copy = try VoiceRecorder.importWAV(source)
                    Task { await cloud.saveRecording(url: copy) }
                } catch { if (error as NSError).code != NSUserCancelledError { cloud.problem = error.localizedDescription } }
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { if editing { Button("Done") { editing = false } } } }
            .onDisappear { live.cancel() }
    }
}
struct LocalRequestThread: View {
    @ObservedObject var model: RelayModel
    let request: RelayMessage
    @FocusState private var editing: Bool
    @State private var text = ""
    @State private var progress = ""
    var body: some View {
        RelayCard {
            Text("Nearby replies and progress").font(.headline)
            ForEach(LocalRequestUpdate.thread(model.messages, request: request), id: \.0.id) { row, update in
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.message.originID == model.deviceID ? "You" : model.peerTitle(row.message.originID)).font(.caption.bold())
                    if let progress = update.progress { Text(progress.replacingOccurrences(of: "_", with: " ")).font(.subheadline.bold()) }
                    if !update.text.isEmpty { Text(update.text) }
                    Text(row.status(deviceID: model.deviceID)).font(.caption).foregroundStyle(RelayTheme.secondary)
                }.padding(.vertical, 6)
            }
            TextField("Reply about this request", text: $text, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder).focused($editing)
            Picker("Progress", selection: $progress) {
                Text("Reply only").tag("")
                if request.destinationID == model.deviceID {
                    Text("Accepted").tag("accepted"); Text("In progress").tag("in_progress")
                    Text("Reported completed").tag("completed"); Text("Unable to help").tag("rejected")
                } else { Text("Request cancellation").tag("cancelled") }
            }
            Button("Send via nearby relay") {
                model.sendRequestUpdate(request, text: text, progress: progress.isEmpty ? nil : progress) { text = ""; progress = "" }
            }.disabled(model.sending || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && progress.isEmpty))
            if editing { Button("Done") { editing = false } }
            Text("Device-reported updates; staff identity is unverified. A cancellation note does not recall messages already carried by other devices.").font(.caption).foregroundStyle(RelayTheme.secondary)
        }
    }
}
