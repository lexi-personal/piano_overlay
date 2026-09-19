use serde::{Deserialize, Serialize};

use crate::calibration::CalibrationData;
use crate::midi::MidiFileSummary;
use crate::overlay_geometry::{ExportSettings, OverlayStyle, SyncSettings};
use crate::video::VideoMetadata;

/// The complete project state, serialized to a .pvproj file.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Project {
    /// Project file format version.
    pub version: String,
    /// User-given project name.
    pub name: String,
    /// When the project was created (ISO 8601).
    pub created_at: String,
    /// When the project was last modified (ISO 8601).
    pub modified_at: String,

    /// Video file info (None if not yet imported).
    pub video: Option<VideoReference>,
    /// MIDI file info (None if not yet imported).
    pub midi: Option<MidiReference>,
    /// Calibration state (None if not yet calibrated).
    pub calibration: Option<CalibrationData>,
    /// Sync settings.
    pub sync: SyncSettings,
    /// Overlay visual style.
    pub style: OverlayStyle,
    /// Export settings.
    pub export: ExportSettings,
}

/// Reference to an imported video file.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct VideoReference {
    /// Absolute path to the video file.
    pub path: String,
    /// Extracted metadata.
    pub metadata: VideoMetadata,
}

/// Reference to an imported MIDI file.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MidiReference {
    /// Absolute path to the MIDI file.
    pub path: String,
    /// Summary info.
    pub summary: MidiFileSummary,
}

impl Project {
    /// Create a new empty project.
    pub fn new(name: String) -> Self {
        let now = chrono_now();
        Self {
            version: "1.0.0".to_string(),
            name,
            created_at: now.clone(),
            modified_at: now,
            video: None,
            midi: None,
            calibration: None,
            sync: SyncSettings::default(),
            style: OverlayStyle::default(),
            export: ExportSettings::default(),
        }
    }

    /// Serialize project to JSON string.
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(self)
    }

    /// Deserialize project from JSON string.
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }

    /// Save project to a .pvproj file.
    pub fn save_to_file(&self, path: &str) -> Result<(), ProjectError> {
        let json = self
            .to_json()
            .map_err(|e| ProjectError::SerializeError(e.to_string()))?;
        std::fs::write(path, json).map_err(|e| ProjectError::IoError(e.to_string()))?;
        Ok(())
    }

    /// Load project from a .pvproj file.
    pub fn load_from_file(path: &str) -> Result<Self, ProjectError> {
        let json =
            std::fs::read_to_string(path).map_err(|e| ProjectError::IoError(e.to_string()))?;
        Self::from_json(&json).map_err(|e| ProjectError::DeserializeError(e.to_string()))
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ProjectError {
    #[error("IO error: {0}")]
    IoError(String),
    #[error("Serialization error: {0}")]
    SerializeError(String),
    #[error("Deserialization error: {0}")]
    DeserializeError(String),
}

/// ISO-8601 UTC timestamp, computed without pulling in a datetime crate.
fn chrono_now() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};

    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    let days = secs.div_euclid(86_400);
    let time_of_day = secs.rem_euclid(86_400);
    let (hour, minute, second) = (
        time_of_day / 3600,
        (time_of_day % 3600) / 60,
        time_of_day % 60,
    );
    let (year, month, day) = civil_from_days(days);

    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        year, month, day, hour, minute, second
    )
}

/// Convert days since the Unix epoch into a (year, month, day) civil date.
/// Howard Hinnant's `civil_from_days` algorithm.
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_civil_from_days() {
        assert_eq!(civil_from_days(0), (1970, 1, 1));
        assert_eq!(civil_from_days(19_723), (2024, 1, 1));
        assert_eq!(civil_from_days(19_782), (2024, 2, 29));
        assert_eq!(civil_from_days(-1), (1969, 12, 31));
    }

    #[test]
    fn test_chrono_now_is_iso8601_and_current() {
        let now = chrono_now();
        assert_eq!(now.len(), 20);
        assert!(now.ends_with('Z'));
        let year: i64 = now[..4].parse().unwrap();
        assert!(year >= 2024, "unexpected year in {now}");
    }

    #[test]
    fn test_project_roundtrip_json() {
        let project = Project::new("Test Project".to_string());
        let json = project.to_json().unwrap();
        let loaded = Project::from_json(&json).unwrap();
        assert_eq!(loaded.name, "Test Project");
        assert_eq!(loaded.version, "1.0.0");
        assert!(loaded.video.is_none());
        assert!(loaded.midi.is_none());
        assert!(loaded.calibration.is_none());
    }

    #[test]
    fn test_project_save_load_file() {
        let project = Project::new("File Test".to_string());
        let path = "/tmp/test_piano_overlay_project.pvproj";
        project.save_to_file(path).unwrap();
        let loaded = Project::load_from_file(path).unwrap();
        assert_eq!(loaded.name, "File Test");
        std::fs::remove_file(path).ok();
    }
}
