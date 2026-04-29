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
        let json = self.to_json().map_err(|e| ProjectError::SerializeError(e.to_string()))?;
        std::fs::write(path, json).map_err(|e| ProjectError::IoError(e.to_string()))?;
        Ok(())
    }

    /// Load project from a .pvproj file.
    pub fn load_from_file(path: &str) -> Result<Self, ProjectError> {
        let json = std::fs::read_to_string(path).map_err(|e| ProjectError::IoError(e.to_string()))?;
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

/// Simple timestamp helper (avoids adding chrono dependency for now).
fn chrono_now() -> String {
    // In production, use proper datetime. For now, placeholder.
    "2026-01-01T00:00:00Z".to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

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
