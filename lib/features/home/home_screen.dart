import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/project_provider.dart';

class HomeScreen extends StatelessWidget {
  final ProjectProvider provider;
  const HomeScreen({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Piano Overlay'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.piano, size: 64, color: Color(0xFF4FC3F7)),
                const SizedBox(height: 24),
                Text(
                  'Piano Overlay',
                  style: Theme.of(context).textTheme.headlineLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Create stunning MIDI visualizations on your piano videos',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                FilledButton.icon(
                  onPressed: () => _createNewProject(context),
                  icon: const Icon(Icons.add),
                  label: const Text('New Project'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _openProject(context),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open Project'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _createNewProject(BuildContext context) {
    provider.createProject('Untitled Project');
    Navigator.pushNamed(context, '/workspace');
  }

  Future<void> _openProject(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pvproj'],
      dialogTitle: 'Open Piano Overlay Project',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    if (!context.mounted) return;

    try {
      await provider.loadProject(path);
      if (!context.mounted) return;
      Navigator.pushNamed(context, '/workspace');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open project: $e')),
        );
      }
    }
  }
}
