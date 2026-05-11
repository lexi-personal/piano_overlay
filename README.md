# Piano Overlay

A Flutter desktop application that creates visual overlays of piano key presses on video. Import a MIDI file and a piano performance video, calibrate the keyboard position, and export a video with animated note strips falling onto the keys.

## Features

- **Import** MP4/MOV/AVI/MKV videos and MIDI files
- **Calibrate** keyboard position by placing 4 corners on the video frame (supports 49, 61, 76, and 88 keys)
- **Sync** MIDI playback offset with video audio (coarse ±5s, fine ±100ms)
- **Style** customizable colors, glow, transparency, fall speed, and direction
- **Preview** real-time overlay visualization with video playback
- **Export** rendered MP4 video with overlay via FFmpeg

## Architecture

```
Flutter UI (Screens + Widgets)
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
# Rust tests
cd native && cargo test

# Flutter tests (requires native library built)
flutter test
```

## Project Files

Project files use the `.pvproj` extension (JSON format) and store video/MIDI paths, calibration data, style settings, and sync offsets.

## License

See LICENSE file for details.
