import 'dart:io';

/// Where the app keeps state that is not part of a project file: the crash
/// recovery snapshot and the recent projects list.
class AppStorage {
  AppStorage._();

  static Directory? _override;

  /// Point storage somewhere else. Used by tests to stay out of the real
  /// user profile.
  static void overrideDirectory(Directory directory) => _override = directory;

  static void clearOverride() => _override = null;

  /// The per-user application data directory, created if missing.
  static Future<Directory> directory() async {
    final dir = _override ?? Directory(_platformPath());
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> file(String name) async =>
      File('${(await directory()).path}${Platform.pathSeparator}$name');

  static String _platformPath() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      final appData = env['APPDATA'] ?? env['USERPROFILE'] ?? '.';
      return '$appData\\PianoOverlay';
    }
    final home = env['HOME'] ?? '.';
    if (Platform.isMacOS) {
      return '$home/Library/Application Support/PianoOverlay';
    }
    final dataHome = env['XDG_DATA_HOME'];
    final base = (dataHome != null && dataHome.isNotEmpty)
        ? dataHome
        : '$home/.local/share';
    return '$base/piano_overlay';
  }
}
