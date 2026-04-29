//! Integration test: creates a tiny synthetic video, runs the full export pipeline,
//! and verifies the output file is created.

use std::path::Path;
use std::process::Command;

use piano_overlay_native::calibration::{compute_calibration, KeyboardCorners, KeyboardSize, Point2D};
use piano_overlay_native::export::ExportPipeline;
use piano_overlay_native::export::pipeline::ExportConfig;
use piano_overlay_native::midi::types::MidiNote;
use piano_overlay_native::overlay_geometry::{OverlayStyle, SyncSettings};

#[test]
fn test_full_export_pipeline() {
    // Skip if ffmpeg not available
    let ffmpeg_check = Command::new("ffmpeg")
        .arg("-version")
        .output();
    if ffmpeg_check.is_err() || !ffmpeg_check.unwrap().status.success() {
        eprintln!("Skipping: ffmpeg not available");
        return;
    }

    let test_dir = "/tmp/piano_overlay_test";
    std::fs::create_dir_all(test_dir).unwrap();

    // Create a tiny 2-second test video (160x90, 10fps, solid blue)
    let input_path = format!("{}/test_input.mp4", test_dir);
    let output_path = format!("{}/test_output.mp4", test_dir);

    // Clean up from previous runs
    let _ = std::fs::remove_file(&input_path);
    let _ = std::fs::remove_file(&output_path);

    let gen = Command::new("ffmpeg")
        .args([
            "-y",
            "-f", "lavfi",
            "-i", "color=c=blue:s=160x90:d=2:r=10",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-t", "2",
            &input_path,
        ])
        .output()
        .expect("Failed to generate test video");

    assert!(gen.status.success(), "Failed to create test video: {:?}", 
        String::from_utf8_lossy(&gen.stderr));
    assert!(Path::new(&input_path).exists());

    // Set up calibration (simple rectangular keyboard)
    let corners = KeyboardCorners {
        top_left: Point2D::new(10.0, 50.0),
        top_right: Point2D::new(150.0, 50.0),
        bottom_right: Point2D::new(150.0, 85.0),
        bottom_left: Point2D::new(10.0, 85.0),
    };
    let calibration = compute_calibration(&corners, KeyboardSize::Keys88);

    // Create some MIDI notes
    let notes = vec![
        MidiNote {
            pitch: 60,
            velocity: 100,
            start_ms: 200.0,
            duration_ms: 800.0,
            channel: 0,
            track: 0,
        },
        MidiNote {
            pitch: 64,
            velocity: 90,
            start_ms: 500.0,
            duration_ms: 600.0,
            channel: 0,
            track: 0,
        },
        MidiNote {
            pitch: 67,
            velocity: 85,
            start_ms: 800.0,
            duration_ms: 400.0,
            channel: 0,
            track: 0,
        },
    ];

    let config = ExportConfig {
        input_video_path: input_path.clone(),
        output_path: output_path.clone(),
        width: 160,
        height: 90,
        fps: 10.0,
        duration_ms: 2000.0,
        quality: "low".to_string(),
        notes,
        calibration,
        style: OverlayStyle::default(),
        sync: SyncSettings::default(),
        ffmpeg_path: None,
    };

    // Run the export
    let pipeline = ExportPipeline::new();
    let result = pipeline.run(&config);

    assert!(result.is_ok(), "Export failed: {:?}", result.err());

    // Verify output exists and is a valid video
    assert!(Path::new(&output_path).exists(), "Output file not created");
    let metadata = std::fs::metadata(&output_path).unwrap();
    assert!(metadata.len() > 0, "Output file is empty");

    // Verify with ffprobe
    let probe = Command::new("ffprobe")
        .args(["-v", "error", "-show_format", "-show_streams", "-print_format", "json", &output_path])
        .output()
        .expect("ffprobe failed");
    assert!(probe.status.success(), "ffprobe failed on output");

    let probe_json: serde_json::Value = serde_json::from_slice(&probe.stdout).unwrap();
    let streams = probe_json["streams"].as_array().unwrap();
    let video_stream = streams.iter().find(|s| s["codec_type"] == "video").unwrap();
    assert_eq!(video_stream["width"], 160);
    assert_eq!(video_stream["height"], 90);

    // Check progress
    let progress = pipeline.get_progress();
    assert_eq!(progress.status, piano_overlay_native::export::ExportStatus::Complete);
    assert!(progress.current_frame > 0);

    // Cleanup
    let _ = std::fs::remove_file(&input_path);
    let _ = std::fs::remove_file(&output_path);
    let _ = std::fs::remove_dir(test_dir);
}
