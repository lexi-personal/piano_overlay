import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_overlay/services/native_bridge.dart';
import 'package:piano_overlay/models/calibration.dart';

void main() {
  late NativeBridge bridge;

  setUpAll(() {
    const libPath = 'native/target/release/libpiano_overlay_native.so';
    if (!File(libPath).existsSync()) {
      debugPrint('SKIP: Rust library not built');
      return;
    }
    bridge = NativeBridge();
    bridge.initialize(libraryPath: libPath);
  });

  test('Compute calibration for 88 keys', () {
    if (!bridge.isInitialized) return;

    final result = bridge.computeCalibration(
      topLeft: const Point2D(100, 200),
      topRight: const Point2D(900, 200),
      bottomRight: const Point2D(900, 400),
      bottomLeft: const Point2D(100, 400),
      numKeys: 88,
    );

    expect(result.keyPositions.length, 88);
    expect(result.keyPositions.first.note, 21); // A0
    expect(result.keyPositions.last.note, 108); // C8

    // Check some are black keys
    final blackKeys = result.keyPositions.where((k) => k.isBlack).length;
    expect(blackKeys, 36); // 88 - 52 = 36 black keys
  });

  test('Compute overlay frame with notes', () {
    if (!bridge.isInitialized) return;

    // First get calibration
    final calibration = bridge.computeCalibration(
      topLeft: const Point2D(0, 0),
      topRight: const Point2D(1920, 0),
      bottomRight: const Point2D(1920, 200),
      bottomLeft: const Point2D(0, 200),
      numKeys: 88,
    );

    // Create a simple note
    final notes = [
      {
        'pitch': 60, // Middle C
        'velocity': 100,
        'start_ms': 1000.0,
        'duration_ms': 500.0,
        'channel': 0,
        'track': 0,
      }
    ];

    // Compute frame at time when note is active
    final frame = bridge.computeOverlayFrame(
      timestampMs: 1200.0, // 200ms into the note
      notes: notes,
      calibration: jsonDecode(jsonEncode({
        'corners': {
          'top_left': {'x': 0.0, 'y': 0.0},
          'top_right': {'x': 1920.0, 'y': 0.0},
          'bottom_right': {'x': 1920.0, 'y': 200.0},
          'bottom_left': {'x': 0.0, 'y': 200.0},
        },
        'keyboard_size': 'Keys88',
        'homography': calibration.homography,
        'key_positions': calibration.keyPositions.map((k) => {
          'note': k.note,
          'is_black': k.isBlack,
          'screen_quad': k.screenQuad.map((p) => {'x': p.x, 'y': p.y}).toList(),
          'canonical_x_center': k.canonicalXCenter,
        }).toList(),
      })),
    );

    // Should have at least one strip (the active note)
    expect(frame.strips.isNotEmpty, true);
    // Should have at least one key highlight (note is active)
    expect(frame.keyHighlights.isNotEmpty, true);
  });

  test('Check FFmpeg availability', () {
    if (!bridge.isInitialized) return;

    final result = bridge.checkFfmpeg();
    // FFmpeg should be available in this environment
    expect(result['available'], true);
    expect(result['version'], contains('ffmpeg'));
  });

  group('media probing', () {
    late Directory tmp;

    setUpAll(() {
      tmp = Directory.systemTemp.createTempSync('pv_probe');
    });

    tearDownAll(() => tmp.deleteSync(recursive: true));

    test('probes a real video file', () async {
      final path = '${tmp.path}/clip.mp4';
      final gen = await Process.run('ffmpeg', [
        '-f', 'lavfi', '-i', 'testsrc=size=320x240:rate=25:duration=2',
        '-pix_fmt', 'yuv420p', '-y', path,
      ]);
      if (gen.exitCode != 0) {
        debugPrint('SKIP: ffmpeg could not generate a test clip');
        return;
      }

      final meta = await NativeBridge().getVideoMetadataFallback(path);
      expect(meta.width, 320);
      expect(meta.height, 240);
      expect(meta.fps, closeTo(25, 0.01));
      expect(meta.durationMs, closeTo(2000, 100));
      expect(meta.hasAudio, isFalse);
    });

    test('falls back to a synthetic canvas for audio-only files', () async {
      final path = '${tmp.path}/tone.wav';
      final gen = await Process.run('ffmpeg', [
        '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3',
        '-y', path,
      ]);
      if (gen.exitCode != 0) {
        debugPrint('SKIP: ffmpeg could not generate a test tone');
        return;
      }

      // The video-only probe rejects it...
      await expectLater(
        NativeBridge().getVideoMetadataFallback(path),
        throwsA(isA<Exception>()),
      );

      // ...while the media probe keeps the real duration.
      final meta = await NativeBridge().getMediaMetadataFallback(path);
      expect(meta.width, 1920);
      expect(meta.height, 1080);
      expect(meta.fps, 30);
      expect(meta.hasAudio, isTrue);
      expect(meta.durationMs, closeTo(3000, 100));
    });

    test('throws for a missing file', () async {
      await expectLater(
        NativeBridge().getMediaMetadataFallback('${tmp.path}/nope.mp4'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
