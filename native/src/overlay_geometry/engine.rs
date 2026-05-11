use crate::calibration::{transform_point, CalibrationData};
use crate::midi::types::MidiNote;
use super::types::{FallDirection, KeyHighlight, NoteStrip, OverlayFrame, OverlayStyle, SyncSettings};
use crate::calibration::Point2D;

/// The shared overlay geometry engine.
/// Computes the exact same OverlayFrame data for both preview and export rendering.
pub struct OverlayEngine;

impl OverlayEngine {
    /// Compute the overlay frame for a given timestamp.
    /// This is the single source of truth for both preview and export.
    pub fn compute_frame(
        timestamp_ms: f64,
        notes: &[MidiNote],
        calibration: &CalibrationData,
        style: &OverlayStyle,
        sync: &SyncSettings,
    ) -> OverlayFrame {
        let effective_time = apply_sync(timestamp_ms, sync);
        let visible_notes = Self::get_visible_notes(notes, effective_time, style);

        let mut strips = Vec::with_capacity(visible_notes.len());
        let mut key_highlights = Vec::new();

        for note in &visible_notes {
            if let Some(strip) = Self::compute_note_strip(note, effective_time, calibration, style) {
                strips.push(strip);
            }

            // Key highlight for currently-active notes
            if style.key_highlight_enabled && Self::is_note_active(note, effective_time) {
                if let Some(highlight) = Self::compute_key_highlight(note, calibration, style) {
                    key_highlights.push(highlight);
                }
            }
        }

        OverlayFrame {
            strips,
            key_highlights,
            timestamp_ms,
        }
    }

    /// Get all notes that should be visible at the given time.
    fn get_visible_notes<'a>(
        notes: &'a [MidiNote],
        time_ms: f64,
        style: &OverlayStyle,
    ) -> Vec<&'a MidiNote> {
        let lookahead = if style.show_before_play {
            style.lookahead_ms as f64
        } else {
            0.0
        };

        // A note is visible if:
        // - It starts within the lookahead window (future notes falling down), OR
        // - It's currently being played (start <= time <= end), if show_during_play
        notes
            .iter()
            .filter(|n| {
                let note_start = n.start_ms;
                let note_end = n.start_ms + n.duration_ms;

                // Note is in the lookahead window (hasn't started yet)
                let in_lookahead = style.show_before_play
                    && note_start > time_ms
                    && note_start <= time_ms + lookahead;

                // Note is currently active
                let is_active = style.show_during_play
                    && note_start <= time_ms
                    && note_end >= time_ms;

                // Note recently ended (trail effect, show for a brief moment)
                let just_ended = style.show_during_play
                    && note_end < time_ms
                    && note_end > time_ms - 100.0;

                in_lookahead || is_active || just_ended
            })
            .collect()
    }

    /// Compute the strip geometry for a single note.
    fn compute_note_strip(
        note: &MidiNote,
        time_ms: f64,
        calibration: &CalibrationData,
        style: &OverlayStyle,
    ) -> Option<NoteStrip> {
        // Find the key position for this note
        let key_pos = calibration
            .key_positions
            .iter()
            .find(|k| k.note == note.pitch)?;

        // Compute strip position in canonical space
        let key_x_center = key_pos.canonical_x_center;
        let half_width = if key_pos.is_black {
            0.3 * style.strip_thickness as f64
        } else {
            0.5 * style.strip_thickness as f64
        };
        let x_left = key_x_center - half_width;
        let x_right = key_x_center + half_width;

        // Compute y-position based on timing
        // The "keyboard surface" is at y = 0 (top edge of canonical keyboard)
        // Notes fall from negative y (above) toward y=0
        let pixels_per_ms = style.fall_speed as f64 / 1000.0;

        let note_start_offset = note.start_ms - time_ms; // ms until note starts
        let note_end_offset = (note.start_ms + note.duration_ms) - time_ms;

        // Map time offset to y position
        // Positive offset = future = above keyboard (negative y in canonical space)
        let (y_top, y_bottom) = match style.fall_direction {
            FallDirection::TopToBottom => {
                let y_start = -(note_start_offset * pixels_per_ms); // strip leading edge
                let y_end = -(note_end_offset * pixels_per_ms);     // strip trailing edge
                // Clamp to visible range
                let y_bottom = y_start.min(0.0);   // Can't go past keyboard
                let y_top = y_end.min(y_bottom);
                (y_top, y_bottom)
            }
            FallDirection::BottomToTop => {
                let y_start = 1.0 + (note_start_offset * pixels_per_ms);
                let y_end = 1.0 + (note_end_offset * pixels_per_ms);
                let y_top = y_start.max(1.0);
                let y_bottom = y_end.max(y_top);
                (y_top, y_bottom)
            }
            FallDirection::Custom { .. } => {
                // For custom angles, use top-to-bottom as fallback
                let y_start = -(note_start_offset * pixels_per_ms);
                let y_end = -(note_end_offset * pixels_per_ms);
                let y_bottom = y_start.min(0.0);
                let y_top = y_end.min(y_bottom);
                (y_top, y_bottom)
            }
        };

        // Skip strips that are too thin to be visible
        if (y_bottom - y_top).abs() < 0.001 {
            return None;
        }

        // Transform canonical quad to screen space via homography
        let h = &calibration.homography;
        let tl = transform_point(h, &Point2D::new(x_left, y_top));
        let tr = transform_point(h, &Point2D::new(x_right, y_top));
        let br = transform_point(h, &Point2D::new(x_right, y_bottom));
        let bl = transform_point(h, &Point2D::new(x_left, y_bottom));

        // Determine color
        let base_color = if key_pos.is_black {
            style.black_key_color
        } else {
            style.white_key_color
        };

        // Apply transparency
        let mut color = base_color;
        color[3] = base_color[3] * style.transparency;

        // Fade notes that are ending
        let note_end = note.start_ms + note.duration_ms;
        if note_end < time_ms {
            let fade = 1.0 - ((time_ms - note_end) / 100.0) as f32;
            color[3] *= fade.max(0.0);
        }

        Some(NoteStrip {
            quad: [tl, tr, br, bl],
            color,
            glow_radius: style.glow_radius,
            glow_intensity: style.glow_strength,
        })
    }

    /// Compute key highlight for an active note.
    fn compute_key_highlight(
        note: &MidiNote,
        calibration: &CalibrationData,
        style: &OverlayStyle,
    ) -> Option<KeyHighlight> {
        let key_pos = calibration
            .key_positions
            .iter()
            .find(|k| k.note == note.pitch)?;

        Some(KeyHighlight {
            quad: key_pos.screen_quad,
            color: style.key_highlight_color,
        })
    }

    /// Check if a note is currently being played.
    fn is_note_active(note: &MidiNote, time_ms: f64) -> bool {
        note.start_ms <= time_ms && (note.start_ms + note.duration_ms) >= time_ms
    }
}

