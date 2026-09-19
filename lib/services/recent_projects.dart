import 'dart:convert';
import 'dart:io';

import 'app_storage.dart';

/// A project the user opened or saved before.
class RecentProject {
  final String path;
  final String name;
  final DateTime openedAt;

  const RecentProject({
    required this.path,
    required this.name,
    required this.openedAt,
  });

  /// Whether the file is still where we left it.
  bool get exists => File(path).existsSync();

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'opened_at': openedAt.toIso8601String(),
      };

  static RecentProject? fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    if (path is! String || path.isEmpty) return null;
    return RecentProject(
      path: path,
      name: json['name'] as String? ?? path.split(Platform.pathSeparator).last,
      openedAt:
          DateTime.tryParse(json['opened_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Keeps the most recently used projects so the home screen can offer them
/// without a file dialog.
class RecentProjects {
  static const String fileName = 'recent_projects.json';
  static const int maxEntries = 10;

  /// Most recent first. Entries whose file has been deleted or moved are
  /// dropped, so the list never offers a dead link.
  static Future<List<RecentProject>> load() async {
    final file = await AppStorage.file(fileName);
    if (!await file.exists()) return <RecentProject>[];

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <RecentProject>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(RecentProject.fromJson)
          .whereType<RecentProject>()
          .where((entry) => entry.exists)
          .toList();
    } on FormatException {
      return <RecentProject>[];
    }
  }

  /// Move [path] to the top of the list.
  static Future<void> record(String path, String name) async {
    final entries = await load();
    entries.removeWhere((entry) => entry.path == path);
    entries.insert(
      0,
      RecentProject(path: path, name: name, openedAt: DateTime.now()),
    );

    await _write(entries.take(maxEntries).toList());
  }

  static Future<void> remove(String path) async {
    final entries = await load()
      ..removeWhere((entry) => entry.path == path);
    await _write(entries);
  }

  static Future<void> clear() async => _write(<RecentProject>[]);

  static Future<void> _write(List<RecentProject> entries) async {
    final file = await AppStorage.file(fileName);
    await file.writeAsString(
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }
}
