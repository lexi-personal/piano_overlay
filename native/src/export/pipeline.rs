//! Export pipeline: decodes video via FFmpeg subprocess, composites overlay,
//! encodes to H.264/MP4 via FFmpeg. No dynamic linking to FFmpeg libraries.
//!
//! Architecture:
//!   ffmpeg (decode) → stdout (raw RGBA) → Rust composite → stdin → ffmpeg (encode + mux audio)
//!
//! This approach is 100% license-safe for commercial use since FFmpeg is only
//! invoked as a subprocess (no linking of any kind).

use std::io::{Read, Write};
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Arc;

use super::compositor::Compositor;
use crate::calibration::CalibrationData;
use crate::midi::types::MidiNote;
use crate::overlay_geometry::{OverlayEngine, OverlayStyle, SyncSettings};

/// Export progress information.
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct ExportProgress {
    /// Current frame being processed.
    pub current_frame: u32,
    /// Total frames to process.
    pub total_frames: u32,
    /// Progress percentage (0-100).
    pub percent: f32,
    /// Current status.
    pub status: ExportStatus,
    /// Error message if failed.
    pub error: Option<String>,
}

/// Export status enum.
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize, PartialEq)]
pub enum ExportStatus {
    Idle,
    Preparing,
    Encoding,
    Finalizing,
    Complete,
    Failed,
    Cancelled,
}

/// Export configuration.
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct ExportConfig {
    /// Input video file path.
    pub input_video_path: String,
    /// Output file path.
    pub output_path: String,
    /// Video width.
    pub width: u32,
    /// Video height.
    pub height: u32,
    /// Frame rate.
    pub fps: f64,
    /// Total duration in milliseconds.
    pub duration_ms: f64,
    /// Quality preset: "low", "medium", "high", "lossless".
    pub quality: String,
    /// MIDI notes to overlay.
    pub notes: Vec<MidiNote>,
    /// Calibration data.
    pub calibration: CalibrationData,
    /// Overlay style settings.
    pub style: OverlayStyle,
    /// Sync settings.
    pub sync: SyncSettings,
    /// Path to ffmpeg binary (default: "ffmpeg" from PATH).
    pub ffmpeg_path: Option<String>,
}

/// The export pipeline.
pub struct ExportPipeline {
    /// Shared progress state for polling from the UI.
    progress: Arc<ExportProgressState>,
}

struct ExportProgressState {
    current_frame: AtomicU32,
    total_frames: AtomicU32,
    status: std::sync::Mutex<ExportStatus>,
    error: std::sync::Mutex<Option<String>>,
    cancelled: AtomicBool,
}

impl Default for ExportPipeline {
    fn default() -> Self {
        Self::new()
    }
}

impl ExportPipeline {
    pub fn new() -> Self {
        Self {
            progress: Arc::new(ExportProgressState {
                current_frame: AtomicU32::new(0),
                total_frames: AtomicU32::new(0),
                status: std::sync::Mutex::new(ExportStatus::Idle),
                error: std::sync::Mutex::new(None),
                cancelled: AtomicBool::new(false),
            }),
        }
    }

    /// Get current progress (for polling from FFI).
    pub fn get_progress(&self) -> ExportProgress {
        let current = self.progress.current_frame.load(Ordering::Relaxed);
        let total = self.progress.total_frames.load(Ordering::Relaxed);
        let percent = if total > 0 {
            (current as f32 / total as f32) * 100.0
        } else {
            0.0
        };

        ExportProgress {
            current_frame: current,
            total_frames: total,
            percent,
            status: self.progress.status.lock().unwrap().clone(),
            error: self.progress.error.lock().unwrap().clone(),
        }
    }

    /// Request cancellation of the current export.
    pub fn cancel(&self) {
        self.progress.cancelled.store(true, Ordering::Relaxed);
    }

