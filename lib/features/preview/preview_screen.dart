import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../services/project_provider.dart';
import 'overlay_painter.dart';

class PreviewScreen extends StatefulWidget {
  final ProjectProvider provider;
  const PreviewScreen({super.key, required this.provider});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  Player? _player;
  VideoController? _videoController;
  bool _showOverlay = true;
  bool _isPlaying = false;
  double _currentTimeMs = 0;
  double _durationMs = 10000;
  bool _hasVideo = false;

  @override
  void initState() {
    super.initState();
    _durationMs = widget.provider.project?.video?.durationMs ?? 10000;
    _animController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _durationMs.toInt()),
    )..addListener(() {
        if (!_hasVideo) {
          setState(() {
            _currentTimeMs = _animController.value * _durationMs;
          });
        }
      });

    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    final videoPath = widget.provider.project?.videoPath;
    if (videoPath == null) {
      // No video: use animation controller for demo
      _animController.repeat();
      return;
    }

    _player = Player();
    _videoController = VideoController(_player!);

    // Listen to position changes
    _player!.stream.position.listen((position) {
      if (mounted) {
        setState(() {
          _currentTimeMs = position.inMilliseconds.toDouble();
          _isPlaying = _player!.state.playing;
        });
      }
    });

    _player!.stream.duration.listen((duration) {
      if (mounted && duration.inMilliseconds > 0) {
        setState(() {
          _durationMs = duration.inMilliseconds.toDouble();
        });
      }
    });

    await _player!.open(Media(videoPath), play: false);
    setState(() => _hasVideo = true);
  }

  @override
  void dispose() {
    _animController.dispose();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview'),
        actions: [
          IconButton(
            icon: Icon(_showOverlay ? Icons.layers : Icons.layers_clear),
            tooltip: 'Toggle Overlay',
            onPressed: () => setState(() => _showOverlay = !_showOverlay),
          ),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/export'),
            child: const Text('Export →'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              child: Center(
                child: AspectRatio(
                  aspectRatio: _getAspectRatio(),
                  child: Stack(
                    children: [
                      // Video layer (real or placeholder)
                      if (_hasVideo && _videoController != null)
                        Video(controller: _videoController!, fill: Colors.black)
                      else
                        Container(
                          color: Colors.grey[900],
                          child: Center(
                            child: Text(
                              widget.provider.hasVideo
                                  ? 'Loading video...'
                                  : 'No video loaded (demo mode)',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ),
                        ),
                      // Overlay layer
                      if (_showOverlay)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final frame = _computeOverlayFrame(
                              constraints.maxWidth, constraints.maxHeight);
                            return CustomPaint(
                              size: Size(constraints.maxWidth, constraints.maxHeight),
                              painter: OverlayPainter(
                                strips: frame.strips,
                                keyHighlights: frame.keyHighlights,
                                backgroundDim: widget.provider.project?.style.backgroundDim ?? 0,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _buildTimeline(),
          _buildControls(),
        ],
      ),
    );
  }

  double _getAspectRatio() {
    final video = widget.provider.project?.video;
    if (video != null && video.width > 0 && video.height > 0) {
      return video.width / video.height;
    }
    return 16 / 9;
  }

  Widget _buildTimeline() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(_formatTime(_currentTimeMs), style: const TextStyle(fontSize: 12)),
          Expanded(
            child: Slider(
              value: _currentTimeMs.clamp(0, _durationMs),
              min: 0,
              max: _durationMs,
              onChanged: (v) {
                setState(() => _currentTimeMs = v);
                if (_hasVideo && _player != null) {
                  _player!.seek(Duration(milliseconds: v.toInt()));
                } else {
                  _animController.value = v / _durationMs;
                }
              },
            ),
          ),
          Text(_formatTime(_durationMs), style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.replay_10),
            onPressed: () => _seekRelative(-10000),
          ),
          const SizedBox(width: 16),
          IconButton.filled(
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            iconSize: 36,
            onPressed: _togglePlayPause,
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.forward_10),
            onPressed: () => _seekRelative(10000),
          ),
        ],
      ),
    );
  }

  void _togglePlayPause() {
    if (_hasVideo && _player != null) {
      _player!.playOrPause();
    } else {
      setState(() {
        _isPlaying = !_isPlaying;
        if (_isPlaying) {
          _animController.repeat();
        } else {
          _animController.stop();
        }
      });
    }
  }

  void _seekRelative(int deltaMs) {
    final target = (_currentTimeMs + deltaMs).clamp(0.0, _durationMs);
    if (_hasVideo && _player != null) {
      _player!.seek(Duration(milliseconds: target.toInt()));
    } else {
      _animController.value = target / _durationMs;
    }
  }

  /// Compute overlay frame using MIDI data or demo.
  OverlayFrameData _computeOverlayFrame(double width, double height) {
    final strips = <NoteStripRenderData>[];
    final highlights = <KeyHighlightRenderData>[];

    final project = widget.provider.project;
    final style = project?.style;
    final midi = project?.midi;

    if (midi != null && midi.noteCount > 0) {
      final allNotes = midi.allNotesSorted;
      final syncOffset = project?.sync.offsetMs ?? 0;
      final effectiveTime = _currentTimeMs + syncOffset;
      final lookahead = style?.lookaheadMs ?? 2000;
      final keyboardTop = height * 0.7;
      final keyWidth = width / 52;
      final pixelsPerMs = keyboardTop / lookahead;

      for (final note in allNotes) {
        final startOffset = note.startMs - effectiveTime;
        final endOffset = note.endMs - effectiveTime;

        if (endOffset < -100 || startOffset > lookahead) continue;

        double yBottom = keyboardTop - (startOffset * pixelsPerMs);
        double yTop = keyboardTop - (endOffset * pixelsPerMs);
        yBottom = yBottom.clamp(-50.0, height * 0.95);
        yTop = yTop.clamp(-50.0, yBottom);
        if (yBottom < 0) continue;

        final whiteIndex = _midiToWhiteKeyIndex(note.pitch);
        if (whiteIndex < 0) continue;
        final x = whiteIndex * keyWidth;

        final color = note.isBlackKey
            ? (style?.blackKeyColor ?? const Color(0xD9FF7043))
            : (style?.whiteKeyColor ?? const Color(0xD94FC3F7));

        strips.add(NoteStripRenderData(
          quad: [Offset(x, yTop), Offset(x + keyWidth * 0.8, yTop),
                 Offset(x + keyWidth * 0.8, yBottom), Offset(x, yBottom)],
          color: color.withOpacity(style?.transparency ?? 0.85),
          glowRadius: style?.glowRadius ?? 6,
          glowIntensity: style?.glowStrength ?? 0.5,
        ));

        if (startOffset <= 0 && endOffset >= 0) {
          highlights.add(KeyHighlightRenderData(
            quad: [Offset(x, keyboardTop), Offset(x + keyWidth * 0.8, keyboardTop),
                   Offset(x + keyWidth * 0.8, height * 0.95), Offset(x, height * 0.95)],
            color: Colors.white.withOpacity(0.25),
          ));
        }
      }
    } else {
      _generateDemoStrips(strips, highlights, width, height);
    }

    return OverlayFrameData(strips: strips, keyHighlights: highlights, timestampMs: _currentTimeMs);
  }

  void _generateDemoStrips(List<NoteStripRenderData> strips, List<KeyHighlightRenderData> highlights,
      double width, double height) {
    final keyboardTop = height * 0.7;
    final keyWidth = width / 52;

    for (int i = 0; i < 8; i++) {
      final keyIndex = 10 + i * 6;
      final x = keyIndex * keyWidth;
      final noteStartMs = i * 500.0 + 1000.0;
      final noteDuration = 400.0 + i * 100.0;
      final noteEndMs = noteStartMs + noteDuration;
      final pixelsPerMs = keyboardTop / 2000.0;
      final startOffset = noteStartMs - _currentTimeMs;
      final endOffset = noteEndMs - _currentTimeMs;
      double yBottom = (keyboardTop - (startOffset * pixelsPerMs)).clamp(-50.0, height * 0.95);
      double yTop = (keyboardTop - (endOffset * pixelsPerMs)).clamp(-50.0, yBottom);
      if (yBottom < 0) continue;

      final isBlack = i % 3 == 1;
      final color = isBlack ? const Color(0xD9FF7043) : const Color(0xD94FC3F7);
      strips.add(NoteStripRenderData(
        quad: [Offset(x, yTop), Offset(x + keyWidth * 0.8, yTop),
               Offset(x + keyWidth * 0.8, yBottom), Offset(x, yBottom)],
        color: color, glowRadius: 6, glowIntensity: 0.5,
      ));
      if (startOffset <= 0 && endOffset >= 0) {
        highlights.add(KeyHighlightRenderData(
          quad: [Offset(x, keyboardTop), Offset(x + keyWidth * 0.8, keyboardTop),
                 Offset(x + keyWidth * 0.8, height * 0.95), Offset(x, height * 0.95)],
          color: Colors.white.withOpacity(0.25),
        ));
      }
    }
  }

  int _midiToWhiteKeyIndex(int pitch) {
    final offset = pitch - 21;
    if (offset < 0 || offset >= 88) return -1;
    int whiteCount = 0;
    for (int i = 21; i < pitch; i++) {
      if (!_isBlack(i)) whiteCount++;
    }
    return whiteCount;
  }

  bool _isBlack(int pitch) {
    const blacks = [1, 3, 6, 8, 10];
    return blacks.contains(pitch % 12);
  }

  String _formatTime(double ms) {
    final seconds = (ms / 1000).floor();
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
