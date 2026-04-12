import SwiftUI

struct SettingsView: View {
    @State private var settings = SettingsManager.shared

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            connectionTab
                .tabItem { Label("Connections", systemImage: "network") }
        }
        .frame(width: 450, height: 300)
    }

    private var generalTab: some View {
        Form {
            Picker("Microphone", selection: $settings.selectedMicDeviceUID) {
                Text("System Default").tag(nil as String?)
                ForEach(settings.availableMicrophones, id: \.uid) { mic in
                    Text(mic.name).tag(mic.uid as String?)
                }
            }

            Toggle("Record audio by default", isOn: $settings.defaultRecordAudio)
        }
        .padding()
    }

    private var connectionTab: some View {
        Form {
            Section("AssemblyAI") {
                SecureField("API Key", text: $settings.assemblyAIKey)
            }

            Section("Obsidian (optional)") {
                TextField("URL", text: $settings.obsidianURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Key", text: $settings.obsidianAPIKey)
            }
        }
        .padding()
    }
}
