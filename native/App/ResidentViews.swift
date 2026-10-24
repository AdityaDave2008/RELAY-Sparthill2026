import SwiftUI
import RelayCore
import PhotosUI
import ImageIO

struct ResidentAvatar: View {
    let data: Data?
    var size: CGFloat = 96
    var body: some View {
        Group {
            if let data, let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Image(systemName: "person.fill").resizable().scaledToFit().padding(size * 0.25).foregroundStyle(RelayTheme.secondary)
                    .background(RelayTheme.incoming)
            }
        }.frame(width: size, height: size).clipShape(Circle()).overlay(Circle().strokeBorder(.black.opacity(0.15)))
            .accessibilityLabel(data == nil ? "No profile photo" : "Profile photo")
    }
}

struct ResidentWelcomeView: View {
    @EnvironmentObject private var cloud: CloudModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if !cloud.residentSetup.profileOffered {
                ResidentDetailsEditor(firstRun: true) { }
            } else {
                ResidentGuideView(firstRun: true) { dismiss() }
            }
        }.interactiveDismissDisabled()
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 650)
        #endif
    }
}

struct ResidentDetailsEditor: View {
    @EnvironmentObject private var cloud: CloudModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ResidentDetailsDraft()
    @State private var validationProblem = ""
    @State private var clearing = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var photoLoading = false
    @FocusState private var editing: Bool
    var firstRun = false
    var finished: (() -> Void)? = nil
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        if firstRun { Text("WELCOME TO RELAY").font(.caption.bold()).foregroundStyle(RelayTheme.accent) }
                        Text(firstRun ? "A little about you" : "Personal details").font(.largeTitle.bold())
                        Text("A name, preferred language and relevant support details can help dispatchers understand who needs help and how to respond. Choose what to share when reviewing each request.").foregroundStyle(RelayTheme.secondary)
                        Text("Display name and preferred language are required to save a profile. Health information and your photo are optional.").font(.subheadline)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Private on this device", systemImage: "lock").font(.headline)
                        Text("Your profile and photo are saved on this device. Request review lets you share selected text details with your shelter. The photo stays local. Attached profile fields are not used by AI.").font(.subheadline)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RelayTheme.incoming, in: RoundedRectangle(cornerRadius: 12))
                    if cloud.residentContextID == nil {
                        if cloud.residentDetailsProblem.isEmpty { ProgressView("Loading your profile…") }
                        else {
                            WorkflowNotice(text: cloud.residentDetailsProblem)
                            Button("Retry loading details") { Task { await cloud.loadResidentContext(force: true) } }
                        }
                    }
                    else if !cloud.residentDetailsAvailable {
                        WorkflowNotice(text: cloud.residentDetailsProblem)
                        Button("Retry loading details") { Task { await cloud.loadResidentContext(force: true) } }
                    } else {
                        HStack(spacing: 20) {
                            ResidentAvatar(data: draft.photoJPEG)
                            VStack(alignment: .leading, spacing: 8) {
                                PhotosPicker(selection: $photoSelection, matching: .images, preferredItemEncoding: .compatible) {
                                    Text(photoLoading ? "Preparing photo…" : draft.photoJPEG == nil ? "Add profile photo" : "Change photo").font(.headline)
                                }.disabled(photoLoading).accessibilityIdentifier("chooseResidentPhoto")
                                if draft.photoJPEG != nil { Button("Remove photo") { draft.photoJPEG = nil; photoSelection = nil }.font(.caption).disabled(photoLoading) }
                                Text("Optional · stays on this device").font(.caption).foregroundStyle(RelayTheme.secondary)
                            }
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            Text("About you").font(.title2.bold())
                            field("Display name *", placeholder: "What should staff call you?", value: $draft.name, id: "residentName")
                            HStack {
                                Text("Preferred language *").font(.headline)
                                Spacer()
                                Picker("Preferred language", selection: $draft.preferredLanguage) {
                                    Text("Choose").tag("")
                                    ForEach(ResidentDetails.languages, id: \.self) { Text($0).tag($0) }
                                }.labelsHidden().accessibilityIdentifier("residentLanguage")
                            }
                            field("Age (years)", placeholder: "Optional", value: $draft.age, id: "residentAge", numeric: true)
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: 14) { heightField; weightField }
                                VStack(alignment: .leading, spacing: 14) { heightField; weightField }
                            }
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Health & support").font(.title2.bold())
                            HStack {
                                Text("Blood group").font(.headline)
                                Spacer()
                                Picker("Blood group", selection: $draft.bloodGroup) {
                                    ForEach(ResidentDetails.bloodGroups, id: \.self) { value in Text(value.isEmpty ? "Not sure / skip" : value).tag(value) }
                                }.labelsHidden().accessibilityIdentifier("residentBloodGroup")
                            }
                            Text("Self-reported details; leave unknown information blank.").font(.caption).foregroundStyle(RelayTheme.secondary)
                            field("Allergies", placeholder: "Anything you want to keep a note of", value: $draft.allergies, id: "residentAllergies", multiline: true)
                            field("Health conditions", placeholder: "Optional health information", value: $draft.healthConditions, id: "residentConditions", multiline: true)
                            field("Medications", placeholder: "Names, if you want to record them", value: $draft.medications, id: "residentMedications", multiline: true)
                            field("Accessibility & support needs", placeholder: "For example, mobility or communication needs", value: $draft.accessibilityNeeds, id: "residentAccessibility", multiline: true)
                        }
                    }
                    if !validationProblem.isEmpty { WorkflowNotice(text: validationProblem) }
                    if cloud.residentDetailsAvailable, !cloud.residentDetailsProblem.isEmpty { WorkflowNotice(text: cloud.residentDetailsProblem) }
                    if !firstRun, !cloud.residentDetails.isEmpty {
                        Button("Clear saved personal details", role: .destructive) { editing = false; clearing = true }
                            .frame(minHeight: 44).disabled(cloud.residentDetailsBusy).accessibilityIdentifier("clearResidentDetails")
                    }
                }.padding(24).frame(maxWidth: 660).frame(maxWidth: .infinity)
            }.background(RelayTheme.canvas).navigationTitle("")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        Divider()
                        Button(cloud.residentDetailsBusy ? "Saving…" : firstRun ? "Save and continue" : "Save details") {
                            editing = false; validationProblem = ""
                            do {
                                let value = try draft.validated(requireBasics: true)
                                Task { if await cloud.saveResidentDetails(value) { finish() } }
                            } catch { validationProblem = error.localizedDescription }
                        }.buttonStyle(PrimaryButton()).disabled(cloud.residentDetailsBusy || !cloud.residentDetailsAvailable || photoLoading)
                            .padding(.horizontal, 24).padding(.vertical, 12).accessibilityIdentifier("saveResidentDetails")
                    }.frame(maxWidth: 660).frame(maxWidth: .infinity).background(RelayTheme.canvas)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(firstRun ? "Skip for now" : "Cancel") {
                            editing = false
                            if firstRun { Task { if await cloud.completeResidentStep(profile: true) { finish() } } }
                            else { finish() }
                        }.disabled(cloud.residentDetailsBusy || (firstRun && cloud.residentContextID == nil)).accessibilityIdentifier("skipResidentDetails")
                    }
                    ToolbarItem(placement: .primaryAction) { if editing { Button("Done") { editing = false } } }
                }
                .task(id: cloud.residentContextID) { draft = ResidentDetailsDraft(cloud.residentDetails) }
                .task(id: photoSelection) {
                    guard let selection = photoSelection else { return }
                    photoLoading = true; validationProblem = ""; defer { photoLoading = false }
                    do {
                        guard let data = try await selection.loadTransferable(type: Data.self) else { throw RelayError.invalid("This photo could not be loaded.") }
                        let resized = try await Task.detached(priority: .userInitiated) { try ResidentPhoto.thumbnail(data) }.value
                        guard !Task.isCancelled else { return }; draft.photoJPEG = resized
                    } catch { if !Task.isCancelled { validationProblem = "Could not load this photo. If it is stored only in iCloud, connect to internet or choose a downloaded image." } }
                }
                .confirmationDialog("Clear your saved personal details on this device? Your existing requests will remain.", isPresented: $clearing, titleVisibility: .visible) {
                    Button("Clear personal details", role: .destructive) { if cloud.clearResidentDetails() { draft = ResidentDetailsDraft(); validationProblem = "" } }
                }
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
                #endif
        }.interactiveDismissDisabled(firstRun || cloud.residentDetailsBusy)
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 650)
        #endif
    }
    private func finish() { if let finished { finished() } else { dismiss() } }
    private var heightField: some View { field("Height (cm)", placeholder: "Optional", value: $draft.height, id: "residentHeight", numeric: true).frame(minWidth: 120) }
    private var weightField: some View { field("Weight (kg)", placeholder: "Optional", value: $draft.weight, id: "residentWeight", numeric: true).frame(minWidth: 120) }
    private func field(_ title: String, placeholder: String, value: Binding<String>, id: String, numeric: Bool = false, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            TextField(placeholder, text: value, axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 2...4 : 1...1).textFieldStyle(WorkflowInput()).focused($editing)
                .accessibilityLabel(title).accessibilityIdentifier(id)
                #if os(iOS)
                .keyboardType(numeric ? .decimalPad : .default)
                #endif
        }
    }
}

