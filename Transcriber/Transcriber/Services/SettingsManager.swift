import Foundation
import AVFoundation

@Observable
final class SettingsManager {
    static let shared = SettingsManager()

    var assemblyAIKey: String {
        didSet { UserDefaults.standard.set(assemblyAIKey, forKey: "assemblyai_api_key") }
    }

    var obsidianURL: String {
        didSet { UserDefaults.standard.set(obsidianURL, forKey: "obsidian_url") }
    }

    var obsidianAPIKey: String {
        didSet { UserDefaults.standard.set(obsidianAPIKey, forKey: "obsidian_api_key") }
    }

    var selectedMicDeviceUID: String? {
        didSet { UserDefaults.standard.set(selectedMicDeviceUID, forKey: "mic_device_uid") }
    }

    var defaultRecordAudio: Bool {
        didSet { UserDefaults.standard.set(defaultRecordAudio, forKey: "default_record_audio") }
    }

    var isConfigured: Bool {
        !assemblyAIKey.isEmpty
    }

    private init() {
        self.assemblyAIKey = UserDefaults.standard.string(forKey: "assemblyai_api_key") ?? ""
        self.obsidianURL = UserDefaults.standard.string(forKey: "obsidian_url") ?? "https://127.0.0.1:27124"
        self.obsidianAPIKey = UserDefaults.standard.string(forKey: "obsidian_api_key") ?? ""
        self.selectedMicDeviceUID = UserDefaults.standard.string(forKey: "mic_device_uid")
        self.defaultRecordAudio = UserDefaults.standard.bool(forKey: "default_record_audio")
    }

    var availableMicrophones: [(uid: String, name: String)] {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
        return devices.map { ($0.uniqueID, $0.localizedName) }
    }
}
