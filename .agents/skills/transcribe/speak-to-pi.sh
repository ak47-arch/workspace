#!/usr/bin/env bash
set -euo pipefail

# Record audio from microphone, transcribe, and send as prompt to pi

# Config
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(cd "$SKILL_DIR/../../.." && pwd)"

# Ensure pi is in PATH (xbindkeys may not have the full user PATH)
export PATH="$HOME/.npm-global/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
WHISPER_DIR="$WORKSPACE/opensource/whisper.cpp"
WHISPER_CLI="$WHISPER_DIR/build/bin/whisper-cli"
MODEL="$WHISPER_DIR/models/ggml-small.bin"
TEMP_DIR=$(mktemp -d /tmp/pi-speak-XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT

AUDIO_FILE="$TEMP_DIR/recording.wav"

# Default recording duration (seconds). Use -d flag to override.
DURATION=5
PI_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--duration)
            DURATION="$2"
            shift 2
            ;;
        -p|--print)
            PI_ARGS+=("-p")
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options] [-- pi-args...]"
            echo ""
            echo "Record audio from microphone, transcribe it, and send to pi."
            echo ""
            echo "Options:"
            echo "  -d, --duration SECS  Recording duration (default: $DURATION)"
            echo "  -p, --print          Non-interactive mode (pi -p)"
            echo "  -h, --help           Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                          # Record 5s, then interactive pi session"
            echo "  $0 -d 10                    # Record 10s"
            echo "  $0 -p                       # Non-interactive (just print response)"
            echo "  $0 -- -n \"my session\"       # Pass extra args to pi"
            exit 0
            ;;
        --)
            shift
            # Remaining args are passed to pi
            PI_ARGS+=("$@")
            break
            ;;
        *)
            PI_ARGS+=("$1")
            shift
            ;;
    esac
done

echo "🎤 Recording for ${DURATION}s... (speak now)" >&2

# Record from default microphone (16kHz, 16-bit, mono)
# Try ALSA (arecord) first, then PulseAudio (parec) as fallback
if command -v arecord &>/dev/null; then
    arecord -q -r 16000 -c 1 -f S16_LE -d "$DURATION" "$AUDIO_FILE" 2>/dev/null || true
elif command -v parec &>/dev/null; then
    # PulseAudio/PipeWire
    timeout "$DURATION" parec \
        --rate=16000 \
        --channels=1 \
        --format=s16le \
        --raw \
        "$AUDIO_FILE.raw" 2>/dev/null || true
    # Convert raw to WAV
    ffmpeg -y -f s16le -ar 16000 -ac 1 -i "$AUDIO_FILE.raw" "$AUDIO_FILE" -loglevel error 2>/dev/null
    rm -f "$AUDIO_FILE.raw"
else
    echo "❌ No recording tool found (install arecord or parec)" >&2
    exit 1
fi

echo "📝 Transcribing..." >&2

# Transcribe
TRANSCRIPT=$("$WHISPER_CLI" -m "$MODEL" -f "$AUDIO_FILE" -t "$(nproc)" -ng -np 2>/dev/null)

if [ -z "$TRANSCRIPT" ]; then
    echo "❌ No speech detected or transcription failed." >&2
    exit 1
fi

echo "💬 Transcript: $TRANSCRIPT" >&2
echo "" >&2

# Send to pi
cd "$WORKSPACE"
exec pi "${PI_ARGS[@]}" "$TRANSCRIPT"