    /// Run the export pipeline (blocking).
    /// Returns Ok(()) on success or Err with description.
    pub fn run(&self, config: &ExportConfig) -> Result<(), String> {
        self.progress.cancelled.store(false, Ordering::Relaxed);
        *self.progress.status.lock().unwrap() = ExportStatus::Preparing;

        let ffmpeg = config.ffmpeg_path.as_deref().unwrap_or("ffmpeg");

        // Validate ffmpeg is available
        if !Self::check_ffmpeg(ffmpeg) {
            let msg = format!(
                "FFmpeg not found at '{}'. Please install FFmpeg or provide the correct path.",
                ffmpeg
            );
            *self.progress.status.lock().unwrap() = ExportStatus::Failed;
            *self.progress.error.lock().unwrap() = Some(msg.clone());
            return Err(msg);
        }

        // Validate input exists
        if !Path::new(&config.input_video_path).exists() {
            let msg = format!("Input video not found: {}", config.input_video_path);
            *self.progress.status.lock().unwrap() = ExportStatus::Failed;
            *self.progress.error.lock().unwrap() = Some(msg.clone());
            return Err(msg);
        }

        let total_frames = (config.duration_ms / 1000.0 * config.fps).ceil() as u32;
        self.progress
            .total_frames
            .store(total_frames, Ordering::Relaxed);
        self.progress.current_frame.store(0, Ordering::Relaxed);
        *self.progress.status.lock().unwrap() = ExportStatus::Encoding;

        // Quality to CRF mapping
        let crf = match config.quality.as_str() {
            "low" => "28",
            "medium" => "23",
            "high" => "18",
            "lossless" => "0",
            _ => "20",
        };

        // --- Start FFmpeg decoder process ---
        // Decodes input video to raw RGBA frames via stdout
        let mut decoder = Command::new(ffmpeg)
            .args([
                "-i",
                &config.input_video_path,
                "-f",
                "rawvideo",
                "-pix_fmt",
                "rgba",
                "-v",
                "error",
                "-",
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("Failed to start FFmpeg decoder: {}", e))?;

        // --- Start FFmpeg encoder process ---
        // Accepts raw RGBA via stdin, muxes with original audio
        let fps_str = format!("{}", config.fps);
        let size_str = format!("{}x{}", config.width, config.height);

        let mut encoder = Command::new(ffmpeg)
            .args([
                "-y", // Overwrite output
                // Raw video input from pipe
                "-f",
                "rawvideo",
                "-pix_fmt",
                "rgba",
                "-s",
                &size_str,
                "-r",
                &fps_str,
                "-i",
                "pipe:0",
                // Audio from original video
                "-i",
                &config.input_video_path,
                // Map video from pipe, audio from original
                "-map",
                "0:v",
                "-map",
                "1:a?",
                // Encode settings
                "-c:v",
                "libx264",
                "-preset",
                "medium",
                "-crf",
                crf,
                "-pix_fmt",
                "yuv420p",
                "-c:a",
                "aac",
                "-b:a",
                "192k",
                // Shortest stream determines duration
                "-shortest",
                "-v",
                "error",
                &config.output_path,
            ])
            .stdin(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("Failed to start FFmpeg encoder: {}", e))?;

        let decoder_stdout = decoder
            .stdout
            .take()
            .ok_or("Failed to capture decoder stdout")?;
        let encoder_stdin = encoder
            .stdin
            .take()
            .ok_or("Failed to capture encoder stdin")?;

        // Process frames
        let result = self.process_frames(decoder_stdout, encoder_stdin, config, total_frames);

        // Wait for processes to finish
        let _ = decoder.wait();
        let encoder_result = encoder.wait();

        match result {
            Ok(()) => {
                if let Ok(status) = encoder_result {
                    if status.success() {
                        *self.progress.status.lock().unwrap() = ExportStatus::Complete;
                        Ok(())
                    } else {
                        let msg = "FFmpeg encoder exited with error".to_string();
                        *self.progress.status.lock().unwrap() = ExportStatus::Failed;
                        *self.progress.error.lock().unwrap() = Some(msg.clone());
                        Err(msg)
                    }
                } else {
                    *self.progress.status.lock().unwrap() = ExportStatus::Complete;
                    Ok(())
                }
            }
            Err(e) => {
                *self.progress.status.lock().unwrap() = ExportStatus::Failed;
                *self.progress.error.lock().unwrap() = Some(e.clone());
                Err(e)
            }
        }
    }

    /// Process frames: read from decoder, composite overlay, write to encoder.
    fn process_frames(
        &self,
        mut decoder_out: impl Read,
        mut encoder_in: impl Write,
        config: &ExportConfig,
        total_frames: u32,
    ) -> Result<(), String> {
        let frame_size = (config.width * config.height * 4) as usize; // RGBA
        let mut frame_buffer = vec![0u8; frame_size];
        let ms_per_frame = 1000.0 / config.fps;

        for frame_idx in 0..total_frames {
            // Check for cancellation
            if self.progress.cancelled.load(Ordering::Relaxed) {
                *self.progress.status.lock().unwrap() = ExportStatus::Cancelled;
                return Err("Export cancelled by user".to_string());
            }

            // Read one frame from decoder
            match decoder_out.read_exact(&mut frame_buffer) {
                Ok(()) => {}
                Err(e) => {
                    if frame_idx > 0 {
                        // Likely end of video (decoder finished)
                        break;
                    }
                    return Err(format!("Failed to read frame {}: {}", frame_idx, e));
                }
            }

            // Compute overlay for this timestamp
            let timestamp_ms = frame_idx as f64 * ms_per_frame;
            let overlay_frame = OverlayEngine::compute_frame(
                timestamp_ms,
                &config.notes,
                &config.calibration,
                &config.style,
                &config.sync,
            );

            // Composite overlay onto frame
            Compositor::composite_frame(
                &mut frame_buffer,
                config.width,
                config.height,
                &overlay_frame,
                config.style.background_dim,
            );

            // Write composited frame to encoder
            encoder_in
                .write_all(&frame_buffer)
                .map_err(|e| format!("Failed to write frame {}: {}", frame_idx, e))?;

            // Update progress
            self.progress
                .current_frame
                .store(frame_idx + 1, Ordering::Relaxed);
        }

        // Flush and close encoder stdin to signal end of input
        drop(encoder_in);

        *self.progress.status.lock().unwrap() = ExportStatus::Finalizing;
        Ok(())
    }

    /// Check if ffmpeg is available.
    fn check_ffmpeg(path: &str) -> bool {
        Command::new(path)
            .arg("-version")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_export_progress_initial() {
        let pipeline = ExportPipeline::new();
        let progress = pipeline.get_progress();
        assert_eq!(progress.current_frame, 0);
        assert_eq!(progress.total_frames, 0);
        assert_eq!(progress.status, ExportStatus::Idle);
    }

    #[test]
    fn test_cancel_flag() {
        let pipeline = ExportPipeline::new();
        assert!(!pipeline.progress.cancelled.load(Ordering::Relaxed));
        pipeline.cancel();
        assert!(pipeline.progress.cancelled.load(Ordering::Relaxed));
    }

    #[test]
    fn test_check_ffmpeg_exists() {
        // This test depends on ffmpeg being installed
        let has_ffmpeg = ExportPipeline::check_ffmpeg("ffmpeg");
        // Just verify it doesn't panic — actual availability depends on env
        let _ = has_ffmpeg;
    }
}
