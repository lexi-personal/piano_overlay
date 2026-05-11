use std::fs;
use std::path::Path;

use midly::{MetaMessage, MidiMessage, Smf, Timing, TrackEventKind};
use thiserror::Error;

use super::types::{MidiFileData, MidiNote, MidiTrack};

#[derive(Error, Debug)]
pub enum MidiParseError {
    #[error("Failed to read MIDI file: {0}")]
    IoError(#[from] std::io::Error),
    #[error("Failed to parse MIDI file: {0}")]
    ParseError(String),
    #[error("Unsupported MIDI timing format: SMPTE timecodes are not supported. \
             This file uses absolute time frames instead of ticks-per-beat. \
             Please re-export the MIDI file using metrical (ticks-per-beat) timing.")]
    UnsupportedTiming,
    #[error("MIDI file contains no notes")]
    NoNotes,
}

/// Parse a MIDI file from disk and return structured note data with absolute millisecond timing.
pub fn parse_midi_file(path: &str) -> Result<MidiFileData, MidiParseError> {
    let bytes = fs::read(Path::new(path))?;
    parse_midi_bytes(&bytes)
}

/// Parse MIDI from a byte buffer.
pub fn parse_midi_bytes(bytes: &[u8]) -> Result<MidiFileData, MidiParseError> {
    let smf = Smf::parse(bytes).map_err(|e| MidiParseError::ParseError(e.to_string()))?;

    let ticks_per_beat = match smf.header.timing {
        Timing::Metrical(tpb) => tpb.as_int(),
        Timing::Timecode(..) => return Err(MidiParseError::UnsupportedTiming),
    };

    let mut tracks: Vec<MidiTrack> = Vec::new();
    let mut total_notes = 0u32;

    // Build a global tempo map from all tracks (tempo events can appear in any track).
    let tempo_map = build_tempo_map(&smf, ticks_per_beat);

    for (track_idx, track) in smf.tracks.iter().enumerate() {
        let mut track_name = String::new();
        let mut notes: Vec<MidiNote> = Vec::new();
        let mut active_notes: Vec<PendingNote> = Vec::new();
        let mut tick: u64 = 0;
        let mut channel_counts = [0u32; 16];

        for event in track.iter() {
            tick += event.delta.as_int() as u64;
            let time_ms = tempo_map.tick_to_ms(tick);

            match event.kind {
                TrackEventKind::Meta(MetaMessage::TrackName(name_bytes)) => {
                    if let Ok(name) = std::str::from_utf8(name_bytes) {
                        track_name = name.to_string();
                    }
                }
                TrackEventKind::Midi { channel, message } => {
                    let ch = channel.as_int();
                    channel_counts[ch as usize] += 1;

                    match message {
                        MidiMessage::NoteOn { key, vel } => {
                            if vel.as_int() == 0 {
                                // NoteOn with velocity 0 = NoteOff
                                finish_note(&mut active_notes, &mut notes, ch, key.as_int(), time_ms);
                            } else {
                                active_notes.push(PendingNote {
                                    pitch: key.as_int(),
                                    velocity: vel.as_int(),
                                    channel: ch,
                                    start_ms: time_ms,
                                });
                            }
                        }
                        MidiMessage::NoteOff { key, .. } => {
                            finish_note(&mut active_notes, &mut notes, ch, key.as_int(), time_ms);
                        }
                        _ => {}
                    }
                }
                _ => {}
            }
        }

        // Close any notes still active at end of track
        let end_ms = tempo_map.tick_to_ms(tick);
        for pending in active_notes.drain(..) {
            notes.push(MidiNote {
                pitch: pending.pitch,
                velocity: pending.velocity,
                start_ms: pending.start_ms,
                duration_ms: (end_ms - pending.start_ms).max(1.0),
                channel: pending.channel,
                track: track_idx as u16,
            });
        }

        if !notes.is_empty() {
            notes.sort_by(|a, b| a.start_ms.partial_cmp(&b.start_ms).unwrap());
            total_notes += notes.len() as u32;

            let primary_channel = channel_counts
                .iter()
                .enumerate()
                .max_by_key(|(_, &count)| count)
                .map(|(idx, _)| idx as u8)
                .unwrap_or(0);

            tracks.push(MidiTrack {
                name: track_name,
                notes,
                channel: primary_channel,
            });
        }
    }

    if total_notes == 0 {
        return Err(MidiParseError::NoNotes);
    }

    let duration_ms = tracks
        .iter()
        .flat_map(|t| &t.notes)
        .map(|n| n.start_ms + n.duration_ms)
        .fold(0.0f64, f64::max);

    let initial_tempo = tempo_map.initial_tempo_bpm();

    Ok(MidiFileData {
        tracks,
        duration_ms,
        note_count: total_notes,
        initial_tempo_bpm: initial_tempo,
        ticks_per_beat,
        track_count: smf.tracks.len() as u16,
    })
}

// --- Internal helpers ---

struct PendingNote {
    pitch: u8,
    velocity: u8,
    channel: u8,
    start_ms: f64,
}

fn finish_note(
    active: &mut Vec<PendingNote>,
    completed: &mut Vec<MidiNote>,
    channel: u8,
    pitch: u8,
    end_ms: f64,
) {
    if let Some(idx) = active
        .iter()
        .rposition(|n| n.pitch == pitch && n.channel == channel)
    {
        let pending = active.remove(idx);
        let duration = (end_ms - pending.start_ms).max(0.0);
        completed.push(MidiNote {
            pitch: pending.pitch,
            velocity: pending.velocity,
            start_ms: pending.start_ms,
            duration_ms: duration,
            channel: pending.channel,
            track: 0, // Will be set by caller
        });
    }
}

/// Tempo map: maps MIDI ticks to milliseconds accounting for tempo changes.
struct TempoMap {
    entries: Vec<TempoEntry>,
    ticks_per_beat: u16,
}

struct TempoEntry {
    tick: u64,
    tempo_us_per_beat: u32, // microseconds per quarter note
    time_ms: f64,           // absolute time at this tick
}

impl TempoMap {
    fn tick_to_ms(&self, tick: u64) -> f64 {
        // Find the last tempo entry at or before this tick
        let entry = match self.entries.binary_search_by_key(&tick, |e| e.tick) {
            Ok(idx) => &self.entries[idx],
            Err(0) => &self.entries[0],
            Err(idx) => &self.entries[idx - 1],
        };

        let delta_ticks = tick - entry.tick;
        let ms_per_tick =
            (entry.tempo_us_per_beat as f64) / (self.ticks_per_beat as f64 * 1000.0);
        entry.time_ms + (delta_ticks as f64 * ms_per_tick)
    }

