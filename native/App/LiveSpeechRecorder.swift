import AVFoundation
import SwiftUI
import RelayCore

struct LiveSpeechContext {
    let baseURL: URL
    let token: String
    let subject: String
    let incident: String
    let scope: String
    let generation: UUID
}

@MainActor final class LiveSpeechRecorder: ObservableObject {
    @Published var state = "idle"
    @Published var text = ""
    @Published var seconds: Double = 0
    @Published var problem = ""
    var working: Bool { ["connecting", "recording", "finishing"].contains(state) }
    var recording: Bool { state == "recording" }
    private var engine: AVAudioEngine?
    private var socket: SpeechStreamClient?
    private var context: LiveSpeechContext?
    private weak var cloud: CloudModel?
    private var sender: Task<Void, Never>?
    private var receiver: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var chunks: AsyncStream<Data>.Continuation?
    private var pcm = Data()
    private var pending = Data()
    private var transcript = LiveTranscript()
    private var generation = UUID()
    private var savedURL: URL?

    func start(cloud: CloudModel) async {
        guard !working, !cloud.audioBusy else { return }
        let run = UUID(); generation = run; context = nil; socket = nil
        self.cloud = cloud; state = "connecting"; cloud.audioBusy = true
        text = ""; problem = ""; seconds = 0; pcm = Data(); pending = Data(); transcript = LiveTranscript(); savedURL = nil
        do {
            let allowed: Bool
            #if os(iOS)
            allowed = await AVAudioApplication.requestRecordPermission()
            #else
            allowed = await AVCaptureDevice.requestAccess(for: .audio)
            #endif
            guard generation == run, state == "connecting" else { return }
            guard allowed else { throw RelayError.invalid("Allow microphone access to record. You can still type a request.") }
            context = try await cloud.liveSpeechContext()
            guard generation == run, state == "connecting", let context else { return }
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let engine = AVAudioEngine(), input = engine.inputNode
            let source = input.outputFormat(forBus: 0)
            guard source.sampleRate > 0, source.channelCount > 0,
                  let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: source, to: target) else { throw RelayError.invalid("Microphone audio format is unavailable") }
            self.engine = engine
            input.installTap(onBus: 0, bufferSize: 2048, format: source) { [weak self] buffer, _ in
                let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / source.sampleRate) + 32)
                guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
                var supplied = false, error: NSError?
                let status = converter.convert(to: converted, error: &error) { _, state in
                    if supplied { state.pointee = .noDataNow; return nil }
                    supplied = true; state.pointee = .haveData; return buffer
                }
                if status == .error || error != nil {
                    Task { @MainActor in guard let self, self.generation == run else { return }; await self.fail("Microphone conversion failed. Try recording again.") }; return
                }
                guard converted.frameLength > 0, let samples = converted.int16ChannelData?[0] else { return }
                let data = Data(bytes: samples, count: Int(converted.frameLength) * 2)
                Task { @MainActor in guard self?.generation == run else { return }; self?.capture(data) }
            }
            engine.prepare()
            let client = SpeechStreamClient(); socket = client
            let ready = try await client.connect(baseURL: context.baseURL, token: context.token)
            guard generation == run, state == "connecting" else { await client.cancel(); return }
            guard ready.type == "ready" else { throw RelayError.invalid("Start a new recording session") }
            let stream = AsyncStream<Data>(bufferingPolicy: .bufferingOldest(32)) { self.chunks = $0 }
            sender = Task { [weak self] in
                do {
                    for await chunk in stream { try Task.checkCancellation(); try await client.send(chunk) }
                    if !Task.isCancelled { try await client.finish() }
                } catch { if !Task.isCancelled, self?.generation == run { await self?.fail("Connection interrupted. The recording is retained for retry.") } }
            }
            receiver = Task { [weak self] in
                do {
                    while !Task.isCancelled {
                        let event = try await client.next()
                        guard let self, self.generation == run else { return }
                        if event.type == "error" { await self.fail(event.message ?? "Live transcription was interrupted."); return }
                        try self.transcript.apply(event); self.text = self.transcript.text
                        if event.type == "complete" { try await self.complete(identifier: client.id); return }
                    }
                } catch { if !Task.isCancelled, self?.generation == run { await self?.fail(error.localizedDescription) } }
            }
            try engine.start(); state = "recording"
            deadline = Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, self?.generation == run else { return }; self?.stop()
            }
        } catch { if generation == run { await fail(error.localizedDescription) } }
    }

    private func capture(_ data: Data) {
        guard recording else { return }
        let remaining = 1_920_000 - pcm.count
        let accepted = Data(data.prefix(max(0, remaining)))
        pcm.append(accepted); pending.append(accepted); seconds = Double(pcm.count) / 32000
        while pending.count >= 3200 {
            let chunk = Data(pending.prefix(3200)); pending.removeFirst(3200)
            if case .dropped = chunks?.yield(chunk) {
                Task { await fail("The connection cannot keep up. Your recording is retained for retry.") }; return
            }
        }
        if pcm.count >= 1_920_000 { stop() }
    }
    func stop() {
        guard recording else { return }
        state = "finishing"; stopMicrophone()
        deadline?.cancel()
        let run = generation
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.generation == run, self.working else { return }
            await self.fail("Transcription did not finish. The recording is retained for retry.")
        }
        if !pending.isEmpty {
            if case .dropped = chunks?.yield(pending) { Task { await fail("Connection interrupted while finishing. The recording is retained.") }; return }
            pending = Data()
        }
        chunks?.finish(); chunks = nil
        do { savedURL = try saveWAV() }
        catch { Task { await fail("Could not save the recording on this device.") } }
    }
    func cancel() {
        guard working else { return }
        Task { await fail("Recording stopped. Any captured audio remains available for retry.") }
    }
    private func saveWAV() throws -> URL? {
        guard !pcm.isEmpty else { return nil }
        if let savedURL { return savedURL }
        let url = try VoiceRecorder.folder().appendingPathComponent((socket?.id ?? UUID().uuidString) + ".wav")
        try PCM16WAV.encode(pcm).write(to: url, options: .atomic); return url
    }
    private func stopMicrophone() {
        if let engine { engine.inputNode.removeTap(onBus: 0); engine.stop() }; engine = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
    }
    private func complete(identifier: String) async throws {
        guard working, let context, let cloud, transcript.completed else { return }
        stopMicrophone()
        guard let url = try saveWAV() else { throw RelayError.invalid("No recording was saved") }
        try await cloud.retainLiveSpeech(context: context, identifier: identifier, text: text, url: url)
        generation = UUID(); state = "completed"; cloud.audioBusy = false; deadline?.cancel(); deadline = nil
        sender?.cancel(); sender = nil; receiver = nil
        await socket?.cancel(); socket = nil
    }
    private func fail(_ message: String) async {
        guard working else { return }
        generation = UUID(); state = "failed"; problem = message
        stopMicrophone(); chunks?.finish(); chunks = nil
        sender?.cancel(); sender = nil; receiver?.cancel(); receiver = nil; deadline?.cancel(); deadline = nil
        if let cloud, let context, let identifier = socket?.id, let url = try? saveWAV() {
            try? await cloud.retainLiveSpeech(context: context, identifier: identifier, text: nil, url: url)
        }
        cloud?.audioBusy = false
        await socket?.cancel(); socket = nil
    }
}
