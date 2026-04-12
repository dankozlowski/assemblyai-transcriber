# Live Transcription with Speaker Diarization

A terminal-based live transcription tool that captures both system audio and microphone input, streams it to AssemblyAI for real-time transcription with speaker diarization, and saves the transcript to Obsidian.

Built for macOS. Designed for transcribing meetings, interviews, and conversations where you need to know who said what.

## What It Does

- Captures system audio (via BlackHole) and microphone simultaneously, mixes them into a single stream
- Streams to AssemblyAI's Universal-3 Pro real-time model with speaker labels
- Displays a live TUI with the last 10 transcript lines, detected speakers, time remaining, and estimated cost
- Saves transcripts to Obsidian via the Local REST API as speaker-attributed markdown
- Optionally records the audio to a compressed Opus file (~42MB for 4 hours)
- Auto-stops after configurable silence or inactivity timeouts
- Pause/resume with spacebar — disconnects from AssemblyAI to stop billing

```
┌─ Live Transcription ──────────────────── 3:42:15 remaining ─┐
│ [A] So I think we should go with the first option            │
│ [B] Yeah that makes sense to me                              │
│ [C] I agree, let's move forward with that                    │
│   [A] Great, I'll send out the follow up...                  │
├──────────────────────────────────────────────────────────────┤
│ Speakers: A · B · C                                  $0.0342 │
├──────────────────────────────────────────────────────────────┤
│ Space: pause  ·  Ctrl+C: quit                                │
└──────────────────────────────────────────────────────────────┘
```

## Requirements

- **macOS** (uses CoreAudio devices and `termios` for raw terminal input)
- **Python 3.10+**
- **BlackHole 2ch** — virtual audio driver for capturing system audio
- **ffmpeg** with libopus — only needed if you want to save audio recordings
- **Obsidian** with the [Local REST API](https://github.com/coddingtonbear/obsidian-local-rest-api) plugin — for saving transcripts

## Setup

### 1. Install BlackHole

Download from [existential.audio/blackhole](https://existential.audio/blackhole/) or install via Homebrew:

```bash
brew install blackhole-2ch
```

Then create a **Multi-Output Device** in Audio MIDI Setup (Applications > Utilities) that includes both your speakers/headphones and BlackHole 2ch. Set this as your system output so audio goes to both your ears and the virtual device.

### 2. Install Python dependencies

```bash
pip install assemblyai pyaudio
```

### 3. Install ffmpeg (optional, for audio recording)

```bash
brew install ffmpeg
```

### 4. Configure Obsidian

Install the [Local REST API](https://github.com/coddingtonbear/obsidian-local-rest-api) plugin in Obsidian and enable it. The script expects it at `https://127.0.0.1:27124`.

Set your API key via the `OBSIDIAN_API_KEY` environment variable, or edit the default in `transcribe.py`.

### 5. Configure AssemblyAI

Replace the `API_KEY` value in `transcribe.py` with your own key from [assemblyai.com/dashboard](https://www.assemblyai.com/dashboard/).

## Usage

```bash
python transcribe.py
```

You'll be prompted to configure the session:

```
┌─ Session Setup ─────────────────────────────┐
│  Press Enter to accept defaults              │
└──────────────────────────────────────────────┘

  Max speakers [2]: 3
  Max duration (hours) [4]:
  Silence timeout (minutes) [5]:
  Inactivity timeout (minutes) [5]:
  Save audio recording [y/N]: y
  Output file [recording_2025-04-02_14-30-00.ogg]:
```

### Controls

| Key | Action |
|-----|--------|
| **Space** | Pause/resume (disconnects from AssemblyAI to stop billing) |
| **Ctrl+C** | Quit |

### Auto-Stop Conditions

The script will automatically stop if any of these conditions are met:

- **Max duration** reached (default: 4 hours)
- **Silence timeout** — no audio signal detected (default: 5 minutes)
- **Inactivity timeout** — audio present but no speech transcribed (default: 5 minutes)

A countdown bar appears in the TUI when a timeout is approaching.

### Output

**Obsidian note** — saved to `Transcriptions/YYYY-MM-DD_HH-MM-SS.md` with speaker-attributed entries:

```markdown
# Transcript 2025-04-02 14:30:00

**[14:30:05] A:** So I think we should go with the first option

**[14:30:12] B:** Yeah that makes sense to me
```

**Audio file** (optional) — Opus-encoded OGG at 24kbps with VoIP mode, optimized for speech fidelity at minimal file size.

## Cost

AssemblyAI bills per second of WebSocket connection time. Current rates for this configuration:

| Component | Rate |
|-----------|------|
| Universal-3 Pro Streaming (`u3-rt-pro`) | $0.45/hr |
| Speaker Diarization | $0.12/hr |
| **Total** | **$0.57/hr** |

The TUI shows a live cost estimate. Pausing disconnects the WebSocket, so you're not billed while paused.

## Tools & Libraries

- [AssemblyAI](https://www.assemblyai.com/) — real-time speech-to-text with speaker diarization
- [BlackHole](https://existential.audio/blackhole/) — virtual audio driver for macOS by Existential Audio
- [PyAudio](https://people.csail.mit.edu/hubert/pyaudio/) — PortAudio bindings for Python
- [ffmpeg](https://ffmpeg.org/) + [Opus](https://opus-codec.org/) — audio encoding
- [Obsidian](https://obsidian.md/) — note-taking app
- [Obsidian Local REST API](https://github.com/coddingtonbear/obsidian-local-rest-api) — plugin by Adam Coddington

## Thanks

- **AssemblyAI** for the Universal-3 Pro streaming model — the real-time diarization is remarkably good
- **Existential Audio** for BlackHole — the cleanest virtual audio driver on macOS
- **Adam Coddington** for the Obsidian Local REST API plugin that makes programmatic note creation possible