private struct ResidentGuidePage {
    let emoji: String
    let title: String
    let description: String
    let points: [String]
    static let all: [Self] = [
        .init(emoji: "📝", title: "Ask your shelter for help", description: "Choose a shelter, then describe what you need.", points: ["Pick water, food, blankets, medicines or another need. Add quantities and the number of people if you know them.", "Attach a location snapshot or type a landmark. You can send without granting GPS permission.", "Open shelter information for its address, arrival instructions and straight-line distance. Distance is not a verified travel route."]),
        .init(emoji: "🎙️", title: "Speak, then review", description: "Use your voice when typing is difficult.", points: ["Speak turns your recording into editable text. Review names, quantities and locations.", "Extract details suggests structured fields. Correct them and choose the urgency before you send.", "Speech and AI need internet. You can always type and fill in the fields yourself."]),
        .init(emoji: "📬", title: "Follow your request", description: "Open Requests for your shelter’s replies and progress.", points: ["Saved on your phone means your request is queued. A nearby relay saving a copy does not mean the shelter has it yet.", "Shelter received confirms destination receipt. Approval and supply handover are separate staff actions.", "Staff replies and inventory updates currently refresh through the cloud while the app is open."]),
        .init(emoji: "📡", title: "Keep going without internet", description: "Nearby phones can carry a request to your shelter.", points: ["Sign in and download the shelter setup once while online. Use a separate account for each resident.", "Keep Wi-Fi enabled and RELAY open. Delivery can wait until phones meet and a carrier reaches the shelter.", "Select the shelter as your destination. You do not need to select every phone along the way. Nearby chat is available in Settings."]),
        .init(emoji: "📣", title: "Stay up to date with Alerts", description: "Read announcements from dispatchers in your incident.", points: ["Open an alert to read the full notice, or tap Listen to hear it. Stop ends playback.", "Check the last refresh and expiry times. Downloaded notices remain available offline.", "New announcements and withdrawals need cloud refresh. An empty or old feed does not confirm that conditions are safe."]),
        .init(emoji: "👤", title: "Make RELAY work for you", description: "Your Settings keep the essentials within reach.", points: ["Edit your profile and photo in Settings. Name and preferred language are required to save; medical details remain optional. Review lets you share selected text details with your shelter.", "Choose larger text or high contrast. Use Done above the keyboard to finish typing. Your profile photo stays on this device.", "Reopen this walkthrough using the question-mark icon beside Ask for help, or from Settings."])
    ]
}

