import XCTest
@testable import RelayCore

final class SpeechStreamTests: XCTestCase {
    func testPartialSegmentsReplaceAndDoNotRegressAfterFinalization() throws {
        var value = LiveTranscript()
        try value.apply(.init(type: "transcript", resultID: "b", text: "water", partial: true, start: 1))
        try value.apply(.init(type: "transcript", resultID: "a", text: "Need two", partial: false, start: 0))
        try value.apply(.init(type: "transcript", resultID: "b", text: "water packs", partial: false, start: 1))
        try value.apply(.init(type: "transcript", resultID: "b", text: "wrong late partial", partial: true, start: 1))
        XCTAssertEqual(value.text, "Need two water packs"); XCTAssertFalse(value.completed)
        try value.apply(.init(type: "error")); XCTAssertFalse(value.completed)
        try value.apply(.init(type: "complete", text: "Need two water packs."))
        XCTAssertTrue(value.completed); XCTAssertEqual(value.text, "Need two water packs.")
    }
    func testInvalidAndOversizedTranscriptIsRejected() throws {
        var value = LiveTranscript()
        XCTAssertThrowsError(try value.apply(.init(type: "transcript", resultID: "x", text: "Hi", partial: true, start: .nan)))
        XCTAssertThrowsError(try value.apply(.init(type: "complete", text: "")))
        XCTAssertThrowsError(try value.apply(.init(type: "complete", text: String(repeating: "x", count: 4097))))
    }
    func testPCMFileRoundTripAndTruncation() throws {
        let pcm = Data(repeating: 1, count: 32000)
        let wav = try PCM16WAV.encode(pcm)
        XCTAssertEqual(wav.count, 32044)
        XCTAssertEqual(try PCM16WAV.decode(wav), pcm)
        XCTAssertThrowsError(try PCM16WAV.decode(wav.dropLast()))
        XCTAssertThrowsError(try PCM16WAV.encode(Data([1])))
        var stereo = wav; stereo[22] = 2
        XCTAssertThrowsError(try PCM16WAV.decode(stereo))
    }
    func testExistingAudioJobStillDecodesAndStreamingRetainsItsID() throws {
        let old = CloudAudioJob(fileName: "test.wav", incidentID: "incident-demo", data: Data(repeating: 0, count: 32044))
        let data = try CloudCodec.encode(old)
        XCTAssertNil(try CloudCodec.decode(CloudAudioJob.self, data).source)
        let id = UUID().uuidString.lowercased()
        let stream = CloudAudioJob(fileName: "test.wav", incidentID: "incident-demo", data: Data(repeating: 0, count: 32044), id: id, source: "streaming")
        let copy = try CloudCodec.decode(CloudAudioJob.self, CloudCodec.encode(stream))
        XCTAssertEqual(copy.id, id); XCTAssertEqual(copy.source, "streaming")
    }

}
