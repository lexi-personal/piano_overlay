use super::types::{
    FallDirection, KeyHighlight, LaneProjection, NoteStrip, OverlayFrame, OverlayStyle,
    SyncSettings,
};
use crate::calibration::Point2D;
use crate::calibration::{is_black_key, transform_point, CalibrationData};
use crate::midi::types::MidiNote;

/// The shared overlay geometry engine.
/// Computes the exact same OverlayFrame data for both preview and export rendering.
pub struct OverlayEngine;

impl OverlayEngine {
    /// Canonical height of the fall lane, in keyboard-height units.
    const CANONICAL_LANE_HEIGHT: f64 = 6.0;

    /// How long (ms) a finished note keeps fading out.
    const TRAIL_FADE_MS: f64 = 200.0;

    /// Strip width per unit of `strip_thickness`, chosen so the default
    /// thickness of 0.8 yields the historical widths of 0.9 / 0.55 keys.
    const WHITE_STRIP_WIDTH_UNIT: f64 = 1.125;
    const BLACK_STRIP_WIDTH_UNIT: f64 = 0.6875;

    /// Compute the overlay frame for a given timestamp.
    /// This is the single source of truth for both preview and export.
    ///
    /// Strips are laid out in an upright, screen-space "fall lane": each strip
    /// is anchored to its own key's calibrated boundaries on the keyboard edge
    /// and rises straight up (or drops straight down) the screen. Extending the
    /// lane along the keyboard plane instead makes it slide sideways on angled
    /// shots and invert once the plane crosses the horizon.
    pub fn compute_frame(
        timestamp_ms: f64,
        notes: &[MidiNote],
        calibration: &CalibrationData,
        style: &OverlayStyle,
        sync: &SyncSettings,
    ) -> OverlayFrame {
        let effective_time = apply_sync(timestamp_ms, sync);
        let key_range = calibration.effective_key_range();
        let white_keys = key_range.white_keys as f64;
        let h = &calibration.homography;

        // Top-to-bottom anchors the lane on the keyboard's far edge (y = 0);
        // bottom-to-top anchors it on the near edge (y = 1).
        let (anchor_y, lane_dir) = match style.fall_direction {
            FallDirection::BottomToTop => (1.0, 1.0),
            _ => (0.0, -1.0),
        };
        let tabletop = matches!(style.lane_projection, LaneProjection::Tabletop);
        let kb_left = transform_point(h, &Point2D::new(0.0, anchor_y));
        let kb_right = transform_point(h, &Point2D::new(white_keys, anchor_y));

        let lane_extent = if tabletop {
            safe_lane_extent(h, anchor_y, lane_dir, white_keys)
        } else {
            Self::CANONICAL_LANE_HEIGHT
        };

        let lane = |u: f64, t: f64| -> Point2D {
            if tabletop {
                transform_point(h, &Point2D::new(u, anchor_y + lane_dir * lane_extent * t))
            } else {
                let base = transform_point(h, &Point2D::new(u, anchor_y));
                Point2D::new(
                    base.x,
                    base.y + lane_dir * lane_height_at(h, u, white_keys) * t,
                )
            }
        };

        let lane_top_left = lane(0.0, 1.0);
        let lane_top_right = lane(white_keys, 1.0);

        let lookahead = style.lookahead_ms.max(1e-6);

        let mut strips = Vec::new();
        let mut key_highlights = Vec::new();

        for note in notes {
            if note.pitch < key_range.lowest_note || note.pitch > key_range.highest_note {
                continue;
            }

            let start_offset = note.start_ms - effective_time;
            let end_offset = (note.start_ms + note.duration_ms) - effective_time;

            if end_offset < -Self::TRAIL_FADE_MS || start_offset > lookahead {
                continue;
            }
            let is_sounding = start_offset <= 0.0 && end_offset >= 0.0;
            if !style.show_before_play && start_offset > 0.0 {
                continue;
            }
            if !style.show_during_play && is_sounding {
                continue;
            }

            let is_black = is_black_key(note.pitch);
            let key_x = key_canonical_x(note.pitch, key_range.lowest_note, is_black);

            let t_bottom = (start_offset / lookahead).clamp(0.0, 1.0);
            let t_top = (end_offset / lookahead).clamp(t_bottom, 1.0);
            if t_top - t_bottom < 0.0005 {
                continue;
            }

            let width_unit = if is_black {
                Self::BLACK_STRIP_WIDTH_UNIT
            } else {
                Self::WHITE_STRIP_WIDTH_UNIT
            };
            let half_width = width_unit * style.strip_thickness as f64 / 2.0;
            let u_left = key_x - half_width;
            let u_right = key_x + half_width;

            let bottom_left = lane(u_left, t_bottom);
            let bottom_right = lane(u_right, t_bottom);
            let top_right = lane(u_right, t_top);
            let top_left = lane(u_left, t_top);

            let mut color = if style.use_hand_colors {
                if note.track == 0 {
                    style.left_hand_color
                } else {
                    style.right_hand_color
                }
            } else if is_black {
                style.black_key_color
            } else {
                style.white_key_color
            };

            let mut opacity = style.transparency;
            if end_offset < 0.0 {
                let fade = 1.0 - (-end_offset / Self::TRAIL_FADE_MS).clamp(0.0, 1.0);
                opacity *= fade as f32;
            }
            color[3] = opacity;

            // Rounding and outline are stored as fractions of the strip width so
            // that preview and export agree at different resolutions.
            let strip_px_width = distance(&bottom_left, &bottom_right);
            strips.push(NoteStrip {
                quad: [top_left, top_right, bottom_right, bottom_left],
                color,
                glow_radius: style.glow_radius,
                glow_intensity: style.glow_strength,
                corner_radius: (style.corner_radius as f64 * strip_px_width) as f32,
                border_width: (style.border_width as f64 * strip_px_width) as f32,
                border_color: style.border_color,
            });

            if style.key_highlight_enabled && is_sounding {
                key_highlights.push(KeyHighlight {
                    quad: key_quad(h, key_x, is_black),
                    color: style.key_highlight_color,
                });
            }
        }

        OverlayFrame {
            strips,
            key_highlights,
            timestamp_ms,
            fall_lane_quad: Some([kb_left, kb_right, lane_top_right, lane_top_left]),
            lane_opacity: style.lane_opacity,
        }
    }
}

