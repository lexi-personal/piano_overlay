import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/project_provider.dart';
import '../../services/native_bridge.dart';
import '../../models/midi_note.dart';

class ImportScreen extends StatefulWidget {
  final ProjectProvider provider;
  const ImportScreen({super.key, required this.provider});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _bridge = NativeBridge();
  bool _loadingVideo = false;
  bool _loadingMidi = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tryInitBridge();
  }

  void _tryInitBridge() {
    if (_bridge.isInitialized) return;
    try {
      _bridge.initialize();
    } catch (e) {
      if (kDebugMode) debugPrint('NativeBridge: failed to initialize: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.provider.project;
    final video = project?.video;
    final midi = project?.midi;

    return Scaffold(
      appBar: AppBar(title: const Text('Import Files')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStepHeader(context, '1', 'Import Video'),
            const SizedBox(height: 8),
            _buildImportCard(
              context,
              icon: Icons.video_file,
              title: project?.videoPath != null
                  ? project!.videoPath!.split('/').last
                  : 'Select video file',
              subtitle: video != null
                  ? '${video.resolution} · '
                      '${video.fps.toStringAsFixed(1)} fps · '
                      '${video.durationFormatted}'
                  : 'MP4, MOV, AVI, or MKV',
              hasFile: project?.videoPath != null,
              loading: _loadingVideo,
              onTap: _pickVideoFile,
            ),
            const SizedBox(height: 24),
            _buildStepHeader(context, '2', 'Import MIDI'),
            const SizedBox(height: 8),
            _buildImportCard(
              context,
              icon: Icons.music_note,
              title: project?.midiPath != null
                  ? project!.midiPath!.split('/').last
                  : 'Select MIDI file',
              subtitle: midi != null
                  ? '${midi.noteCount} notes · '
                      '${midi.trackCount} tracks · '
                      '${_formatDuration(midi.durationMs)}'
                  : '.mid or .midi file',
              hasFile: project?.midiPath != null,
              loading: _loadingMidi,
              onTap: _pickMidiFile,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const Spacer(),
            FilledButton(
              onPressed: _canProceed ? _proceedToCalibration : null,
              child: const Text('Continue to Calibration →'),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canProceed =>
      widget.provider.hasVideo && widget.provider.hasMidi;

  Widget _buildStepHeader(BuildContext context, String step, String title) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(step, style: const TextStyle(fontSize: 12, color: Colors.black)),
        ),
        const SizedBox(width: 12),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }

  Widget _buildImportCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool hasFile,
    required bool loading,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: loading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, color: hasFile ? Colors.green : null),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: hasFile
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.upload_file),
        onTap: loading ? null : onTap,
      ),
    );
  }

  Future<void> _pickVideoFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mov', 'avi', 'mkv', 'webm'],
      dialogTitle: 'Select Video File',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    setState(() { _loadingVideo = true; _error = null; });

    try {
      final metadata = await _bridge.getVideoMetadataFallback(path);
      widget.provider.setVideo(path, metadata);
    } catch (e) {
      setState(() => _error = 'Video import failed: $e');
    } finally {
      setState(() => _loadingVideo = false);
    }
  }

  Future<void> _pickMidiFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mid', 'midi'],
      dialogTitle: 'Select MIDI File',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    setState(() { _loadingMidi = true; _error = null; });

    try {
      if (_bridge.isInitialized) {
        final data = _bridge.parseMidi(path);
        widget.provider.setMidi(path, data);
      } else {
        final file = File(path);
        if (!await file.exists()) throw Exception('File not found');
        widget.provider.setMidi(path, MidiFileData(
          tracks: const [],
          durationMs: 0,
          noteCount: 0,
          initialTempoBpm: 120,
          ticksPerBeat: 480,
          trackCount: 0,
        ));
        setState(() => _error = 'Note: Rust library not loaded. MIDI will be parsed on export.');
      }
    } catch (e) {
      setState(() => _error = 'MIDI import failed: $e');
    } finally {
      setState(() => _loadingMidi = false);
    }
  }

  void _proceedToCalibration() {
    Navigator.pushNamed(context, '/calibrate');
  }

  String _formatDuration(double ms) {
    final seconds = ms.toInt() ~/ 1000;
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}m ${secs}s';
  }
}
