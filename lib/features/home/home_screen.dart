import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/project_provider.dart';
import '../../services/recent_projects.dart';
import '../../services/recovery_service.dart';

class HomeScreen extends StatefulWidget {
  final ProjectProvider provider;
  const HomeScreen({super.key, required this.provider});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ProjectProvider get provider => widget.provider;

  List<RecentProject> _recent = const [];
  bool _checkedForRecovery = false;

  @override
  void initState() {
    super.initState();
    _refreshRecent();
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerRecovery());
  }

  Future<void> _refreshRecent() async {
    final recent = await RecentProjects.load();
    if (mounted) setState(() => _recent = recent);
  }

  /// A snapshot on disk means the last session ended without saving, so offer
  /// to bring that work back.
  Future<void> _offerRecovery() async {
    if (_checkedForRecovery) return;
    _checkedForRecovery = true;

    final snapshot = await RecoveryService.findSnapshot();
    if (snapshot == null || !mounted) return;

    final restore = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recover unsaved work?'),
        content: Text(
          '"${snapshot.projectName}" was auto-saved on '
          '${_formatTimestamp(snapshot.savedAt)} but never saved to a project '
          'file. Would you like to restore it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (restore != true) {
      await RecoveryService.discard();
      return;
    }

    provider.restoreFromJson(snapshot.project,
        savedPath: snapshot.originalPath);
    if (mounted) _toWorkspace(context);
  }

  static String _formatTimestamp(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

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
                if (_recent.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Recent Projects',
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                      TextButton(
                        onPressed: () async {
                          await RecentProjects.clear();
                          await _refreshRecent();
                        },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _recent.length,
                      itemBuilder: (context, index) {
                        final entry = _recent[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.piano, size: 20),
                          title: Text(entry.name,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(entry.path,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            tooltip: 'Remove from list',
                            onPressed: () async {
                              await RecentProjects.remove(entry.path);
                              await _refreshRecent();
                            },
                          ),
                          onTap: () => _openPath(context, entry.path),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _createNewProject(BuildContext context) {
    provider.createProject('Untitled Project');
    _toWorkspace(context);
  }

  /// Open the workspace and pick up any project saved while we were away.
  void _toWorkspace(BuildContext context) {
    Navigator.pushNamed(context, '/workspace').then((_) => _refreshRecent());
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
    await _openPath(context, path);
  }

  Future<void> _openPath(BuildContext context, String path) async {
    try {
      await provider.loadProject(path);
      await RecentProjects.record(
          path, provider.project?.name ?? 'Untitled Project');
      if (!context.mounted) return;
      _toWorkspace(context);
    } catch (e) {
      await RecentProjects.remove(path);
      await _refreshRecent();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open project: $e')),
        );
      }
    }
  }
}
