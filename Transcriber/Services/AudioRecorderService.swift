import AVFoundation

final class AudioRecorderService {

    private var audioFile: AVAudioFile?
    private let inputFormat: AVAudioFormat
    let outputURL: URL

    init(fileStem: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.outputURL = dir.appendingPathComponent("\(fileStem).wav")

        // 16kHz mono Int16 — matches exactly what AudioCaptureManager produces
        self.inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!

        // Write as linear PCM WAV — no encoding, guaranteed to work with Int16
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        self.audioFile = try? AVAudioFile(
            forWriting: outputURL,
            settings: outputSettings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
    }

    func write(_ pcmData: Data) {
        guard let audioFile else { return }

        let frameCount = AVAudioFrameCount(pcmData.count / MemoryLayout<Int16>.size)
        guard frameCount > 0 else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        pcmData.withUnsafeBytes { rawBuffer in
            guard let src = rawBuffer.baseAddress else { return }
            memcpy(buffer.mutableAudioBufferList.pointee.mBuffers.mData!, src, pcmData.count)
        }

        try? audioFile.write(from: buffer)
    }

    func close() {
        audioFile = nil
    }
}
