import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../services/file_dialogs.dart';
import '../../services/project_provider.dart';
import '../../services/recent_projects.dart';
import '../../services/recovery_service.dart';
import '../../services/video_rendering.dart';
import '../../services/native_bridge.dart';
import '../../services/ableton/ableton_parser.dart';
import '../../models/overlay_style.dart';
import '../../models/calibration.dart';
import '../../models/midi_note.dart';
import '../../models/video_metadata.dart';
import '../../shared/overlay_geometry.dart';
import '../calibration/calibration_editor.dart';
import '../preview/overlay_painter.dart';
import 'ableton_import_dialog.dart';
import 'timeline_panel.dart';

/// Unified workspace screen with collapsible panels, video center, and toolbar.
class WorkspaceScreen extends StatefulWidget {
  final ProjectProvider provider;
  const WorkspaceScreen({super.key, required this.provider});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final _bridge = NativeBridge();
  late Player _player;
  late VideoController _videoController;
  bool _leftPanelOpen = true;
  bool _rightPanelOpen = true;
  String _leftTab = 'files';
  String _rightTab = 'style';
  bool _isPlaying = false;
  bool _overlayVisible = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  late final RecoveryService _recovery;
  bool _timelineExpanded = false;

  /// Non-null while the user is placing keyboard corners on the video.
  CalibrationDraft? _calibrationDraft;

  @override
  void initState() {
    super.initState();
    _recovery = RecoveryService(widget.provider)..start();
    _player = Player();
    _videoController = VideoRendering.controllerFor(_player);
    _player.stream.playing.listen((p) => setState(() => _isPlaying = p));
    _player.stream.position.listen((p) => setState(() => _position = p));
    _player.stream.duration.listen((d) => setState(() => _duration = d));

    if (widget.provider.hasVideo) {
      _loadVideo(widget.provider.project!.videoPath!);
    }
  }

  @override
  void dispose() {
    _recovery.stop();
    _player.dispose();
    super.dispose();
  }

