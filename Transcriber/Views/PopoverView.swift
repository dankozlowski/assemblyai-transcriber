import SwiftUI

struct PopoverView: View {
    @Bindable var viewModel: TranscriptViewModel
    let onShowTranscript: () -> Void

    @State private var showSettings = false
    @State private var settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 12) {
            if showSettings {
                settingsContent
            } else {
                mainContent
            }
        }
        .padding()
        .frame(width: 280, height: showSettings ? 340 : nil)
    }

    // MARK: - Main

    private var mainContent: some View {
        VStack(spacing: 12) {
            recordButton
            showTranscriptButton
            Divider()
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Settings

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    showSettings = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .contentShape(Rectangle())
                }
                Spacer()
                Text("Settings").font(.headline)
                Spacer()
                Color.clear.frame(width: 50, height: 1)
            }

            Divider()

            Group {
                Text("AssemblyAI").font(.caption).foregroundStyle(.secondary)
                SecureField("API Key", text: $settings.assemblyAIKey)
                    .textFieldStyle(.roundedBorder)
            }

            Group {
                Text("Obsidian (optional)").font(.caption).foregroundStyle(.secondary)
                TextField("URL", text: $settings.obsidianURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Key", text: $settings.obsidianAPIKey)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            Picker("Microphone", selection: $settings.selectedMicDeviceUID) {
                Text("System Default").tag(nil as String?)
                ForEach(settings.availableMicrophones, id: \.uid) { mic in
                    Text(mic.name).tag(mic.uid as String?)
                }
            }
            .controlSize(.small)

            Toggle("Record audio by default", isOn: $settings.defaultRecordAudio)
                .controlSize(.small)
        }
    }

    // MARK: - Record Button

    @ViewBuilder
    private var recordButton: some View {
        switch viewModel.state {
        case .setup, .stopped:
            Button {
                onShowTranscript()
            } label: {
                Label("Record", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

        case .recording:
            Button {
                Task { await viewModel.stopRecording() }
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

        case .paused:
            Button {
                Task { await viewModel.resumeRecording() }
            } label: {
                Label("Resume", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
    }

    private var showTranscriptButton: some View {
        Button {
            onShowTranscript()
        } label: {
            Label("Show Transcript", systemImage: "text.alignleft")
                .frame(maxWidth: .infinity)
        }
    }
}
