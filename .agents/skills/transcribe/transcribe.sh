#!/usr/bin/env bash
set -euo pipefail

# Resolve paths relative to this script's directory
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(cd "$SKILL_DIR/../../.." && pwd)"
WHISPER_DIR="$WORKSPACE/opensource/whisper.cpp"
WHISPER_CLI="$WHISPER_DIR/build/bin/whisper-cli"
MODEL="$WHISPER_DIR/models/ggml-small.bin"
AUDIO_FILE="$1"

if [ -z "$AUDIO_FILE" ]; then
    echo "Usage: $0 <audio-file>" >&2
    exit 1
fi

if [ ! -f "$AUDIO_FILE" ]; then
    echo "Error: file not found: $AUDIO_FILE" >&2
    exit 1
fi

# Check if the file is WAV; if not, convert via ffmpeg
if [[ "$AUDIO_FILE" != *.wav ]]; then
    if ! command -v ffmpeg &>/dev/null; then
        echo "Error: ffmpeg is required for non-WAV files. Install with: sudo apt install ffmpeg" >&2
        exit 1
    fi
    TEMP_WAV=$(mktemp /tmp/whisper-XXXXXX.wav)
    trap 'rm -f "$TEMP_WAV"' EXIT
    ffmpeg -y -i "$AUDIO_FILE" -ar 16000 -ac 1 -c:a pcm_s16le "$TEMP_WAV" -loglevel error
    AUDIO_FILE="$TEMP_WAV"
fi

"$WHISPER_CLI" -m "$MODEL" -f "$AUDIO_FILE" -t "$(nproc)" -ng -np 2>/dev/null