import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../models/project.dart';
import '../models/midi_note.dart';
import '../models/video_metadata.dart';
import '../models/calibration.dart';
import '../models/overlay_style.dart';
import '../models/track_settings.dart';

/// Central project state, shared across all screens.
/// Uses ChangeNotifier for simple, framework-native state management.
class ProjectProvider extends ChangeNotifier {
  Project? _project;
  String? _savedPath;
  bool _isDirty = false;

  Project? get project => _project;
  bool get hasProject => _project != null;

  /// Path of the `.pvproj` file this project was last saved to or loaded from.
  String? get savedPath => _savedPath;

  /// True when the project has unsaved modifications.
  bool get isDirty => _isDirty;

  /// Whether there is work that no project file holds yet, either because the
  /// project has never been saved or because it changed since the last save.
  bool get hasUnsavedWork => _project != null && (_isDirty || _savedPath == null);

  bool get hasVideo => _project?.hasVideo ?? false;
  bool get hasMidi => _project?.hasMidi ?? false;
  bool get hasCalibration => _project?.hasCalibration ?? false;
  bool get isReadyForPreview => _project?.isReadyForPreview ?? false;
  bool get isReadyForExport => _project?.isReadyForExport ?? false;

  /// Create a new empty project.
  void createProject(String name) {
    _project = Project.create(name);
    _savedPath = null;
    _isDirty = false;
    notifyListeners();
  }

  /// Rename the current project.
  void renameProject(String name) {
    if (_project == null) return;
    _project!.name = name;
    _markModified();
  }

  /// Stamp the modification time, flag unsaved changes and notify listeners.
  void _markModified() {
    _project!.modifiedAt = DateTime.now().toIso8601String();
    _isDirty = true;
    notifyListeners();
  }

  /// Set video file and metadata.
  void setVideo(String path, VideoMetadata metadata) {
    if (_project == null) return;
    _project!.videoPath = path;
    _project!.video = metadata;
    _markModified();
  }

  /// Set MIDI file data.
  void setMidi(String path, MidiFileData data) {
    if (_project == null) return;
    _project!.midiPath = path;
    _project!.midi = data;
    _markModified();
  }

  /// Set calibration result.
  void setCalibration(CalibrationData calibration) {
    if (_project == null) return;
    _project!.calibration = calibration;
    _markModified();
  }

  /// Update sync settings.
  void updateSync(SyncSettings sync) {
    if (_project == null) return;
    _project!.sync = sync;
    _markModified();
  }

  /// Update overlay style.
  /// Replace the timeline state for one MIDI track.
  void updateTrackSettings(int index, TrackSettings settings) {
    if (_project == null) return;
    _project!.trackSettings[index] = settings;
    _markModified();
  }

  void updateStyle(OverlayStyle style) {
    if (_project == null) return;
    _project!.style = style;
    _markModified();
  }

  /// Update export settings.
  void updateExportSettings(ExportSettings settings) {
    if (_project == null) return;
    _project!.export_ = settings;
    _markModified();
  }

