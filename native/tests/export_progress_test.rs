//! Verifies that a running export reports live progress through the FFI
//! polling entry point, and that it can be cancelled while running.

use std::ffi::{CStr, CString};
use std::process::Command;

use piano_overlay_native::calibration::{
    compute_calibration, KeyboardCorners, KeyboardSize, Point2D,
};
use piano_overlay_native::export::pipeline::ExportConfig;
use piano_overlay_native::ffi::{ffi_cancel_export, ffi_free_string, ffi_get_export_progress,
    ffi_start_export};
use piano_overlay_native::overlay_geometry::{OverlayStyle, SyncSettings};

fn ffmpeg_available() -> bool {
    Command::new("ffmpeg")
        .arg("-version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

/// The active export is process-global, so these tests must not overlap.
fn serial_guard() -> std::sync::MutexGuard<'static, ()> {
    static LOCK: std::sync::OnceLock<std::sync::Mutex<()>> = std::sync::OnceLock::new();
    let lock = LOCK.get_or_init(|| std::sync::Mutex::new(()));
    lock.lock().unwrap_or_else(|e| e.into_inner())
}

fn poll_progress() -> serde_json::Value {
    let ptr = ffi_get_export_progress();
    let json = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned();
    ffi_free_string(ptr);
    serde_json::from_str(&json).expect("progress should be valid JSON")
}

fn make_config(dir: &std::path::Path, name: &str) -> ExportConfig {
    let input_path = dir.join(format!("{}_in.mp4", name));
    let output_path = dir.join(format!("{}_out.mp4", name));
    let _ = std::fs::remove_file(&output_path);

    // A long enough clip that the export is still running when we poll.
    let gen = Command::new("ffmpeg")
        .args([
            "-y",
            "-f",
            "lavfi",
            "-i",
            "color=c=blue:s=640x360:d=6:r=30",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-t",
            "6",
        ])
        .arg(&input_path)
        .output()
        .expect("failed to generate test video");
    assert!(gen.status.success(), "could not create test video");

    let corners = KeyboardCorners {
        top_left: Point2D::new(40.0, 200.0),
        top_right: Point2D::new(600.0, 200.0),
        bottom_right: Point2D::new(600.0, 340.0),
        bottom_left: Point2D::new(40.0, 340.0),
    };

    ExportConfig {
        input_video_path: input_path.to_string_lossy().into_owned(),
        output_path: output_path.to_string_lossy().into_owned(),
        width: 640,
        height: 360,
        fps: 30.0,
        duration_ms: 6000.0,
        quality: "low".to_string(),
        notes: Vec::new(),
        calibration: compute_calibration(&corners, KeyboardSize::Keys88)
            .expect("calibration should succeed"),
        style: OverlayStyle::default(),
        sync: SyncSettings::default(),
        ffmpeg_path: None,
    }
}

fn run_export_in_background(config: &ExportConfig) -> std::thread::JoinHandle<serde_json::Value> {
    let config_json = serde_json::to_string(config).unwrap();
    std::thread::spawn(move || {
        let input = CString::new(config_json).unwrap();
        let ptr = ffi_start_export(input.as_ptr());
        let json = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned();
        ffi_free_string(ptr);
        serde_json::from_str(&json).expect("result should be valid JSON")
    })
}

#[test]
fn progress_is_observable_while_the_export_runs() {
    let _guard = serial_guard();
    if !ffmpeg_available() {
        eprintln!("Skipping: ffmpeg not available");
        return;
    }

    let dir = std::env::temp_dir().join("piano_overlay_progress_test");
    std::fs::create_dir_all(&dir).unwrap();
    let config = make_config(&dir, "progress");
    let output_path = config.output_path.clone();
    let input_path = config.input_video_path.clone();

    let handle = run_export_in_background(&config);

    // Poll until the pipeline reports real work, rather than only a final result.
    let mut saw_running_progress = false;
    for _ in 0..600 {
        let progress = poll_progress();
        let status = progress["status"].as_str().unwrap_or("");
        if status == "Encoding" && progress["total_frames"].as_u64().unwrap_or(0) > 0 {
            saw_running_progress = true;
            break;
        }
        if status == "Complete" || status == "Failed" {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    }

    let result = handle.join().expect("export thread panicked");
    assert_eq!(
        result["status"], "Complete",
        "export should succeed: {:?}",
        result["error"]
    );
    assert!(
        saw_running_progress,
        "progress was never observable while the export was running"
    );

    // Once finished, polling reports the idle state instead of stale progress.
    assert_eq!(poll_progress()["status"], "Idle");

    let _ = std::fs::remove_file(&input_path);
    let _ = std::fs::remove_file(&output_path);
}

#[test]
fn a_running_export_can_be_cancelled() {
    let _guard = serial_guard();
    if !ffmpeg_available() {
        eprintln!("Skipping: ffmpeg not available");
        return;
    }

    let dir = std::env::temp_dir().join("piano_overlay_cancel_test");
    std::fs::create_dir_all(&dir).unwrap();
    let config = make_config(&dir, "cancel");
    let output_path = config.output_path.clone();
    let input_path = config.input_video_path.clone();

    let handle = run_export_in_background(&config);

    // Wait for the pipeline to actually start before cancelling it.
    let mut cancelled = false;
    for _ in 0..600 {
        if poll_progress()["status"].as_str() == Some("Encoding") {
            let ptr = ffi_cancel_export();
            let json = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned();
            ffi_free_string(ptr);
            let value: serde_json::Value = serde_json::from_str(&json).unwrap();
            cancelled = value["cancelled"].as_bool().unwrap_or(false);
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    }

    assert!(cancelled, "cancellation request was not accepted");

    let result = handle.join().expect("export thread panicked");
    assert_eq!(
        result["status"], "Cancelled",
        "a cancelled export should not be reported as a failure"
    );

    let _ = std::fs::remove_file(&input_path);
    let _ = std::fs::remove_file(&output_path);
}
