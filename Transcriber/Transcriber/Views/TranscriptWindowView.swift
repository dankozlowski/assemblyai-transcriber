import SwiftUI

struct TranscriptWindowView: View {
    @Bindable var viewModel: TranscriptViewModel

    var body: some View {
        ZStack {
            Color(nsColor: .init(white: 0.96, alpha: 1))
                .ignoresSafeArea()

            switch viewModel.state {
            case .setup:
                setupView
            case .recording, .paused:
                VStack(spacing: 0) {
                    recordingHeaderView
                    liveTranscriptView
                    statusBarView
                }
            case .stopped:
                stoppedView
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Setup

    private var setupView: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Session card
                GroupCard {
                    SectionLabel("Session")
                    TextField("Meeting name (optional)", text: $viewModel.config.sessionName)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color(nsColor: .init(white: 0.97, alpha: 1)))
                        .cornerRadius(8)

                    HStack(spacing: 16) {
                        CompactStepper(
                            label: "Speakers",
                            value: $viewModel.config.maxSpeakers,
                            range: 1...10
                        )
                        CompactStepper(
                            label: "Duration",
                            value: $viewModel.config.maxDurationMinutes,
                            range: 1...720,
                            step: 30,
                            format: { "\($0 / 60)h \($0 % 60)m" }
                        )
                    }
                }

                // Timeouts card
                GroupCard {
                    SectionLabel("Timeouts")
                    HStack(spacing: 16) {
                        CompactStepper(
                            label: "Silence",
                            value: $viewModel.config.silenceTimeoutMinutes,
                            range: 1...60,
                            format: { "\($0) min" }
                        )
                        CompactStepper(
                            label: "Inactivity",
                            value: $viewModel.config.inactivityTimeoutMinutes,
                            range: 1...60,
                            format: { "\($0) min" }
                        )
                    }
                }

                // Recording card
                GroupCard {
                    Toggle(isOn: $viewModel.config.recordAudio) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save audio recording")
                                .fontWeight(.medium)
                            Text(".wav to ~/Documents/Transcripts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                // Start button
                Button {
                    Task { await viewModel.startRecording() }
                } label: {
                    Text("Start Recording")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
                .keyboardShortcut(.return)
                .disabled(!viewModel.canRecord)

                if !viewModel.canRecord {
                    Text("Configure your AssemblyAI API key in Settings to begin.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(20)
            .frame(width: 380)
        }
    }

    // MARK: - Recording Header

    private var recordingHeaderView: some View {
        HStack(spacing: 12) {
            // Recording indicator
            Circle()
                .fill(viewModel.state == .recording ? .red : .orange)
                .frame(width: 10, height: 10)
                .opacity(viewModel.state == .recording ? 1 : 0.8)

            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.config.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Text(formattedElapsed)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                if viewModel.state == .recording {
                    ControlButton(icon: "pause.fill", color: .primary) {
                        Task { await viewModel.pauseRecording() }
                    }
                    .help("Pause")
                } else if viewModel.state == .paused {
                    ControlButton(icon: "play.fill", color: .green) {
                        Task { await viewModel.resumeRecording() }
                    }
                    .help("Resume")
                }

                ControlButton(icon: "stop.fill", color: .red) {
                    Task { await viewModel.stopRecording() }
                }
                .help("Stop")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.background)
    }

    // MARK: - Live Transcript

    private var liveTranscriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.entries) { entry in
                        TranscriptRow(entry: entry)
                            .id(entry.id)
                    }
                    if let partial = viewModel.partialEntry {
                        TranscriptRow(entry: partial, isPartial: true)
                            .id("partial")
                    }

                    if viewModel.entries.isEmpty && viewModel.partialEntry == nil {
                        VStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.system(size: 24))
                                .foregroundStyle(.quaternary)
                            Text("Waiting for speech...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                }
                .padding(.vertical, 12)
            }
            .background(.background)
            .onChange(of: viewModel.entries.count) {
                if let last = viewModel.entries.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Status Bar

    private var statusBarView: some View {
        HStack(spacing: 6) {
            if !viewModel.detectedSpeakers.isEmpty {
                ForEach(viewModel.detectedSpeakers.sorted(), id: \.self) { speaker in
                    SpeakerBadge(speaker: speaker)
                }
            } else {
                Text("No speakers detected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if viewModel.state == .paused {
                Text("PAUSED")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange)
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .init(white: 0.97, alpha: 1)))
    }

    // MARK: - Stopped (Session Info)

    private var stoppedView: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                GroupCard {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.config.displayName)
                                .font(.system(size: 15, weight: .semibold))
                            if let start = viewModel.sessionStartTime {
                                Text(start.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }

                // Stats
                GroupCard {
                    SectionLabel("Session")
                    HStack(spacing: 0) {
                        SessionStat(label: "Duration", value: formattedElapsed)
                        Divider().frame(height: 32)
                        SessionStat(label: "Entries", value: "\(viewModel.entries.count)")
                        Divider().frame(height: 32)
                        SessionStat(label: "Speakers", value: "\(viewModel.detectedSpeakers.count)")
                    }
                }

                // Files
                GroupCard {
                    SectionLabel("Files")

                    if let url = viewModel.transcriptFileURL {
                        FileRow(
                            icon: "doc.text.fill",
                            color: .blue,
                            label: url.lastPathComponent,
                            caption: "Transcript"
                        ) {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    if let url = viewModel.audioFileURL {
                        FileRow(
                            icon: "waveform.circle.fill",
                            color: .purple,
                            label: url.lastPathComponent,
                            caption: "Audio recording"
                        ) {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    if viewModel.transcriptFileURL == nil && viewModel.audioFileURL == nil {
                        Text("No files saved")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                // New Session button
                Button {
                    viewModel.resetToSetup()
                } label: {
                    Text("New Session")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
            }
            .padding(20)
            .frame(width: 380)
        }
    }

    // MARK: - Helpers

    private var formattedElapsed: String {
        let total = Int(viewModel.elapsedSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Components

private let speakerColors: [Color] = [
    .init(red: 0.345, green: 0.337, blue: 0.839),  // purple
    .init(red: 0.204, green: 0.780, blue: 0.349),   // green
    .init(red: 0.945, green: 0.549, blue: 0.133),   // orange
    .init(red: 0.220, green: 0.557, blue: 0.878),   // blue
    .init(red: 0.878, green: 0.275, blue: 0.373),   // red
    .init(red: 0.549, green: 0.337, blue: 0.788),   // violet
]

private func colorForSpeaker(_ speaker: String) -> Color {
    let index = abs(speaker.hashValue) % speakerColors.count
    return speakerColors[index]
}

private struct TranscriptRow: View {
    let entry: TranscriptEntry
    var isPartial: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Speaker avatar
            ZStack {
                Circle()
                    .fill(colorForSpeaker(entry.speaker))
                Text(entry.speaker)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Speaker \(entry.speaker)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(colorForSpeaker(entry.speaker))
                    Text(entry.timestamp.formatted(Date.FormatStyle().hour().minute().second()))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Text(entry.text)
                    .font(.system(size: 13))
                    .foregroundStyle(isPartial ? .secondary : .primary)
                    .italic(isPartial)
                    .textSelection(.enabled)
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .opacity(isPartial ? 0.6 : 1)
    }
}

private struct SpeakerBadge: View {
    let speaker: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(colorForSpeaker(speaker))
                .frame(width: 8, height: 8)
            Text(speaker)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .init(white: 0.92, alpha: 1)))
        .cornerRadius(10)
    }
}

private struct GroupCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(16)
        .background(.background)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }
}

private struct CompactStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var format: ((Int) -> String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    value = max(range.lowerBound, value - step)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 24, height: 24)
                        .background(Color(nsColor: .init(white: 0.94, alpha: 1)))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(value <= range.lowerBound)

                Text(format?(value) ?? "\(value)")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(minWidth: 40)
                    .multilineTextAlignment(.center)

                Button {
                    value = min(range.upperBound, value + step)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 24, height: 24)
                        .background(Color(nsColor: .init(white: 0.94, alpha: 1)))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(value >= range.upperBound)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ControlButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(Color(nsColor: .init(white: 0.95, alpha: 1)))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

private struct SessionStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .semibold))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FileRow: View {
    let icon: String
    let color: Color
    let label: String
    let caption: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
