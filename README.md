# Transcriber

A native macOS menu bar app for real-time transcription with speaker diarization. Captures both system audio and microphone input, streams to AssemblyAI for live transcription, and saves speaker-attributed transcripts to Obsidian (with local fallback).

Built with Swift and SwiftUI. Designed for transcribing meetings, interviews, podcasts, and any conversation where you need to know who said what — without installing virtual audio drivers or configuring multi-output devices.

## What It Does

- **Captures system audio natively** via ScreenCaptureKit — no BlackHole, no virtual audio devices, no Audio MIDI Setup configuration
- **Captures microphone input** via AVAudioEngine — uses the system default mic or a user-selected device
- **Mixes both audio sources** into a single 16kHz mono PCM stream and sends it to AssemblyAI's Universal-3 Pro real-time model with speaker labels
- **Shows a live scrolling transcript** in a clean, polished window with colored speaker avatars, timestamps, and partial (in-progress) text
- **Saves transcripts to Obsidian** via the Local REST API as speaker-attributed markdown — falls back to `~/Documents/Transcripts/` if Obsidian is unavailable
- **Records audio** to a WAV file in `~/Documents/Transcripts/` (optional, toggled per session)
- **Pause/resume** — disconnects from AssemblyAI on pause to stop billing, reconnects on resume
- **Auto-stops** after configurable silence, inactivity, or max duration timeouts — sends a macOS notification explaining why
- **Lives in the menu bar** — no dock icon, minimal footprint, always accessible

## Screenshots

The app has four main states:

**Setup** — Configure session name, speaker count, timeouts, and audio recording before starting:

```
┌─────────────────────────────────────────┐
│  SESSION                                │
│  ┌───────────────────────────────────┐  │
│  │ Meeting name (optional)           │  │
│  └───────────────────────────────────┘  │
│  Speakers  [−] 2 [+]   Duration [−] 4h 0m [+]  │
├─────────────────────────────────────────┤
│  TIMEOUTS                               │
│  Silence   [−] 5 min [+]  Inactivity [−] 5 min [+]  │
├─────────────────────────────────────────┤
│  Save audio recording                 ○ │
│  .wav to ~/Documents/Transcripts        │
├─────────────────────────────────────────┤
│           [ Start Recording ]           │
└─────────────────────────────────────────┘
```

**Recording** — Live transcript with speaker labels, colored avatars, and playback controls:

```
● Team Standup                    4:32  ⏸ ⏹
─────────────────────────────────────────
  A  Speaker A              2:15
     We need to finalize the API changes
     before the sprint ends.

  B  Speaker B              2:28
     I can take the authentication
     endpoints. Should be done by Thursday.

  A  Speaker A
     That works, and then we can...
─────────────────────────────────────────
  ● A  ● B
```

**Session Info** — After stopping, shows stats and clickable links to saved files:

```
✓  Team Standup
   Apr 11, 2026 at 3:37 PM
─────────────────────────────────────────
   4:32        12         2
  Duration    Entries    Speakers
─────────────────────────────────────────
  📄 team_standup_2026_04_11.md    ↗
     Transcript
  🎵 team_standup_2026_04_11.wav   ↗
     Audio recording
─────────────────────────────────────────
          [ New Session ]
```

## Requirements