  void _loadVideo(String path) {
    _player.open(Media(path), play: false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.provider.isDirty,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) {
          await RecoveryService.discard();
          navigator.pop();
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (widget.provider.hasProject) _saveProject();
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
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
          ),
        ),
      ),
    );
  }

  // ── Project persistence ──

  Future<void> _saveProject() async {
    if (!widget.provider.hasProject) return;
    try {
      final saved = await widget.provider.saveToExistingPath();
      if (saved == null) {
        await _saveProjectAs();
        return;
      }
      await _afterSave(saved);
      _showInfo('Saved to $saved');
    } catch (e) {
      _showError('Save failed: $e');
    }
  }

  Future<void> _saveProjectAs() async {
    if (!widget.provider.hasProject) return;
    final directory = await _pick(() => FileDialogs.pickDirectory(
          dialogTitle: 'Choose a folder for the project file',
        ));
    if (directory == null) return;
    try {
      final path = await widget.provider.saveProject(directory);
      await _afterSave(path);
      _showInfo('Saved to $path');
    } catch (e) {
      _showError('Save failed: $e');
    }
  }

  /// Run a file dialog, reporting a missing system dialog instead of letting
  /// it escape as an unhandled exception.
  Future<String?> _pick(Future<String?> Function() open) async {
    try {
      return await open();
    } on FileDialogUnavailable catch (e) {
      _showError(e.message);
      return null;
    }
  }

  /// A saved project has nothing left to recover, and earns its place in the
  /// recent projects list.
  Future<void> _afterSave(String path) async {
    await RecoveryService.discard();
    await RecentProjects.record(
        path, widget.provider.project?.name ?? 'Untitled Project');
  }

  /// Returns true when it is safe to leave the workspace.
  Future<bool> _confirmDiscard() async {
    if (!widget.provider.isDirty) return true;
    if (!mounted) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('This project has unsaved changes. Save before leaving?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Discard')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Save')),
        ],
      ),
    );
    if (choice == 'save') {
      await _saveProject();
      return !widget.provider.isDirty;
    }
    return choice == 'discard';
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
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
            onPressed: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 8),
          Text(widget.provider.project?.name ?? 'Untitled',
              style: Theme.of(context).textTheme.titleMedium),
          if (widget.provider.isDirty)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Text('•', style: TextStyle(fontSize: 22, color: Colors.orangeAccent)),
            ),
          const Spacer(),
          IconButton(
            icon: Icon(_overlayVisible ? Icons.layers : Icons.layers_clear),
            tooltip: _overlayVisible ? 'Hide Overlay' : 'Show Overlay',
            onPressed: () => setState(() => _overlayVisible = !_overlayVisible),
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save (Ctrl+S)',
            onPressed: widget.provider.hasProject ? _saveProject : null,
          ),
          IconButton(
            icon: const Icon(Icons.save_as),
            tooltip: 'Save As…',
            onPressed: widget.provider.hasProject ? _saveProjectAs : null,
          ),
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
    final draft = _calibrationDraft;
    if (draft != null) {
      return CalibrationEditorPanel(
        draft: draft,
        onChanged: () => setState(() {}),
        onReset: () => setState(() => draft.corners.clear()),
        onCancel: () => setState(() => _calibrationDraft = null),
        onApply: _applyCalibration,
      );
    }

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
              onPressed: _startCalibration,
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
        if (cal.calibrationWidth <= 0 || cal.calibrationHeight <= 0) ...[
          const SizedBox(height: 12),
          const Text(
            'This calibration was saved by an older version and is not tied '
            'to the video resolution. Recalibrate so the overlay lines up.',
            style: TextStyle(fontSize: 12, color: Colors.orange),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _startCalibration,
          child: const Text('Recalibrate'),
        ),
      ],
    );
  }

  /// Enter calibration mode on the video already loaded in the workspace.
  ///
  /// Calibration deliberately reuses this screen's player: opening a second
  /// `media_kit` player for the same video deadlocks the app.
  void _startCalibration() {
    if (!widget.provider.hasVideo) {
      _showError('Import a video before calibrating.');
      return;
    }
    _player.pause();
    setState(() {
      _leftTab = 'calibrate';
      _leftPanelOpen = true;
      _calibrationDraft =
          CalibrationDraft.from(widget.provider.project?.calibration);
    });
  }

  void _applyCalibration() {
    final draft = _calibrationDraft;
    if (draft == null || !draft.isComplete) return;

    final size = _videoFrameSize();
    if (size == null) {
      _showError('Could not determine the video resolution.');
      return;
    }

    widget.provider.setCalibration(draft.toCalibration(
      videoWidth: size.width,
      videoHeight: size.height,
    ));
    setState(() => _calibrationDraft = null);
  }

  /// Native pixel size of the loaded video, used as the coordinate space for
  /// calibration corners. Falls back to what the player reports when the
  /// metadata probe could not determine it.
  Size? _videoFrameSize() {
    final meta = widget.provider.project?.video;
    if (meta != null && meta.width > 0 && meta.height > 0) {
      return Size(meta.width.toDouble(), meta.height.toDouble());
    }
    final w = _player.state.width ?? 0;
    final h = _player.state.height ?? 0;
    if (w > 0 && h > 0) return Size(w.toDouble(), h.toDouble());
    return null;
  }

  /// The rectangle the video occupies inside [container] once letterboxing is
  /// taken into account.
  Rect _videoDisplayRect(Size container) {
    final size = _videoFrameSize();
    if (size == null) return Offset.zero & container;
    return OverlayGeometry.fitVideoRect(
      container: container,
      videoWidth: size.width,
      videoHeight: size.height,
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
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: sync.offsetMs == 0
                ? null
                : () => widget.provider.updateSync(sync.copyWith(offsetMs: 0)),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Reset to 0'),
          ),
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
        _sliderRow('Glow Radius', style.glowRadius, 0, 30, (v) =>
            widget.provider.updateStyle(style.copyWith(glowRadius: v)),
            suffix: ' px'),
        _sliderRow('Strip Width', style.stripThickness, 0.3, 1.5, (v) =>
            widget.provider.updateStyle(style.copyWith(stripThickness: v))),
        _sliderRow('Background Dim', style.backgroundDim, 0, 1, (v) =>
            widget.provider.updateStyle(style.copyWith(backgroundDim: v))),
        const SizedBox(height: 16),
        _sectionHeader('Shape'),
        _sliderRow('Corner Radius', style.cornerRadius, 0, 0.5, (v) =>
            widget.provider.updateStyle(style.copyWith(cornerRadius: v))),
        _sliderRow('Border Width', style.borderWidth, 0, 0.3, (v) =>
            widget.provider.updateStyle(style.copyWith(borderWidth: v))),
        if (style.borderWidth > 0)
          _colorRow('Border', style.borderColor, (c) =>
              widget.provider.updateStyle(style.copyWith(borderColor: c))),
        const SizedBox(height: 16),
        _sectionHeader('Key Highlight'),
        SwitchListTile(
          title: const Text('Light up keys being played'),
          value: style.keyHighlightEnabled,
          dense: true,
          onChanged: (v) => widget.provider
              .updateStyle(style.copyWith(keyHighlightEnabled: v)),
        ),
        if (style.keyHighlightEnabled)
          _colorRow('Highlight', style.keyHighlightColor, (c) =>
              widget.provider.updateStyle(style.copyWith(keyHighlightColor: c))),
        const SizedBox(height: 16),
        _sectionHeader('Timing'),
        _sliderRow('Lookahead', style.lookaheadMs, 500, 5000, (v) =>
            widget.provider.updateStyle(style.copyWith(lookaheadMs: v)),
            suffix: ' ms'),
        _sliderRow('Fall Speed', style.fallSpeed, 50, 800, (v) =>
            widget.provider.updateStyle(style.copyWith(fallSpeed: v)),
            suffix: ' px/s'),
        ListTile(
          dense: true,
          title: const Text('Direction', style: TextStyle(fontSize: 13)),
          trailing: DropdownButton<FallDirection>(
            value: style.fallDirection,
            underline: const SizedBox.shrink(),
            onChanged: (v) => v == null
                ? null
                : widget.provider.updateStyle(style.copyWith(fallDirection: v)),
            items: const [
              DropdownMenuItem(
                value: FallDirection.topToBottom,
                child: Text('Falling down', style: TextStyle(fontSize: 13)),
              ),
              DropdownMenuItem(
                value: FallDirection.bottomToTop,
                child: Text('Rising up', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        SwitchListTile(
          title: const Text('Show notes before they play'),
          value: style.showBeforePlay,
          dense: true,
          onChanged: (v) =>
              widget.provider.updateStyle(style.copyWith(showBeforePlay: v)),
        ),
        SwitchListTile(
          title: const Text('Show notes while they play'),
          value: style.showDuringPlay,
          dense: true,
          onChanged: (v) =>
              widget.provider.updateStyle(style.copyWith(showDuringPlay: v)),
        ),
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
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final videoRect = _videoDisplayRect(constraints.biggest);
              final draft = _calibrationDraft;
              if (draft != null) {
                return _buildCalibrationLayer(draft, videoRect);
              }
              if (widget.provider.hasCalibration &&
                  widget.provider.hasMidi &&
                  _overlayVisible) {
                return CustomPaint(painter: _buildOverlayPainter(videoRect));
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

  /// Interactive corner placement drawn on top of the video.
  ///
  /// Taps are converted from widget coordinates into video frame pixels, so a
  /// calibration stays valid no matter how the window is resized later.
  Widget _buildCalibrationLayer(CalibrationDraft draft, Rect videoRect) {
    Offset toVideo(Offset local) {
      final size = _videoFrameSize();
      if (size == null || videoRect.width <= 0 || videoRect.height <= 0) {
        return local;
      }
      return Offset(
        ((local.dx - videoRect.left) / videoRect.width * size.width)
            .clamp(0.0, size.width),
        ((local.dy - videoRect.top) / videoRect.height * size.height)
            .clamp(0.0, size.height),
      );
    }

    Offset toDisplay(Offset video) {
      final size = _videoFrameSize();
      if (size == null || size.width <= 0 || size.height <= 0) return video;
      return Offset(
        videoRect.left + video.dx / size.width * videoRect.width,
        videoRect.top + video.dy / size.height * videoRect.height,
      );
    }

    final displayCorners = draft.corners.map(toDisplay).toList();

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              if (draft.corners.length >= 4) return;
              if (!videoRect.contains(details.localPosition)) return;
              setState(() => draft.corners.add(toVideo(details.localPosition)));
            },
            child: CustomPaint(
              painter: CalibrationOverlayPainter(
                corners: displayCorners,
                showGrid: draft.showGrid,
                whiteKeys: draft.keyRange.whiteKeys,
              ),
            ),
          ),
        ),
        for (var i = 0; i < displayCorners.length; i++)
          Positioned(
            left: displayCorners[i].dx - 16,
            top: displayCorners[i].dy - 16,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  draft.corners[i] =
                      toVideo(displayCorners[i] + details.delta);
                });
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: calibrationCornerColor(i),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          top: 8,
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(draft.instruction),
            ),
          ),
        ),
      ],
    );
  }

  OverlayPainter _buildOverlayPainter(Rect videoRect) {
    final project = widget.provider.project!;
    final cal = project.calibration!;
    final style = project.style;
    final sync = project.sync;
    final posMs = _position.inMilliseconds.toDouble();

    final frameData = OverlayGeometry.computeFrame(
      calibration: cal,
      notes: project.renderableNotes,
      style: style,
      sync: sync,
      timestampMs: posMs,
      displayWidth: videoRect.width,
      displayHeight: videoRect.height,
      displayOffsetX: videoRect.left,
      displayOffsetY: videoRect.top,
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
    final tracks = widget.provider.project?.midi?.tracks ?? const [];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_timelineExpanded && tracks.isNotEmpty)
          TimelinePanel(
            duration: _duration,
            position: _position,
            videoName: widget.provider.project?.videoPath?.split(Platform.pathSeparator).last,
            tracks: tracks,
            settingsFor: (index) => widget.provider.project!.trackFor(index),
            onTrackChanged: (index, settings) =>
                widget.provider.updateTrackSettings(index, settings),
            onSeek: (position) => _player.seek(position),
          ),
        _buildTransport(tracks.isNotEmpty),
      ],
    );
  }

  Widget _buildTransport(bool hasTracks) {
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
          IconButton(
            icon: Icon(_timelineExpanded
                ? Icons.keyboard_arrow_down
                : Icons.keyboard_arrow_up),
            tooltip: hasTracks
                ? (_timelineExpanded ? 'Hide tracks' : 'Show tracks')
                : 'Import a MIDI file to see its tracks',
            onPressed: hasTracks
                ? () => setState(() => _timelineExpanded = !_timelineExpanded)
                : null,
          ),
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
    final path = await _pick(() => FileDialogs.pickFile(
          dialogTitle: 'Select Video',
          type: FileType.video,
        ));
    if (path == null) return;

    VideoMetadata metadata;
    try {
      metadata = _bridge.isInitialized
          ? _bridge.extractVideoMetadata(path)
          : await _bridge.getVideoMetadataFallback(path);
    } catch (e) {
      try {
        metadata = await _bridge.getVideoMetadataFallback(path);
      } catch (e2) {
        _showError('Could not read video metadata: $e2');
        return;
      }
    }
    widget.provider.setVideo(path, metadata);
    _loadVideo(path);
  }

  Future<void> _importMidi() async {
    final path = await _pick(() => FileDialogs.pickFile(
          dialogTitle: 'Select MIDI File',
          allowedExtensions: const ['mid', 'midi'],
        ));
    if (path == null) return;

    if (!_bridge.isInitialized) {
      _showError('Native library not loaded — cannot parse MIDI.');
      return;
    }
    try {
      final data = _bridge.parseMidi(path);
      widget.provider.setMidi(path, data);
      _showInfo('Imported ${data.noteCount} notes from ${data.trackCount} track(s).');
    } catch (e) {
      _showError('MIDI import failed: $e');
    }
  }

  Future<void> _importAbleton() async {
    if (!mounted) return;
    final result = await showDialog<({List<AbletonMidiTrack> tracks, AbletonAudioFile? audio})>(
      context: context,
      builder: (_) => const AbletonImportDialog(),
    );
    if (result == null) return;
    final tracks = result.tracks;
    if (tracks.isEmpty) return;

    // Convert Ableton tracks to MidiFileData
    final midiTracks = <MidiTrack>[];
    for (int i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      // AbletonMidiTrack.notes are already MidiNote objects
      midiTracks.add(MidiTrack(name: t.name, channel: i, notes: t.notes));
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
    if (audio != null) {
      final audioPath = audio.path;
      if (await File(audioPath).exists()) {
        VideoMetadata metadata;
        try {
          metadata = await _bridge.getMediaMetadataFallback(audioPath);
        } catch (e) {
          metadata = VideoMetadata(
            width: 1920,
            height: 1080,
            fps: 30,
            durationMs: midiData.durationMs,
            codec: 'none',
            hasAudio: true,
            fileSizeBytes: 0,
            filePath: audioPath,
          );
        }
        widget.provider.setVideo(audioPath, metadata);
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
