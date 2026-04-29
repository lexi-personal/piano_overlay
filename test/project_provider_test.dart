import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_overlay/services/project_provider.dart';
import 'package:piano_overlay/models/video_metadata.dart';
import 'package:piano_overlay/models/overlay_style.dart';

void main() {
  group('ProjectProvider', () {
    test('creates new project with defaults', () {
      final provider = ProjectProvider();
      provider.createProject('Test Project');
      expect(provider.project, isNotNull);
      expect(provider.project!.name, 'Test Project');
      expect(provider.project!.video, isNull);
      expect(provider.project!.midi, isNull);
    });

    test('saves and loads project to disk', () async {
      final provider = ProjectProvider();
      provider.createProject('Save Test');

      // Set video metadata
      final meta = VideoMetadata(
        width: 1920,
        height: 1080,
        fps: 30.0,
        durationMs: 120000,
        codec: 'h264',
        hasAudio: true,
        fileSizeBytes: 50000000,
        filePath: '/tmp/test_video.mp4',
      );
      provider.setVideo('/tmp/test_video.mp4', meta);

      // Update style
      provider.updateStyle(const OverlayStyle(
        stripThickness: 0.9,
        glowStrength: 0.7,
      ));

      // Update sync offset
      provider.updateSync(const SyncSettings(offsetMs: 250.0));

      // Save to directory
      final path = await provider.saveProject('/tmp');

      // Load into new provider
      final provider2 = ProjectProvider();
      await provider2.loadProject(path);
      expect(provider2.project, isNotNull);
      expect(provider2.project!.name, 'Save Test');
      expect(provider2.project!.videoPath, '/tmp/test_video.mp4');
      expect(provider2.project!.video!.width, 1920);
      expect(provider2.project!.video!.fps, 30.0);
      expect(provider2.project!.style.stripThickness, 0.9);
      expect(provider2.project!.style.glowStrength, 0.7);
      expect(provider2.project!.sync.offsetMs, 250.0);

      // Cleanup
      File(path).deleteSync();
    });
  });
}
