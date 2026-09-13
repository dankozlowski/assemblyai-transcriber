import Foundation

struct TranscriptEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let speaker: String
    let text: String
    let isFinal: Bool

    init(speaker: String, text: String, isFinal: Bool, timestamp: Date = Date()) {
        self.speaker = speaker
        self.text = text
        self.isFinal = isFinal
        self.timestamp = timestamp
    }

    var markdownLine: String {
        let ts = timestamp.formatted(Date.FormatStyle().hour().minute().second())
        return "**[\(ts)] \(speaker):** \(text)\n\n"
    }
}
