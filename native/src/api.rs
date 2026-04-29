//! Public API exposed to Dart via flutter_rust_bridge.
//! All functions here are callable from the Flutter UI layer.

use crate::midi;
use crate::video;
use crate::project::types::Project;
use crate::midi::types::{MidiFileData, MidiFileSummary};
use crate::video::VideoMetadata;

/// Parse a MIDI file and return structured data with absolute millisecond timing.
pub fn api_parse_midi(path: String) -> Result<MidiFileData, String> {
    midi::parse_midi_file(&path).map_err(|e| e.to_string())
}

/// Get a brief summary of a MIDI file without full parsing.
pub fn api_get_midi_summary(path: String) -> Result<MidiFileSummary, String> {
    let data = midi::parse_midi_file(&path).map_err(|e| e.to_string())?;
    Ok(data.summary())
}

/// Extract video metadata (resolution, fps, duration, codec, audio info).
pub fn api_extract_video_metadata(path: String) -> Result<VideoMetadata, String> {
    video::extract_video_metadata(&path).map_err(|e| e.to_string())
}

/// Create a new empty project.
pub fn api_create_project(name: String) -> String {
    let project = Project::new(name);
    project.to_json().unwrap_or_default()
}

/// Save a project to disk.
pub fn api_save_project(project_json: String, path: String) -> Result<(), String> {
    let project = Project::from_json(&project_json).map_err(|e| e.to_string())?;
    project.save_to_file(&path).map_err(|e| e.to_string())
}

/// Load a project from disk.
pub fn api_load_project(path: String) -> Result<String, String> {
    let project = Project::load_from_file(&path).map_err(|e| e.to_string())?;
    project.to_json().map_err(|e| e.to_string())
}

/// Simple health check to verify FFI is working.
pub fn api_health_check() -> String {
    "piano_overlay_native v0.1.0".to_string()
}
