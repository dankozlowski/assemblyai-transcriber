import os
import re
import select
import shutil
import struct
import ssl
import subprocess
import sys
import termios
import time
import tty
from collections import deque
from datetime import datetime
from urllib.request import Request, urlopen

import pyaudio
import assemblyai as aai
from assemblyai.streaming.v3 import (
    BeginEvent,
    StreamingClient,
    StreamingClientOptions,
    StreamingError,
    StreamingEvents,
    StreamingParameters,
    TurnEvent,
    TerminationEvent,
)

API_KEY = os.environ["ASSEMBLYAI_API_KEY"]
CLEAR_SCREEN = "\033[H\033[J"
BLACKHOLE_DEVICE_NAME = "BlackHole 2ch"
MIC_DEVICE_NAME = "MacBook Pro Microphone"
SAMPLE_RATE = 16000

# AssemblyAI published rates (per hour) — update if pricing changes
COST_RATES = {
    "u3-rt-pro": 0.45,
    "speaker_labels": 0.12,
}
COST_PER_SECOND = sum(COST_RATES.values()) / 3600

OBSIDIAN_URL = "https://127.0.0.1:27124"
OBSIDIAN_API_KEY = os.environ["OBSIDIAN_API_KEY"]
OBSIDIAN_SSL = ssl.create_default_context()
OBSIDIAN_SSL.check_hostname = False
OBSIDIAN_SSL.verify_mode = ssl.CERT_NONE

def make_obsidian_note_path(session_name, start_time):
    """Build the Obsidian note path from a session name.

    Filename: snake_case of the first 24 chars + datetime stamp.
    Doc title: the session name as-is.
    """
    slug = re.sub(r"[^a-z0-9]+", "_", session_name[:24].lower()).strip("_")
    stamp = start_time.strftime("%Y_%m_%d_%H%M")
    return f"Transcriptions/{slug}_{stamp}.md"


class PauseRequested(Exception):
    pass


def check_keypress():
    """Return a character if a key was pressed, None otherwise. Requires raw terminal mode."""
    if select.select([sys.stdin], [], [], 0)[0]:
        return sys.stdin.read(1)
    return None


def obsidian_put(path, content):
    """Create or overwrite a note in Obsidian."""
    req = Request(
        f"{OBSIDIAN_URL}/vault/{path}",
        data=content.encode("utf-8"),
        method="PUT",
        headers={
            "Authorization": f"Bearer {OBSIDIAN_API_KEY}",
            "Content-Type": "text/markdown",
        },
    )
    urlopen(req, context=OBSIDIAN_SSL)


def obsidian_read(path):
    """Read a note from Obsidian."""
    req = Request(
        f"{OBSIDIAN_URL}/vault/{path}",
        method="GET",
        headers={
            "Authorization": f"Bearer {OBSIDIAN_API_KEY}",
            "Accept": "text/markdown",
        },
    )
    return urlopen(req, context=OBSIDIAN_SSL).read().decode("utf-8")


def obsidian_append(path, content):
    """Append content to an existing note in Obsidian by reading and rewriting."""
    existing = obsidian_read(path)
    obsidian_put(path, existing + content)


def find_device_index(name):
    p = pyaudio.PyAudio()
    for i in range(p.get_device_count()):
        info = p.get_device_info_by_index(i)
        if info["name"] == name and info["maxInputChannels"] > 0:
            p.terminate()
            return i
    p.terminate()
    raise RuntimeError(f"Audio device '{name}' not found")


