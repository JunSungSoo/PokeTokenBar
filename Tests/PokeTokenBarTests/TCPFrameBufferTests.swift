import XCTest
@testable import PokeTokenBar

final class TCPFrameBufferTests: XCTestCase {
    func testSingleFrameArrivingWhole() throws {
        var buffer = TCPFrameBuffer()
        let payload = Data("hello".utf8)
        XCTAssertEqual(try buffer.append(TCPFrameBuffer.frame(payload)), [payload])
    }

    func testFrameSplitAcrossTwoAppends() throws {
        var buffer = TCPFrameBuffer()
        let framed = TCPFrameBuffer.frame(Data("hello".utf8))
        let firstHalf = Data(framed.prefix(3))
        let secondHalf = Data(framed.suffix(from: 3))
        XCTAssertTrue(try buffer.append(firstHalf).isEmpty)
        XCTAssertEqual(try buffer.append(secondHalf), [Data("hello".utf8)])
    }

    func testTwoFramesArrivingTogether() throws {
        var buffer = TCPFrameBuffer()
        var combined = TCPFrameBuffer.frame(Data("a".utf8))
        combined.append(TCPFrameBuffer.frame(Data("bb".utf8)))
        XCTAssertEqual(try buffer.append(combined), [Data("a".utf8), Data("bb".utf8)])
    }

    func testEmptyPayloadRoundTrips() throws {
        var buffer = TCPFrameBuffer()
        XCTAssertEqual(try buffer.append(TCPFrameBuffer.frame(Data())), [Data()])
    }

    /// 길이 프리픽스(4바이트)는 전부 도착했지만 페이로드는 아직 일부만 도착한 경우 — 길이를 안다고 바로
    /// 잘라내면 안 되고, 페이로드 전체가 도착할 때까지 기다려야 한다.
    func testPayloadArrivesSplitAfterCompleteLengthPrefix() throws {
        var buffer = TCPFrameBuffer()
        let framed = TCPFrameBuffer.frame(Data("hello".utf8))
        let prefixPlusPartialPayload = Data(framed.prefix(6))
        let remainingPayload = Data(framed.suffix(from: 6))
        XCTAssertTrue(try buffer.append(prefixPlusPartialPayload).isEmpty)
        XCTAssertEqual(try buffer.append(remainingPayload), [Data("hello".utf8)])
    }

    /// 길이 프리픽스(4바이트) 자체가 두 조각으로 쪼개져 도착하는 경우 — 첫 조각만으론 프레임 길이를 알 수 없다.
    func testLengthPrefixItselfArrivesSplit() throws {
        var buffer = TCPFrameBuffer()
        let framed = TCPFrameBuffer.frame(Data("hello".utf8))
        let firstTwoBytes = Data(framed.prefix(2))
        let remainder = Data(framed.suffix(from: 2))
        XCTAssertTrue(try buffer.append(firstTwoBytes).isEmpty)
        XCTAssertEqual(try buffer.append(remainder), [Data("hello".utf8)])
    }

    /// subdata(in:)/removeSubrange(_:) 앞에 이미 소비된 프레임이 있어, 버퍼 내부 인덱스가 0에서
    /// 시작하지 않는 상태에서도 다음 프레임을 올바르게 잘라내는지 확인 — 인덱스 오프셋 누락은 크래시/오염으로 이어진다.
    func testThirdFrameAfterTwoPriorFramesConsumed() throws {
        var buffer = TCPFrameBuffer()
        var combined = TCPFrameBuffer.frame(Data("a".utf8))
        combined.append(TCPFrameBuffer.frame(Data("bb".utf8)))
        combined.append(TCPFrameBuffer.frame(Data("ccc".utf8)))
        XCTAssertEqual(try buffer.append(combined), [Data("a".utf8), Data("bb".utf8), Data("ccc".utf8)])
    }

    /// R23 — 조작된 길이 프리픽스(상한을 넘는 값)는 무제한 버퍼 증가로 이어지지 않고 던져야 한다.
    /// 상대는 사용자가 직접 입력한 임의 IP:포트라 이 길이 값을 신뢰할 수 없다.
    func testLengthExceedingCapThrows() {
        var buffer = TCPFrameBuffer()
        var oversizedLength = UInt32(TCPFrameBuffer.maxFrameLength + 1).bigEndian
        let malformedPrefix = Data(bytes: &oversizedLength, count: 4)
        XCTAssertThrowsError(try buffer.append(malformedPrefix)) { error in
            XCTAssertEqual(error as? TCPFrameBuffer.FrameError,
                            .frameTooLarge(length: TCPFrameBuffer.maxFrameLength + 1, limit: TCPFrameBuffer.maxFrameLength))
        }
    }

    /// 상한 안의 길이는 정상적으로 통과해야 한다 — R23 의 가드가 과하게 좁지 않은지 확인.
    func testLengthAtCapIsAccepted() throws {
        var buffer = TCPFrameBuffer()
        let payload = Data(repeating: 0, count: TCPFrameBuffer.maxFrameLength)
        XCTAssertEqual(try buffer.append(TCPFrameBuffer.frame(payload)), [payload])
    }
}
