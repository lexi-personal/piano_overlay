import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../models/midi_note.dart';
import '../models/video_metadata.dart';
import '../models/calibration.dart';
import '../features/preview/overlay_painter.dart';

/// Typedef for FFI functions returning char* (no args).
typedef _FfiHealthCheckC = Pointer<Utf8> Function();
typedef _FfiHealthCheckDart = Pointer<Utf8> Function();

/// Typedef for FFI functions taking char* path and returning char*.
typedef _FfiStringArgC = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _FfiStringArgDart = Pointer<Utf8> Function(Pointer<Utf8>);

/// Typedef for ffi_free_string.
typedef _FfiFreeStringC = Void Function(Pointer<Utf8>);
typedef _FfiFreeStringDart = void Function(Pointer<Utf8>);

/// Service that bridges Flutter UI to the Rust native core via dart:ffi.
///
/// Uses C-compatible FFI (JSON over CString) to call Rust functions
/// defined in native/src/ffi.rs.
class NativeBridge {
  static final NativeBridge _instance = NativeBridge._();
  factory NativeBridge() => _instance;
  NativeBridge._();

  DynamicLibrary? _lib;
  bool _initialized = false;

  // Cached function lookups
  late _FfiHealthCheckDart _healthCheck;
  late _FfiStringArgDart _parseMidi;
  late _FfiStringArgDart _extractVideoMetadata;
  late _FfiStringArgDart _computeCalibration;
  late _FfiStringArgDart _computeOverlayFrame;
  late _FfiStringArgDart _startExport;
  late _FfiHealthCheckDart _checkFfmpeg;
  late _FfiStringArgDart _saveProject;
  late _FfiStringArgDart _loadProject;
  late _FfiFreeStringDart _freeString;

  /// Initialize the native library. Must be called before any other method.
  void initialize({String? libraryPath}) {
    if (_initialized) return;

    _lib = _loadLibrary(libraryPath);

    _healthCheck = _lib!
        .lookupFunction<_FfiHealthCheckC, _FfiHealthCheckDart>('ffi_health_check');
    _parseMidi = _lib!
        .lookupFunction<_FfiStringArgC, _FfiStringArgDart>('ffi_parse_midi');
    _extractVideoMetadata = _lib!
        .lookupFunction<_FfiStringArgC, _FfiStringArgDart>('ffi_extract_video_metadata');
    _computeCalibration = _lib!
        .lookupFunction<_FfiStringArgC, _FfiStringArgDart>('ffi_compute_calibration');
    _computeOverlayFrame = _lib!
        .lookupFunction<_FfiStringArgC, _FfiStringArgDart>('ffi_compute_overlay_frame');
    _startExport = _lib!
        .lookupFunction<_FfiStringArgC, _FfiStringArgDart>('ffi_start_export');
    _checkFfmpeg = _lib!
        .lookupFunction<_FfiHealthCheckC, _FfiHealthCheckDart>('ffi_check_ffmpeg');
    _saveProject = _lib!
        .lookupFunction<_FfiStringArgC, _FfiStringArgDart>('ffi_save_project');
    _loadProject = _lib!
        .lookupFunction<_FfiStringArgC, _FfiStringArgDart>('ffi_load_project');
    _freeString = _lib!
        .lookupFunction<_FfiFreeStringC, _FfiFreeStringDart>('ffi_free_string');

    _initialized = true;
  }

  /// Whether the native library is loaded and ready.
  bool get isInitialized => _initialized;

  /// Health check — verifies Rust library is responsive.
  String healthCheck() {
    _ensureInitialized();
    final resultPtr = _healthCheck();
    final result = resultPtr.toDartString();
    _freeString(resultPtr);
    return result;
  }

  /// Parse a MIDI file and return structured data.
  MidiFileData parseMidi(String path) {
    _ensureInitialized();
    final pathPtr = path.toNativeUtf8();
    Pointer<Utf8>? resultPtr;
    try {
      resultPtr = _parseMidi(pathPtr);
      final jsonStr = resultPtr.toDartString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (json.containsKey('error')) {
        throw Exception('MIDI parse error: ${json['error']}');
      }
      return MidiFileData.fromJson(json);
    } finally {
      calloc.free(pathPtr);
      if (resultPtr != null) _freeString(resultPtr);
    }
  }

  /// Extract video metadata using ffprobe (via Rust).
  VideoMetadata extractVideoMetadata(String path) {
    _ensureInitialized();
    final pathPtr = path.toNativeUtf8();
    Pointer<Utf8>? resultPtr;
    try {
      resultPtr = _extractVideoMetadata(pathPtr);
      final jsonStr = resultPtr.toDartString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (json.containsKey('error')) {
        throw Exception('Video metadata error: ${json['error']}');
      }
      return VideoMetadata.fromJson(json);
    } finally {
      calloc.free(pathPtr);
      if (resultPtr != null) _freeString(resultPtr);
    }
  }

