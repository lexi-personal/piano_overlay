# Piano Overlay

A Flutter desktop application that creates visual overlays of piano key presses on video. Import a MIDI file and a piano performance video, calibrate the keyboard position, and export a video with animated note strips falling onto the keys.

## Features

- **Import** MP4/MOV/AVI/MKV videos, MIDI files, and MIDI clips from Ableton `.als` sets
- **Calibrate** keyboard position by placing 4 corners directly on the workspace video (49/61/76/88 keys, or a custom range)
- **Sync** MIDI playback offset with video audio (±60s slider, ±10/±100 ms nudges, manual entry)
- **Style** per-hand or per-key-type colors, glow, transparency, lane opacity, fall speed, lookahead,
  lane projection (in perspective or upright),
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
The calibration grid uses the same perspective mapping as the notes, so check its key
boundaries against the video before applying. On a steeply angled shot,
**Style → Timing → Projection → Upright** often reads better than the default.
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

### Importing from Ableton Live

An `.als` import takes only the notes Live actually plays, which is narrower than the notes the
file stores:

- **Take lanes are ignored.** Comping a recording leaves every raw pass in the set. Live plays
  only the arrangement clip you comped, so importing the lanes would multiply the note count
  several times over.
- **The loop brace decides what sounds.** Trimming a clip in Live hides notes rather than
  deleting them, so notes outside the brace are dropped, and a note running past it is cut off
  there instead of ringing on.
- **Looping clips are expanded**, repeating their brace until the arrangement clip is filled.
- **Deactivated clips and deactivated individual notes are skipped.**
- Arrangement clips win; a set that only ever used the Session view falls back to its clip slots.

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

### How note strips are placed

The calibration gives a homography mapping a canonical keyboard rectangle onto the four corners
you placed in the video. **Every strip corner goes through that homography**, so a strip always
sits exactly where its key sits.

This matters more than it sounds. Under perspective, key spacing is not uniform on screen: keys
compress toward the far end of an angled keyboard. Positioning notes by interpolating linearly
along the keyboard edge instead drags them off target by up to two octaves in the middle of the
keyboard, while still looking correct at the two ends.

**Projection** (Style -> Timing) chooses where the strips travel:

- **In perspective** (default) - notes recede along the keyboard plane, as if painted on the
  surface behind the keys. Keeps the camera's perspective and stays readable at steep angles. The
  lane is clamped so it stops short of the horizon on shots that look along the keyboard plane.
- **Upright** - notes rise straight up the screen, as if on a wall standing behind the keys. The
  rise at each end is scaled by the keyboard's depth there, so the near side gets a taller lane.
  Ignores the camera angle entirely, but on a near edge-on shot the keyboard's horizontal screen
  extent is small, so the lane is narrow and notes bunch together. Best on head-on shots.

Neither is a full 3D reconstruction: at extreme angles projected keys can overlap or occlude one
another.

The same geometry is implemented twice — `lib/shared/overlay_geometry.dart` for the live preview
and `native/src/overlay_geometry/engine.rs` for the export — and the two **must** stay in sync, or
the exported video will not match what you previewed.

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

### Running under WSL

WSLg routes OpenGL through a Direct3D 12 translation layer, and Flutter's compositor deadlocks
against it: the window stops repainting and the app looks frozen even though nothing in it is
actually blocked. The app detects WSL at startup and falls back to Mesa's software rasteriser,
which avoids that driver. Video decoding is kept off the GPU for the same reason.

If you are on WSL with a working GPU stack and want to try the hardware path:

```bash
PIANO_OVERLAY_GPU=1 PIANO_OVERLAY_VIDEO_HWACCEL=1 ./piano_overlay
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
