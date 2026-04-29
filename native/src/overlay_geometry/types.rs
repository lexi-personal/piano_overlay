use serde::{Deserialize, Serialize};

use crate::calibration::Point2D;

/// Style settings for the MIDI overlay visualization.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct OverlayStyle {
    /// Color for notes on white keys (RGBA, 0.0-1.0).
    pub white_key_color: [f32; 4],
    /// Color for notes on black keys (RGBA, 0.0-1.0).
    pub black_key_color: [f32; 4],
    /// Strip thickness as fraction of key width (0.0-1.0).
    pub strip_thickness: f32,
    /// Glow strength (0.0-1.0).
    pub glow_strength: f32,
    /// Glow radius in pixels.
    pub glow_radius: f32,
    /// Overall transparency of strips (0.0-1.0, where 1.0 = fully opaque).
    pub transparency: f32,
    /// How far ahead (in ms) to show notes before they are played.
    pub lookahead_ms: f64,
    /// Whether notes appear as they fall toward the keyboard.
    pub show_before_play: bool,
    /// Whether notes remain visible during their sounding duration.
    pub show_during_play: bool,
    /// Fall speed: pixels per second in canonical space.
    pub fall_speed: f32,
    /// Fall direction.
    pub fall_direction: FallDirection,
    /// Whether to highlight keys when they are being pressed.
    pub key_highlight_enabled: bool,
    /// Key highlight color (RGBA).
    pub key_highlight_color: [f32; 4],
    /// Background dimming (0.0 = no dim, 1.0 = fully black).
    pub background_dim: f32,
}

impl Default for OverlayStyle {
    fn default() -> Self {
        Self {
            white_key_color: [0.31, 0.76, 0.97, 0.85], // Light blue
            black_key_color: [1.0, 0.44, 0.26, 0.85],  // Orange
            strip_thickness: 0.8,
            glow_strength: 0.5,
            glow_radius: 8.0,
            transparency: 0.85,
            lookahead_ms: 2000.0,
            show_before_play: true,
            show_during_play: true,
            fall_speed: 200.0,
            fall_direction: FallDirection::TopToBottom,
            key_highlight_enabled: true,
            key_highlight_color: [1.0, 1.0, 1.0, 0.25],
            background_dim: 0.0,
        }
    }
}

/// Direction note strips flow from.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum FallDirection {
    TopToBottom,
    BottomToTop,
    Custom { angle_degrees: f32 },
}

/// A single rendered note strip in screen space.
/// This is the output of the shared overlay geometry engine.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct NoteStrip {
    /// Four vertices of the strip trapezoid in screen-space pixels.
    /// Order: top-left, top-right, bottom-right, bottom-left.
    pub quad: [Point2D; 4],
    /// Fill color (RGBA, 0.0-1.0).
    pub color: [f32; 4],
    /// Glow radius for this strip (pixels).
    pub glow_radius: f32,
    /// Glow intensity (0.0-1.0).
    pub glow_intensity: f32,
}

/// A key highlight rectangle for an active note.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct KeyHighlight {
    /// Four vertices in screen space.
    pub quad: [Point2D; 4],
    /// Highlight color (RGBA).
    pub color: [f32; 4],
}

/// Complete overlay frame data for a single point in time.
/// This is the shared output consumed by BOTH the Flutter preview painter
/// and the Rust export compositor.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct OverlayFrame {
    /// All note strips visible at this timestamp.
    pub strips: Vec<NoteStrip>,
    /// Key highlights for currently-active notes.
    pub key_highlights: Vec<KeyHighlight>,
    /// The timestamp this frame was computed for (ms).
    pub timestamp_ms: f64,
}

/// Sync settings for aligning MIDI timing to video.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SyncSettings {
    /// Global offset in milliseconds. Positive = MIDI plays later, Negative = MIDI plays earlier.
    pub offset_ms: f64,
    /// Whether drift correction is enabled.
    pub drift_enabled: bool,
    /// Offset at the start of the piece (for linear drift correction).
    pub drift_start_ms: f64,
    /// Offset at the end of the piece (for linear drift correction).
    pub drift_end_ms: f64,
}

impl Default for SyncSettings {
    fn default() -> Self {
        Self {
            offset_ms: 0.0,
            drift_enabled: false,
            drift_start_ms: 0.0,
            drift_end_ms: 0.0,
        }
    }
}

/// Export settings.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ExportSettings {
    /// Output file path.
    pub output_path: String,
    /// Video codec ("h264" for MVP).
    pub codec: String,
    /// Quality preset ("low", "medium", "high").
    pub quality: String,
    /// Whether to use original resolution (true) or custom.
    pub use_original_resolution: bool,
    /// Custom width (only if use_original_resolution is false).
    pub custom_width: Option<u32>,
    /// Custom height (only if use_original_resolution is false).
    pub custom_height: Option<u32>,
    /// Whether to use original FPS.
    pub use_original_fps: bool,
    /// Custom FPS (only if use_original_fps is false).
    pub custom_fps: Option<f64>,
}

impl Default for ExportSettings {
    fn default() -> Self {
        Self {
            output_path: String::new(),
            codec: "h264".to_string(),
            quality: "high".to_string(),
            use_original_resolution: true,
            custom_width: None,
            custom_height: None,
            use_original_fps: true,
            custom_fps: None,
        }
    }
}
