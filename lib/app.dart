import 'package:flutter/material.dart';
import 'features/home/home_screen.dart';
import 'features/import/import_screen.dart';
import 'features/calibration/calibration_screen.dart';
import 'features/sync/sync_screen.dart';
import 'features/style/style_screen.dart';
import 'features/preview/preview_screen.dart';
import 'features/export/export_screen.dart';
import 'services/project_provider.dart';

class PianoOverlayApp extends StatelessWidget {
  final ProjectProvider projectProvider;

  const PianoOverlayApp({super.key, required this.projectProvider});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: projectProvider,
      builder: (context, _) {
        return MaterialApp(
          title: 'Piano Overlay',
          debugShowCheckedModeBanner: false,
          theme: _buildDarkTheme(),
          initialRoute: '/',
          routes: {
            '/': (context) => HomeScreen(provider: projectProvider),
            '/import': (context) => ImportScreen(provider: projectProvider),
            '/calibrate': (context) => CalibrationScreen(provider: projectProvider),
            '/sync': (context) => SyncScreen(provider: projectProvider),
            '/style': (context) => StyleScreen(provider: projectProvider),
            '/preview': (context) => PreviewScreen(provider: projectProvider),
            '/export': (context) => ExportScreen(provider: projectProvider),
          },
        );
      },
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4FC3F7),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      cardTheme: const CardTheme(
        elevation: 2,
        margin: EdgeInsets.all(8),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
      ),
    );
  }
}
