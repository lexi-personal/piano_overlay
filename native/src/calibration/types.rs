use serde::{Deserialize, Serialize};

/// A 2D point in screen space (pixels).
#[derive(Clone, Copy, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct Point2D {
    pub x: f64,
    pub y: f64,
}

impl Point2D {
    pub fn new(x: f64, y: f64) -> Self {
        Self { x, y }
    }
}

/// The four corners of the piano keyboard as seen in the video frame.
/// Points should be placed at the outermost visible key edges.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct KeyboardCorners {
    /// Top-left corner of the keyboard (far edge, left side).
    pub top_left: Point2D,
    /// Top-right corner of the keyboard (far edge, right side).
    pub top_right: Point2D,
    /// Bottom-right corner of the keyboard (near edge, right side).
    pub bottom_right: Point2D,
    /// Bottom-left corner of the keyboard (near edge, left side).
    pub bottom_left: Point2D,
}

/// Supported keyboard sizes.
#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq)]
pub enum KeyboardSize {
    Keys88,
    Keys76,
    Keys61,
    Keys49,
}

impl KeyboardSize {
    /// Total number of keys.
    pub fn total_keys(&self) -> u8 {
        match self {
            KeyboardSize::Keys88 => 88,
            KeyboardSize::Keys76 => 76,
            KeyboardSize::Keys61 => 61,
            KeyboardSize::Keys49 => 49,
        }
    }

    /// Number of white keys.
    pub fn white_keys(&self) -> u8 {
        match self {
            KeyboardSize::Keys88 => 52,
            KeyboardSize::Keys76 => 45,
            KeyboardSize::Keys61 => 36,
            KeyboardSize::Keys49 => 29,
        }
    }

    /// Lowest MIDI note number.
    pub fn lowest_note(&self) -> u8 {
        match self {
            KeyboardSize::Keys88 => 21, // A0
            KeyboardSize::Keys76 => 28, // E1
            KeyboardSize::Keys61 => 36, // C2
            KeyboardSize::Keys49 => 36, // C2
        }
    }

    /// Highest MIDI note number.
    pub fn highest_note(&self) -> u8 {
        self.lowest_note() + self.total_keys() - 1
    }
}

/// Full calibration data including computed homography and key positions.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CalibrationData {
    /// User-placed corner points in video frame coordinates.
    pub corners: KeyboardCorners,
    /// Selected keyboard size.
    pub keyboard_size: KeyboardSize,
    /// 3x3 homography matrix (row-major) mapping canonical → screen space.
    pub homography: [[f64; 3]; 3],
    /// Pre-computed screen-space positions for each key.
    pub key_positions: Vec<KeyPosition>,
    /// Explicit key range. Absent for projects calibrated before custom
    /// ranges existed, in which case it is derived from `keyboard_size`.
    #[serde(default)]
    pub key_range: Option<KeyRange>,
}

/// The span of keys the calibration covers.
#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq)]
pub struct KeyRange {
    /// Lowest MIDI note on the keyboard.
    pub lowest_note: u8,
    /// Highest MIDI note on the keyboard.
    pub highest_note: u8,
    /// Number of white keys in the range.
    pub white_keys: u8,
}

impl KeyRange {
    /// Build a range from an inclusive note span, counting the white keys.
    pub fn new(lowest_note: u8, highest_note: u8) -> Self {
        let white_keys = (lowest_note..=highest_note)
            .filter(|n| !matches!(n % 12, 1 | 3 | 6 | 8 | 10))
            .count() as u8;
        Self {
            lowest_note,
            highest_note,
            white_keys,
        }
    }
}

impl CalibrationData {
    /// The effective key range, falling back to the standard keyboard sizes.
    pub fn effective_key_range(&self) -> KeyRange {
        self.key_range.unwrap_or_else(|| {
            KeyRange::new(
                self.keyboard_size.lowest_note(),
                self.keyboard_size.highest_note(),
            )
        })
    }
}

/// Screen-space position of a single piano key (perspective-transformed trapezoid).
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct KeyPosition {
    /// MIDI note number for this key.
    pub note: u8,
    /// Whether this is a black key.
    pub is_black: bool,
    /// The four corners of this key in screen space (perspective-corrected).
    /// Order: top-left, top-right, bottom-right, bottom-left.
    pub screen_quad: [Point2D; 4],
    /// Center x-position in canonical (normalized) space. Used for strip alignment.
    pub canonical_x_center: f64,
}
