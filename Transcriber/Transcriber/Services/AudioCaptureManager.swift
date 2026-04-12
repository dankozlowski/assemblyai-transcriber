import AVFoundation
import CoreMedia
import ScreenCaptureKit

enum AudioCaptureError: LocalizedError {
    case noDisplayAvailable
    case screenRecordingDenied

    case engineStartFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No display found for audio capture."
        case .screenRecordingDenied:
            return "Screen Recording permission is required to capture system audio."
        case .engineStartFailed(let error):
            return "Audio engine failed to start: \(error.localizedDescription)"
        }
    }
}

@Observable
@MainActor
final class AudioCaptureManager {

    private(set) var isCapturing = false

    private var scStream: SCStream?
    private var scOutput: SCStreamAudioOutput?
    private let engine = AVAudioEngine()

    nonisolated(unsafe) private let systemConverter = SampleRateConverter()
    nonisolated(unsafe) private let micConverter = SampleRateConverter()
    private let mixingBuffer = MixingBuffer(targetFrameCount: 1600) // 100ms at 16kHz

    private var continuation: AsyncStream<Data>.Continuation?
    private var drainTask: Task<Void, Never>?
    private var cachedFilter: SCContentFilter?
    private var pickerObserver: PickerObserver?

    /// Starts capture and returns an AsyncStream of 16kHz mono Int16 PCM chunks.
    func start(micDeviceUID: String? = nil) async throws -> AsyncStream<Data> {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        self.continuation = continuation

        try await startSystemAudioCapture()
        try startMicCapture(deviceUID: micDeviceUID)

        // Periodically drain the mixing buffer
        drainTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self else { return }
                if let chunk = self.mixingBuffer.drainIfReady() {
                    await MainActor.run { [chunk] in _ = self.continuation?.yield(chunk) }
                }
            }
        }

        isCapturing = true
        return stream
    }

    func stop() async {
        drainTask?.cancel()
        drainTask = nil

        engine.stop()
        engine.inputNode.removeTap(onBus: 0)

        if let scStream {
            try? await scStream.stopCapture()
            self.scStream = nil
        }

        continuation?.finish()
        continuation = nil
        mixingBuffer.reset()
        isCapturing = false
    }

    // MARK: - System Audio (ScreenCaptureKit)

    private func startSystemAudioCapture() async throws {
        let filter: SCContentFilter
        if let cached = cachedFilter {
            filter = cached
        } else {
            filter = try await requestFilterViaPicker()
            cachedFilter = filter
        }
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.width = 2
        config.height = 2

        let output = SCStreamAudioOutput { [weak self] buffer in
            self?.handleSystemAudio(buffer)
        }
        self.scOutput = output

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(
            output,
            type: .audio,
            sampleHandlerQueue: DispatchQueue(label: "com.transcriber.scaudio", qos: .userInteractive)
        )
        self.scStream = stream
        try await stream.startCapture()
    }

    private nonisolated func handleSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let pcmBuffer = Self.extractPCMBuffer(from: sampleBuffer),
              let converted = systemConverter.convert(pcmBuffer),
              let data = converted.int16Data else { return }

        let frames = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        mixingBuffer.addSystemFrames(frames)
    }

    // MARK: - Microphone (AVAudioEngine)

    private func startMicCapture(deviceUID: String?) throws {
        #if os(macOS)
        if let uid = deviceUID {
            var deviceID = AudioDeviceID(0)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfUID = uid as CFString
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            let status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address, UInt32(MemoryLayout<CFString>.size), &cfUID,
                &size, &deviceID
            )
            if status == noErr {
                var deviceID = deviceID
                let err = AudioUnitSetProperty(
                    engine.inputNode.audioUnit!,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global, 0,
                    &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                if err != noErr {
                    print("Warning: could not set mic device, using default")
                }
            }
        }
        #endif

        let inputNode = engine.inputNode
        let hwFormat = inputNode.inputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            self?.handleMicAudio(buffer)
        }

        do {
            try engine.start()
        } catch {
            throw AudioCaptureError.engineStartFailed(error)
        }
    }

    private nonisolated func handleMicAudio(_ buffer: AVAudioPCMBuffer) {
        guard let converted = micConverter.convert(buffer),
              let data = converted.int16Data else { return }

        let frames = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        mixingBuffer.addMicFrames(frames)
    }

    // MARK: - CMSampleBuffer -> AVAudioPCMBuffer

    private nonisolated static func extractPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = sampleBuffer.formatDescription else { return nil }

        var asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)!.pointee
        guard let avFormat = AVAudioFormat(streamDescription: &asbd) else { return nil }

        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: avFormat, frameCapacity: frameCount) else {
            return nil
        }
        pcmBuffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return pcmBuffer
    }

    // MARK: - Content Sharing Picker

    private func requestFilterViaPicker() async throws -> SCContentFilter {
        try await withCheckedThrowingContinuation { continuation in
            let picker = SCContentSharingPicker.shared
            let observer = PickerObserver { filter in
                continuation.resume(returning: filter)
            } onCancel: {
                continuation.resume(throwing: AudioCaptureError.screenRecordingDenied)
            }

            self.pickerObserver = observer
            picker.add(observer)

            var config = SCContentSharingPickerConfiguration()
            config.allowedPickerModes = [.singleDisplay]
            picker.defaultConfiguration = config

            picker.isActive = true
            picker.present()
        }
    }
}

// MARK: - Picker Observer

@MainActor
private final class PickerObserver: NSObject, SCContentSharingPickerObserver {
    let onPick: (SCContentFilter) -> Void
    let onCancel: () -> Void

    init(onPick: @escaping (SCContentFilter) -> Void, onCancel: @escaping () -> Void) {
        self.onPick = onPick
        self.onCancel = onCancel
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        picker.remove(self)
        onPick(filter)
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        picker.remove(self)
        onCancel()
    }

    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        onCancel()
    }
}

// MARK: - SCStreamOutput handler

private final class SCStreamAudioOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio, sampleBuffer.isValid else { return }
        handler(sampleBuffer)
    }
}

