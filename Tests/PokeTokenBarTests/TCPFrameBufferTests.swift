import XCTest
@testable import PokeTokenBar

final class TCPFrameBufferTests: XCTestCase {
    func testSingleFrameArrivingWhole() {
        var buffer = TCPFrameBuffer()
        let payload = Data("hello".utf8)
        XCTAssertEqual(buffer.append(TCPFrameBuffer.frame(payload)), [payload])
    }

    func testFrameSplitAcrossTwoAppends() {
        var buffer = TCPFrameBuffer()
        let framed = TCPFrameBuffer.frame(Data("hello".utf8))
        let firstHalf = Data(framed.prefix(3))
        let secondHalf = Data(framed.suffix(from: 3))
        XCTAssertTrue(buffer.append(firstHalf).isEmpty)
        XCTAssertEqual(buffer.append(secondHalf), [Data("hello".utf8)])
    }

    func testTwoFramesArrivingTogether() {
        var buffer = TCPFrameBuffer()
        var combined = TCPFrameBuffer.frame(Data("a".utf8))
        combined.append(TCPFrameBuffer.frame(Data("bb".utf8)))
        XCTAssertEqual(buffer.append(combined), [Data("a".utf8), Data("bb".utf8)])
    }

    func testEmptyPayloadRoundTrips() {
        var buffer = TCPFrameBuffer()
        XCTAssertEqual(buffer.append(TCPFrameBuffer.frame(Data())), [Data()])
    }

    /// 길이 프리픽스(4바이트)는 전부 도착했지만 페이로드는 아직 일부만 도착한 경우 — 길이를 안다고 바로
    /// 잘라내면 안 되고, 페이로드 전체가 도착할 때까지 기다려야 한다.
    func testPayloadArrivesSplitAfterCompleteLengthPrefix() {
        var buffer = TCPFrameBuffer()
        let framed = TCPFrameBuffer.frame(Data("hello".utf8))
        let prefixPlusPartialPayload = Data(framed.prefix(6))
        let remainingPayload = Data(framed.suffix(from: 6))
        XCTAssertTrue(buffer.append(prefixPlusPartialPayload).isEmpty)
        XCTAssertEqual(buffer.append(remainingPayload), [Data("hello".utf8)])
    }

    /// 길이 프리픽스(4바이트) 자체가 두 조각으로 쪼개져 도착하는 경우 — 첫 조각만으론 프레임 길이를 알 수 없다.
    func testLengthPrefixItselfArrivesSplit() {
        var buffer = TCPFrameBuffer()
        let framed = TCPFrameBuffer.frame(Data("hello".utf8))
        let firstTwoBytes = Data(framed.prefix(2))
        let remainder = Data(framed.suffix(from: 2))
        XCTAssertTrue(buffer.append(firstTwoBytes).isEmpty)
        XCTAssertEqual(buffer.append(remainder), [Data("hello".utf8)])
    }

    /// subdata(in:)/removeSubrange(_:) 앞에 이미 소비된 프레임이 있어, 버퍼 내부 인덱스가 0에서
    /// 시작하지 않는 상태에서도 다음 프레임을 올바르게 잘라내는지 확인 — 인덱스 오프셋 누락은 크래시/오염으로 이어진다.
    func testThirdFrameAfterTwoPriorFramesConsumed() {
        var buffer = TCPFrameBuffer()
        var combined = TCPFrameBuffer.frame(Data("a".utf8))
        combined.append(TCPFrameBuffer.frame(Data("bb".utf8)))
        combined.append(TCPFrameBuffer.frame(Data("ccc".utf8)))
        XCTAssertEqual(buffer.append(combined), [Data("a".utf8), Data("bb".utf8), Data("ccc".utf8)])
    }
}
