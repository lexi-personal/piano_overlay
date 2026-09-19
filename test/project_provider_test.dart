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
      const meta = VideoMetadata(
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

    test('tracks dirty state across edits and saves', () async {
      final provider = ProjectProvider();
      provider.createProject('Dirty Test');
      expect(provider.isDirty, isFalse);
      expect(provider.savedPath, isNull);

      provider.updateSync(const SyncSettings(offsetMs: 120));
      expect(provider.isDirty, isTrue);

      final dir = Directory.systemTemp.createTempSync('pv_dirty');
      final path = await provider.saveProject(dir.path);
      expect(provider.isDirty, isFalse);
      expect(provider.savedPath, path);

      // Saving again re-uses the known path.
      provider.updateStyle(const OverlayStyle(glowStrength: 0.4));
      expect(provider.isDirty, isTrue);
      expect(await provider.saveToExistingPath(), path);
      expect(provider.isDirty, isFalse);

      dir.deleteSync(recursive: true);
    });

    test('saveToExistingPath returns null before a first save', () async {
      final provider = ProjectProvider();
      provider.createProject('Never Saved');
      expect(await provider.saveToExistingPath(), isNull);
    });

    test('saveProjectToFile appends the .pvproj extension and reloads', () async {
      final provider = ProjectProvider();
      provider.createProject('Extension Test');
      final dir = Directory.systemTemp.createTempSync('pv_ext');

      final path = await provider.saveProjectToFile('${dir.path}/my_take');
      expect(path, '${dir.path}/my_take.pvproj');
      expect(File(path).existsSync(), isTrue);

      final reloaded = ProjectProvider();
      await reloaded.loadProject(path);
      expect(reloaded.project!.name, 'Extension Test');
      expect(reloaded.savedPath, path);
      expect(reloaded.isDirty, isFalse);

      dir.deleteSync(recursive: true);
    });

    test('renameProject updates the name and marks the project dirty', () {
      final provider = ProjectProvider();
      provider.createProject('Old Name');
      provider.renameProject('New Name');
      expect(provider.project!.name, 'New Name');
      expect(provider.isDirty, isTrue);
    });
  });
}
