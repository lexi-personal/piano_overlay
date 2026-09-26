import 'package:flutter/material.dart';
import 'features/home/home_screen.dart';
import 'features/export/export_screen.dart';
import 'features/workspace/workspace_screen.dart';
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
            '/export': (context) => ExportScreen(provider: projectProvider),
            '/workspace': (context) => WorkspaceScreen(provider: projectProvider),
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
