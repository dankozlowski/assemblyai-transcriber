import Foundation
import UserNotifications

@Observable
@MainActor
final class TranscriptViewModel {

    // State
    var config = SessionConfig()
    var entries: [TranscriptEntry] = []
    var partialEntry: TranscriptEntry?
    var detectedSpeakers: Set<String> = []
    var errorMessage: String?
    var elapsedSeconds: Double = 0

    enum State: Equatable {
        case setup
        case recording
        case paused
        case stopped
    }
    var state: State = .setup

    // Session results (available after stopping)
    var sessionStartTime: Date?
    var transcriptFileURL: URL?
    var audioFileURL: URL?

    // Services
    private let captureManager = AudioCaptureManager()
    private var transcriptionService = TranscriptionService()
    private var obsidianService: ObsidianService?
    private var audioRecorder: AudioRecorderService?
    private var notePath: String = ""

    // Tasks
    private var audioStreamTask: Task<Void, Never>?
    private var eventStreamTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    // Timeouts
    private var lastAudioTime: Date = Date()
    private var lastTranscriptTime: Date = Date()

    var canRecord: Bool {
        SettingsManager.shared.isConfigured
    }

    // MARK: - Session Lifecycle

    func startRecording() async {
        let settings = SettingsManager.shared
        guard settings.isConfigured else {
            errorMessage = "Please configure your AssemblyAI API key in Settings."
            return
        }

        let startTime = Date()
        sessionStartTime = startTime
        let displayName = config.displayName
        let fileStem = config.fileStem

        // Local transcript fallback path
        let transcriptsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Transcripts", isDirectory: true)
        transcriptFileURL = transcriptsDir.appendingPathComponent("\(fileStem).md")

        obsidianService = ObsidianService(
            baseURL: settings.obsidianURL,
            apiKey: settings.obsidianAPIKey
        )
        notePath = "Transcriptions/\(fileStem).md"

        let header = "# \(displayName)\n\n\(startTime.formatted())\n\n"
        await obsidianService?.writeNote(path: notePath, content: header)

        if config.recordAudio {
            audioRecorder = AudioRecorderService(fileStem: fileStem)
            audioFileURL = audioRecorder?.outputURL
        }

        do {
            let audioStream = try await captureManager.start(
                micDeviceUID: settings.selectedMicDeviceUID
            )

            let maxSpeakers = config.maxSpeakers > 2 ? config.maxSpeakers : nil
            let eventStream = transcriptionService.connect(
                apiKey: settings.assemblyAIKey,
                speakerLabels: true,
                maxSpeakers: maxSpeakers
            )

            state = .recording
            errorMessage = nil
            lastAudioTime = Date()
            lastTranscriptTime = Date()

            audioStreamTask = Task {
                for await chunk in audioStream {
                    transcriptionService.sendAudio(chunk)
                    audioRecorder?.write(chunk)
                    lastAudioTime = Date()
                }
            }

            eventStreamTask = Task {
                for await event in eventStream {
                    await handleEvent(event)
                }
            }

            startTimer()

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pauseRecording() async {
        state = .paused

        audioStreamTask?.cancel()
        audioStreamTask = nil
        timerTask?.cancel()
        timerTask = nil

        await captureManager.stop()
        transcriptionService.disconnect()

        partialEntry = nil
    }

    func resumeRecording() async {
        let settings = SettingsManager.shared

        do {
            let audioStream = try await captureManager.start(
                micDeviceUID: settings.selectedMicDeviceUID
            )

            let maxSpeakers = config.maxSpeakers > 2 ? config.maxSpeakers : nil
            transcriptionService = TranscriptionService()
            let eventStream = transcriptionService.connect(
                apiKey: settings.assemblyAIKey,
                speakerLabels: true,
                maxSpeakers: maxSpeakers
            )

            state = .recording
            lastAudioTime = Date()
            lastTranscriptTime = Date()

            audioStreamTask = Task {
                for await chunk in audioStream {
                    transcriptionService.sendAudio(chunk)
                    audioRecorder?.write(chunk)
                    lastAudioTime = Date()
                }
            }

            eventStreamTask = Task {
                for await event in eventStream {
                    await handleEvent(event)
                }
            }

            startTimer()

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() async {
        audioStreamTask?.cancel()
        audioStreamTask = nil
        eventStreamTask?.cancel()
        eventStreamTask = nil
        timerTask?.cancel()
        timerTask = nil

        await captureManager.stop()
        transcriptionService.disconnect()
        audioRecorder?.close()
        audioRecorder = nil

        state = .stopped
    }

    func resetToSetup() {
        entries.removeAll()
        partialEntry = nil
        detectedSpeakers.removeAll()
        errorMessage = nil
        elapsedSeconds = 0
        sessionStartTime = nil
        transcriptFileURL = nil
        audioFileURL = nil
        state = .setup
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: TranscriptionEvent) async {
        switch event {
        case .begin:
            break

        case .turn(let speaker, let text, let endOfTurn):
            detectedSpeakers.insert(speaker)
            if endOfTurn {
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    let entry = TranscriptEntry(speaker: speaker, text: text, isFinal: true)
                    entries.append(entry)
                    lastTranscriptTime = Date()
                    await obsidianService?.appendToNote(path: notePath, content: entry.markdownLine)
                }
                partialEntry = nil
            } else {
                partialEntry = TranscriptEntry(speaker: speaker, text: text, isFinal: false)
            }

        case .termination:
            await stopRecording()

        case .error(let message):
            errorMessage = message
        }
    }

    // MARK: - Timer & Timeouts

    private func startTimer() {
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsedSeconds += 1
                checkTimeouts()
            }
        }
    }

    private func checkTimeouts() {
        guard state == .recording else { return }
        let now = Date()

        if elapsedSeconds >= Double(config.maxDurationMinutes * 60) {
            Task { await stopWithNotification("Max duration reached.") }
        } else if now.timeIntervalSince(lastAudioTime) >= Double(config.silenceTimeoutMinutes * 60) {
            Task { await stopWithNotification("No audio detected — silence timeout.") }
        } else if now.timeIntervalSince(lastTranscriptTime) >= Double(config.inactivityTimeoutMinutes * 60) {
            Task { await stopWithNotification("No speech detected — inactivity timeout.") }
        }
    }

    private func stopWithNotification(_ reason: String) async {
        await stopRecording()

        let content = UNMutableNotificationContent()
        content.title = "Transcriber Stopped"
        content.body = reason
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
