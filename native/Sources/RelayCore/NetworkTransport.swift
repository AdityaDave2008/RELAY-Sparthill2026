import Foundation
import Network

public struct TransportPeer: Identifiable {
    public let id: String
    public let details: String
}
/// Network.framework TCP + Bonjour; no cloud, no third-party networking library.
/// Call only on `queue`. UI marshals calls onto it and snapshots back to main.
public final class NetworkTransport {
    public static let serviceType = "_relay-poc._tcp"
    public let queue: DispatchQueue
    private let engine: RelayEngine
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var timer: DispatchSourceTimer?
    private var links: [String: Link] = [:]
    private var discovered: [String: NWEndpoint] = [:]
    private var nextAttempt: [String: Date] = [:]
    public private(set) var paths: [String: String] = [:]
    public private(set) var running = false
    public var onDiscovery: (([TransportPeer]) -> Void)?
    public var onState: ((String) -> Void)?
    public var listeningPort: UInt16? { listener?.port?.rawValue }
    public var interruptNextMessage = false
    private final class Link {
        let connection: NWConnection
        var decoder = FrameDecoder()
        let endpointKey: String?
        let created = Date()
        var lastReceived = Date()
        var ready = false
        init(_ connection: NWConnection, endpointKey: String?) { self.connection = connection; self.endpointKey = endpointKey }
    }
    public init(engine: RelayEngine, queue: DispatchQueue) {
        self.engine = engine; self.queue = queue
        engine.send = { [weak self] id, packet in self?.send(packet, on: id) }
        engine.disconnect = { [weak self] id in self?.close(id) }
    }
    public static func parameters() -> NWParameters {
        let p = NWParameters.tcp
        p.includePeerToPeer = true
        p.prohibitedInterfaceTypes = [.cellular]
        // No requiredInterfaceType: .wifi would not prove AWDL and can overconstrain paths.
        return p
    }
    public func start(discovery: Bool = true) {
        guard !running else { return }
        running = true
        do {
            let l = try NWListener(using: Self.parameters())
            listener = l
            if discovery { l.service = NWListener.Service(name: engine.store.deviceID, type: Self.serviceType) }
            l.stateUpdateHandler = { [weak self, weak l] state in
                guard let self, let l, self.listener === l, self.running else { return }
                self.engine.event("LISTENER \(state)"); self.onState?("Listener: \(state)")
                if case .failed = state { self.stop() }
            }
            l.serviceRegistrationUpdateHandler = { [weak self] change in self?.engine.event("BONJOUR_ADVERTISEMENT \(change)") }
            l.newConnectionHandler = { [weak self] connection in
                guard let self, self.running else { connection.cancel(); return }
                self.attach(connection, endpointKey: nil)
            }
            l.start(queue: queue)
            if discovery {
                let b = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: Self.parameters())
                browser = b
                b.stateUpdateHandler = { [weak self, weak b] state in
                    guard let self, let b, self.browser === b, self.running else { return }
                    self.engine.event("BROWSER \(state)"); self.onState?("Browser: \(state)")
                }
                b.browseResultsChangedHandler = { [weak self] results, _ in self?.update(results) }
                b.start(queue: queue)
            }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 1, repeating: 1)
            t.setEventHandler { [weak self] in
                guard let self else { return }
                self.engine.tick()
                for (id, link) in self.links {
                    if (!link.ready && Date().timeIntervalSince(link.created) > 20) || Date().timeIntervalSince(link.lastReceived) > 30 {
                        self.engine.event("CONNECTION_TIMEOUT session=\(id)"); self.close(id)
                    }
                }
                self.connectDiscovered()
            }
            timer = t; t.resume()
            engine.event("TRANSPORT_STARTED includePeerToPeer=true cellular=prohibited path=UNVERIFIED plaintext=true discovery=\(discovery)")
        } catch { engine.event("LISTENER_START_FAILED \(error)"); stop() }
    }
    public func stop() {
        running = false; timer?.cancel(); timer = nil
        browser?.cancel(); browser = nil; listener?.cancel(); listener = nil
        for id in Array(links.keys) { close(id) }
        discovered.removeAll(); onDiscovery?([]); onState?("Stopped")
        engine.event("TRANSPORT_STOPPED")
    }
    private func update(_ results: Set<NWBrowser.Result>) {
        guard running else { return }
        var peers: [TransportPeer] = []
        discovered.removeAll()
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint, name != engine.store.deviceID else { continue }
            let key = String(describing: result.endpoint)
            discovered[key] = result.endpoint
            let interfaces = result.interfaces.map { "\($0.name):\($0.type)" }.joined(separator: ",")
            peers.append(TransportPeer(id: key, details: "\(name) interfaces=[\(interfaces)]"))
        }
        onDiscovery?(peers.sorted { $0.id < $1.id })
        engine.event("DISCOVERY count=\(peers.count) peers=\(peers.map(\.details))")
        connectDiscovered()
    }
    private func connectDiscovered() {
        guard running else { return }
        for (key, endpoint) in discovered {
            guard case let .service(name, _, _, _) = endpoint else { continue }
            // One dialer per pair. This avoids symmetric duplicate connections, while both listen/browse.
            guard engine.store.deviceID < name, Date() >= (nextAttempt[key] ?? .distantPast),
                  !links.values.contains(where: { $0.endpointKey == key }) else { continue }
            nextAttempt[key] = Date().addingTimeInterval(10)
            attach(NWConnection(to: endpoint, using: Self.parameters()), endpointKey: key)
        }
    }
    /// Only for same-host/control tests. UI always uses Bonjour discovery.
    public func connectForControl(host: String = "127.0.0.1", port: UInt16) {
        attach(NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: Self.parameters()), endpointKey: nil)
    }
    private func attach(_ connection: NWConnection, endpointKey: String?) {
        guard running, links.count < 8 else { connection.cancel(); return }
        let id = UUID().uuidString.lowercased()
        let link = Link(connection, endpointKey: endpointKey); links[id] = link
        connection.stateUpdateHandler = { [weak self, weak link] state in
            guard let self, let link, self.links[id] === link else { return }
            self.engine.event("CONNECTION_STATE session=\(id) endpoint=\(connection.endpoint) state=\(state)")
            switch state {
            case .ready:
                guard !link.ready else { return }; link.ready = true
                self.describePath(connection.currentPath, id: id)
                self.engine.connected(id); self.receive(id)
            case .failed, .cancelled: self.close(id)
            default: break
            }
        }
        connection.pathUpdateHandler = { [weak self] path in self?.describePath(path, id: id) }
        connection.start(queue: queue)
    }
    private func describePath(_ path: NWPath?, id: String) {
        guard links[id] != nil, let path else { return }
        let interfaces = path.availableInterfaces.map { "\($0.name):\($0.type)" }.joined(separator: ",")
        let line = "status=\(path.status) interfaces=[\(interfaces)] wifi=\(path.usesInterfaceType(.wifi)) cellular=\(path.usesInterfaceType(.cellular)) expensive=\(path.isExpensive) local=\(String(describing: path.localEndpoint)) remote=\(String(describing: path.remoteEndpoint)); infrastructure_independence=UNVERIFIED"
        paths[id] = line; engine.event("PATH session=\(id) \(line)")
    }
    private func receive(_ id: String) {
        guard let link = links[id] else { return }
        link.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak link] data, _, complete, error in
            guard let self, let link, self.links[id] === link else { return }
            do {
                if let data, !data.isEmpty {
                    link.lastReceived = Date()
                    for packet in try link.decoder.append(data) {
                        guard self.links[id] != nil else { break }
                        self.engine.receive(packet, from: id)
                    }
                }
                if complete || error != nil {
                    self.engine.event("STREAM_END session=\(id) partial=\(link.decoder.hasPartialFrame) error=\(String(describing: error))")
                    self.close(id)
                } else { self.receive(id) }
            } catch { self.engine.event("FRAME_REJECTED session=\(id) \(error)"); self.close(id) }
        }
    }
    private func send(_ packet: WirePacket, on id: String) {
        guard let link = links[id] else { return }
        do {
            let data = try FrameDecoder.frame(packet)
            if interruptNextMessage && packet.kind == .message {
                interruptNextMessage = false
                engine.event("FAULT_INJECTION partial_frame id=\(packet.message!.id) bytes=\(data.count / 2)")
                link.connection.send(content: Data(data.prefix(data.count / 2)), completion: .contentProcessed { [weak self] _ in self?.close(id) })
                return
            }
            link.connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error { self?.engine.event("SEND_ERROR session=\(id) \(error)"); self?.close(id) }
                // contentProcessed is NOT a durability acknowledgement.
            })
        } catch { engine.event("ENCODE_FAILED \(error)"); close(id) }
    }
    private func close(_ id: String) {
        guard let link = links.removeValue(forKey: id) else { return }
        if link.decoder.hasPartialFrame { engine.event("PARTIAL_FRAME_DISCARDED session=\(id)") }
        link.connection.stateUpdateHandler = nil; link.connection.pathUpdateHandler = nil
        link.connection.cancel(); paths.removeValue(forKey: id)
        engine.disconnected(id)
    }
}
