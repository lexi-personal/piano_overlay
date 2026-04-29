use serde::{Deserialize, Serialize};

/// A single MIDI note event with absolute timing in milliseconds.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MidiNote {
    /// MIDI pitch (0-127). Middle C = 60, A0 = 21, C8 = 108.
    pub pitch: u8,
    /// Note velocity (0-127).
    pub velocity: u8,
    /// Start time in milliseconds from the beginning of the file.
    pub start_ms: f64,
    /// Duration in milliseconds.
    pub duration_ms: f64,
    /// MIDI channel (0-15).
    pub channel: u8,
    /// Track index within the MIDI file.
    pub track: u16,
}

/// A single track within a MIDI file.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MidiTrack {
    /// Track name from the MIDI metadata (may be empty).
    pub name: String,
    /// All notes in this track, sorted by start_ms.
    pub notes: Vec<MidiNote>,
    /// Primary channel used by this track (heuristic: most common channel).
    pub channel: u8,
}

/// Parsed MIDI file with all timing converted to absolute milliseconds.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MidiFileData {
    /// All tracks in the MIDI file.
    pub tracks: Vec<MidiTrack>,
    /// Total duration in milliseconds (end of last note).
    pub duration_ms: f64,
    /// Total note count across all tracks.
    pub note_count: u32,
    /// Initial tempo in BPM (may change throughout the piece).
    pub initial_tempo_bpm: f64,
    /// Ticks per quarter note (from MIDI header).
    pub ticks_per_beat: u16,
    /// Number of tracks.
    pub track_count: u16,
}

/// Summary info for displaying to the user before full parsing.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MidiFileSummary {
    pub duration_ms: f64,
    pub note_count: u32,
    pub track_count: u16,
    pub initial_tempo_bpm: f64,
    pub lowest_note: u8,
    pub highest_note: u8,
}

impl MidiFileData {
    /// Get a flat list of all notes across all tracks, sorted by start time.
    pub fn all_notes_sorted(&self) -> Vec<&MidiNote> {
        let mut notes: Vec<&MidiNote> = self.tracks.iter().flat_map(|t| &t.notes).collect();
        notes.sort_by(|a, b| a.start_ms.partial_cmp(&b.start_ms).unwrap());
        notes
    }

    /// Get summary info.
    pub fn summary(&self) -> MidiFileSummary {
        let all_notes: Vec<&MidiNote> = self.tracks.iter().flat_map(|t| &t.notes).collect();
        let lowest = all_notes.iter().map(|n| n.pitch).min().unwrap_or(0);
        let highest = all_notes.iter().map(|n| n.pitch).max().unwrap_or(127);

        MidiFileSummary {
            duration_ms: self.duration_ms,
            note_count: self.note_count,
            track_count: self.track_count,
            initial_tempo_bpm: self.initial_tempo_bpm,
            lowest_note: lowest,
            highest_note: highest,
        }
    }
}
