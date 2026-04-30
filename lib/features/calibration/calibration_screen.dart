import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../models/calibration.dart';
import '../../services/project_provider.dart';
import '../../services/native_bridge.dart';

class CalibrationScreen extends StatefulWidget {
  final ProjectProvider provider;
  const CalibrationScreen({super.key, required this.provider});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  // The 4 corner points placed by the user (normalized 0-1 relative to widget size)
  final List<Offset> _corners = [];
  KeyboardSize _keyboardSize = KeyboardSize.keys88;
  int _customLowest = 21;
  int _customHighest = 108;
  bool _showGrid = true;
  bool _computing = false;
  String? _error;

  // Video player for frame seeking
  Player? _player;
  VideoController? _videoController;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _videoReady = false;

  static const _cornerLabels = ['Top-Left', 'Top-Right', 'Bottom-Right', 'Bottom-Left'];

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    final videoPath = widget.provider.project?.videoPath;
    if (videoPath == null) return;

    _player = Player();
    _videoController = VideoController(_player!);

    _player!.stream.position.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _player!.stream.duration.listen((dur) {
      if (mounted && dur.inMilliseconds > 0) {
        setState(() => _duration = dur);
      }
    });

    await _player!.open(Media(videoPath), play: false);
    setState(() => _videoReady = true);
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calibrate Piano'),
        actions: [
          if (_corners.length == 4)
            TextButton(
              onPressed: _proceedToSync,
              child: const Text('Continue →'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Instructions
          _buildInstructions(),
          // Main calibration area
          Expanded(
            child: _buildCalibrationArea(),
          ),
          // Video seek slider
          _buildSeekSlider(),
          // Keyboard size selector
          _buildKeyboardSelector(),
          // Controls
          _buildControls(),
          // Error display
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          // Computing indicator
          if (_computing)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildInstructions() {
    final step = _corners.length;
    String instruction;
    if (step < 4) {
      instruction = 'Tap the ${_cornerLabels[step]} corner of the keyboard';
    } else {
      instruction = 'Calibration complete! Drag corners to adjust, then continue.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Text(
        instruction,
        style: Theme.of(context).textTheme.bodyLarge,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildCalibrationArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: (details) => _handleTap(details, constraints),
          child: Container(
            color: Colors.black,
            child: Stack(
              children: [
                // Video frame display
                Center(
                  child: _videoReady && _videoController != null
                      ? SizedBox(
                          width: constraints.maxWidth * 0.9,
                          height: constraints.maxHeight * 0.9,
                          child: Video(
                            controller: _videoController!,
                            controls: (state) => const SizedBox.shrink(),
                          ),
                        )
                      : Container(
                          width: constraints.maxWidth * 0.9,
                          height: constraints.maxHeight * 0.9,
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            border: Border.all(color: Colors.grey[700]!),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                ),
                // Overlay with corners and grid
                CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: CalibrationOverlayPainter(
                    corners: _corners,
                    showGrid: _showGrid && _corners.length == 4,
                    keyboardSize: _keyboardSize,
                  ),
                ),
                // Draggable corner handles
                ..._buildCornerHandles(constraints),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildCornerHandles(BoxConstraints constraints) {
    return List.generate(_corners.length, (index) {
      final pos = _corners[index];
      return Positioned(
        left: pos.dx - 16,
        top: pos.dy - 16,
        child: GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              _corners[index] = Offset(
                (_corners[index].dx + details.delta.dx).clamp(0, constraints.maxWidth),
                (_corners[index].dy + details.delta.dy).clamp(0, constraints.maxHeight),
              );
            });
          },
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _cornerColor(index),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: _cornerColor(index).withOpacity(0.5),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Color _cornerColor(int index) {
    const colors = [Colors.red, Colors.green, Colors.blue, Colors.orange];
    return colors[index % 4];
  }

  Widget _buildSeekSlider() {
    if (!_videoReady) return const SizedBox.shrink();

    final totalMs = _duration.inMilliseconds.toDouble();
    final currentMs = _position.inMilliseconds.toDouble();

    String formatDuration(Duration d) {
      final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$minutes:$seconds';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            formatDuration(_position),
            style: const TextStyle(fontSize: 12),
          ),
          Expanded(
            child: Slider(
              value: totalMs > 0 ? currentMs.clamp(0, totalMs) : 0,
              min: 0,
              max: totalMs > 0 ? totalMs : 1,
              onChanged: (value) {
                _player?.seek(Duration(milliseconds: value.toInt()));
              },
            ),
          ),
          Text(
            formatDuration(_duration),
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyboardSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Keyboard: '),
              const SizedBox(width: 8),
              SegmentedButton<KeyboardSize>(
                segments: KeyboardSize.values.map((size) {
                  return ButtonSegment(
                    value: size,
                    label: Text(size.label),
                  );
                }).toList(),
                selected: {_keyboardSize},
                onSelectionChanged: (selected) {
                  setState(() {
                    _keyboardSize = selected.first;
                    if (_keyboardSize != KeyboardSize.custom) {
                      _customLowest = _keyboardSize.lowestNote;
                      _customHighest = _keyboardSize.highestNote;
                    }
                  });
                },
              ),
            ],
          ),
          if (_keyboardSize == KeyboardSize.custom) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Lowest: ${KeyRange.noteName(_customLowest)} (MIDI $_customLowest)',
                          style: const TextStyle(fontSize: 12)),
                      Slider(
                        value: _customLowest.toDouble(),
                        min: 21,
                        max: (_customHighest - 1).toDouble(),
                        divisions: _customHighest - 22,
                        onChanged: (v) => setState(() => _customLowest = v.round()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Highest: ${KeyRange.noteName(_customHighest)} (MIDI $_customHighest)',
                          style: const TextStyle(fontSize: 12)),
                      Slider(
                        value: _customHighest.toDouble(),
                        min: (_customLowest + 1).toDouble(),
                        max: 108,
                        divisions: 107 - _customLowest,
                        onChanged: (v) => setState(() => _customHighest = v.round()),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Text(
              'Range: ${KeyRange.noteName(_customLowest)} – ${KeyRange.noteName(_customHighest)} '
              '(${KeyRange(lowestNote: _customLowest, highestNote: _customHighest).whiteKeys} white keys)',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          FilterChip(
            label: const Text('Show Grid'),
            selected: _showGrid,
            onSelected: (v) => setState(() => _showGrid = v),
          ),
          const SizedBox(width: 12),
          if (_corners.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() => _corners.clear()),
              icon: const Icon(Icons.undo),
              label: const Text('Reset'),
            ),
          const Spacer(),
          if (_corners.length == 4)
            FilledButton(
              onPressed: _proceedToSync,
              child: const Text('Continue to Sync →'),
            ),
        ],
      ),
    );
  }

  void _handleTap(TapDownDetails details, BoxConstraints constraints) {
    if (_corners.length >= 4) return;
    setState(() {
      _corners.add(details.localPosition);
    });
  }

  void _proceedToSync() {
    _computeCalibrationAndProceed();
  }

  Future<void> _computeCalibrationAndProceed() async {
    if (_corners.length != 4) return;

    setState(() { _computing = true; _error = null; });

    try {
      final keyRange = _keyboardSize == KeyboardSize.custom
          ? KeyRange(lowestNote: _customLowest, highestNote: _customHighest)
          : KeyRange.fromPreset(_keyboardSize);

      final corners = KeyboardCorners(
        topLeft: Point2D(_corners[0].dx, _corners[0].dy),
        topRight: Point2D(_corners[1].dx, _corners[1].dy),
        bottomRight: Point2D(_corners[2].dx, _corners[2].dy),
        bottomLeft: Point2D(_corners[3].dx, _corners[3].dy),
      );

      // Try Rust bridge first, fall back to Dart-side computation
      CalibrationData? calibration;
      try {
        final bridge = NativeBridge();
        if (bridge.isInitialized) {
          calibration = bridge.computeCalibration(
            topLeft: Point2D(_corners[0].dx, _corners[0].dy),
            topRight: Point2D(_corners[1].dx, _corners[1].dy),
            bottomRight: Point2D(_corners[2].dx, _corners[2].dy),
            bottomLeft: Point2D(_corners[3].dx, _corners[3].dy),
            numKeys: keyRange.totalKeys,
          );
        }
      } catch (_) {
        // Rust bridge not available, use Dart-side homography
      }

      calibration ??= CalibrationData(
        corners: corners,
        keyboardSize: _keyboardSize,
        keyRange: keyRange,
        homography: _computeDartHomography(corners, keyRange.whiteKeys),
        keyPositions: const [],
      );

      widget.provider.setCalibration(calibration);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _error = 'Calibration failed: $e');
    } finally {
      if (mounted) setState(() => _computing = false);
    }
  }

  /// Simple Dart-side 3x3 homography from 4 corner points.
  List<List<double>> _computeDartHomography(KeyboardCorners corners, int whiteKeys) {
    // Map canonical space (0..whiteKeys, 0..1) to screen coords via the 4 corners
    // Source points (canonical): TL=(0,0), TR=(wk,0), BR=(wk,1), BL=(0,1)
    // Dest points (screen): user's 4 corner taps
    final wk = whiteKeys.toDouble();
    final srcPts = [
      [0.0, 0.0], [wk, 0.0], [wk, 1.0], [0.0, 1.0],
    ];
    final dstPts = [
      [corners.topLeft.x, corners.topLeft.y],
      [corners.topRight.x, corners.topRight.y],
      [corners.bottomRight.x, corners.bottomRight.y],
      [corners.bottomLeft.x, corners.bottomLeft.y],
    ];

    // Build 8x9 augmented matrix for DLT
    final a = List.generate(8, (_) => List.filled(9, 0.0));
    for (int i = 0; i < 4; i++) {
      final sx = srcPts[i][0], sy = srcPts[i][1];
      final dx = dstPts[i][0], dy = dstPts[i][1];
      a[i * 2][0] = sx; a[i * 2][1] = sy; a[i * 2][2] = 1;
      a[i * 2][6] = -dx * sx; a[i * 2][7] = -dx * sy; a[i * 2][8] = dx;
      a[i * 2 + 1][3] = sx; a[i * 2 + 1][4] = sy; a[i * 2 + 1][5] = 1;
      a[i * 2 + 1][6] = -dy * sx; a[i * 2 + 1][7] = -dy * sy; a[i * 2 + 1][8] = dy;
    }

    // Gaussian elimination
    for (int col = 0; col < 8; col++) {
      int maxRow = col;
      for (int row = col + 1; row < 8; row++) {
        if (a[row][col].abs() > a[maxRow][col].abs()) maxRow = row;
      }
      final temp = a[col]; a[col] = a[maxRow]; a[maxRow] = temp;
      final pivot = a[col][col];
      if (pivot.abs() < 1e-12) continue;
      for (int j = col; j < 9; j++) a[col][j] /= pivot;
      for (int row = 0; row < 8; row++) {
        if (row == col) continue;
        final factor = a[row][col];
        for (int j = col; j < 9; j++) a[row][j] -= factor * a[col][j];
      }
    }

    // Extract h values: h[i] = a[i][8], h8 = 1
    final h = List.generate(8, (i) => a[i][8]);
    return [
      [h[0], h[1], h[2]],
      [h[3], h[4], h[5]],
      [h[6], h[7], 1.0],
    ];
  }
}

/// Custom painter that draws the calibration overlay (corners, connecting lines, grid).
class CalibrationOverlayPainter extends CustomPainter {
  final List<Offset> corners;
  final bool showGrid;
  final KeyboardSize keyboardSize;

  CalibrationOverlayPainter({
    required this.corners,
    required this.showGrid,
    required this.keyboardSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.isEmpty) return;

    final linePaint = Paint()
      ..color = Colors.cyan.withOpacity(0.8)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Draw connecting lines between placed corners
    if (corners.length >= 2) {
      for (int i = 0; i < corners.length - 1; i++) {
        canvas.drawLine(corners[i], corners[i + 1], linePaint);
      }
      if (corners.length == 4) {
        canvas.drawLine(corners[3], corners[0], linePaint);
      }
    }

    // Draw grid if all 4 corners placed
    if (showGrid && corners.length == 4) {
      _drawKeyGrid(canvas, size);
    }
  }

  void _drawKeyGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.cyan.withOpacity(0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final whiteKeys = keyboardSize.whiteKeys;

    // Draw vertical lines for each white key boundary
    for (int i = 0; i <= whiteKeys; i++) {
      final t = i / whiteKeys;
      // Interpolate along top edge
      final topPoint = Offset.lerp(corners[0], corners[1], t)!;
      // Interpolate along bottom edge
      final bottomPoint = Offset.lerp(corners[3], corners[2], t)!;
      canvas.drawLine(topPoint, bottomPoint, gridPaint);
    }

    // Draw horizontal line at ~60% (black key boundary)
    final blackKeyLine = 0.6;
    for (int i = 0; i < 4; i++) {
      // nothing for now, just the verticals are sufficient for visual feedback
    }
    final midLeft = Offset.lerp(corners[0], corners[3], blackKeyLine)!;
    final midRight = Offset.lerp(corners[1], corners[2], blackKeyLine)!;
    canvas.drawLine(midLeft, midRight, gridPaint);
  }

  @override
  bool shouldRepaint(covariant CalibrationOverlayPainter oldDelegate) {
    return corners != oldDelegate.corners ||
        showGrid != oldDelegate.showGrid ||
        keyboardSize != oldDelegate.keyboardSize;
  }
}
