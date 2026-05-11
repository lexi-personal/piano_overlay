import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart';
import 'services/project_provider.dart';
import 'services/native_bridge.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Initialize native bridge early so all screens can use it
  try {
    NativeBridge().initialize();
    if (kDebugMode) debugPrint('NativeBridge: loaded successfully');
  } catch (e) {
    if (kDebugMode) debugPrint('NativeBridge: failed to load: $e');
  }

  runApp(PianoOverlayApp(projectProvider: ProjectProvider()));
}
