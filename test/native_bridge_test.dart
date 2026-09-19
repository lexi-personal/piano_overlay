import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_overlay/services/native_bridge.dart';

void main() {
  test('NativeBridge loads library and health check works', () {
    // Find the built library
    const libPath = 'native/target/release/libpiano_overlay_native.so';
    if (!File(libPath).existsSync()) {
      // Skip if library not built
      debugPrint('Skipping: Rust library not found at \$libPath');
      return;
    }

    final bridge = NativeBridge();
    bridge.initialize(libraryPath: libPath);

    expect(bridge.isInitialized, true);

    final health = bridge.healthCheck();
    expect(health, contains('ok'));
    expect(health, contains('piano_overlay_native'));
  });
}