- **macOS 14.0+** (Sonoma or later) — uses ScreenCaptureKit, AVAudioEngine, `@Observable`, and modern SwiftUI APIs
- **Xcode 16+** — for building (Swift 5.10)
- **xcodegen** — for generating the Xcode project from `project.yml`
- **AssemblyAI API key** — for real-time transcription ([sign up](https://www.assemblyai.com/dashboard/))
- **Obsidian** with the [Local REST API](https://github.com/coddingtonbear/obsidian-local-rest-api) plugin (optional) — for saving transcripts directly into your vault

## Setup

### 1. Install xcodegen

```bash
brew install xcodegen
```

### 2. Generate the Xcode project

```bash
cd Transcriber
xcodegen generate
```

This creates `Transcriber.xcodeproj` from `project.yml`.

### 3. Create a code signing certificate (recommended)

Without a stable signing identity, macOS will prompt for Screen Recording permission on every rebuild. Create a self-signed certificate to avoid this:

```bash
# Generate the certificate
openssl req -x509 -newkey rsa:2048 -keyout /tmp/dev.key -out /tmp/dev.crt \
  -days 3650 -nodes -subj '/CN=Transcriber Dev' \
  -addext 'keyUsage=critical,digitalSignature' \
  -addext 'extendedKeyUsage=critical,codeSigning'

# Convert to PKCS12 and import
openssl pkcs12 -export -inkey /tmp/dev.key -in /tmp/dev.crt \
  -out /tmp/dev.p12 -passout pass:dev123 -legacy
security import /tmp/dev.p12 -k ~/Library/Keychains/login.keychain-db \
  -P dev123 -T /usr/bin/codesign

# Trust it for code signing (requires admin password)
sudo security add-trusted-cert -d -r trustRoot -p codeSign \
  -k ~/Library/Keychains/login.keychain-db /tmp/dev.crt

# Clean up
rm /tmp/dev.key /tmp/dev.crt /tmp/dev.p12
```

The `project.yml` is already configured to sign with `Transcriber Dev`. If you name your certificate differently, update the `CODE_SIGN_IDENTITY` in `project.yml`.

### 4. Build and run

```bash
cd Transcriber
xcodebuild -project Transcriber.xcodeproj -scheme Transcriber -configuration Debug build
```

Then launch the app:

```bash
open $(xcodebuild -project Transcriber.xcodeproj -scheme Transcriber \
  -configuration Debug -showBuildSettings 2>/dev/null \
  | grep ' BUILT_PRODUCTS_DIR' | awk '{print $3}')/Transcriber.app
```

### 5. Configure the app

Click the **mic icon** in the menu bar, then **Settings**:

1. **AssemblyAI API Key** — paste your key from [assemblyai.com/dashboard](https://www.assemblyai.com/dashboard/)
2. **Obsidian URL** (optional) — defaults to `https://127.0.0.1:27124`
3. **Obsidian API Key** (optional) — from the Local REST API plugin settings
4. **Microphone** — select a specific mic or leave as System Default
5. **Record audio by default** — toggle on if you always want audio saved

Settings are stored in UserDefaults and persist across launches.

### 6. Grant permissions

On first recording, macOS will ask for:

- **Screen Recording** — via the system content sharing picker (select your display). This is required for ScreenCaptureKit to capture system audio. The selection is cached for the session.
- **Microphone** — standard macOS mic permission dialog. Grant once and it persists.

## Usage

### Starting a recording

1. Click the **mic icon** in the menu bar
2. Click **Record** — this opens the transcript window with the session setup form
3. Configure the session (or accept defaults):
   - **Session name** — optional, used for the transcript filename
   - **Max speakers** — tell AssemblyAI how many distinct speakers to expect (default: 2)
   - **Max duration** — auto-stop after this many minutes (default: 240 = 4 hours)
   - **Silence timeout** — auto-stop if no audio signal for this long (default: 5 minutes)
   - **Inactivity timeout** — auto-stop if audio present but no speech transcribed (default: 5 minutes)
   - **Save audio recording** — toggle to save a .wav file alongside the transcript
4. Click **Start Recording**
5. On first launch, select your display from the system sharing picker

### During a recording

The transcript window shows:

- **Recording indicator** — red dot with session name and elapsed time
- **Live transcript** — speaker-labeled entries with colored avatars and timestamps
- **Partial text** — currently-being-spoken text shown in lighter italic
- **Speaker badges** — detected speakers shown in the status bar

**Controls** (in the transcript window header):
- **Pause** (⏸) — disconnects from AssemblyAI to stop billing. Audio capture stops.
- **Resume** (▶) — reconnects and resumes transcription
- **Stop** (⏹) — ends the session and shows session info

**Controls** (in the menu bar popover):
- **Stop** — ends the current recording
- **Show Transcript** — brings the transcript window to front

### After a recording

The session info screen shows:
- Session name and start time
- Duration, entry count, and speaker count
- **Clickable file links** — click to open the transcript markdown or play the audio file
- **New Session** button to start another recording

### Output files

All files are saved to `~/Documents/Transcripts/`:

**Transcript** — `{slug}_{timestamp}.md`

```markdown
# Team Standup

Apr 11, 2026 at 3:37 PM

**[3:37:05 PM] A:** We need to finalize the API changes before the sprint ends.

**[3:37:12 PM] B:** I can take the authentication endpoints. Should be done by Thursday.

**[3:37:18 PM] A:** That works. I'll send out the follow-up email after this.
```

If Obsidian is configured and running, the transcript is also saved to `Transcriptions/{slug}_{timestamp}.md` in your vault.

**Audio** — `{slug}_{timestamp}.wav` (16kHz mono, 16-bit PCM)

Saved only when "Save audio recording" is enabled. This is the same mixed audio stream sent to AssemblyAI — both system audio and microphone combined.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        TranscriberApp                        │
│  MenuBarExtra (popover) ←→ Window (transcript/setup/info)   │
│                              ↕                               │
│                     TranscriptViewModel                      │
│              (orchestrates all services)                     │
├─────────────┬──────────────┬──────────────┬─────────────────┤
│ AudioCapture│ Transcription│  Obsidian    │ AudioRecorder   │
│   Manager   │   Service    │  Service     │   Service       │
│             │              │              │                 │
│ SCK + AVAudio│ WebSocket   │ REST API +   │ AVAudioFile     │
│ Engine      │ to AssemblyAI│ local fallback│ WAV writer     │
│             │              │              │                 │
│ → PCM chunks│ ← JSON events│ → markdown   │ → .wav file    │
└─────────────┴──────────────┴──────────────┴─────────────────┘
```

### Services

| Service | Responsibility | Key API |
|---------|---------------|---------|
| **AudioCaptureManager** | Captures system audio (ScreenCaptureKit) and mic (AVAudioEngine), mixes to 16kHz mono Int16, exposes AsyncStream\<Data\> | `SCContentSharingPicker`, `SCStream`, `AVAudioEngine` |
| **SampleRateConverter** | Converts any AVAudioPCMBuffer to 16kHz mono Int16 | `AVAudioConverter` |
| **MixingBuffer** | Thread-safe buffer that additively mixes two Int16 audio sources | NSLock-guarded arrays |
| **TranscriptionService** | WebSocket client for AssemblyAI streaming v3 — sends audio, receives events | `URLSessionWebSocketTask` |
| **ObsidianService** | Saves transcripts via Obsidian REST API, falls back to local files | `URLSession` with self-signed TLS |
| **AudioRecorderService** | Writes PCM audio chunks to a WAV file | `AVAudioFile` |
| **SettingsManager** | Persists API keys, mic selection, and defaults in UserDefaults | `@Observable` singleton |

### Models

| Model | Purpose |
|-------|---------|
| **SessionConfig** | Session parameters (name, speakers, timeouts, record toggle) with computed `fileSlug` and `fileStem` |
| **TranscriptEntry** | Single transcript line: speaker, text, timestamp, isFinal flag, `markdownLine` formatter |

### Views

| View | Purpose |
|------|---------|
| **PopoverView** | Menu bar popover — record/stop button, show transcript, inline settings |
| **TranscriptWindowView** | Main window — four states: setup form, recording with live transcript, session info |
| **SettingsView** | Settings tab view (embedded in popover) — API keys, mic selection, defaults |

## AssemblyAI WebSocket Protocol

The app connects to AssemblyAI's streaming v3 API:

- **URL:** `wss://streaming.assemblyai.com/v3/ws?sample_rate=16000&speech_model=u3-rt-pro&speaker_labels=true`
- **Headers:** `Authorization: <api_key>`, `AssemblyAI-Version: 2025-05-12`
- **Audio:** Raw binary WebSocket frames — 16-bit signed little-endian PCM, 16kHz mono
- **Events received:**
  - `Begin` — session started, returns session ID
  - `Turn` — transcript update with `speaker_label`, `transcript`, `end_of_turn`
  - `Termination` — session ended, returns audio duration
  - Error — `{"error": "message"}` (no type field)
- **Disconnect:** Send `{"type": "Terminate"}`, server responds with Termination event

## Audio Pipeline

```
System Audio (48kHz stereo)          Microphone (hardware rate)
         ↓                                    ↓
  SCStream callback                   AVAudioEngine tap
         ↓                                    ↓
  CMSampleBuffer → AVAudioPCMBuffer    AVAudioPCMBuffer
         ↓                                    ↓
  SampleRateConverter (→ 16kHz mono Int16)    SampleRateConverter
         ↓                                    ↓
  MixingBuffer.addSystemFrames()      MixingBuffer.addMicFrames()
                    ↓
         MixingBuffer.drainIfReady()
         (additive mix, Int16 clamping)
                    ↓
              AsyncStream<Data>
              ↓              ↓
     TranscriptionService   AudioRecorderService
     (WebSocket binary)      (.wav file)
```

The mixing buffer accumulates frames from both sources and drains every 50ms (1600 frames = 100ms at 16kHz). The two sources don't need to be perfectly synchronized — for speech transcription, the slight timing variation is imperceptible.

## Cost

AssemblyAI bills per second of WebSocket connection time. Current rates:

| Component | Rate |
|-----------|------|
| Universal-3 Pro Streaming (`u3-rt-pro`) | $0.45/hr |
| Speaker Diarization | $0.12/hr |
| **Total** | **$0.57/hr** |

Pausing disconnects the WebSocket, so you are not billed while paused.

## Project Structure

```
assemblyai-play/
├── README.md                              ← you are here
├── .gitignore
├── Transcriber/
│   ├── project.yml                        # xcodegen project definition
│   ├── Transcriber.xcodeproj/             # generated — do not edit manually
│   ├── Transcriber/
│   │   ├── TranscriberApp.swift           # @main — menu bar, window scenes
│   │   ├── Info.plist                     # LSUIElement, mic usage description
│   │   ├── Transcriber.entitlements       # sandbox disabled for dev builds
│   │   ├── Models/
│   │   │   ├── SessionConfig.swift        # session parameters + file naming
│   │   │   └── TranscriptEntry.swift      # single transcript line
│   │   ├── Services/
│   │   │   ├── AudioCaptureManager.swift  # ScreenCaptureKit + AVAudioEngine
│   │   │   ├── SampleRateConverter.swift  # AVAudioConverter wrapper
│   │   │   ├── MixingBuffer.swift         # thread-safe two-source mixer
│   │   │   ├── TranscriptionService.swift # WebSocket client for AssemblyAI
│   │   │   ├── ObsidianService.swift      # REST API + local fallback
│   │   │   ├── AudioRecorderService.swift # WAV file writer
│   │   │   ├── SettingsManager.swift      # UserDefaults-backed settings
│   │   │   └── KeychainHelper.swift       # Keychain read/write (unused in dev)
│   │   ├── ViewModels/
│   │   │   └── TranscriptViewModel.swift  # orchestrates all services
│   │   └── Views/
│   │       ├── PopoverView.swift          # menu bar popover + inline settings
│   │       ├── TranscriptWindowView.swift # setup, recording, session info
│   │       └── SettingsView.swift         # settings tab view (unused, inline now)
│   └── TranscriberTests/
│       ├── SessionConfigTests.swift
│       ├── TranscriptEntryTests.swift
│       ├── MixingBufferTests.swift
│       └── TranscriptionServiceTests.swift
└── legacy/
    ├── README.md                          # original Python CLI documentation
    └── transcribe.py                      # original Python CLI implementation
```

## Running Tests

```bash
cd Transcriber
xcodebuild test -project Transcriber.xcodeproj -scheme Transcriber -configuration Debug
```

15 tests covering:
- **SessionConfigTests** — default values, slug generation, empty name handling
- **TranscriptEntryTests** — final/partial entries, markdown formatting
- **MixingBufferTests** — drain threshold, overflow clamping, single-source operation
- **TranscriptionServiceTests** — JSON parsing for all event types (Begin, Turn, Termination, Error)

## Troubleshooting

### Screen Recording permission keeps prompting

This happens when the app's code signing identity changes between builds. Follow the certificate setup in step 3 above to create a stable signing identity. After creating the certificate:

1. Do a clean build: `xcodebuild clean build ...`
2. Launch the app
3. Grant Screen Recording when prompted (select your display from the picker)
4. Subsequent rebuilds should not prompt again

### No system audio captured

Make sure you selected a display (not a window or app) from the content sharing picker. System audio capture requires a display-level selection.

### No microphone audio

Check System Settings > Privacy & Security > Microphone and ensure Transcriber is listed and enabled. If you selected a specific mic in Settings but it's disconnected, the app falls back to the system default.

### Empty WAV files

This was a bug in earlier versions that used AAC encoding. The current version uses linear PCM WAV, which works reliably. If you see empty files, make sure you're running the latest build.

### Transcript not appearing in Obsidian

- Verify Obsidian is running with the Local REST API plugin enabled
- Check the URL in Settings matches your Obsidian REST API URL (default: `https://127.0.0.1:27124`)
- Check the API key matches
- The transcript is always saved locally to `~/Documents/Transcripts/` as a fallback regardless of Obsidian connectivity

### App doesn't appear in dock

This is by design — `LSUIElement = true` in Info.plist hides the dock icon. The app lives in the menu bar (mic icon).

## Legacy CLI

The original Python command-line transcription tool is preserved in the `legacy/` directory. It uses BlackHole for system audio capture and a terminal UI. See `legacy/README.md` for documentation.

## Tools & Libraries

- [AssemblyAI](https://www.assemblyai.com/) — real-time speech-to-text with speaker diarization (Universal-3 Pro model)
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) — Apple's framework for capturing screen content and system audio
- [AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine) — Apple's audio processing framework for mic capture
- [SwiftUI](https://developer.apple.com/xcode/swiftui/) — declarative UI framework
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — Xcode project generation from YAML
- [Obsidian](https://obsidian.md/) — knowledge management app
- [Obsidian Local REST API](https://github.com/coddingtonbear/obsidian-local-rest-api) — plugin by Adam Coddington

## License

This project is unlicensed — personal use.
