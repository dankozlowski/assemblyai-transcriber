import AVFoundation

final class SampleRateConverter {

    static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!

    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    func convert(_ inputBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if converter == nil || inputBuffer.format != inputFormat {
            inputFormat = inputBuffer.format
            converter = AVAudioConverter(from: inputBuffer.format, to: Self.outputFormat)
        }
        guard let converter else { return nil }

        let ratio = Self.outputFormat.sampleRate / inputBuffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(
            ceil(Double(inputBuffer.frameLength) * ratio)
        )
        guard outputFrameCapacity > 0 else { return nil }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: Self.outputFormat,
            frameCapacity: outputFrameCapacity
        ) else { return nil }

        var error: NSError?
        var inputConsumed = false

        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputConsumed = true
            return inputBuffer
        }

        guard status != .error, error == nil, outputBuffer.frameLength > 0 else {
            return nil
        }
        return outputBuffer
    }
}

extension AVAudioPCMBuffer {
    var int16Data: Data? {
        guard format.commonFormat == .pcmFormatInt16,
              let channelData = int16ChannelData else { return nil }
        let byteCount = Int(frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: channelData[0], count: byteCount)
    }
}
