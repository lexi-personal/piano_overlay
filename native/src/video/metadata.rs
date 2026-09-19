use serde::{Deserialize, Serialize};
use thiserror::Error;

/// Video file metadata extracted without decoding frames.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct VideoMetadata {
    /// Video width in pixels.
    pub width: u32,
    /// Video height in pixels.
    pub height: u32,
    /// Frames per second.
    pub fps: f64,
    /// Total duration in milliseconds.
    pub duration_ms: f64,
    /// Video codec name (e.g., "h264", "hevc").
    pub codec: String,
    /// Whether the file contains an audio track.
    pub has_audio: bool,
    /// Audio sample rate in Hz (if audio present).
    pub audio_sample_rate: Option<u32>,
    /// File size in bytes.
    pub file_size_bytes: u64,
    /// File path (stored for reference).
    pub file_path: String,
}

#[derive(Error, Debug)]
pub enum VideoMetadataError {
    #[error("Failed to read video file: {0}")]
    IoError(#[from] std::io::Error),
    #[error("Failed to probe video metadata: {0}")]
    ProbeError(String),
    #[error("No video stream found in file")]
    NoVideoStream,
    #[error("File not found: {0}")]
    FileNotFound(String),
}

/// Extract video metadata by probing the file.
///
/// For the MVP, this uses ffprobe (command-line) as a simple cross-platform approach.
/// In production, this will use FFmpeg C bindings via Rust for better performance.
pub fn extract_video_metadata(path: &str) -> Result<VideoMetadata, VideoMetadataError> {
    use std::path::Path;
    use std::process::Command;

    let file_path = Path::new(path);
    if !file_path.exists() {
        return Err(VideoMetadataError::FileNotFound(path.to_string()));
    }

    let file_size = std::fs::metadata(file_path)?.len();

    // Use ffprobe to extract metadata as JSON
    let output = Command::new("ffprobe")
        .args([
            "-v",
            "quiet",
            "-print_format",
            "json",
            "-show_format",
            "-show_streams",
            path,
        ])
        .output()
        .map_err(|e| {
            VideoMetadataError::ProbeError(format!("ffprobe not found or failed: {}", e))
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(VideoMetadataError::ProbeError(format!(
            "ffprobe failed: {}",
            stderr
        )));
    }

    let json_str = String::from_utf8_lossy(&output.stdout);
    let probe: serde_json::Value = serde_json::from_str(&json_str).map_err(|e| {
        VideoMetadataError::ProbeError(format!("Failed to parse ffprobe output: {}", e))
    })?;

    // Find video stream
    let streams = probe["streams"]
        .as_array()
        .ok_or_else(|| VideoMetadataError::ProbeError("No streams in ffprobe output".into()))?;

    let video_stream = streams
        .iter()
        .find(|s| s["codec_type"].as_str() == Some("video"))
        .ok_or(VideoMetadataError::NoVideoStream)?;

    let audio_stream = streams
        .iter()
        .find(|s| s["codec_type"].as_str() == Some("audio"));

    // Extract video properties
    let width = video_stream["width"].as_u64().unwrap_or(0) as u32;
    let height = video_stream["height"].as_u64().unwrap_or(0) as u32;
    let codec = video_stream["codec_name"]
        .as_str()
        .unwrap_or("unknown")
        .to_string();

    // Parse frame rate from "r_frame_rate" field (e.g., "30/1" or "30000/1001")
    let fps = parse_frame_rate(video_stream["r_frame_rate"].as_str().unwrap_or("30/1"));

    // Duration: prefer format duration, fall back to stream duration
    let duration_s = probe["format"]["duration"]
        .as_str()
        .and_then(|s| s.parse::<f64>().ok())
        .or_else(|| {
            video_stream["duration"]
                .as_str()
                .and_then(|s| s.parse::<f64>().ok())
        })
        .unwrap_or(0.0);

    let has_audio = audio_stream.is_some();
    let audio_sample_rate = audio_stream.and_then(|s| {
        s["sample_rate"]
            .as_str()
            .and_then(|r| r.parse::<u32>().ok())
    });

    Ok(VideoMetadata {
        width,
        height,
        fps,
        duration_ms: duration_s * 1000.0,
        codec,
        has_audio,
        audio_sample_rate,
        file_size_bytes: file_size,
        file_path: path.to_string(),
    })
}

fn parse_frame_rate(rate_str: &str) -> f64 {
    if let Some((num_str, den_str)) = rate_str.split_once('/') {
        let num: f64 = num_str.parse().unwrap_or(30.0);
        let den: f64 = den_str.parse().unwrap_or(1.0);
        if den > 0.0 {
            num / den
        } else {
            30.0
        }
    } else {
        rate_str.parse().unwrap_or(30.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_frame_rate() {
        assert!((parse_frame_rate("30/1") - 30.0).abs() < 0.01);
        assert!((parse_frame_rate("30000/1001") - 29.97).abs() < 0.01);
        assert!((parse_frame_rate("24/1") - 24.0).abs() < 0.01);
        assert!((parse_frame_rate("60") - 60.0).abs() < 0.01);
    }
}