/// How far the tabletop lane may travel along the keyboard plane, in keyboard
/// depths, before it reaches the horizon.
///
/// A point is in front of the camera while the homography's third row stays
/// positive. That row is linear in the canonical coordinates, so the crossing
/// point is exact: `w(t) = w0 + dw * t`. On most shots the lane runs *away*
/// from the horizon and nothing is clamped; on shots looking along the keyboard
/// plane this stops the lane just short of turning inside out.
fn safe_lane_extent(h: &[[f64; 3]; 3], anchor_y: f64, lane_dir: f64, white_keys: f64) -> f64 {
    let mut extent = OverlayEngine::CANONICAL_LANE_HEIGHT;
    let dw = h[2][1] * lane_dir;
    if dw >= 0.0 {
        return extent;
    }
    for u in [0.0, white_keys] {
        let w0 = h[2][0] * u + h[2][1] * anchor_y + h[2][2];
        if w0 <= 0.0 {
            continue;
        }
        let limit = 0.9 * w0 / -dw;
        if limit < extent {
            extent = limit;
        }
    }
    extent.max(0.0)
}

/// On-screen height of the upright lane above the key at canonical x `u`, in pixels.
///
/// The keyboard's own depth at that x is the perspective cue: a wall of constant
/// world height looks taller where it is nearer the camera. `u` is clamped into
/// the calibrated span so the measurement never leaves the quad -- extrapolating
/// past it is exactly what made the old lane degenerate.
fn lane_height_at(h: &[[f64; 3]; 3], u: f64, white_keys: f64) -> f64 {
    let clamped = u.clamp(0.0, white_keys);
    let far = transform_point(h, &Point2D::new(clamped, 0.0));
    let near = transform_point(h, &Point2D::new(clamped, 1.0));
    distance(&far, &near) * OverlayEngine::CANONICAL_LANE_HEIGHT
}

/// Screen-space quad of a key on the keyboard surface (canonical y = 0..1).
fn key_quad(homography: &[[f64; 3]; 3], key_x: f64, is_black: bool) -> [Point2D; 4] {
    let half_width = if is_black { 0.55 } else { 0.9 } / 2.0;
    let x_left = key_x - half_width;
    let x_right = key_x + half_width;
    [
        transform_point(homography, &Point2D::new(x_left, 0.0)),
        transform_point(homography, &Point2D::new(x_right, 0.0)),
        transform_point(homography, &Point2D::new(x_right, 1.0)),
        transform_point(homography, &Point2D::new(x_left, 1.0)),
    ]
}

/// Canonical x-centre of a key, in white-key units from the lowest note.
fn key_canonical_x(pitch: u8, lowest_note: u8, is_black: bool) -> f64 {
    let white_below = count_white_keys_below(pitch, lowest_note) as f64;
    if !is_black {
        return white_below + 0.5;
    }
    // A black key straddles the seam between two white keys, and `white_below`
    // is exactly that seam: it counts every white key to the left of this note.
    // Real keyboards nudge the keys within a group away from the seam rather
    // than sitting dead on it.
    let seam_offset = match pitch % 12 {
        1 => -0.05, // C#
        3 => 0.05,  // D#
        6 => -0.10, // F#
        8 => 0.0,   // G#
        10 => 0.10, // A#
        _ => 0.0,
    };
    white_below + seam_offset
}