  /// Compute keyboard calibration from corner points and key count.
  CalibrationData computeCalibration({
    required Point2D topLeft,
    required Point2D topRight,
    required Point2D bottomRight,
    required Point2D bottomLeft,
    required int numKeys,
  }) {
    _ensureInitialized();
    final input = jsonEncode({
      'corners': {
        'top_left': {'x': topLeft.x, 'y': topLeft.y},
        'top_right': {'x': topRight.x, 'y': topRight.y},
        'bottom_right': {'x': bottomRight.x, 'y': bottomRight.y},
        'bottom_left': {'x': bottomLeft.x, 'y': bottomLeft.y},
      },
      'num_keys': numKeys,
    });

    final inputPtr = input.toNativeUtf8();
    Pointer<Utf8>? resultPtr;
    try {
      resultPtr = _computeCalibration(inputPtr);
      final jsonStr = resultPtr.toDartString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (json.containsKey('error')) {
        throw Exception('Calibration error: ${json['error']}');
      }
      return CalibrationData.fromJson(json);
    } finally {
      calloc.free(inputPtr);
      if (resultPtr != null) _freeString(resultPtr);
    }
  }

  /// Compute overlay frame for a given timestamp.
  /// Returns the pre-computed geometry for the Flutter painter.
  OverlayFrameData computeOverlayFrame({
    required double timestampMs,
    required List<Map<String, dynamic>> notes,
    required Map<String, dynamic> calibration,
    Map<String, dynamic>? style,
    Map<String, dynamic>? sync,
  }) {
    _ensureInitialized();
    final input = jsonEncode({
      'timestamp_ms': timestampMs,
      'notes': notes,
      'calibration': calibration,
      'style': style,
      'sync': sync,
    });

    final inputPtr = input.toNativeUtf8();
    Pointer<Utf8>? resultPtr;
    try {
      resultPtr = _computeOverlayFrame(inputPtr);
      final jsonStr = resultPtr.toDartString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (json.containsKey('error')) {
        throw Exception('Overlay frame error: ${json['error']}');
      }
      return OverlayFrameData.fromJson(json);
    } finally {
      calloc.free(inputPtr);
      if (resultPtr != null) _freeString(resultPtr);
    }
  }

  /// Check if FFmpeg is available on this system.
  Map<String, dynamic> checkFfmpeg() {
    _ensureInitialized();
    final resultPtr = _checkFfmpeg();
    final jsonStr = resultPtr.toDartString();
    _freeString(resultPtr);
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }

  /// Start video export (blocking — call from an isolate for non-blocking UI).
  /// Returns export progress/result.
  Map<String, dynamic> startExport(Map<String, dynamic> config) {
    _ensureInitialized();
    final inputStr = jsonEncode(config);
    final inputPtr = inputStr.toNativeUtf8();
    Pointer<Utf8>? resultPtr;
    try {
      resultPtr = _startExport(inputPtr);
      final jsonStr = resultPtr.toDartString();
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } finally {
      calloc.free(inputPtr);
      if (resultPtr != null) _freeString(resultPtr);
    }
  }

  /// Save project JSON to a .pvproj file via Rust.
  void saveProjectFile(String path, Map<String, dynamic> projectJson) {
    _ensureInitialized();
    final input = jsonEncode({'path': path, 'project': projectJson});
    final inputPtr = input.toNativeUtf8();
    Pointer<Utf8>? resultPtr;
    try {
      resultPtr = _saveProject(inputPtr);
      final jsonStr = resultPtr.toDartString();
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (result.containsKey('error')) {
        throw Exception('Save failed: ${result['error']}');
      }
    } finally {
      calloc.free(inputPtr);
      if (resultPtr != null) _freeString(resultPtr);
    }
  }

  /// Load project JSON from a .pvproj file via Rust.
  Map<String, dynamic> loadProjectFile(String path) {
    _ensureInitialized();
    final pathPtr = path.toNativeUtf8();
    Pointer<Utf8>? resultPtr;
    try {
      resultPtr = _loadProject(pathPtr);
      final jsonStr = resultPtr.toDartString();
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (result.containsKey('error')) {
        throw Exception('Load failed: ${result['error']}');
      }
      return result;
    } finally {
      calloc.free(pathPtr);
      if (resultPtr != null) _freeString(resultPtr);
    }
  }

  /// Fallback: extract video metadata using ffprobe subprocess (no Rust needed).
  Future<VideoMetadata> getVideoMetadataFallback(String path) async {
    final probe = await _runFfprobe(path);
    final streams = probe['streams'] as List;
    final videoStream = streams.firstWhere(
      (s) => s['codec_type'] == 'video',
      orElse: () => throw Exception('No video stream found'),
    );
    return _metadataFromProbe(path, probe, videoStream);
  }

