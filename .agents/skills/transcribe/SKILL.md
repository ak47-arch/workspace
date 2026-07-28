---
name: transcribe
description: Local speech-to-text transcription using whisper.cpp. Supports WAV, MP3, FLAC, OGG, and any ffmpeg-compatible format. Also supports live microphone recording with automatic transcription and sending to pi as a prompt. Use when the user wants to transcribe audio files, speak to pi, or use voice input.
---

# Transcribe

Local speech-to-text using [whisper.cpp](https://github.com/ggerganov/whisper.cpp) on Linux.

## Setup

The whisper.cpp build is at `{baseDir}/../../../opensource/whisper.cpp/` with binaries in `build/bin/`.

Model: `{baseDir}/../../../opensource/whisper.cpp/models/ggml-small.bin` (Whisper Small, 487 MB, ~9s per 11s audio on CPU).

## Usage

### Transcribe an audio file

```bash
{baseDir}/transcribe.sh <audio-file>
```

Outputs plain text transcription to stdout.

### Speak to pi (voice input)

```bash
{baseDir}/speak-to-pi.sh
```

Records audio from your microphone for 5 seconds, transcribes it, and sends the result as a prompt to pi.

Options:

| Flag | Description |
|------|-------------|
| `-d SECS` / `--duration SECS` | Recording duration (default: 5) |
| `-p` / `--print` | Non-interactive mode (pi -p) |
| `--` | Pass remaining args to pi |

Examples:

```bash
# Record 5s, then interactive pi session
{baseDir}/speak-to-pi.sh

# Record 10s
{baseDir}/speak-to-pi.sh -d 10

# Record and print response (non-interactive)
{baseDir}/speak-to-pi.sh -p

# Record and pass session name to pi
{baseDir}/speak-to-pi.sh -- -n "voice session"
```

## Requirements

- Linux x86_64
- `ffmpeg` for non-WAV formats: `sudo apt install ffmpeg`
- Microphone (PulseAudio or ALSA)
- `parec` (pulseaudio-utils) or `arecord` (alsa-utils)