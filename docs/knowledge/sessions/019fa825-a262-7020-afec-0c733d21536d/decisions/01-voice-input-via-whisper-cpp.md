## Decision: Voice Input to Pi via whisper.cpp

**Status**: accepted
**Date**: 2026-07-28
**Project**: software-factory
**Session**: sessions/019fa825-a262-7020-afec-0c733d21536d/session.jsonl

### Context

The user wanted offline speech-to-text capability to use as voice input to pi (the AI coding assistant). Two approaches were explored: Handy (a Tauri-based STT app) and whisper.cpp (a C++ STT engine).

### Problem

- **Handy** (https://github.com/cjpais/Handy) was built from source and installed, but its `transcribe-cpp` library hangs on `Model::load_with()` for both the Parakeet GGUF and Whisper `.bin` models, on both CPU and Vulkan backends. The official v0.9.4 DEB release has the same issue.
- The user needed a working voice-to-prompt pipeline that could be triggered from a keyboard shortcut.

### Alternatives

1. **Handy (official release)** — fully installed but the model loading hangs indefinitely. The bug is in transcribe-cpp, which is vendored by Handy and not easily fixable without upstream changes. Rejected.
2. **whisper.cpp directly** — cloned, built, and tested successfully. The Whisper Small model transcribed JFK's 11-second speech in ~9 seconds on CPU. Accepted.
3. **Other STT tools** (Speech Note, etc.) — not evaluated since whisper.cpp worked immediately.

### Decision

Use **whisper.cpp** as the speech-to-text engine, with a custom pi skill (`transcribe`) that wraps it. Voice input is triggered by pressing `Ctrl+Super+V` via `xbindkeys`, which:
1. Records 5 seconds from the microphone via `arecord`
2. Transcribes with `whisper-cli` using the Whisper Small model
3. Sends the transcribed text to pi as a prompt

### Rationale

- whisper.cpp built and worked immediately with no hanging issues
- The Whisper Small model (487 MB) provides good accuracy/speed trade-off on CPU
- `xbindkeys` provides reliable global hotkey support on X11
- The custom pi skill makes the capability auto-discoverable by the agent
- Minimal dependencies: `ffmpeg` for audio conversion, `xbindkeys`/`xdotool` for hotkeys

### Consequences

- **Easier**: Voice input to pi is now a single keypress away
- **Easier**: Audio file transcription via `pi, transcribe this file` works
- **Harder**: Handy's Parakeet model support is not available — whisper.cpp's `parakeet-cli` doesn't support the GGUF format that Handy uses
- **Limitation**: Current model is English-only; larger models require more RAM/CPU
- **Limitation**: Fixed 5-second recording duration; silence detection not implemented
- **Deprecated**: The Handy installation (both self-built and DEB) is essentially broken for this system

### Revision triggers

- Handy releases a fix for the transcribe-cpp model loading hang
- The user wants multilingual transcription (switch to Whisper Medium/Large or a multilingual model)
- The user switches to Wayland (xbindkeys won't work; need to switch to KDE's native shortcut system)
- The user finds the 5-second fixed recording too restrictive (implement silence-based VAD)