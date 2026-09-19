import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_storage.dart';
import 'project_provider.dart';

/// An auto-saved project left behind by a previous run.
class RecoverySnapshot {
  final Map<String, dynamic> project;
  final String? originalPath;
  final String projectName;
  final DateTime savedAt;

  const RecoverySnapshot({
    required this.project,
    required this.originalPath,
    required this.projectName,
    required this.savedAt,
  });
}

/// Periodically writes the open project to a scratch file so unsaved work
/// survives a crash or a power cut.
///
/// The snapshot is written only while the project has unsaved work, and is
/// deleted as soon as the project is saved properly or closed cleanly, so a
/// snapshot on disk at startup means the last run ended badly.
class RecoveryService {
  static const String fileName = 'recovery.json';
  static const Duration defaultInterval = Duration(seconds: 30);

  final ProjectProvider provider;
  final Duration interval;
  Timer? _timer;

  RecoveryService(this.provider, {this.interval = defaultInterval});

  bool get isRunning => _timer != null;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => saveNow());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  /// Write a snapshot if there is unsaved work, or clear a stale one if the
  /// project has since been saved.
  Future<void> saveNow() async {
    try {
      if (provider.project == null) return;
      if (!provider.hasUnsavedWork) {
        await discard();
        return;
      }

      final file = await AppStorage.file(fileName);
      await file.writeAsString(jsonEncode({
        'saved_at': DateTime.now().toIso8601String(),
        'original_path': provider.savedPath,
        'project': provider.toJson(),
      }));
    } catch (e) {
      // Auto-save is best effort; a failure here must never interrupt the
      // user's session.
      debugPrint('Auto-save failed: $e');
    }
  }

  /// The snapshot left by a previous run, or null when the last run exited
  /// cleanly or the snapshot is unreadable.
  static Future<RecoverySnapshot?> findSnapshot() async {
    try {
      final file = await AppStorage.file(fileName);
      if (!await file.exists()) return null;

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final project = decoded['project'];
      if (project is! Map<String, dynamic>) return null;

      return RecoverySnapshot(
        project: project,
        originalPath: decoded['original_path'] as String?,
        projectName: project['name'] as String? ?? 'Recovered Project',
        savedAt: DateTime.tryParse(decoded['saved_at'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (e) {
      debugPrint('Could not read recovery snapshot: $e');
      return null;
    }
  }

  /// Throw away the snapshot, e.g. after a real save or once the user has
  /// declined to recover it.
  static Future<void> discard() async {
    try {
      final file = await AppStorage.file(fileName);
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (e) {
      debugPrint('Could not delete recovery snapshot: $e');
    }
  }
}