    fn initial_tempo_bpm(&self) -> f64 {
        if self.entries.is_empty() {
            120.0
        } else {
            60_000_000.0 / self.entries[0].tempo_us_per_beat as f64
        }
    }
}

fn build_tempo_map(smf: &Smf, ticks_per_beat: u16) -> TempoMap {
    let mut entries: Vec<TempoEntry> = Vec::new();

    // Default tempo: 120 BPM = 500000 us/beat
    entries.push(TempoEntry {
        tick: 0,
        tempo_us_per_beat: 500_000,
        time_ms: 0.0,
    });

    // Collect all tempo changes from all tracks
    let mut tempo_events: Vec<(u64, u32)> = Vec::new();
    for track in &smf.tracks {
        let mut tick: u64 = 0;
        for event in track.iter() {
            tick += event.delta.as_int() as u64;
            if let TrackEventKind::Meta(MetaMessage::Tempo(tempo)) = event.kind {
                tempo_events.push((tick, tempo.as_int()));
            }
        }
    }

    // Sort by tick
    tempo_events.sort_by_key(|(tick, _)| *tick);
    // Deduplicate (same tick, keep last)
    tempo_events.dedup_by_key(|(tick, _)| *tick);

    // Build map with cumulative time
    let mut map = TempoMap {
        entries: vec![TempoEntry {
            tick: 0,
            tempo_us_per_beat: 500_000,
            time_ms: 0.0,
        }],
        ticks_per_beat,
    };

    for (tick, tempo_us) in tempo_events {
        if tick == 0 {
            map.entries[0].tempo_us_per_beat = tempo_us;
        } else {
            let time_ms = map.tick_to_ms(tick);
            map.entries.push(TempoEntry {
                tick,
                tempo_us_per_beat: tempo_us,
                time_ms,
            });
        }
    }

    map
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tempo_map_default() {
        let map = TempoMap {
            entries: vec![TempoEntry {
                tick: 0,
                tempo_us_per_beat: 500_000,
                time_ms: 0.0,
            }],
            ticks_per_beat: 480,
        };
        // At 120 BPM, 480 ticks = 1 beat = 500ms
        let ms = map.tick_to_ms(480);
        assert!((ms - 500.0).abs() < 0.01);

        let ms2 = map.tick_to_ms(960);
        assert!((ms2 - 1000.0).abs() < 0.01);
    }

    #[test]
    fn test_tempo_map_with_change() {
        let map = TempoMap {
            entries: vec![
                TempoEntry {
                    tick: 0,
                    tempo_us_per_beat: 500_000, // 120 BPM
                    time_ms: 0.0,
                },
                TempoEntry {
                    tick: 480,
                    tempo_us_per_beat: 250_000, // 240 BPM
                    time_ms: 500.0,
                },
            ],
            ticks_per_beat: 480,
        };
        // After tempo change: 480 ticks at 240 BPM = 250ms
        let ms = map.tick_to_ms(960);
        assert!((ms - 750.0).abs() < 0.01);
    }
}
