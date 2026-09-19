import 'midi_note.dart';

/// Which hand a MIDI track is played with, which decides its colour when
/// per-hand colouring is on.
enum Hand { left, right }

/// Per-track editing state for the timeline.
class TrackSettings {
  /// Whether the track is drawn in the overlay at all.
  final bool visible;

  /// The hand this track belongs to.
  final Hand hand;

  /// Nudge applied to every note in the track, in milliseconds. Dragging a
  /// lane in the timeline changes this.
  final double offsetMs;

  /// Only notes starting at or after this point are kept.
  final double trimStartMs;

  /// Only notes starting before this point are kept. Null means no end trim.
  final double? trimEndMs;

  const TrackSettings({
    this.visible = true,
    this.hand = Hand.right,
    this.offsetMs = 0.0,
    this.trimStartMs = 0.0,
    this.trimEndMs,
  });

  /// The default for track [index]: the first track is conventionally the
  /// left hand in two-track piano MIDI files.
  factory TrackSettings.forTrack(int index) =>
      TrackSettings(hand: index == 0 ? Hand.left : Hand.right);

  TrackSettings copyWith({
    bool? visible,
    Hand? hand,
    double? offsetMs,
    double? trimStartMs,
    double? trimEndMs,
    bool clearTrimEnd = false,
  }) {
    return TrackSettings(
      visible: visible ?? this.visible,
      hand: hand ?? this.hand,
      offsetMs: offsetMs ?? this.offsetMs,
      trimStartMs: trimStartMs ?? this.trimStartMs,
      trimEndMs: clearTrimEnd ? null : (trimEndMs ?? this.trimEndMs),
    );
  }

  /// Apply this track's edits to [notes], dropping trimmed ones and rewriting
  /// the track index to the hand so the renderers can colour by hand.
  List<MidiNote> apply(List<MidiNote> notes) {
    if (!visible) return const [];

    final result = <MidiNote>[];
    for (final note in notes) {
      final start = note.startMs + offsetMs;
      if (start < trimStartMs) continue;
      if (trimEndMs != null && start >= trimEndMs!) continue;

      result.add(MidiNote(
        pitch: note.pitch,
        velocity: note.velocity,
        startMs: start,
        durationMs: note.durationMs,
        channel: note.channel,
        track: hand == Hand.left ? 0 : 1,
      ));
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
        'visible': visible,
        'hand': hand.name,
        'offset_ms': offsetMs,
        'trim_start_ms': trimStartMs,
        'trim_end_ms': trimEndMs,
      };

  factory TrackSettings.fromJson(Map<String, dynamic> json) {
    return TrackSettings(
      visible: json['visible'] as bool? ?? true,
      hand: json['hand'] == 'left' ? Hand.left : Hand.right,
      offsetMs: (json['offset_ms'] as num?)?.toDouble() ?? 0.0,
      trimStartMs: (json['trim_start_ms'] as num?)?.toDouble() ?? 0.0,
      trimEndMs: (json['trim_end_ms'] as num?)?.toDouble(),
    );
  }
}
