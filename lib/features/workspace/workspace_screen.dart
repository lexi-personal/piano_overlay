import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../services/project_provider.dart';
import '../../models/overlay_style.dart';
import '../../models/calibration.dart';
import '../../models/midi_note.dart';
import '../../models/video_metadata.dart';
import '../../shared/overlay_geometry.dart';
import '../preview/overlay_painter.dart';
import 'ableton_import_dialog.dart';

/// Unified workspace screen with collapsible panels, video center, and toolbar.
class WorkspaceScreen extends StatefulWidget {
  final ProjectProvider provider;
  const WorkspaceScreen({super.key, required this.provider});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  late Player _player;
  late VideoController _videoController;
  bool _leftPanelOpen = true;
  bool _rightPanelOpen = true;
  String _leftTab = 'files';
  String _rightTab = 'style';
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _player.stream.playing.listen((p) => setState(() => _isPlaying = p));
    _player.stream.position.listen((p) => setState(() => _position = p));
    _player.stream.duration.listen((d) => setState(() => _duration = d));

    if (widget.provider.hasVideo) {
      _loadVideo(widget.provider.project!.videoPath!);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _loadVideo(String path) {
    _player.open(Media(path), play: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: Row(
              children: [
                if (_leftPanelOpen) _buildLeftPanel(),
                Expanded(child: _buildCenterArea()),
                if (_rightPanelOpen) _buildRightPanel(),
              ],
            ),
          ),
          _buildTimeline(),
        ],
      ),
    );
  }

  // ── Toolbar ──

  Widget _buildToolbar() {
    return Container(
      height: 48,
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to Home',
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Text(widget.provider.project?.name ?? 'Untitled',
              style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          IconButton(
            icon: Icon(_leftPanelOpen ? Icons.chevron_left : Icons.chevron_right),
            tooltip: 'Toggle Left Panel',
            onPressed: () => setState(() => _leftPanelOpen = !_leftPanelOpen),
          ),
          IconButton(
            icon: Icon(_rightPanelOpen ? Icons.chevron_right : Icons.chevron_left),
            tooltip: 'Toggle Right Panel',
            onPressed: () => setState(() => _rightPanelOpen = !_rightPanelOpen),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _importFiles,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Import'),
          ),
        ],
      ),
    );
  }

  // ── Left Panel ──

  Widget _buildLeftPanel() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: Colors.grey.shade800)),
      ),
      child: Column(
        children: [
          _buildPanelTabs(['files', 'calibrate', 'sync'], _leftTab,
              (t) => setState(() => _leftTab = t)),
          Expanded(child: _buildLeftContent()),
        ],
      ),
    );
  }

  Widget _buildLeftContent() {
    switch (_leftTab) {
      case 'calibrate':
        return _buildCalibrationPanel();
      case 'sync':
        return _buildSyncPanel();
      default:
        return _buildFilesPanel();
    }
  }

  Widget _buildFilesPanel() {
    final p = widget.provider.project;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionHeader('Video'),
        if (p?.videoPath != null)
          _fileCard(p!.videoPath!, Icons.videocam)
        else
          _emptyPrompt('No video imported', Icons.videocam_off, _importVideo),
        const SizedBox(height: 16),
        _sectionHeader('MIDI'),
        if (p?.midiPath != null)
          _fileCard(p!.midiPath!, Icons.music_note)
        else
          _emptyPrompt('No MIDI imported', Icons.music_off, _importMidi),
      ],
    );
  }

  Widget _buildCalibrationPanel() {
    final cal = widget.provider.project?.calibration;
    if (cal == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.straighten, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Calibration not set'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.pushNamed(context, '/calibrate'),
              child: const Text('Calibrate Keyboard'),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionHeader('Keyboard'),
        Text('Size: ${cal.keyboardSize.label}'),
        Text('Range: ${KeyRange.noteName(cal.keyRange.lowestNote)} – ${KeyRange.noteName(cal.keyRange.highestNote)}'),
        Text('White keys: ${cal.keyRange.whiteKeys}'),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => Navigator.pushNamed(context, '/calibrate'),
          child: const Text('Recalibrate'),
        ),
      ],
    );
  }

  Widget _buildSyncPanel() {
    final sync = widget.provider.project?.sync ?? const SyncSettings();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionHeader('Sync Offset'),
        Text('${sync.offsetMs.toStringAsFixed(0)} ms',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        // Coarse slider: ±60 seconds
        Slider(
          value: sync.offsetMs.clamp(-60000, 60000),
          min: -60000,
          max: 60000,
          divisions: 2400,
          label: '${sync.offsetMs.toStringAsFixed(0)} ms',
          onChanged: (v) {
            widget.provider.updateSync(sync.copyWith(offsetMs: v));
          },
        ),
        const SizedBox(height: 8),
        // Fine nudge buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.fast_rewind),
              tooltip: '-100ms',
              onPressed: () => widget.provider.updateSync(
                  sync.copyWith(offsetMs: sync.offsetMs - 100)),
            ),
            IconButton(
              icon: const Icon(Icons.remove),
              tooltip: '-10ms',
              onPressed: () => widget.provider.updateSync(
                  sync.copyWith(offsetMs: sync.offsetMs - 10)),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '+10ms',
              onPressed: () => widget.provider.updateSync(
                  sync.copyWith(offsetMs: sync.offsetMs + 10)),
            ),
            IconButton(
              icon: const Icon(Icons.fast_forward),
              tooltip: '+100ms',
              onPressed: () => widget.provider.updateSync(
                  sync.copyWith(offsetMs: sync.offsetMs + 100)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Manual entry
        TextFormField(
          initialValue: sync.offsetMs.toStringAsFixed(0),
          decoration: const InputDecoration(
            labelText: 'Manual offset (ms)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          keyboardType: TextInputType.number,
          onFieldSubmitted: (v) {
            final ms = double.tryParse(v);
            if (ms != null) {
              widget.provider.updateSync(sync.copyWith(offsetMs: ms));
            }
          },
        ),
      ],
    );
  }

  // ── Right Panel ──

  Widget _buildRightPanel() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Colors.grey.shade800)),
      ),
      child: Column(
        children: [
          _buildPanelTabs(['style', 'export'], _rightTab,
              (t) => setState(() => _rightTab = t)),
          Expanded(child: _buildRightContent()),
        ],
      ),
    );
  }

  Widget _buildRightContent() {
    switch (_rightTab) {
      case 'export':
        return _buildExportPanel();
      default:
        return _buildStylePanel();
    }
  }

  Widget _buildStylePanel() {
    final style = widget.provider.project?.style ?? const OverlayStyle();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionHeader('Colors'),
        SwitchListTile(
          title: const Text('Per-hand colors'),
          value: style.useHandColors,
          dense: true,
          onChanged: (v) =>
              widget.provider.updateStyle(style.copyWith(useHandColors: v)),
        ),
        if (style.useHandColors) ...[
          _colorRow('Left Hand', style.leftHandColor, (c) =>
              widget.provider.updateStyle(style.copyWith(leftHandColor: c))),
          _colorRow('Right Hand', style.rightHandColor, (c) =>
              widget.provider.updateStyle(style.copyWith(rightHandColor: c))),
        ] else ...[
          _colorRow('White Keys', style.whiteKeyColor, (c) =>
              widget.provider.updateStyle(style.copyWith(whiteKeyColor: c))),
          _colorRow('Black Keys', style.blackKeyColor, (c) =>
              widget.provider.updateStyle(style.copyWith(blackKeyColor: c))),
        ],
        const SizedBox(height: 16),
        _sectionHeader('Appearance'),
        _sliderRow('Transparency', style.transparency, 0, 1, (v) =>
            widget.provider.updateStyle(style.copyWith(transparency: v))),
        _sliderRow('Lane Opacity', style.laneOpacity, 0, 1, (v) =>
            widget.provider.updateStyle(style.copyWith(laneOpacity: v))),
        _sliderRow('Glow', style.glowStrength, 0, 1, (v) =>
            widget.provider.updateStyle(style.copyWith(glowStrength: v))),
        _sliderRow('Strip Width', style.stripThickness, 0.3, 1.5, (v) =>
            widget.provider.updateStyle(style.copyWith(stripThickness: v))),
        const SizedBox(height: 16),
        _sectionHeader('Timing'),
        _sliderRow('Lookahead', style.lookaheadMs, 500, 5000, (v) =>
            widget.provider.updateStyle(style.copyWith(lookaheadMs: v)),
            suffix: ' ms'),
      ],
    );
  }

  Widget _buildExportPanel() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionHeader('Export'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => Navigator.pushNamed(context, '/export'),
          icon: const Icon(Icons.movie_creation),
          label: const Text('Export Video'),
        ),
      ],
    );
  }

  // ── Center: Video + Overlay ──

  Widget _buildCenterArea() {
    if (!widget.provider.hasVideo) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Import a video to get started'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _importVideo,
              icon: const Icon(Icons.video_file),
              label: const Text('Import Video'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Center(child: Video(controller: _videoController)),
        if (widget.provider.hasCalibration && widget.provider.hasMidi)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return CustomPaint(
                  painter: _buildOverlayPainter(constraints.biggest),
                );
              },
            ),
          ),
      ],
    );
  }

  OverlayPainter _buildOverlayPainter(Size size) {
    final project = widget.provider.project!;
    final cal = project.calibration!;
    final style = project.style;
    final sync = project.sync;
    final posMs = _position.inMilliseconds.toDouble();

    final frameData = OverlayGeometry.computeFrame(
      calibration: cal,
      notes: project.midi?.allNotes ?? [],
      style: style,
      sync: sync,
      timestampMs: posMs,
      displayWidth: size.width,
      displayHeight: size.height,
      calibrationWidth: cal.calibrationWidth > 0 ? cal.calibrationWidth : null,
      calibrationHeight: cal.calibrationHeight > 0 ? cal.calibrationHeight : null,
    );

    return OverlayPainter(
      strips: frameData.strips,
      keyHighlights: frameData.keyHighlights,
      backgroundDim: style.backgroundDim,
      fallLaneQuad: frameData.fallLaneQuad,
      laneOpacity: style.laneOpacity,
    );
  }

  // ── Timeline ──

  Widget _buildTimeline() {
    return Container(
      height: 56,
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: () => _isPlaying ? _player.pause() : _player.play(),
          ),
          const SizedBox(width: 8),
          Text(_formatDuration(_position), style: const TextStyle(fontSize: 12)),
          Expanded(
            child: Slider(
              value: _duration.inMilliseconds > 0
                  ? _position.inMilliseconds
                      .toDouble()
                      .clamp(0, _duration.inMilliseconds.toDouble())
                  : 0,
              min: 0,
              max: _duration.inMilliseconds > 0
                  ? _duration.inMilliseconds.toDouble()
                  : 1,
              onChanged: (v) {
                _player.seek(Duration(milliseconds: v.toInt()));
              },
            ),
          ),
          Text(_formatDuration(_duration), style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  // ── Import Actions ──

  Future<void> _importFiles() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Import'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'video'),
            child: const ListTile(
              leading: Icon(Icons.videocam),
              title: Text('Video File'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'midi'),
            child: const ListTile(
              leading: Icon(Icons.music_note),
              title: Text('MIDI File'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'ableton'),
            child: const ListTile(
              leading: Icon(Icons.album),
              title: Text('Ableton Live Set (.als)'),
            ),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'video':
        await _importVideo();
        break;
      case 'midi':
        await _importMidi();
        break;
      case 'ableton':
        await _importAbleton();
        break;
    }
  }

  Future<void> _importVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      dialogTitle: 'Select Video',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    // TODO: extract video metadata properly
    widget.provider.setVideo(
      path,
      widget.provider.project?.video ??
          VideoMetadata(width: 1920, height: 1080, fps: 30, durationMs: 0, codec: 'h264', hasAudio: true, fileSizeBytes: 0, filePath: path),
    );
    _loadVideo(path);
  }

  Future<void> _importMidi() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mid', 'midi'],
      dialogTitle: 'Select MIDI File',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    // TODO: parse MIDI via native bridge
    widget.provider.setMidi(path, MidiFileData.empty());
  }

  Future<void> _importAbleton() async {
    if (!mounted) return;
    final result = await showDialog(
      context: context,
      builder: (_) => const AbletonImportDialog(),
    );
    if (result == null) return;
    // result is ({tracks, audio}) record from AbletonImportDialog
    final tracks = result.tracks as List;
    if (tracks.isEmpty) return;

    // Convert Ableton tracks to MidiFileData
    final midiTracks = <MidiTrack>[];
    for (int i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      final notes = t.notes
          .map((n) => MidiNote(
                pitch: n.pitch,
                startMs: n.startMs,
                durationMs: n.durationMs,
                velocity: n.velocity,
                channel: i,
                track: i,
              ))
          .toList();
      midiTracks.add(MidiTrack(name: t.name, channel: i, notes: notes));
    }
    final midiData = MidiFileData(
      tracks: midiTracks,
      durationMs: midiTracks.expand((t) => t.notes).fold<double>(
          0, (max, n) => n.startMs + n.durationMs > max ? n.startMs + n.durationMs : max),
      noteCount: midiTracks.fold(0, (sum, t) => sum + t.notes.length),
      initialTempoBpm: 120,
      ticksPerBeat: 480,
      trackCount: midiTracks.length,
    );
    widget.provider.setMidi('ableton_import', midiData);

    // If audio file selected, use it as video
    final audio = result.audio;
    if (audio != null && audio.path != null) {
      final audioPath = audio.path as String;
      if (await File(audioPath).exists()) {
        widget.provider.setVideo(
          audioPath,
          VideoMetadata(width: 1920, height: 1080, fps: 30, durationMs: 0, codec: 'h264', hasAudio: true, fileSizeBytes: 0, filePath: audioPath),
        );
        _loadVideo(audioPath);
      }
    }
  }

  // ── Helpers ──

  Widget _buildPanelTabs(
      List<String> tabs, String active, ValueChanged<String> onTap) {
    return Container(
      height: 36,
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Row(
        children: tabs
            .map((t) => Expanded(
                  child: InkWell(
                    onTap: () => onTap(t),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: t == active
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        t[0].toUpperCase() + t.substring(1),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              t == active ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _fileCard(String path, IconData icon) {
    final name = path.split(Platform.pathSeparator).last;
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 20),
        title: Text(name, overflow: TextOverflow.ellipsis),
        dense: true,
      ),
    );
  }

  Widget _emptyPrompt(String text, IconData icon, VoidCallback onTap) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: Colors.grey),
              const SizedBox(width: 12),
              Text(text, style: const TextStyle(color: Colors.grey)),
              const Spacer(),
              const Icon(Icons.add_circle_outline, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorRow(String label, Color color, ValueChanged<Color> onChange) {
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      trailing: GestureDetector(
        onTap: () => _pickColor(color, onChange),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white24),
          ),
        ),
      ),
    );
  }

  void _pickColor(Color current, ValueChanged<Color> onChange) {
    // Simple color picker using predefined palette
    final colors = [
      const Color(0xFF4FC3F7),
      const Color(0xFFFF7043),
      const Color(0xFF66BB6A),
      const Color(0xFFAB47BC),
      const Color(0xFFFFCA28),
      const Color(0xFFEF5350),
      const Color(0xFF26C6DA),
      const Color(0xFFEC407A),
      const Color(0xFF7E57C2),
      const Color(0xFF29B6F6),
      const Color(0xFFFFA726),
      const Color(0xFF8D6E63),
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick Color'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors
              .map((c) => GestureDetector(
                    onTap: () {
                      onChange(c);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(6),
                        border: c == current
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _sliderRow(String label, double value, double min, double max,
      ValueChanged<double> onChange,
      {String suffix = ''}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(label, style: const TextStyle(fontSize: 12))),
              Text('${value.toStringAsFixed(value >= 100 ? 0 : 2)}$suffix',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          SizedBox(
            height: 24,
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChange,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
