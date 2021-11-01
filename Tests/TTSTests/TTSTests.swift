import XCTest
import AudioSwitchboard
import Combine
@testable import TTS


var switchBoard = AudioSwitchboard()
final class TTSTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()
    let tts = TTS(AppleTTS(audioSwitchBoard: switchBoard))
    func testFinished() {
        let expectation = XCTestExpectation(description: "testFinished")
        let u = TTSUtterance.init("Hej", voice: TTSVoice.init(locale: Locale(identifier: "sv-SE")))
        var statuses:[TTSUtteranceStatus] = [.none,.queued,.preparing,.speaking,.finished]
        u.statusPublisher.sink { status in
            statuses.removeAll { $0 == status }
            if status == .finished {
                XCTAssert(statuses.count == 0)
                expectation.fulfill()
            }
        }.store(in: &cancellables)
        tts.play(u)
        wait(for: [expectation], timeout: 20.0)
    }
    func testFailure() {
        let expectation = XCTestExpectation(description: "testFailure")
        let u = TTSUtterance.init("Hej", voice: TTSVoice.init(locale: Locale(identifier: "hr-HR")))
        var statuses:[TTSUtteranceStatus] = [.none,.queued,.preparing,.failed]
        u.failurePublisher.sink { error in
            expectation.fulfill()
            XCTAssert(statuses.count == 0)
        }.store(in: &cancellables)
        
        u.statusPublisher.sink { status in
            statuses.removeAll { $0 == status }
        }.store(in: &cancellables)
        tts.play(u)
        wait(for: [expectation], timeout: 20.0)
    }
    func testCancelled() {
        let expectation = XCTestExpectation(description: "testCancelled")
        let tts = TTS(AppleTTS(audioSwitchBoard: switchBoard))
        let u = TTSUtterance.init("Hej", voice: TTSVoice.init(locale: Locale(identifier: "sv-SE")))
        var statuses:[TTSUtteranceStatus] = [.none,.queued,.preparing,.speaking,.cancelled]
        u.statusPublisher.sink { status in
            statuses.removeAll { $0 == status }
            if status == .speaking {
                tts.cancel(u)
            }
            if status == .cancelled {
                XCTAssert(statuses.count == 0)
                expectation.fulfill()
            }
        }.store(in: &cancellables)
        tts.play(u)
        wait(for: [expectation], timeout: 20.0)
    }
    func testWordBoundary() {
        let expectation = XCTestExpectation(description: "testCancelled")
        let tts = TTS(AppleTTS(audioSwitchBoard: switchBoard))
        let string = "Hello world"
        let u = TTSUtterance.init(string, voice: TTSVoice.init(locale: Locale(identifier: "en-US")))
        var words = string.split(separator: " ").map { String($0) }
        u.wordBoundaryPublisher.sink { boundary in
            XCTAssert(string[boundary.range] == boundary.string)
            words.removeAll { $0 == boundary.string }
        }.store(in: &cancellables)
        u.statusPublisher.sink { status in
            if status == .finished {
                XCTAssert(words.count == 0)
                expectation.fulfill()
            }
        }.store(in: &cancellables)
        
        tts.play(u)
        wait(for: [expectation], timeout: 20.0)
    }
    func testAppleSupport() {
        let tts = AppleTTS(audioSwitchBoard: switchBoard)
        XCTAssertTrue(tts.hasSupportFor(locale: Locale(identifier: "sv-SE")))
        XCTAssertTrue(tts.hasSupportFor(locale: Locale(identifier: "sv")))
        XCTAssertFalse(tts.hasSupportFor(locale: Locale(identifier: "")))
        XCTAssertFalse(tts.hasSupportFor(locale: Locale(identifier: "hr-HR")))
    }
}
