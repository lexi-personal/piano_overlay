import 'package:flutter/material.dart';
import '../../services/file_dialogs.dart';
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
  bool _showSamples = false;

  Future<void> _pickFile() async {
    String? path;
    try {
      path = await FileDialogs.pickFile(
        dialogTitle: 'Open Ableton Live Set',
        allowedExtensions: const ['als'],
      );
    } on FileDialogUnavailable catch (e) {
      setState(() => _error = e.message);
      return;
    }
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
              title: Text('${i + 1} · ${r.midiTracks[i].name}'),
              subtitle: Text(_trackSummary(r.midiTracks[i])),
              dense: true,
            ),
        ],
        if (r.audioFiles.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Media source', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Optional. Picking an audio file here replaces the media loaded in '
            'the workspace, so the overlay plays against that audio instead of '
            'your video. Leave it on "Keep current video" to only import MIDI.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          RadioListTile<int?>(
            value: null,
            groupValue: _selectedAudioIndex,
            onChanged: (v) => setState(() => _selectedAudioIndex = v),
            title: const Text('Keep current video'),
            dense: true,
          ),
          ..._audioTiles(_recordings(r)),
          if (_recordings(r).isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                'This project has no bounces or recorded clips — only sampler '
                'instrument samples, which are not what you want here.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_samples(r).isNotEmpty) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setState(() => _showSamples = !_showSamples),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(_showSamples
                        ? Icons.expand_less
                        : Icons.expand_more),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Instrument samples (${_samples(r).length}) — single '
                        'notes from a sampler, rarely useful',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_showSamples) ..._audioTiles(_samples(r)),
          ],
        ],
      ],
    );
  }

  List<AbletonAudioFile> _recordings(AbletonParseResult r) => r.audioFiles
      .where((a) => a.kind == AbletonAudioKind.recording)
      .toList();

  List<AbletonAudioFile> _samples(AbletonParseResult r) => r.audioFiles
      .where((a) => a.kind == AbletonAudioKind.instrumentSample)
      .toList();

  /// Radio tiles keyed by each file's index in the full `audioFiles` list, so
  /// splitting the list into groups does not change what a selection means.
  List<Widget> _audioTiles(List<AbletonAudioFile> files) {
    final all = _result!.audioFiles;
    return [
      for (final file in files)
        RadioListTile<int?>(
          value: all.indexOf(file),
          groupValue: _selectedAudioIndex,
          onChanged: (v) => setState(() => _selectedAudioIndex = v),
          title: Text(file.name),
          subtitle: Text([
            'Replace video',
            if (file.relativeDir.isNotEmpty) file.relativeDir,
            _formatSize(file.sizeBytes),
          ].join(' • ')),
          dense: true,
        ),
    ];
  }

  /// Live happily lets several tracks share a name, so describe the content:
  /// note count, clip count and the span the notes cover.
  static String _trackSummary(AbletonMidiTrack track) {
    if (track.notes.isEmpty) return 'empty';

    var start = track.notes.first.startMs;
    var end = 0.0;
    for (final note in track.notes) {
      if (note.startMs < start) start = note.startMs;
      if (note.endMs > end) end = note.endMs;
    }

    return [
      '${track.noteCount} notes',
      if (track.clipCount > 0) '${track.clipCount} clips',
      '${_timestamp(start)}–${_timestamp(end)}',
    ].join(' • ');
  }

  static String _timestamp(double ms) {
    final total = (ms / 1000).round();
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
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