/// Count white keys from `lowest` up to (but not including) `note`.
fn count_white_keys_below(note: u8, lowest: u8) -> u32 {
    (lowest..note).filter(|n| !is_black_key(*n)).count() as u32
}

fn distance(a: &Point2D, b: &Point2D) -> f64 {
    ((b.x - a.x).powi(2) + (b.y - a.y).powi(2)).sqrt()
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

    /// A real calibration from an angled hand-held shot. Extending the lane
    /// along the keyboard plane here sends the low end far off the left of a
    /// 1920 px frame while the high end barely rises -- the bug this guards.
    fn make_angled_calibration() -> CalibrationData {
        let corners = KeyboardCorners {
            top_left: Point2D::new(694.2353, 1131.8663),
            top_right: Point2D::new(1248.8021, 495.5775),
            bottom_right: Point2D::new(1347.2727, 508.6364),
            bottom_left: Point2D::new(1006.3636, 1195.9091),
        };
        compute_calibration(&corners, KeyboardSize::Keys88)
            .expect("angled calibration should succeed")
    }

    fn angled_note(pitch: u8) -> Vec<MidiNote> {
        vec![MidiNote {
            pitch,
            velocity: 100,
            start_ms: 0.0,
            duration_ms: 2000.0,
            channel: 0,
            track: 0,
        }]
    }

    fn upright_style() -> OverlayStyle {
        OverlayStyle {
            lane_projection: LaneProjection::Upright,
            ..OverlayStyle::default()
        }
    }

    /// Middle C is the 24th white key up from A0, so its centre is at canonical
    /// x 23.5. Through the homography that is x = 1099 in the video.
    /// Interpolating linearly along the keyboard edge instead puts it at
    /// x = 945 -- 18 white keys, over two octaves, too far left.
    #[test]
    fn test_angled_shot_places_middle_c_through_the_homography() {
        let cal = make_angled_calibration();
        let sync = SyncSettings::default();

        for style in [OverlayStyle::default(), upright_style()] {
            let frame = OverlayEngine::compute_frame(0.0, &angled_note(60), &cal, &style, &sync);
            let quad = frame.strips[0].quad;
            let landing = (quad[2].x + quad[3].x) / 2.0;
            assert!(
                (landing - 1098.96).abs() < 0.5,
                "middle C landed at {landing}, expected 1098.96"
            );
            assert!(
                (landing - 944.86).abs() > 100.0,
                "notes are being placed by linear interpolation again"
            );
        }
    }

    #[test]
    fn test_angled_shot_notes_land_left_to_right_on_their_own_keys() {
        let cal = make_angled_calibration();
        let sync = SyncSettings::default();

        for style in [OverlayStyle::default(), upright_style()] {
            let mut previous = f64::NEG_INFINITY;
            for pitch in 21u8..=108 {
                let frame =
                    OverlayEngine::compute_frame(0.0, &angled_note(pitch), &cal, &style, &sync);
                let quad = frame.strips[0].quad;
                let landing = (quad[2].x + quad[3].x) / 2.0;
                assert!(
                    landing > previous,
                    "pitch {pitch} landed left of the note below it"
                );
                previous = landing;
            }
        }
    }

    #[test]
    fn test_tabletop_lane_keeps_the_camera_perspective() {
        let cal = make_angled_calibration();
        let style = OverlayStyle::default();
        let sync = SyncSettings::default();
        let frame = OverlayEngine::compute_frame(0.0, &angled_note(21), &cal, &style, &sync);
        let quad = frame.strips[0].quad;
        assert!(
            (quad[0].x - quad[3].x).abs() > 50.0,
            "the tabletop lane should recede along the keyboard plane"
        );
    }

    #[test]
    fn test_tabletop_lane_stays_in_front_of_the_camera() {
        let cal = make_angled_calibration();
        let style = OverlayStyle::default();
        let sync = SyncSettings::default();
        let frame = OverlayEngine::compute_frame(0.0, &[], &cal, &style, &sync);
        for p in frame.fall_lane_quad.expect("lane quad") {
            assert!(
                p.x.is_finite() && p.y.is_finite(),
                "lane corner is not finite"
            );
        }
    }

    #[test]
    fn test_upright_shot_strips_rise_without_sliding_sideways() {
        let cal = make_angled_calibration();
        let style = upright_style();
        let sync = SyncSettings::default();

        for pitch in [21u8, 48, 72, 108] {
            let frame = OverlayEngine::compute_frame(0.0, &angled_note(pitch), &cal, &style, &sync);
            let quad = frame.strips[0].quad;
            assert!(
                (quad[0].x - quad[3].x).abs() < 1e-6,
                "pitch {pitch} drifted sideways along the lane"
            );
            assert!(
                quad[0].y < quad[3].y,
                "pitch {pitch} should rise up the screen"
            );
        }
    }

    #[test]
    fn test_upright_lane_stays_inside_the_frame() {
        let cal = make_angled_calibration();
        let style = upright_style();
        let sync = SyncSettings::default();
        let frame = OverlayEngine::compute_frame(0.0, &[], &cal, &style, &sync);
        for p in frame.fall_lane_quad.expect("lane quad") {
            assert!(
                (0.0..=1920.0).contains(&p.x),
                "lane corner left the frame sideways: {}",
                p.x
            );
        }
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
        assert!(!frame.strips.is_empty());
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
    fn test_hand_colors_follow_the_track() {
        let cal = make_test_calibration();
        let notes = vec![
            MidiNote {
                pitch: 60,
                velocity: 100,
                start_ms: 1000.0,
                duration_ms: 500.0,
                channel: 0,
                track: 0, // left hand
            },
            MidiNote {
                pitch: 64,
                velocity: 100,
                start_ms: 1000.0,
                duration_ms: 500.0,
                channel: 0,
                track: 1, // right hand
            },
        ];
        let style = OverlayStyle {
            use_hand_colors: true,
            left_hand_color: [1.0, 0.0, 0.0, 1.0],
            right_hand_color: [0.0, 1.0, 0.0, 1.0],
            transparency: 1.0,
            ..Default::default()
        };

        let frame =
            OverlayEngine::compute_frame(0.0, &notes, &cal, &style, &SyncSettings::default());
        assert_eq!(frame.strips.len(), 2);
        assert_eq!(
            frame.strips[0].color[0], 1.0,
            "track 0 uses the left colour"
        );
        assert_eq!(
            frame.strips[1].color[1], 1.0,
            "track 1 uses the right colour"
        );
    }

    #[test]
    fn test_frame_carries_the_fall_lane() {
        let cal = make_test_calibration();
        let frame = OverlayEngine::compute_frame(
            0.0,
            &make_test_notes(),
            &cal,
            &OverlayStyle::default(),
            &SyncSettings::default(),
        );
        let lane = frame.fall_lane_quad.expect("lane should be present");
        // Lane starts on the keyboard and extends upward, away from it.
        assert!((lane[0].y - 100.0).abs() < 1.0);
        assert!(
            lane[3].y < lane[0].y,
            "lane should extend above the keyboard"
        );
        assert_eq!(frame.lane_opacity, OverlayStyle::default().lane_opacity);
    }

    #[test]
    fn test_strip_thickness_changes_strip_width() {
        let cal = make_test_calibration();
        let notes = make_test_notes();
        let sync = SyncSettings::default();

        let thin = OverlayStyle {
            strip_thickness: 0.4,
            ..Default::default()
        };
        let thick = OverlayStyle {
            strip_thickness: 1.0,
            ..Default::default()
        };

        let width_of = |style: &OverlayStyle| {
            let frame = OverlayEngine::compute_frame(0.0, &notes, &cal, style, &sync);
            let quad = frame.strips[0].quad;
            distance(&quad[3], &quad[2])
        };

        assert!(
            width_of(&thick) > width_of(&thin) * 2.0 - 1e-6,
            "width should scale with strip_thickness"
        );
    }

    #[test]
    fn test_corner_radius_scales_with_strip_width() {
        let cal = make_test_calibration();
        let notes = make_test_notes();
        let style = OverlayStyle {
            corner_radius: 0.25,
            ..Default::default()
        };
        let frame =
            OverlayEngine::compute_frame(0.0, &notes, &cal, &style, &SyncSettings::default());
        let strip = &frame.strips[0];
        let width = distance(&strip.quad[3], &strip.quad[2]);
        assert!((strip.corner_radius as f64 - width * 0.25).abs() < 0.01);
    }

    #[test]
    fn test_notes_outside_the_key_range_are_skipped() {
        let cal = make_test_calibration();
        let notes = vec![MidiNote {
            pitch: 12, // below A0 on an 88-key board
            velocity: 100,
            start_ms: 1000.0,
            duration_ms: 500.0,
            channel: 0,
            track: 0,
        }];
        let frame = OverlayEngine::compute_frame(
            0.0,
            &notes,
            &cal,
            &OverlayStyle::default(),
            &SyncSettings::default(),
        );
        assert!(frame.strips.is_empty());
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
