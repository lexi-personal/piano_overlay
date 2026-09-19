//! C-compatible FFI interface for calling from Dart via dart:ffi.
//! Each function takes/returns C strings (JSON) for maximum simplicity.
//!
//! Every entry point here is a C ABI boundary that receives borrowed C strings
//! from the caller, so raw-pointer dereferences are inherent to the design.
#![allow(clippy::not_unsafe_ptr_arg_deref)]

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use crate::calibration::{compute_calibration, KeyboardCorners, KeyboardSize, Point2D};
use crate::export::{ExportPipeline, ExportProgress};
use crate::midi;
use crate::overlay_geometry::{OverlayEngine, OverlayStyle, SyncSettings};
use crate::video;

/// Free a string previously returned by this library.
#[no_mangle]
pub extern "C" fn ffi_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

/// Health check. Returns a JSON string.
#[no_mangle]
pub extern "C" fn ffi_health_check() -> *mut c_char {
    let result = serde_json::json!({
        "status": "ok",
        "version": "0.1.0",
        "engine": "piano_overlay_native"
    });
    to_c_string(&result.to_string())
}

/// Parse a MIDI file. Input: path (C string). Output: JSON MidiFileData or error.
#[no_mangle]
pub extern "C" fn ffi_parse_midi(path: *const c_char) -> *mut c_char {
    let path_str = unsafe { CStr::from_ptr(path).to_str().unwrap_or("") };

    match midi::parse_midi_file(path_str) {
        Ok(data) => {
            let json = serde_json::to_string(&data).unwrap_or_default();
            to_c_string(&json)
        }
        Err(e) => to_c_string(&format!("{{\"error\":\"{}\"}}", e)),
    }
}

/// Extract video metadata. Input: path (C string). Output: JSON VideoMetadata or error.
#[no_mangle]
pub extern "C" fn ffi_extract_video_metadata(path: *const c_char) -> *mut c_char {
    let path_str = unsafe { CStr::from_ptr(path).to_str().unwrap_or("") };

    match video::extract_video_metadata(path_str) {
        Ok(data) => {
            let json = serde_json::to_string(&data).unwrap_or_default();
            to_c_string(&json)
        }
        Err(e) => to_c_string(&format!("{{\"error\":\"{}\"}}", e)),
    }
}

/// Compute calibration. Input: JSON string with corners + keyboard_size. Output: JSON CalibrationData.
#[no_mangle]
pub extern "C" fn ffi_compute_calibration(input_json: *const c_char) -> *mut c_char {
    let input_str = unsafe { CStr::from_ptr(input_json).to_str().unwrap_or("") };

    let result: Result<String, String> = (|| {
        let input: serde_json::Value =
            serde_json::from_str(input_str).map_err(|e| e.to_string())?;

        let corners = KeyboardCorners {
            top_left: parse_point(&input["corners"]["top_left"])?,
            top_right: parse_point(&input["corners"]["top_right"])?,
            bottom_right: parse_point(&input["corners"]["bottom_right"])?,
            bottom_left: parse_point(&input["corners"]["bottom_left"])?,
        };

        let size = match input["num_keys"].as_u64().unwrap_or(88) {
            88 => KeyboardSize::Keys88,
            76 => KeyboardSize::Keys76,
            61 => KeyboardSize::Keys61,
            49 => KeyboardSize::Keys49,
            _ => KeyboardSize::Keys88,
        };

        let calibration = compute_calibration(&corners, size).map_err(|e| e.to_string())?;
        serde_json::to_string(&calibration).map_err(|e| e.to_string())
    })();

    match result {
        Ok(json) => to_c_string(&json),
        Err(e) => to_c_string(&format!("{{\"error\":\"{}\"}}", e)),
    }
}

/// Compute overlay frame. Input: JSON with timestamp, notes, calibration, style, sync.
/// Output: JSON OverlayFrame.
#[no_mangle]
pub extern "C" fn ffi_compute_overlay_frame(input_json: *const c_char) -> *mut c_char {
    let input_str = unsafe { CStr::from_ptr(input_json).to_str().unwrap_or("") };

    let result: Result<String, String> = (|| {
        let input: serde_json::Value =
            serde_json::from_str(input_str).map_err(|e| e.to_string())?;

        let timestamp_ms = input["timestamp_ms"].as_f64().unwrap_or(0.0);

        let notes: Vec<crate::midi::types::MidiNote> =
            serde_json::from_value(input["notes"].clone()).map_err(|e| e.to_string())?;

        let calibration: crate::calibration::CalibrationData =
            serde_json::from_value(input["calibration"].clone()).map_err(|e| e.to_string())?;

        let style: OverlayStyle = if input["style"].is_object() {
            serde_json::from_value(input["style"].clone()).unwrap_or_default()
        } else {
            OverlayStyle::default()
        };

        let sync: SyncSettings = if input["sync"].is_object() {
            serde_json::from_value(input["sync"].clone()).unwrap_or_default()
        } else {
            SyncSettings::default()
        };

        let frame = OverlayEngine::compute_frame(timestamp_ms, &notes, &calibration, &style, &sync);
        serde_json::to_string(&frame).map_err(|e| e.to_string())
    })();

    match result {
        Ok(json) => to_c_string(&json),
        Err(e) => to_c_string(&format!("{{\"error\":\"{}\"}}", e)),
    }
}

