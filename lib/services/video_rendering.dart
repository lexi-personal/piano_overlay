import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// How video frames are handed to Flutter.
///
/// media_kit renders into a GPU texture by default. That path deadlocks the
/// whole application on some Linux GL stacks — most reliably under WSLg, where
/// mpv's OpenGL output and Flutter's compositor end up waiting on each other
/// and every thread goes idle with the window permanently frozen. Falling back
/// to CPU rendering costs some performance but keeps the app usable.
class VideoRendering {
  VideoRendering._();

  static const String _envOverride = 'PIANO_OVERLAY_VIDEO_HWACCEL';

  static bool? _cached;

  /// Whether the GPU texture path should be used.
  ///
  /// Set `PIANO_OVERLAY_VIDEO_HWACCEL=1` to force it on, or `0` to force it
  /// off. Without an override it is disabled on WSL and enabled everywhere
  /// else.
  static bool get hardwareAccelerationEnabled =>
      _cached ??= _detectHardwareAcceleration();

  /// Reset the cached decision. Only useful in tests.
  static void resetCache() => _cached = null;

  static bool _detectHardwareAcceleration() {
    final override = Platform.environment[_envOverride]?.trim().toLowerCase();
    if (override == '1' || override == 'true' || override == 'yes') return true;
    if (override == '0' || override == 'false' || override == 'no') return false;
    return !isWsl;
  }

  /// True when running inside the Windows Subsystem for Linux.
  static bool get isWsl {
    if (!Platform.isLinux) return false;
    if (Platform.environment.containsKey('WSL_DISTRO_NAME') ||
        Platform.environment.containsKey('WSL_INTEROP')) {
      return true;
    }
    try {
      return File('/proc/version')
          .readAsStringSync()
          .toLowerCase()
          .contains('microsoft');
    } on FileSystemException {
      return false;
    }
  }

  /// The controller configuration to use for every player in the app.
  static VideoControllerConfiguration get controllerConfiguration =>
      VideoControllerConfiguration(
        enableHardwareAcceleration: hardwareAccelerationEnabled,
      );

  /// Create a video controller that is safe on the current platform.
  static VideoController controllerFor(Player player) =>
      VideoController(player, configuration: controllerConfiguration);
}
