import 'midi_note.dart';
import 'video_metadata.dart';
import 'calibration.dart';
import 'overlay_style.dart';

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
  });

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
}