/// Start export. Input: JSON ExportConfig. Output: JSON ExportProgress (blocking until complete).
/// For the MVP, this is synchronous. A future version will use threading with progress polling.
#[no_mangle]
pub extern "C" fn ffi_start_export(input_json: *const c_char) -> *mut c_char {
    let input_str = unsafe { CStr::from_ptr(input_json).to_str().unwrap_or("") };

    let result: Result<String, String> = (|| {
        let config: crate::export::pipeline::ExportConfig =
            serde_json::from_str(input_str).map_err(|e| format!("Invalid config: {}", e))?;

        let pipeline = ExportPipeline::new();
        pipeline.run(&config)?;

        let progress = pipeline.get_progress();
        serde_json::to_string(&progress).map_err(|e| e.to_string())
    })();

    match result {
        Ok(json) => to_c_string(&json),
        Err(e) => {
            let err_progress = ExportProgress {
                current_frame: 0,
                total_frames: 0,
                percent: 0.0,
                status: crate::export::ExportStatus::Failed,
                error: Some(e),
            };
            to_c_string(&serde_json::to_string(&err_progress).unwrap_or_default())
        }
    }
}

/// Check if ffmpeg is available. Returns JSON {"available": true/false, "version": "..."}.
#[no_mangle]
pub extern "C" fn ffi_check_ffmpeg() -> *mut c_char {
    let available = std::process::Command::new("ffmpeg")
        .arg("-version")
        .output();

    let result = match available {
        Ok(output) if output.status.success() => {
            let version_str = String::from_utf8_lossy(&output.stdout);
            let first_line = version_str.lines().next().unwrap_or("unknown");
            serde_json::json!({
                "available": true,
                "version": first_line,
            })
        }
        _ => {
            serde_json::json!({
                "available": false,
                "version": null,
            })
        }
    };

    to_c_string(&result.to_string())
}

/// Save project to file. Input: JSON {"path": "...", "project": {...}}.
#[no_mangle]
pub extern "C" fn ffi_save_project(input_json: *const c_char) -> *mut c_char {
    let input_str = unsafe { CStr::from_ptr(input_json).to_str().unwrap_or("") };

    let result: Result<String, String> = (|| {
        let input: serde_json::Value =
            serde_json::from_str(input_str).map_err(|e| e.to_string())?;

        let path = input["path"].as_str().ok_or("Missing 'path' field")?;
        let project_json =
            serde_json::to_string_pretty(&input["project"]).map_err(|e| e.to_string())?;

        std::fs::write(path, &project_json).map_err(|e| e.to_string())?;

        Ok(serde_json::json!({"success": true, "path": path}).to_string())
    })();

    match result {
        Ok(json) => to_c_string(&json),
        Err(e) => to_c_string(&format!("{{\"error\":\"{}\"}}", e)),
    }
}

/// Load project from file. Input: path (C string). Output: JSON project or error.
#[no_mangle]
pub extern "C" fn ffi_load_project(path: *const c_char) -> *mut c_char {
    let path_str = unsafe { CStr::from_ptr(path).to_str().unwrap_or("") };

    match std::fs::read_to_string(path_str) {
        Ok(content) => {
            // Validate it's valid JSON
            match serde_json::from_str::<serde_json::Value>(&content) {
                Ok(_) => to_c_string(&content),
                Err(e) => to_c_string(&format!("{{\"error\":\"Invalid project JSON: {}\"}}", e)),
            }
        }
        Err(e) => to_c_string(&format!("{{\"error\":\"Failed to read file: {}\"}}", e)),
    }
}

// --- Helpers ---

fn to_c_string(s: &str) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

fn parse_point(val: &serde_json::Value) -> Result<Point2D, String> {
    let x = val["x"].as_f64().ok_or("Missing x coordinate")?;
    let y = val["y"].as_f64().ok_or("Missing y coordinate")?;
    Ok(Point2D::new(x, y))
}