/// Apply sync offset (and drift correction if enabled) to convert playback time to MIDI time.
fn apply_sync(playback_time_ms: f64, sync: &SyncSettings) -> f64 {
    if sync.drift_enabled {
        // Linear interpolation between start and end offsets
        // This handles cases where MIDI and video slowly drift apart
        let t = playback_time_ms;
        let offset = sync.drift_start_ms
            + (sync.drift_end_ms - sync.drift_start_ms) * (t / playback_time_ms.max(1.0));
        playback_time_ms + offset
    } else {
        playback_time_ms + sync.offset_ms
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::calibration::{compute_calibration, KeyboardCorners, KeyboardSize};

    fn make_test_calibration() -> CalibrationData {
        let corners = KeyboardCorners {
            top_left: Point2D::new(100.0, 100.0),
            top_right: Point2D::new(1820.0, 100.0),
            bottom_right: Point2D::new(1820.0, 300.0),
            bottom_left: Point2D::new(100.0, 300.0),
        };
        compute_calibration(&corners, KeyboardSize::Keys88)
            .expect("test calibration should succeed")
    }

    fn make_test_notes() -> Vec<MidiNote> {
        vec![
            MidiNote {
                pitch: 60, // C4
                velocity: 100,
                start_ms: 1000.0,
                duration_ms: 500.0,
                channel: 0,
                track: 0,
            },
            MidiNote {
                pitch: 64, // E4
                velocity: 80,
                start_ms: 1200.0,
                duration_ms: 300.0,
                channel: 0,
                track: 0,
            },
        ]
    }

    #[test]
    fn test_overlay_frame_before_notes() {
        let cal = make_test_calibration();
        let notes = make_test_notes();
        let style = OverlayStyle::default();
        let sync = SyncSettings::default();

        // At time 0, notes start at 1000ms, lookahead is 2000ms
        // Both notes should be visible (within lookahead)
        let frame = OverlayEngine::compute_frame(0.0, &notes, &cal, &style, &sync);
        assert_eq!(frame.strips.len(), 2);
        assert_eq!(frame.key_highlights.len(), 0); // No active notes at t=0
    }

    #[test]
    fn test_overlay_frame_during_note() {
        let cal = make_test_calibration();
        let notes = make_test_notes();
        let style = OverlayStyle::default();
        let sync = SyncSettings::default();

        // At time 1100, first note (C4) is active, second note (E4) is in lookahead
        let frame = OverlayEngine::compute_frame(1100.0, &notes, &cal, &style, &sync);
        assert!(frame.strips.len() >= 1);
        assert_eq!(frame.key_highlights.len(), 1); // C4 is active
    }

    #[test]
    fn test_overlay_frame_after_notes() {
        let cal = make_test_calibration();
        let notes = make_test_notes();
        let style = OverlayStyle::default();
        let sync = SyncSettings::default();

        // At time 5000, all notes are long gone
        let frame = OverlayEngine::compute_frame(5000.0, &notes, &cal, &style, &sync);
        assert_eq!(frame.strips.len(), 0);
        assert_eq!(frame.key_highlights.len(), 0);
    }

    #[test]
    fn test_sync_offset() {
        let sync = SyncSettings {
            offset_ms: -200.0,
            drift_enabled: false,
            drift_start_ms: 0.0,
            drift_end_ms: 0.0,
        };
        // Negative offset: MIDI plays 200ms earlier relative to video
        let effective = apply_sync(1000.0, &sync);
        assert!((effective - 800.0).abs() < 0.01);
    }
}