struct ResidentGuideView: View {
    @EnvironmentObject private var cloud: CloudModel
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    var firstRun = false
    var finished: (() -> Void)? = nil
    private var current: ResidentGuidePage { ResidentGuidePage.all[page] }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("HOW RELAY WORKS").font(.caption.bold()).foregroundStyle(RelayTheme.accent)
                        Spacer()
                        Text("\(page + 1) of \(ResidentGuidePage.all.count)").font(.caption.monospacedDigit()).foregroundStyle(RelayTheme.secondary)
                    }
                    Text(current.emoji).font(.system(size: 52)).accessibilityHidden(true)
                    Text(current.title).font(.largeTitle.bold())
                    Text(current.description).font(.title3).foregroundStyle(RelayTheme.secondary)
                    ForEach(Array(current.points.enumerated()), id: \.offset) { index, point in
                        HStack(alignment: .top, spacing: 14) {
                            Text(String(index + 1)).font(.caption.bold()).foregroundStyle(RelayTheme.accent).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(RelayTheme.accent.opacity(0.4))).accessibilityHidden(true)
                            Text(point).fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, 4)
                    }
                    if !cloud.residentDetailsProblem.isEmpty { WorkflowNotice(text: cloud.residentDetailsProblem) }
                }.padding(24).frame(maxWidth: 660).frame(maxWidth: .infinity)
            }.id(page).background(RelayTheme.canvas).navigationTitle("")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        Divider()
                        HStack(spacing: 14) {
                            if page > 0 { Button("Back") { page -= 1 }.frame(minHeight: 48).accessibilityIdentifier("guideBack") }
                            Button(page == ResidentGuidePage.all.count - 1 ? "Start using RELAY" : "Next") {
                                if page < ResidentGuidePage.all.count - 1 { page += 1 } else { complete() }
                            }.buttonStyle(PrimaryButton()).disabled(cloud.residentDetailsBusy).accessibilityIdentifier("guideNext")
                        }.padding(.horizontal, 24).padding(.vertical, 12)
                    }.frame(maxWidth: 660).frame(maxWidth: .infinity).background(RelayTheme.canvas)
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(firstRun ? "Skip tour" : "Close") { complete() }.disabled(cloud.residentDetailsBusy).accessibilityIdentifier("closeResidentGuide") } }
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }.interactiveDismissDisabled(firstRun || cloud.residentDetailsBusy)
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 650)
        #endif
    }
    private func complete() {
        Task {
            let completed: Bool
            if cloud.residentContextID == nil { completed = true }
            else { completed = await cloud.completeResidentStep(guide: true) }
            if completed {
                if let finished { finished() } else { dismiss() }
            }
        }
    }
}