  /// Probe any media file. When the file has no video stream (e.g. a bounced
  /// audio track from Ableton) a synthetic canvas of [fallbackWidth] x
  /// [fallbackHeight] at [fallbackFps] is returned, carrying the real duration
  /// so the timeline and export stay in sync.
  Future<VideoMetadata> getMediaMetadataFallback(
    String path, {
    int fallbackWidth = 1920,
    int fallbackHeight = 1080,
    double fallbackFps = 30.0,
  }) async {
    final probe = await _runFfprobe(path);
    final streams = probe['streams'] as List;
    final videoStream = streams.cast<Map<String, dynamic>?>().firstWhere(
          (s) => s?['codec_type'] == 'video',
          orElse: () => null,
        );
    if (videoStream != null) {
      return _metadataFromProbe(path, probe, videoStream);
    }

    final audioStream = streams.cast<Map<String, dynamic>?>().firstWhere(
          (s) => s?['codec_type'] == 'audio',
          orElse: () => null,
        );
    final durationStr = probe['format']?['duration'] ?? audioStream?['duration'] ?? '0';
    return VideoMetadata(
      width: fallbackWidth,
      height: fallbackHeight,
      fps: fallbackFps,
      durationMs: (double.tryParse(durationStr.toString()) ?? 0) * 1000,
      codec: audioStream?['codec_name'] as String? ?? 'none',
      hasAudio: audioStream != null,
      audioSampleRate: audioStream != null
          ? int.tryParse(audioStream['sample_rate']?.toString() ?? '')
          : null,
      fileSizeBytes: int.tryParse(probe['format']?['size']?.toString() ?? '0') ?? 0,
      filePath: path,
    );
  }

  Future<Map<String, dynamic>> _runFfprobe(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('Media file not found: $path');
    }

    final result = await Process.run('ffprobe', [
      '-v', 'quiet',
      '-print_format', 'json',
      '-show_format',
      '-show_streams',
      path,
    ]);

    if (result.exitCode != 0) {
      throw Exception('ffprobe failed: ${result.stderr}');
    }
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  }

  VideoMetadata _metadataFromProbe(
      String path, Map<String, dynamic> probe, Map<String, dynamic> videoStream) {
    final audioStream = (probe['streams'] as List).cast<Map<String, dynamic>?>().firstWhere(
          (s) => s?['codec_type'] == 'audio',
          orElse: () => null,
        );

    final durationStr = probe['format']?['duration'] ?? videoStream['duration'] ?? '0';

    return VideoMetadata(
      width: videoStream['width'] as int,
      height: videoStream['height'] as int,
      fps: _parseFrameRate(videoStream['r_frame_rate'] as String),
      durationMs: (double.tryParse(durationStr.toString()) ?? 0) * 1000,
      codec: videoStream['codec_name'] as String,
      hasAudio: audioStream != null,
      audioSampleRate: audioStream != null
          ? int.tryParse(audioStream['sample_rate']?.toString() ?? '')
          : null,
      fileSizeBytes: int.tryParse(probe['format']?['size']?.toString() ?? '0') ?? 0,
      filePath: path,
    );
  }

  // --- Private helpers ---

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'NativeBridge not initialized. Call initialize() first. '
        'Build the Rust library with: cd native && cargo build --release',
      );
    }
  }

  DynamicLibrary _loadLibrary(String? customPath) {
    if (customPath != null) {
      return DynamicLibrary.open(customPath);
    }

    if (Platform.isLinux) {
      // Look in standard locations
      final candidates = [
        'libpiano_overlay_native.so',
        'native/target/release/libpiano_overlay_native.so',
        'native/target/debug/libpiano_overlay_native.so',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) {
          return DynamicLibrary.open(path);
        }
      }
      return DynamicLibrary.open('libpiano_overlay_native.so');
    } else if (Platform.isMacOS) {
      final candidates = [
        'libpiano_overlay_native.dylib',
        'native/target/release/libpiano_overlay_native.dylib',
        'native/target/debug/libpiano_overlay_native.dylib',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) {
          return DynamicLibrary.open(path);
        }
      }
      return DynamicLibrary.open('libpiano_overlay_native.dylib');
    } else if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        '$exeDir\\piano_overlay_native.dll',
        'piano_overlay_native.dll',
        'native\\target\\release\\piano_overlay_native.dll',
        'native\\target\\debug\\piano_overlay_native.dll',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) {
          return DynamicLibrary.open(path);
        }
      }
      return DynamicLibrary.open('piano_overlay_native.dll');
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('libpiano_overlay_native.so');
    } else if (Platform.isIOS) {
      return DynamicLibrary.process(); // Static linked on iOS
    }

    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  double _parseFrameRate(String rateStr) {
    final parts = rateStr.split('/');
    if (parts.length == 2) {
      final num = double.tryParse(parts[0]) ?? 30;
      final den = double.tryParse(parts[1]) ?? 1;
      return den > 0 ? num / den : 30;
    }
    return double.tryParse(rateStr) ?? 30;
  }
}
