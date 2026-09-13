import XCTest
@testable import Transcriber

final class MixingBufferTests: XCTestCase {
    func testDrainsWhenTargetReached() {
        let buffer = MixingBuffer(targetFrameCount: 4)
        let sysFrames: [Int16] = [100, 200, 300, 400]
        let micFrames: [Int16] = [50, 50, 50, 50]
        buffer.addSystemFrames(sysFrames)
        buffer.addMicFrames(micFrames)
        let result = buffer.drainIfReady()
        XCTAssertNotNil(result)
        let mixed = result!.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        XCTAssertEqual(mixed, [150, 250, 350, 450])
    }

    func testDoesNotDrainBelowTarget() {
        let buffer = MixingBuffer(targetFrameCount: 4)
        buffer.addSystemFrames([100, 200])
        buffer.addMicFrames([50, 50])
        XCTAssertNil(buffer.drainIfReady())
    }

    func testClampingOnOverflow() {
        let buffer = MixingBuffer(targetFrameCount: 1)
        buffer.addSystemFrames([Int16.max])
        buffer.addMicFrames([1000])
        let result = buffer.drainIfReady()!
        let mixed = result.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        XCTAssertEqual(mixed, [Int16.max])
    }

    func testDrainsWithOnlyOneSource() {
        let buffer = MixingBuffer(targetFrameCount: 2)
        buffer.addMicFrames([100, 200, 300, 400])
        let result = buffer.drainIfReady()
        XCTAssertNotNil(result)
        let mixed = result!.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        XCTAssertEqual(mixed, [100, 200])
    }
}
