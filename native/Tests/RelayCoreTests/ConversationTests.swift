import XCTest
@testable import RelayCore

final class ConversationTests: XCTestCase {
    let a = "00000000-0000-0000-0000-00000000000a"
    let b = "00000000-0000-0000-0000-00000000000b"
    let c = "00000000-0000-0000-0000-00000000000c"
    func row(from: String, to: String, second: Double, type: MessageType = .request, receipt: String? = nil) -> StoredMessage {
        StoredMessage(message: RelayMessage(originID: from, destinationID: to, messageType: type,
            payload: Payload(text: "SYNTHETIC chat projection"), createdAt: Date(timeIntervalSince1970: second)),
            finalReceiptID: receipt, attempts: 0, acceptedBy: [], destinationAccepted: false)
    }
    func testIncomingAndOutgoingShareOneChronologicalConversation() {
        let first = row(from: a, to: b, second: 1), reply = row(from: b, to: a, second: 2), again = row(from: a, to: b, second: 3)
        let chats = RelayConversation.project([again, first, reply], deviceID: a)
        XCTAssertEqual(chats.count, 1)
        XCTAssertEqual(chats[0].peerID, b)
        XCTAssertEqual(chats[0].messages.map(\.id), [first.id, reply.id, again.id])
    }
    func testCarriedTrafficCannotLeakIntoPersonalConversation() {
        let carried = row(from: b, to: c, second: 5), personal = row(from: b, to: a, second: 1)
        let chats = RelayConversation.project([carried, personal], deviceID: a)
        XCTAssertEqual(chats.count, 1)
        XCTAssertEqual(chats[0].messages.map(\.id), [personal.id])
        XCTAssertTrue(RelayConversation.project([carried], deviceID: a).isEmpty)
    }
    func testReceiptUpdatesOriginalWithoutCreatingChatBubble() {
        let receiptID = UUID().uuidString.lowercased()
        let original = row(from: a, to: b, second: 1, receipt: receiptID)
        let envelope = row(from: b, to: a, second: 2, type: .receipt)
        let chats = RelayConversation.project([original, envelope], deviceID: a)
        XCTAssertEqual(chats[0].messages.count, 1)
        XCTAssertEqual(chats[0].latest.finalReceiptID, receiptID)
    }
    func testPeersRemainSeparateAndLatestConversationComesFirst() {
        let old = row(from: a, to: b, second: 1), recent = row(from: c, to: a, second: 10)
        let chats = RelayConversation.project([recent, old], deviceID: a)
        XCTAssertEqual(chats.map(\.peerID), [c, b])
        XCTAssertEqual(chats.map { $0.messages.count }, [1, 1])
    }
}
