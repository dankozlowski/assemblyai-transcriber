import Foundation

final class MixingBuffer: @unchecked Sendable {
    let targetFrameCount: Int

    private let lock = NSLock()
    private var systemFrames: [Int16] = []
    private var micFrames: [Int16] = []

    init(targetFrameCount: Int) {
        self.targetFrameCount = targetFrameCount
    }

    func addSystemFrames(_ frames: [Int16]) {
        lock.withLock { systemFrames.append(contentsOf: frames) }
    }

    func addMicFrames(_ frames: [Int16]) {
        lock.withLock { micFrames.append(contentsOf: frames) }
    }

    func drainIfReady() -> Data? {
        lock.withLock {
            let available = max(systemFrames.count, micFrames.count)
            guard available >= targetFrameCount else { return nil }

            let count = targetFrameCount
            var mixed = [Int16](repeating: 0, count: count)

            for i in 0..<count {
                let sys: Int32 = i < systemFrames.count ? Int32(systemFrames[i]) : 0
                let mic: Int32 = i < micFrames.count ? Int32(micFrames[i]) : 0
                mixed[i] = Int16(clamping: sys + mic)
            }

            if systemFrames.count >= count {
                systemFrames.removeFirst(count)
            } else {
                systemFrames.removeAll()
            }
            if micFrames.count >= count {
                micFrames.removeFirst(count)
            } else {
                micFrames.removeAll()
            }

            return mixed.withUnsafeBytes { Data($0) }
        }
    }

    func reset() {
        lock.withLock {
            systemFrames.removeAll()
            micFrames.removeAll()
        }
    }
}
