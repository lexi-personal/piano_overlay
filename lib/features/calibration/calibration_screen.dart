import 'package:flutter/material.dart';
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
  bool _showGrid = true;
  bool _computing = false;
  String? _error;

  static const _cornerLabels = ['Top-Left', 'Top-Right', 'Bottom-Right', 'Bottom-Left'];

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
                // Video frame placeholder (in production: actual video frame)
                Center(
                  child: Container(
                    width: constraints.maxWidth * 0.9,
                    height: constraints.maxHeight * 0.9,
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      border: Border.all(color: Colors.grey[700]!),
                    ),
                    child: const Center(
                      child: Text(
                        'Video Frame\n(First frame shown here)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
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

  Widget _buildKeyboardSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
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
              setState(() => _keyboardSize = selected.first);
            },
          ),
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
      final bridge = NativeBridge();
      if (!bridge.isInitialized) {
        // Try to initialize with default paths
        try {
          bridge.initialize();
        } catch (_) {
          // If library not found, store corners without computing homography
          setState(() => _error = 'Rust library not loaded. Calibration stored without homography.');
          Navigator.pushNamed(context, '/sync');
          return;
        }
      }

      final calibration = bridge.computeCalibration(
        topLeft: Point2D(_corners[0].dx, _corners[0].dy),
        topRight: Point2D(_corners[1].dx, _corners[1].dy),
        bottomRight: Point2D(_corners[2].dx, _corners[2].dy),
        bottomLeft: Point2D(_corners[3].dx, _corners[3].dy),
        numKeys: _keyboardSize.totalKeys,
      );

      widget.provider.setCalibration(calibration);

      if (mounted) {
        Navigator.pushNamed(context, '/sync');
      }
    } catch (e) {
      setState(() => _error = 'Calibration failed: $e');
    } finally {
      if (mounted) setState(() => _computing = false);
    }
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
