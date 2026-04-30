import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/ableton/ableton_parser.dart';

/// Dialog for importing tracks from an Ableton .als file.
class AbletonImportDialog extends StatefulWidget {
  const AbletonImportDialog({super.key});

  @override
  State<AbletonImportDialog> createState() => _AbletonImportDialogState();
}

class _AbletonImportDialogState extends State<AbletonImportDialog> {
  AbletonParseResult? _result;
  bool _loading = false;
  String? _error;
  final Set<int> _selectedTracks = {};
  int? _selectedAudioIndex;

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['als'],
      dialogTitle: 'Open Ableton Live Set',
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await AbletonParser.parse(path);
      setState(() {
        _result = result;
        _loading = false;
        if (result.midiTracks.isNotEmpty) {
          _selectedTracks.add(0);
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.music_note, color: Color(0xFFFF9800)),
                  const SizedBox(width: 8),
                  Text('Import from Ableton',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              if (_result == null && !_loading && _error == null)
                _buildPickSection()
              else if (_loading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                _buildError()
              else
                Expanded(child: _buildTrackList()),
              const SizedBox(height: 16),
              if (_result != null) _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickSection() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Select an Ableton Live Set (.als) file'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.file_open),
              label: const Text('Browse...'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Failed to parse: $_error',
                style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _pickFile, child: const Text('Try Again')),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackList() {
    final r = _result!;
    return ListView(
      children: [
        if (r.midiTracks.isNotEmpty) ...[
          Text('MIDI Tracks', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (int i = 0; i < r.midiTracks.length; i++)
            CheckboxListTile(
              value: _selectedTracks.contains(i),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selectedTracks.add(i);
                } else {
                  _selectedTracks.remove(i);
                }
              }),
              title: Text(r.midiTracks[i].name),
              subtitle: Text(() {
                final track = r.midiTracks[i];
                final dur = track.notes.isEmpty ? 0.0 :
                    track.notes.fold<double>(0, (m, n) => n.endMs > m ? n.endMs : m);
                return '${track.noteCount} notes • ${(dur / 1000).toStringAsFixed(1)}s';
              }()),
              dense: true,
            ),
        ],
        if (r.audioFiles.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Audio Files', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (int i = 0; i < r.audioFiles.length; i++)
            RadioListTile<int>(
              value: i,
              groupValue: _selectedAudioIndex,
              onChanged: (v) => setState(() => _selectedAudioIndex = v),
              title: Text(r.audioFiles[i].name),
              subtitle: Text(_formatSize(r.audioFiles[i].sizeBytes)),
              dense: true,
            ),
        ],
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: _selectedTracks.isEmpty ? null : _import,
          child: const Text('Import Selected'),
        ),
      ],
    );
  }

  void _import() {
    final r = _result!;
    final tracks = _selectedTracks.map((i) => r.midiTracks[i]).toList();
    final audio =
        _selectedAudioIndex != null ? r.audioFiles[_selectedAudioIndex!] : null;
    Navigator.pop(context, (tracks: tracks, audio: audio));
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }
}
