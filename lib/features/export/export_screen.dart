import 'dart:isolate';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/project_provider.dart';
import '../../services/native_bridge.dart';

enum ExportState { idle, preparing, encoding, finalizing, complete, failed, cancelled }

class ExportScreen extends StatefulWidget {
  final ProjectProvider provider;
  const ExportScreen({super.key, required this.provider});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  ExportState _state = ExportState.idle;
  double _progress = 0.0;
  String? _errorMessage;
  String _outputPath = '';
  String _quality = 'high';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export Video')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_state == ExportState.idle) ...[
              _buildSettings(),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: widget.provider.isReadyForExport ? _startExport : null,
                icon: const Icon(Icons.movie_creation),
                label: const Text('Export Video with Overlay'),
              ),
              if (!widget.provider.isReadyForExport) ...[
                const SizedBox(height: 12),
                const Text(
                  'Complete video import, MIDI import, and calibration before exporting.',
                  style: TextStyle(color: Colors.orange, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
            if (_state == ExportState.encoding || _state == ExportState.preparing || _state == ExportState.finalizing)
              _buildProgress(),
            if (_state == ExportState.complete) _buildSuccess(),
            if (_state == ExportState.failed) _buildError(),
          ],
        ),
      ),
    );
  }

  Widget _buildSettings() {
    final project = widget.provider.project;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Export Settings', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                const SizedBox(width: 120, child: Text('Quality')),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'low', label: Text('Low')),
                    ButtonSegment(value: 'medium', label: Text('Med')),
                    ButtonSegment(value: 'high', label: Text('High')),
                  ],
                  selected: {_quality},
                  onSelectionChanged: (v) => setState(() => _quality = v.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (project?.video != null) ...[
              Text('Resolution: ${project!.video!.resolution}', style: const TextStyle(fontSize: 13)),
              Text('FPS: ${project.video!.fps.toStringAsFixed(1)}', style: const TextStyle(fontSize: 13)),
              Text('Duration: ${project.video!.durationFormatted}', style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Output: MP4 (H.264 + AAC). Requires FFmpeg.',
                    style: TextStyle(fontSize: 12),
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress() {
    final statusText = switch (_state) {
      ExportState.preparing => 'Preparing...',
      ExportState.encoding => 'Encoding... ${_progress.toStringAsFixed(1)}%',
      ExportState.finalizing => 'Finalizing...',
      _ => '',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.movie_creation, size: 48, color: Colors.blue),
            const SizedBox(height: 16),
            Text(statusText, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress / 100),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: () => setState(() => _state = ExportState.cancelled),
              child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.check_circle, size: 64, color: Colors.green),
            const SizedBox(height: 16),
            Text('Export Complete!', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Saved to: $_outputPath', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => setState(() => _state = ExportState.idle),
              child: const Text('Export Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Export Failed', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(_errorMessage ?? 'Unknown error', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => setState(() => _state = ExportState.idle),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startExport() async {
    final project = widget.provider.project;
    if (project == null) return;

    // Ask user for output path
    final baseName = project.videoPath!.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
    final outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Exported Video',
      fileName: '${baseName}_overlay.mp4',
      type: FileType.custom,
      allowedExtensions: ['mp4'],
    );
    if (outputFile == null) return;
    _outputPath = outputFile.endsWith('.mp4') ? outputFile : '$outputFile.mp4';

    setState(() { _state = ExportState.preparing; _progress = 0; _errorMessage = null; });

    try {
      // Build export config as JSON for the Rust pipeline
      final config = {
        'input_video_path': project.videoPath,
        'output_path': _outputPath,
        'width': project.video!.width,
        'height': project.video!.height,
        'fps': project.video!.fps,
        'duration_ms': project.video!.durationMs,
        'quality': _quality,
        'notes': project.midi!.allNotesSorted.map((n) => n.toJson()).toList(),
        'calibration': _buildCalibrationJson(project),
        'style': _buildStyleJson(project),
        'sync': project.sync.toJson(),
      };

      setState(() => _state = ExportState.encoding);

      // Run export in an isolate to avoid blocking the UI
      final receivePort = ReceivePort();
      await Isolate.spawn(
        _exportIsolateEntry,
        _ExportIsolateMessage(
          config: config,
          sendPort: receivePort.sendPort,
          libraryPath: _findLibraryPath(),
        ),
      );

      await for (final message in receivePort) {
        if (message is Map<String, dynamic>) {
          final status = message['status'] as String?;
          if (status == 'progress') {
            setState(() => _progress = (message['percent'] as num).toDouble());
          } else if (status == 'Complete') {
            setState(() { _state = ExportState.complete; _progress = 100; });
            receivePort.close();
            break;
          } else if (status == 'Failed') {
            setState(() {
              _state = ExportState.failed;
              _errorMessage = message['error'] ?? 'Unknown error';
            });
            receivePort.close();
            break;
          }
        }
      }
    } catch (e) {
      setState(() { _state = ExportState.failed; _errorMessage = e.toString(); });
    }
  }

  Map<String, dynamic> _buildCalibrationJson(project) {
    final cal = project.calibration!;
    return {
      'corners': cal.corners.toJson(),
      'keyboard_size': cal.keyboardSize.name,
      'homography': cal.homography,
      'key_positions': cal.keyPositions.map((k) => {
        'note': k.note,
        'is_black': k.isBlack,
        'screen_quad': k.screenQuad.map((p) => p.toJson()).toList(),
        'canonical_x_center': k.canonicalXCenter,
      }).toList(),
    };
  }

  Map<String, dynamic> _buildStyleJson(project) {
    final s = project.style;
    return {
      'white_key_color': [s.whiteKeyColor.red / 255, s.whiteKeyColor.green / 255,
                          s.whiteKeyColor.blue / 255, s.whiteKeyColor.opacity],
      'black_key_color': [s.blackKeyColor.red / 255, s.blackKeyColor.green / 255,
                          s.blackKeyColor.blue / 255, s.blackKeyColor.opacity],
      'strip_thickness': s.stripThickness,
      'glow_strength': s.glowStrength,
      'glow_radius': s.glowRadius,
      'transparency': s.transparency,
      'lookahead_ms': s.lookaheadMs,
      'show_before_play': s.showBeforePlay,
      'show_during_play': s.showDuringPlay,
      'fall_speed': s.fallSpeed,
      'fall_direction': 'TopToBottom',
      'key_highlight_enabled': s.keyHighlightEnabled,
      'key_highlight_color': [1.0, 1.0, 1.0, 0.25],
      'background_dim': s.backgroundDim,
    };
  }

  String? _findLibraryPath() {
    final candidates = [
      'native/target/release/libpiano_overlay_native.so',
      'libpiano_overlay_native.so',
      'native/target/release/libpiano_overlay_native.dylib',
    ];
    for (final p in candidates) {
      if (File(p).existsSync()) return p;
    }
    return null;
  }
}

/// Message passed to the export isolate.
class _ExportIsolateMessage {
  final Map<String, dynamic> config;
  final SendPort sendPort;
  final String? libraryPath;
  _ExportIsolateMessage({required this.config, required this.sendPort, this.libraryPath});
}

/// Entry point for the export isolate.
/// This runs the blocking Rust export in a separate thread.
void _exportIsolateEntry(_ExportIsolateMessage message) {
  try {
    final bridge = NativeBridge();
    bridge.initialize(libraryPath: message.libraryPath);

    final result = bridge.startExport(message.config);
    message.sendPort.send(result);
  } catch (e) {
    message.sendPort.send({'status': 'Failed', 'error': e.toString()});
  }
}
