# Piano Overlay

A Flutter desktop application that creates visual overlays of piano key presses on video. Import a MIDI file and a piano performance video, calibrate the keyboard position, and export a video with animated note strips falling onto the keys.

## Features

- **Import** MP4/MOV/AVI/MKV videos, MIDI files, and MIDI clips from Ableton `.als` sets
- **Calibrate** keyboard position by placing 4 corners directly on the workspace video (49/61/76/88 keys, or a custom range)
- **Sync** MIDI playback offset with video audio (±60s slider, ±10/±100 ms nudges, manual entry)
- **Style** per-hand or per-key-type colors, glow, transparency, lane opacity, fall speed, lookahead,
  fall direction, key highlighting, background dim, and rounded or outlined note strips
- **Edit** per-track visibility, hand assignment, nudge and trim in the multi-track timeline
- **Preview** real-time overlay visualization with video playback, toggleable overlay
- **Export** rendered MP4 video with overlay via FFmpeg, matching the preview pixel for pixel

## Using the app

Everything happens in the **workspace**: a left panel for files/calibration/sync, a right panel
for style/export, the video with its live overlay in the centre, and a timeline at the bottom.
Calibration happens in place on the workspace video: the **Calibrate** tab puts you in a mode
where you click the four keyboard corners directly on the frame and drag the handles to adjust.
Corners are stored in video pixels, so the overlay keeps lining up when the window is resized.
If your keyboard runs off the edge of the recording, drag the **Frame zoom** slider down: the
video shrinks inside the centre area so you can drop corners in the margin outside the frame.
The overlay itself is always clipped to the video rectangle, matching what the export produces.
Export opens as a dedicated full-screen step.

Projects are saved as `.pvproj` files (JSON). Use **Save** (`Ctrl+S`) or **Save As…** in the
workspace toolbar; an orange dot next to the project name marks unsaved changes, and leaving the
workspace with unsaved work prompts you to save, discard, or cancel. The home screen lists the
projects you opened most recently.

Unsaved work is also auto-saved every 30 seconds to the application data directory. That snapshot
is deleted as soon as you save or close the project properly, so if one is still there at startup
the app offers to restore it.

Expand the timeline with the chevron on the right of the transport bar to see one lane per MIDI
track. Each lane can be hidden, assigned to the left or right hand, and dragged sideways to line
its notes up with the performance.

## Architecture

```
Flutter UI (Workspace with inline calibration + Export screen)
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
- **Linux only**: `zenity` (or `kdialog`), which the file open/save dialogs shell out to

### Installing FFmpeg

- **Linux**: `sudo apt install ffmpeg` or `sudo dnf install ffmpeg`
- **macOS**: `brew install ffmpeg`
- **Windows**: Download from [ffmpeg.org](https://ffmpeg.org/download.html) and add to PATH

### Installing zenity (Linux)

File dialogs are provided by the desktop, not by the app. On a minimal Linux install, or under
WSL, the helper is often missing and importing will report that it needs installing:

```bash
sudo apt install zenity   # or: sudo dnf install zenity
```

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
data, style settings, per-track timeline edits, and sync offsets. Save them from the workspace toolbar and reopen them from
the home screen.

## License

See LICENSE file for details.