  /// Save project into [directoryPath], deriving the file name from the
  /// project name. Returns the written file path.
  Future<String> saveProject(String directoryPath) async {
    if (_project == null) throw StateError('No project to save');

    final fileName = '${_project!.name.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_')}.pvproj';
    return saveProjectToFile('$directoryPath/$fileName');
  }

  /// Save project to an explicit `.pvproj` file path.
  Future<String> saveProjectToFile(String filePath) async {
    if (_project == null) throw StateError('No project to save');

    final path = filePath.toLowerCase().endsWith('.pvproj') ? filePath : '$filePath.pvproj';
    _project!.modifiedAt = DateTime.now().toIso8601String();
    final json = _projectToJson(_project!);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
    _savedPath = path;
    _isDirty = false;
    notifyListeners();
    return path;
  }

  /// Save to the previously used path. Returns null when the project has
  /// never been saved, in which case the caller should prompt for a location.
  Future<String?> saveToExistingPath() async {
    if (_savedPath == null) return null;
    return saveProjectToFile(_savedPath!);
  }

  /// Load project from a .pvproj file.
  Future<void> loadProject(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Project file not found: $filePath');
    }

    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    _project = _projectFromJson(json);
    _savedPath = filePath;
    _isDirty = false;
    notifyListeners();
  }

  /// Snapshot of the project in the same shape as a `.pvproj` file.
  Map<String, dynamic> toJson() {
    if (_project == null) throw StateError('No project to serialize');
    return _projectToJson(_project!);
  }

  /// Adopt a project that did not come from its own file, such as a crash
  /// recovery snapshot. It stays dirty because [savedPath] does not yet
  /// contain these changes.
  void restoreFromJson(Map<String, dynamic> json, {String? savedPath}) {
    _project = _projectFromJson(json);
    _savedPath = savedPath;
    _isDirty = true;
    notifyListeners();
  }

  // --- Serialization ---

  Map<String, dynamic> _projectToJson(Project p) {
    return {
      'version': p.version,
      'name': p.name,
      'created_at': p.createdAt,
      'modified_at': p.modifiedAt,
      'video_path': p.videoPath,
      'video': p.video?.toJson(),
      'midi_path': p.midiPath,
      'midi': p.midi != null ? _midiToJson(p.midi!) : null,
      'calibration': p.calibration != null ? _calibrationToJson(p.calibration!) : null,
      'sync': p.sync.toJson(),
      'style': p.style.toJson(),
      'export': p.export_.toJson(),
      'track_settings': p.trackSettings
          .map((index, settings) => MapEntry('$index', settings.toJson())),
    };
  }

  Project _projectFromJson(Map<String, dynamic> json) {
    return Project(
      version: json['version'] ?? '1.0.0',
      name: json['name'] ?? 'Untitled',
      createdAt: json['created_at'] ?? DateTime.now().toIso8601String(),
      modifiedAt: json['modified_at'] ?? DateTime.now().toIso8601String(),
      videoPath: json['video_path'],
      video: json['video'] != null ? VideoMetadata.fromJson(json['video']) : null,
      midiPath: json['midi_path'],
      midi: json['midi'] != null ? MidiFileData.fromJson(json['midi']) : null,
      calibration: json['calibration'] != null
          ? CalibrationData.fromJson(json['calibration'])
          : null,
      sync: json['sync'] != null
          ? SyncSettings.fromJson(json['sync'])
          : const SyncSettings(),
      style: json['style'] != null
          ? _overlayStyleFromJson(json['style'])
          : const OverlayStyle(),
      trackSettings: _trackSettingsFromJson(json['track_settings']),
    );
  }

  Map<int, TrackSettings> _trackSettingsFromJson(dynamic json) {
    final settings = <int, TrackSettings>{};
    if (json is! Map) return settings;

    json.forEach((key, value) {
      final index = int.tryParse('$key');
      if (index != null && value is Map<String, dynamic>) {
        settings[index] = TrackSettings.fromJson(value);
      }
    });
    return settings;
  }

  Map<String, dynamic> _midiToJson(MidiFileData midi) {
    return {
      'tracks': midi.tracks.map((t) => <String, dynamic>{
        'name': t.name,
        'channel': t.channel,
        'notes': t.notes.map((n) => n.toJson()).toList(),
      }).toList(),
      'duration_ms': midi.durationMs,
      'note_count': midi.noteCount,
      'initial_tempo_bpm': midi.initialTempoBpm,
      'ticks_per_beat': midi.ticksPerBeat,
      'track_count': midi.trackCount,
    };
  }

  Map<String, dynamic> _calibrationToJson(CalibrationData cal) {
    return {
      'corners': cal.corners.toJson(),
      'keyboard_size': cal.keyboardSize.name,
      'key_range': cal.keyRange.toJson(),
      'homography': cal.homography,
      'key_positions': cal.keyPositions.map((k) => <String, dynamic>{
        'note': k.note,
        'is_black': k.isBlack,
        'screen_quad': k.screenQuad.map((p) => p.toJson()).toList(),
        'canonical_x_center': k.canonicalXCenter,
      }).toList(),
      'calibration_width': cal.calibrationWidth,
      'calibration_height': cal.calibrationHeight,
    };
  }

  OverlayStyle _overlayStyleFromJson(Map<String, dynamic> json) {
    return OverlayStyle(
      whiteKeyColor: _hexToColor(json['white_key_color'] ?? '#FF4FC3F7'),
      blackKeyColor: _hexToColor(json['black_key_color'] ?? '#FFFF7043'),
      leftHandColor: _hexToColor(json['left_hand_color'] ?? '#FF4FC3F7'),
      rightHandColor: _hexToColor(json['right_hand_color'] ?? '#FFFF7043'),
      useHandColors: json['use_hand_colors'] ?? false,
      stripThickness: (json['strip_thickness'] as num?)?.toDouble() ?? 0.8,
      glowStrength: (json['glow_strength'] as num?)?.toDouble() ?? 0.5,
      glowRadius: (json['glow_radius'] as num?)?.toDouble() ?? 8.0,
      transparency: (json['transparency'] as num?)?.toDouble() ?? 0.92,
      laneOpacity: (json['lane_opacity'] as num?)?.toDouble() ?? 0.55,
      lookaheadMs: (json['lookahead_ms'] as num?)?.toDouble() ?? 2000.0,
      showBeforePlay: json['show_before_play'] ?? true,
      showDuringPlay: json['show_during_play'] ?? true,
      fallSpeed: (json['fall_speed'] as num?)?.toDouble() ?? 200.0,
      keyHighlightEnabled: json['key_highlight_enabled'] ?? true,
      keyHighlightColor: _hexToColor(json['key_highlight_color'] ?? '#40FFFFFF'),
      fallDirection: json['fall_direction'] == 'bottomToTop'
          ? FallDirection.bottomToTop
          : FallDirection.topToBottom,
      backgroundDim: (json['background_dim'] as num?)?.toDouble() ?? 0.0,
      cornerRadius: (json['corner_radius'] as num?)?.toDouble() ?? 0.0,
      borderWidth: (json['border_width'] as num?)?.toDouble() ?? 0.0,
      borderColor: _hexToColor(json['border_color'] ?? '#E6FFFFFF'),
    );
  }

  static Color _hexToColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}
