# Piano Overlay

A Flutter desktop application that creates visual overlays of piano key presses on video. Import a MIDI file and a piano performance video, calibrate the keyboard position, and export a video with animated note strips falling onto the keys.

## Features

- **Import** MP4/MOV/AVI/MKV videos, MIDI files, and MIDI clips from Ableton `.als` sets
- **Calibrate** keyboard position by placing 4 corners on the video frame (49/61/76/88 keys, or a custom range)
- **Sync** MIDI playback offset with video audio (±60s slider, ±10/±100 ms nudges, manual entry)
- **Style** per-hand or per-key-type colors, glow, transparency, lane opacity, fall speed, and lookahead
- **Preview** real-time overlay visualization with video playback, toggleable overlay
- **Export** rendered MP4 video with overlay via FFmpeg

## Using the app

Everything happens in the **workspace**: a left panel for files/calibration/sync, a right panel
for style/export, the video with its live overlay in the centre, and a timeline at the bottom.
Calibration and export open as dedicated full-screen steps.

Projects are saved as `.pvproj` files (JSON). Use **Save** (`Ctrl+S`) or **Save As…** in the
workspace toolbar; an orange dot next to the project name marks unsaved changes, and leaving the
workspace with unsaved work prompts you to save, discard, or cancel.

## Architecture

```
Flutter UI (Workspace + Calibration/Export screens)
    ↓ (ChangeNotifier)
ProjectProvider (State)
    ↓ (JSON over FFI)
NativeBridge (dart:ffi)
    ↓ (C ABI)
Rust Core (Business Logic)
    ├── MIDI Parsing (midly)
    ├── Video Metadata (ffprobe)
    ├── Calibration & Homography (nalgebra)
    ├── Overlay Geometry Engine
    ├── Export Pipeline (FFmpeg subprocess)
    └── Project Management (.pvproj JSON)
```

## Prerequisites

- **Flutter** ≥ 3.3.0
- **Rust** toolchain (for building the native library)
- **FFmpeg** installed and available in PATH (required for video metadata extraction and export)

### Installing FFmpeg

- **Linux**: `sudo apt install ffmpeg` or `sudo dnf install ffmpeg`
- **macOS**: `brew install ffmpeg`
- **Windows**: Download from [ffmpeg.org](https://ffmpeg.org/download.html) and add to PATH

## Building

### 1. Build the Rust native library

```bash
cd native
cargo build --release
```

This produces:
- Linux: `native/target/release/libpiano_overlay_native.so`
- macOS: `native/target/release/libpiano_overlay_native.dylib`
- Windows: `native/target/release/piano_overlay_native.dll`

### 2. Run the Flutter app

```bash
flutter run -d linux   # or -d macos, -d windows
```

### 3. Run tests

```bash
# Rust tests, formatting and lints
cd native && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test

# Flutter analysis and tests (requires native library built)
flutter analyze
flutter test
```

All of the above run on every push and pull request via `.github/workflows/ci.yml`.

## Project Files

Project files use the `.pvproj` extension (JSON format) and store video/MIDI paths, calibration
data, style settings, and sync offsets. Save them from the workspace toolbar and reopen them from
the home screen.

## License

See LICENSE file for details.
