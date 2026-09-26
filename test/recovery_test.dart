import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_overlay/services/app_storage.dart';
import 'package:piano_overlay/services/project_provider.dart';
import 'package:piano_overlay/services/recent_projects.dart';
import 'package:piano_overlay/services/recovery_service.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('piano_overlay_test');
    AppStorage.overrideDirectory(temp);
  });

  tearDown(() {
    AppStorage.clearOverride();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('recent projects', () {
    File project(String name) {
      final file = File('${temp.path}/$name.pvproj')..writeAsStringSync('{}');
      return file;
    }

    test('starts empty', () async {
      expect(await RecentProjects.load(), isEmpty);
    });

    test('records the newest project first', () async {
      final first = project('first');
      final second = project('second');

      await RecentProjects.record(first.path, 'First');
      await RecentProjects.record(second.path, 'Second');

      final recent = await RecentProjects.load();
      expect(recent.map((e) => e.name), ['Second', 'First']);
    });

    test('re-opening a project moves it back to the top without duplicating',
        () async {
      final first = project('first');
      final second = project('second');

      await RecentProjects.record(first.path, 'First');
      await RecentProjects.record(second.path, 'Second');
      await RecentProjects.record(first.path, 'First');

      final recent = await RecentProjects.load();
      expect(recent.map((e) => e.name), ['First', 'Second']);
    });

    test('projects that no longer exist are hidden', () async {
      final file = project('gone');
      await RecentProjects.record(file.path, 'Gone');
      file.deleteSync();

      expect(await RecentProjects.load(), isEmpty);
    });

    test('keeps at most ten entries', () async {
      for (var i = 0; i < 15; i++) {
        await RecentProjects.record(project('p$i').path, 'Project $i');
      }

      final recent = await RecentProjects.load();
      expect(recent.length, RecentProjects.maxEntries);
      expect(recent.first.name, 'Project 14');
    });

    test('a corrupt list is treated as empty rather than crashing', () async {
      (await AppStorage.file(RecentProjects.fileName))
          .writeAsStringSync('not json');
      expect(await RecentProjects.load(), isEmpty);
    });
  });

  group('crash recovery', () {
    late ProjectProvider provider;
    late RecoveryService recovery;

    setUp(() {
      provider = ProjectProvider();
      recovery = RecoveryService(provider);
    });

    test('nothing to recover on a clean first run', () async {
      expect(await RecoveryService.findSnapshot(), isNull);
    });

    test('unsaved work is snapshotted and can be restored', () async {
      provider.createProject('Night Sonata');
      provider.updateStyle(provider.project!.style.copyWith(glowRadius: 17));

      await recovery.saveNow();

      final snapshot = await RecoveryService.findSnapshot();
      expect(snapshot, isNotNull);
      expect(snapshot!.projectName, 'Night Sonata');
      expect(snapshot.originalPath, isNull);

      final restored = ProjectProvider()..restoreFromJson(snapshot.project);
      expect(restored.project!.name, 'Night Sonata');
      expect(restored.project!.style.glowRadius, 17);
      // Restored work has still never reached a project file.
      expect(restored.isDirty, isTrue);
    });

    test('a saved project leaves nothing to recover', () async {
      provider.createProject('Saved');
      await recovery.saveNow();
      expect(await RecoveryService.findSnapshot(), isNotNull);

      await provider.saveProjectToFile('${temp.path}/saved.pvproj');
      await recovery.saveNow();

      expect(await RecoveryService.findSnapshot(), isNull);
    });

    test('the snapshot remembers where the project came from', () async {
      provider.createProject('Tracked');
      final path = await provider.saveProjectToFile('${temp.path}/t.pvproj');
      provider.renameProject('Tracked v2');

      await recovery.saveNow();

      final snapshot = await RecoveryService.findSnapshot();
      expect(snapshot!.originalPath, path);
      expect(snapshot.projectName, 'Tracked v2');
    });

    test('discarding removes the snapshot', () async {
      provider.createProject('Temporary');
      await recovery.saveNow();

      await RecoveryService.discard();

      expect(await RecoveryService.findSnapshot(), isNull);
    });

    test('a corrupt snapshot is ignored', () async {
      (await AppStorage.file(RecoveryService.fileName))
          .writeAsStringSync(jsonEncode({'saved_at': 'whenever'}));
      expect(await RecoveryService.findSnapshot(), isNull);
    });

    test('auto-save runs on its own once started', () async {
      final fast = RecoveryService(provider,
          interval: const Duration(milliseconds: 20));
      provider.createProject('Ticking');

      fast.start();
      expect(fast.isRunning, isTrue);

      // Wait for the timer to actually fire rather than sleeping a fixed
      // amount, which makes this flaky on a loaded machine.
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (await RecoveryService.findSnapshot() == null) {
        expect(DateTime.now().isBefore(deadline), isTrue,
            reason: 'auto-save never wrote a snapshot');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      await fast.stop();

      expect(await RecoveryService.findSnapshot(), isNotNull);
      expect(fast.isRunning, isFalse);
    });
  });
}
