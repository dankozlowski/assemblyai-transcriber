import Foundation

enum TranscriptionEvent {
    case begin(id: String, expiresAt: String)
    case turn(speaker: String, text: String, endOfTurn: Bool)
    case termination(audioDurationSeconds: Double)
    case error(message: String)
}

@Observable
final class TranscriptionService: @unchecked Sendable {

    private(set) var isConnected = false

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var continuation: AsyncStream<TranscriptionEvent>.Continuation?
    private var receiveTask: Task<Void, Never>?

    func connect(
        apiKey: String,
        sampleRate: Int = 16000,
        speechModel: String = "u3-rt-pro",
        speakerLabels: Bool = true,
        maxSpeakers: Int? = nil
    ) -> AsyncStream<TranscriptionEvent> {
        let (stream, continuation) = AsyncStream<TranscriptionEvent>.makeStream()
        self.continuation = continuation

        var components = URLComponents(string: "wss://streaming.assemblyai.com/v3/ws")!
        var queryItems = [
            URLQueryItem(name: "sample_rate", value: "\(sampleRate)"),
            URLQueryItem(name: "speech_model", value: speechModel),
            URLQueryItem(name: "speaker_labels", value: "\(speakerLabels)"),
        ]
        if let maxSpeakers, maxSpeakers > 2 {
            queryItems.append(URLQueryItem(name: "max_speakers", value: "\(maxSpeakers)"))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("2025-05-12", forHTTPHeaderField: "AssemblyAI-Version")

        let session = URLSession(configuration: .default)
        self.session = session
        let ws = session.webSocketTask(with: request)
        self.webSocket = ws
        ws.resume()
        isConnected = true

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        return stream
    }

    func sendAudio(_ data: Data) {
        webSocket?.send(.data(data)) { _ in }
    }

    func disconnect() {
        let terminateJSON = #"{"type":"Terminate"}"#
        webSocket?.send(.string(terminateJSON)) { [weak self] _ in
            Task {
                try? await Task.sleep(for: .seconds(2))
                self?.forceClose()
            }
        }
    }

    func forceClose() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        continuation?.finish()
        continuation = nil
        isConnected = false
    }

    private func receiveLoop() async {
        guard let ws = webSocket else { return }

        while !Task.isCancelled {
            do {
                let message = try await ws.receive()
                switch message {
                case .string(let text):
                    if let event = try? Self.parseEvent(Data(text.utf8)) {
                        continuation?.yield(event)
                        if case .termination = event {
                            forceClose()
                            return
                        }
                    }
                case .data(let data):
                    if let event = try? Self.parseEvent(data) {
                        continuation?.yield(event)
                    }
                @unknown default:
                    break
                }
            } catch {
                continuation?.yield(.error(message: error.localizedDescription))
                forceClose()
                return
            }
        }
    }

    static func parseEvent(_ data: Data) throws -> TranscriptionEvent {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "TranscriptionService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"]
            )
        }

        if let errorMessage = json["error"] as? String {
            return .error(message: errorMessage)
        }

        guard let type = json["type"] as? String else {
            throw NSError(
                domain: "TranscriptionService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Missing type field"]
            )
        }

        switch type {
        case "Begin":
            let id = json["id"] as? String ?? ""
            let expiresAt = json["expires_at"] as? String ?? ""
            return .begin(id: id, expiresAt: expiresAt)

        case "Turn":
            let speaker = json["speaker_label"] as? String ?? "UNKNOWN"
            let text = json["transcript"] as? String ?? ""
            let endOfTurn = json["end_of_turn"] as? Bool ?? false
            return .turn(speaker: speaker, text: text, endOfTurn: endOfTurn)

        case "Termination":
            let duration = json["audio_duration_seconds"] as? Double ?? 0
            return .termination(audioDurationSeconds: duration)

        default:
            throw NSError(
                domain: "TranscriptionService",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Unknown event: \(type)"]
            )
        }
    }
}
