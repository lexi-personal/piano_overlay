/// A single MIDI note event with absolute timing in milliseconds.
class MidiNote {
  final int pitch;
  final int velocity;
  final double startMs;
  final double durationMs;
  final int channel;
  final int track;

  const MidiNote({
    required this.pitch,
    required this.velocity,
    required this.startMs,
    required this.durationMs,
    required this.channel,
    required this.track,
  });

  factory MidiNote.fromJson(Map<String, dynamic> json) {
    return MidiNote(
      pitch: json['pitch'] as int,
      velocity: json['velocity'] as int,
      startMs: (json['start_ms'] as num).toDouble(),
      durationMs: (json['duration_ms'] as num).toDouble(),
      channel: json['channel'] as int,
      track: json['track'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'pitch': pitch,
        'velocity': velocity,
        'start_ms': startMs,
        'duration_ms': durationMs,
        'channel': channel,
        'track': track,
      };

  /// True if this note is on a black key.
  bool get isBlackKey {
    final semitone = pitch % 12;
    return const [1, 3, 6, 8, 10].contains(semitone);
  }

  /// Note name (e.g., "C4", "F#5").
  String get noteName {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (pitch ~/ 12) - 1;
    final name = names[pitch % 12];
    return '$name$octave';
  }

  /// End time in milliseconds.
  double get endMs => startMs + durationMs;
}

/// A MIDI track.
class MidiTrack {
  final String name;
  final List<MidiNote> notes;
  final int channel;

  const MidiTrack({
    required this.name,
    required this.notes,
    required this.channel,
  });

  factory MidiTrack.fromJson(Map<String, dynamic> json) {
    return MidiTrack(
      name: json['name'] as String,
      notes: (json['notes'] as List).map((n) => MidiNote.fromJson(n)).toList(),
      channel: json['channel'] as int,
    );
  }
}

/// Parsed MIDI file data.
class MidiFileData {
  final List<MidiTrack> tracks;
  final double durationMs;
  final int noteCount;
  final double initialTempoBpm;
  final int ticksPerBeat;
  final int trackCount;

  const MidiFileData({
    required this.tracks,
    required this.durationMs,
    required this.noteCount,
    required this.initialTempoBpm,
    required this.ticksPerBeat,
    required this.trackCount,
  });

  factory MidiFileData.fromJson(Map<String, dynamic> json) {
    return MidiFileData(
      tracks: (json['tracks'] as List).map((t) => MidiTrack.fromJson(t)).toList(),
      durationMs: (json['duration_ms'] as num).toDouble(),
      noteCount: json['note_count'] as int,
      initialTempoBpm: (json['initial_tempo_bpm'] as num).toDouble(),
      ticksPerBeat: json['ticks_per_beat'] as int,
      trackCount: json['track_count'] as int,
    );
  }

  /// All notes across all tracks.
  List<MidiNote> get allNotes {
    return tracks.expand((t) => t.notes).toList();
  }

  /// All notes across all tracks, sorted by start time.
  List<MidiNote> get allNotesSorted {
    final notes = allNotes;
    notes.sort((a, b) => a.startMs.compareTo(b.startMs));
    return notes;
  }

  /// Create an empty MidiFileData.
  factory MidiFileData.empty() {
    return const MidiFileData(
      tracks: [],
      durationMs: 0,
      noteCount: 0,
      initialTempoBpm: 120,
      ticksPerBeat: 480,
      trackCount: 0,
    );
  }
}

/// Brief summary of a MIDI file.
class MidiFileSummary {
  final double durationMs;
  final int noteCount;
  final int trackCount;
  final double initialTempoBpm;
  final int lowestNote;
  final int highestNote;

  const MidiFileSummary({
    required this.durationMs,
    required this.noteCount,
    required this.trackCount,
    required this.initialTempoBpm,
    required this.lowestNote,
    required this.highestNote,
  });

  factory MidiFileSummary.fromJson(Map<String, dynamic> json) {
    return MidiFileSummary(
      durationMs: (json['duration_ms'] as num).toDouble(),
      noteCount: json['note_count'] as int,
      trackCount: json['track_count'] as int,
      initialTempoBpm: (json['initial_tempo_bpm'] as num).toDouble(),
      lowestNote: json['lowest_note'] as int,
      highestNote: json['highest_note'] as int,
    );
  }
}
