import 'midi_note.dart';
import 'video_metadata.dart';
import 'calibration.dart';
import 'overlay_style.dart';
import 'track_settings.dart';

/// Complete project state.
class Project {
  final String version;
  String name;
  final String createdAt;
  String modifiedAt;

  VideoMetadata? video;
  String? videoPath;
  MidiFileData? midi;
  String? midiPath;
  CalibrationData? calibration;
  SyncSettings sync;
  OverlayStyle style;
  ExportSettings export_;

  /// Per-MIDI-track timeline edits, keyed by track index.
  Map<int, TrackSettings> trackSettings;

  Project({
    this.version = '1.0.0',
    required this.name,
    required this.createdAt,
    required this.modifiedAt,
    this.video,
    this.videoPath,
    this.midi,
    this.midiPath,
    this.calibration,
    this.sync = const SyncSettings(),
    this.style = const OverlayStyle(),
    this.export_ = const ExportSettings(),
    Map<int, TrackSettings>? trackSettings,
  }) : trackSettings = trackSettings ?? <int, TrackSettings>{};

  factory Project.create(String name) {
    final now = DateTime.now().toIso8601String();
    return Project(
      name: name,
      createdAt: now,
      modifiedAt: now,
    );
  }

  bool get hasVideo => video != null;
  bool get hasMidi => midi != null;
  bool get hasCalibration => calibration != null;
  bool get isReadyForPreview => hasVideo && hasMidi && hasCalibration;
  bool get isReadyForExport => isReadyForPreview;

  /// The timeline state for track [index], defaulted on first use.
  TrackSettings trackFor(int index) =>
      trackSettings[index] ?? TrackSettings.forTrack(index);

  /// Every note that should be rendered, with each track's visibility, nudge,
  /// trim and hand assignment already applied.
  List<MidiNote> get renderableNotes {
    final tracks = midi?.tracks;
    if (tracks == null) return const [];

    final notes = <MidiNote>[];
    for (var i = 0; i < tracks.length; i++) {
      notes.addAll(trackFor(i).apply(tracks[i].notes));
    }
    notes.sort((a, b) => a.startMs.compareTo(b.startMs));
    return notes;
  }
}
