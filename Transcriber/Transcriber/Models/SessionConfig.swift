import Foundation

struct SessionConfig {
    var sessionName: String = ""
    var maxSpeakers: Int = 2
    var maxDurationMinutes: Int = 240
    var silenceTimeoutMinutes: Int = 5
    var inactivityTimeoutMinutes: Int = 5
    var recordAudio: Bool = false

    var fileSlug: String {
        let base = sessionName.isEmpty ? "transcript" : sessionName
        let slug = base.prefix(24)
            .lowercased()
            .replacing(/[^a-z0-9]+/, with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return slug.isEmpty ? "transcript" : slug
    }

    var fileStem: String {
        let stamp = Date().formatted(.iso8601
            .year().month().day().time(includingFractionalSeconds: false))
            .replacing(/[-:T]/, with: "_")
        return "\(fileSlug)_\(stamp)"
    }

    var displayName: String {
        sessionName.isEmpty
            ? "Transcript \(Date().formatted(date: .abbreviated, time: .shortened))"
            : sessionName
    }
}