class DisplayState:
    def __init__(self, max_duration, silence_timeout, inactivity_timeout):
        self.lines = deque(maxlen=10)
        self.speakers = set()
        self.partial = ""
        self.max_duration = max_duration
        self.silence_timeout = silence_timeout
        self.inactivity_timeout = inactivity_timeout
        self.paused = False
        self.billed_seconds = 0.0
        self.session_start = time.monotonic()
        self.last_audio_time = time.monotonic()
        self.last_transcript_time = time.monotonic()

    @property
    def elapsed_billed(self):
        total = self.billed_seconds
        if not self.paused:
            total += time.monotonic() - self.session_start
        return total

    def pause(self):
        self.billed_seconds += time.monotonic() - self.session_start
        self.paused = True

    def resume(self):
        now = time.monotonic()
        self.session_start = now
        self.last_audio_time = now
        self.last_transcript_time = now
        self.paused = False

    @property
    def stop_reason(self):
        if self.paused:
            return None
        now = time.monotonic()
        if self.elapsed_billed >= self.max_duration:
            return "max_duration"
        if now - self.last_audio_time >= self.silence_timeout:
            return "silence"
        if now - self.last_transcript_time >= self.inactivity_timeout:
            return "inactivity"
        return None

    def _countdown_bar(self, label, elapsed, timeout):
        remaining = max(0, timeout - elapsed)
        m, s = int(remaining // 60), int(remaining % 60)
        filled = int(remaining / timeout * 20)
        bar = "█" * filled + "░" * (20 - filled)
        return f"⚠ {label} — stopping in {m}:{s:02d}  {bar}"

    def _build_frame(self, cols, left_title, right_title):
        pad = cols - len(left_title) - len(right_title) - 6
        header = f"┌─ {left_title} {'─' * max(pad, 1)} {right_title} ─┐"
        divider = f"├{'─' * (cols - 2)}┤"
        bottom = f"└{'─' * (cols - 2)}┘"
        inner_w = cols - 4

        def row(text=""):
            truncated = text[:inner_w]
            return f"│ {truncated:<{inner_w}} │"

        return header, divider, bottom, inner_w, row

    def render(self):
        cols = shutil.get_terminal_size().columns
        now = time.monotonic()
        remaining = max(0, self.max_duration - self.elapsed_billed)
        h, m, s = int(remaining // 3600), int(remaining % 3600 // 60), int(remaining % 60)

        header, divider, bottom, inner_w, row = self._build_frame(
            cols, "Live Transcription", f"{h}:{m:02d}:{s:02d} remaining"
        )

        lines = [header]

        # Transcript lines
        transcript_lines = list(self.lines)
        if not transcript_lines and not self.partial:
            lines.append(row("Waiting for speech..."))
        else:
            for tl in transcript_lines:
                lines.append(row(tl))
        if self.partial:
            lines.append(row(f"  {self.partial}"))

        # Speakers + cost
        lines.append(divider)
        cost = self.elapsed_billed * COST_PER_SECOND
        cost_str = f"${cost:.4f}"
        if self.speakers:
            speaker_str = "Speakers: " + " · ".join(sorted(self.speakers))
        else:
            speaker_str = "Speakers: (none yet)"
        padding = inner_w - len(speaker_str) - len(cost_str)
        if padding > 0:
            lines.append(row(f"{speaker_str}{' ' * padding}{cost_str}"))
        else:
            lines.append(row(speaker_str))
            lines.append(row(f"{'Cost: ':>20}{cost_str}"))

        silence_elapsed = now - self.last_audio_time
        inactivity_elapsed = now - self.last_transcript_time
        footer_msg = None

        if silence_elapsed > 5:
            footer_msg = self._countdown_bar("No audio", silence_elapsed, self.silence_timeout)
        elif inactivity_elapsed > 5:
            footer_msg = self._countdown_bar("No speech", inactivity_elapsed, self.inactivity_timeout)

        if footer_msg:
            lines.append(divider)
            lines.append(row(footer_msg))

        # Hint bar
        lines.append(divider)
        lines.append(row("Space: pause  ·  Ctrl+C: quit"))

        lines.append(bottom)

        output = CLEAR_SCREEN + "\n".join(lines)
        print(output, flush=True)

    def render_paused(self):
        cols = shutil.get_terminal_size().columns
        cost = self.elapsed_billed * COST_PER_SECOND

        header, divider, bottom, inner_w, row = self._build_frame(
            cols, "PAUSED", f"${cost:.4f} spent"
        )

        lines = [header]

        transcript_lines = list(self.lines)
        if transcript_lines:
            for tl in transcript_lines[-5:]:
                lines.append(row(tl))
        else:
            lines.append(row("(no transcriptions yet)"))

        lines.append(divider)
        if self.speakers:
            lines.append(row("Speakers: " + " · ".join(sorted(self.speakers))))

        lines.append(divider)
        lines.append(row("Disconnected — not billing"))
        lines.append(row(""))
        lines.append(row("Space: resume  ·  Ctrl+C: quit"))

        lines.append(bottom)

        output = CLEAR_SCREEN + "\n".join(lines)
        print(output, flush=True)


def make_callbacks(display, session_name, note_path, start_time):
    def on_begin(self, event: BeginEvent):
        header = f"# {session_name}\n\n{start_time.strftime('%Y-%m-%d %H:%M:%S')}\n\n"
        obsidian_put(note_path, header)
        display.render()

    def on_turn(self, event: TurnEvent):
        speaker = getattr(event, "speaker_label", None) or "UNKNOWN"
        display.speakers.add(speaker)
        if event.end_of_turn:
            if event.transcript.strip():
                display.lines.append(f"[{speaker}] {event.transcript}")
                display.last_transcript_time = time.monotonic()
                ts = datetime.now().strftime("%H:%M:%S")
                obsidian_append(note_path, f"**[{ts}] {speaker}:** {event.transcript}\n\n")
            display.partial = ""
        else:
            display.partial = f"[{speaker}] {event.transcript}"
        display.render()

    def on_terminated(self, event: TerminationEvent):
        print(CLEAR_SCREEN, end="")
        print(f"Session ended: {event.audio_duration_seconds}s of audio processed")

    def on_error(self, error: StreamingError):
        print(CLEAR_SCREEN, end="")
        print(f"Error: {error}")

    return on_begin, on_turn, on_terminated, on_error


class MixedAudioStream:
    """Iterator that captures system audio (BlackHole 48kHz stereo) + mic (48kHz mono),
    mixes them, and outputs 16kHz mono for AssemblyAI."""

    CAPTURE_RATE = 48000
    OUTPUT_RATE = 16000
    DOWNSAMPLE_RATIO = CAPTURE_RATE // OUTPUT_RATE  # 3

    SILENCE_THRESHOLD = 50

    def __init__(self, system_device_index, mic_device_index, display, recorder=None, frames_per_buffer=4800):
        self.p = pyaudio.PyAudio()
        self.frames_per_buffer = frames_per_buffer
        self.display = display
        self.recorder = recorder
        self.last_render_time = 0

        # BlackHole: 48kHz stereo
        self.system_stream = self.p.open(
            format=pyaudio.paInt16,
            channels=2,
            rate=self.CAPTURE_RATE,
            input=True,
            input_device_index=system_device_index,
            frames_per_buffer=frames_per_buffer,
        )

        # Mic: 48kHz mono
        self.mic_stream = self.p.open(
            format=pyaudio.paInt16,
            channels=1,
            rate=self.CAPTURE_RATE,
            input=True,
            input_device_index=mic_device_index,
            frames_per_buffer=frames_per_buffer,
        )

    def __iter__(self):
        return self

    def __next__(self):
        key = check_keypress()
        if key == " ":
            raise PauseRequested

        reason = self.display.stop_reason
        if reason:
            print(CLEAR_SCREEN, end="")
            messages = {
                "max_duration": "Max duration reached. Stopping.",
                "silence": "No audio detected. Stopping.",
                "inactivity": "No speech detected. Stopping.",
            }
            print(messages[reason])
            raise StopIteration

        # Read system audio (stereo)
        sys_data = self.system_stream.read(self.frames_per_buffer, exception_on_overflow=False)
        sys_samples = struct.unpack(f"{len(sys_data) // 2}h", sys_data)
        # Stereo to mono
        sys_mono = [(sys_samples[i] + sys_samples[i + 1]) // 2 for i in range(0, len(sys_samples), 2)]

        # Read mic audio (mono)
        mic_data = self.mic_stream.read(self.frames_per_buffer, exception_on_overflow=False)
        mic_mono = list(struct.unpack(f"{len(mic_data) // 2}h", mic_data))

        # Mix: average both sources, clamp to int16 range
        mixed = [
            max(-32768, min(32767, (s + m) // 2))
            for s, m in zip(sys_mono, mic_mono)
        ]

        # Downsample 48kHz -> 16kHz
        downsampled = mixed[:: self.DOWNSAMPLE_RATIO]

        rms = (sum(s * s for s in downsampled) / len(downsampled)) ** 0.5
        now = time.monotonic()
        if rms > self.SILENCE_THRESHOLD:
            self.display.last_audio_time = now

        # Throttle renders to ~1/sec for timer updates
        if now - self.last_render_time >= 1.0:
            self.display.render()
            self.last_render_time = now

        packed = struct.pack(f"{len(downsampled)}h", *downsampled)
        if self.recorder:
            self.recorder.write(packed)
        return packed

    def close(self):
        if self.p is None:
            return
        self.system_stream.stop_stream()
        self.system_stream.close()
        self.mic_stream.stop_stream()
        self.mic_stream.close()
        self.p.terminate()
        self.p = None


class AudioRecorder:
    """Pipes raw PCM audio to ffmpeg for Opus encoding."""

    def __init__(self, path):
        self.path = path
        self.proc = subprocess.Popen(
            [
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                "-f", "s16le", "-ar", "16000", "-ac", "1", "-i", "pipe:0",
                "-c:a", "libopus", "-b:a", "24k", "-application", "voip",
                path,
            ],
            stdin=subprocess.PIPE,
        )

    def write(self, pcm_bytes):
        if self.proc and self.proc.stdin:
            self.proc.stdin.write(pcm_bytes)

    def close(self):
        if self.proc and self.proc.stdin:
            self.proc.stdin.close()
            self.proc.wait()
            self.proc = None


def prompt_setting(label, default, cast=int):
    raw = input(f"  {label} [{default}]: ").strip()
    if not raw:
        return default
    return cast(raw)


def prompt_yn(label, default=False):
    hint = "Y/n" if default else "y/N"
    raw = input(f"  {label} [{hint}]: ").strip().lower()
    if not raw:
        return default
    return raw in ("y", "yes")


def setup_interactive():
    print("┌─ Session Setup ─────────────────────────────┐")
    print("│  Press Enter to accept defaults              │")
    print("└──────────────────────────────────────────────┘")
    print()
    session_name = input("  Session name: ").strip()
    if not session_name:
        session_name = f"Transcript {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
    speakers = prompt_setting("Max speakers", 2, int)
    max_hours = prompt_setting("Max duration (hours)", 4, float)
    silence_min = prompt_setting("Silence timeout (minutes)", 5, float)
    inactivity_min = prompt_setting("Inactivity timeout (minutes)", 5, float)
    record = prompt_yn("Save audio recording")
    audio_path = None
    if record:
        default_path = f"recording_{datetime.now().strftime('%Y-%m-%d_%H-%M-%S')}.ogg"
        raw = input(f"  Output file [{default_path}]: ").strip()
        audio_path = raw or default_path
    print()
    return session_name, speakers, max_hours, silence_min, inactivity_min, audio_path


def wait_for_resume(display):
    """Block until spacebar is pressed."""
    display.render_paused()
    while True:
        key = check_keypress()
        if key == " ":
            return
        if key == "\x03":
            raise KeyboardInterrupt
        time.sleep(0.1)


def main():
    session_name, speakers, max_hours, silence_min, inactivity_min, audio_path = setup_interactive()
    start_time = datetime.now()
    note_path = make_obsidian_note_path(session_name, start_time)

    system_index = find_device_index(BLACKHOLE_DEVICE_NAME)
    mic_index = find_device_index(MIC_DEVICE_NAME)

    display = DisplayState(
        max_duration=max_hours * 3600,
        silence_timeout=silence_min * 60,
        inactivity_timeout=inactivity_min * 60,
    )

    recorder = AudioRecorder(audio_path) if audio_path else None

    params = StreamingParameters(
        sample_rate=SAMPLE_RATE,
        speech_model="u3-rt-pro",
        speaker_labels=True,
    )
    if speakers > 2:
        params.max_speakers = speakers

    old_settings = termios.tcgetattr(sys.stdin)
    try:
        tty.setcbreak(sys.stdin.fileno())

        while True:
            on_begin, on_turn, on_terminated, on_error = make_callbacks(display, session_name, note_path, start_time)

            client = StreamingClient(
                StreamingClientOptions(
                    api_key=API_KEY,
                    api_host="streaming.assemblyai.com",
                )
            )
            client.on(StreamingEvents.Begin, on_begin)
            client.on(StreamingEvents.Turn, on_turn)
            client.on(StreamingEvents.Termination, on_terminated)
            client.on(StreamingEvents.Error, on_error)

            client.connect(params)
            audio_stream = MixedAudioStream(system_index, mic_index, display, recorder)
            paused = False

            try:
                client.stream(audio_stream)
                break  # Normal end (timeout)
            except PauseRequested:
                paused = True
            except KeyboardInterrupt:
                break
            finally:
                audio_stream.close()
                client.disconnect(terminate=True)

            if paused:
                display.partial = ""
                display.pause()
                wait_for_resume(display)
                display.resume()

    finally:
        if recorder:
            recorder.close()
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
        print(CLEAR_SCREEN, end="")
        cost = display.elapsed_billed * COST_PER_SECOND
        msg = f"Session ended. Billed time: {display.elapsed_billed:.0f}s — Est. cost: ${cost:.4f}"
        if audio_path:
            msg += f"\nAudio saved to: {audio_path}"
        print(msg)


if __name__ == "__main__":
    main()
