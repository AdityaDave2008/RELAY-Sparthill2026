import Foundation
import RelayCore

// JSON-lines process harness for real TCP loopback controls. NOT wireless evidence.
let arguments = CommandLine.arguments
func argument(_ key: String) -> String? {
    guard let index = arguments.firstIndex(of: key), arguments.count > index + 1 else { return nil }
    return arguments[index + 1]
}
func emit(_ fields: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
          let line = String(data: data, encoding: .utf8) else { return }
    print(line); fflush(stdout)
}
guard let path = argument("--db"), let roleString = argument("--role"),
      let role = ["A": TestRole.sender, "B": .relay, "C": .receiver][roleString] else {
    fputs("Usage: RelayLab --db PATH --role A|B|C [--id UUID]\nJSON command input; see scripts/tcp_experiment.py. Same-host control only.\n", stderr)
    exit(2)
}
let queue = DispatchQueue(label: "org.relay.lab")
do {
    let store = try RelayStore.open(path: path, deviceID: argument("--id"))
    let engine = RelayEngine(store: store, role: role)
    let transport = NetworkTransport(engine: engine, queue: queue)
    engine.onEvent = { emit(["event": $0]) }
    queue.async { transport.start(discovery: false) }
    DispatchQueue.global().async {
        while let line = readLine() {
            queue.async {
                var request = "unknown"
                do {
                    guard let cmd = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                          let operation = cmd["op"] as? String else { throw RelayError.invalid("command") }
                    request = cmd["request"] as? String ?? "unknown"
                    var result: [String: Any] = ["request": request, "ok": true]
                    switch operation {
                    case "snapshot":
                        result["device_id"] = store.deviceID
                        result["port"] = transport.listeningPort.map(Int.init) ?? 0
                        result["connected"] = engine.connectedPeers.values.map(\.deviceID)
                        result["messages"] = try store.summaries().map { row -> [String: Any] in
                            ["id": row.id, "type": row.message.messageType.rawValue,
                             "origin": row.message.originID, "destination": row.message.destinationID,
                             "hops": row.message.hopCount, "attempts": row.attempts,
                             "accepted_by": row.acceptedBy, "final_receipt": row.finalReceiptID ?? "",
                             "original": row.message.payload.originalMessageID ?? "", "status": row.status(deviceID: store.deviceID)]
                        }
                    case "compose":
                        guard let text = cmd["text"] as? String, let destination = cmd["destination"] as? String else { throw RelayError.invalid("compose arguments") }
                        result["message_id"] = try engine.compose(text: text, destinationID: destination).id
                    case "connect":
                        guard let port = cmd["port"] as? Int, let value = UInt16(exactly: port), value > 0 else { throw RelayError.invalid("port") }
                        transport.connectForControl(port: value)
                    case "interrupt": transport.interruptNextMessage = true
                    case "retransmit":
                        guard let id = cmd["id"] as? String else { throw RelayError.invalid("id") }
                        try engine.retransmitForTest(id)
                    case "stop": transport.stop()
                    case "start": transport.start(discovery: false)
                    case "quit": transport.stop(); emit(result); exit(0)
                    default: throw RelayError.invalid("unknown operation")
                    }
                    emit(result)
                } catch { emit(["request": request, "ok": false, "error": String(describing: error)]) }
            }
        }
        queue.async { transport.stop(); exit(0) }
    }
    dispatchMain()
} catch { emit(["fatal": String(describing: error)]); exit(1) }
