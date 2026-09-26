import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../models/calibration.dart';
import '../../shared/overlay_geometry.dart';

/// The in-progress calibration the user is placing on top of the video.
///
/// Corners are kept in **video frame pixels** so the result is independent of
/// the window size and matches what the Rust exporter expects.
class CalibrationDraft {
  static const List<String> cornerLabels = [
    'Top-Left',
    'Top-Right',
    'Bottom-Right',
    'Bottom-Left',
  ];

  final List<Offset> corners = [];
  KeyboardSize keyboardSize = KeyboardSize.keys88;
  int lowestNote = 21;
  int highestNote = 108;
  bool showGrid = true;

  /// How much of the centre area the video is shrunk into while calibrating.
  ///
  /// Anything below 1.0 leaves a margin around the frame so corners of a
  /// keyboard that runs off the edge of the recording can still be placed.
  double zoom = 1.0;

  static const double minZoom = 0.35;
  static const double maxZoom = 1.0;

  CalibrationDraft();

  /// Start from an existing calibration so "Recalibrate" keeps the old corners
  /// as a starting point instead of forcing a fresh set of taps.
  factory CalibrationDraft.from(CalibrationData? calibration) {
    final draft = CalibrationDraft();
    if (calibration == null) return draft;

    draft.keyboardSize = calibration.keyboardSize;
    draft.lowestNote = calibration.keyRange.lowestNote;
    draft.highestNote = calibration.keyRange.highestNote;
    draft.corners.addAll([
      calibration.corners.topLeft.toOffset(),
      calibration.corners.topRight.toOffset(),
      calibration.corners.bottomRight.toOffset(),
      calibration.corners.bottomLeft.toOffset(),
    ]);
    return draft;
  }

  bool get isComplete => corners.length == 4;

  KeyRange get keyRange => keyboardSize == KeyboardSize.custom
      ? KeyRange(lowestNote: lowestNote, highestNote: highestNote)
      : KeyRange.fromPreset(keyboardSize);

  String get instruction => isComplete
      ? 'Drag the numbered handles to fine-tune, then apply.'
      : 'Click the ${cornerLabels[corners.length]} corner of the keyboard.';

  /// Build the calibration for a video of the given native size.
  CalibrationData toCalibration({
    required double videoWidth,
    required double videoHeight,
  }) {
    final range = keyRange;
    return CalibrationData(
      corners: KeyboardCorners(
        topLeft: Point2D(corners[0].dx, corners[0].dy),
        topRight: Point2D(corners[1].dx, corners[1].dy),
        bottomRight: Point2D(corners[2].dx, corners[2].dy),
        bottomLeft: Point2D(corners[3].dx, corners[3].dy),
      ),
      keyboardSize: keyboardSize,
      keyRange: range,
      homography: OverlayGeometry.computeHomographyPublic(
        range.whiteKeys,
        List<Offset>.from(corners),
      ),
      keyPositions: const [],
      calibrationWidth: videoWidth,
      calibrationHeight: videoHeight,
    );
  }
}

/// Colour of the handle for corner [index].
Color calibrationCornerColor(int index) {
  const colors = [Colors.red, Colors.green, Colors.blue, Colors.orange];
  return colors[index % 4];
}

/// Draws the calibration quad and the white key grid.
///
/// [corners] are in the painter's own (display) coordinates.
class CalibrationOverlayPainter extends CustomPainter {
  final List<Offset> corners;
  final bool showGrid;
  final int whiteKeys;

  const CalibrationOverlayPainter({
    required this.corners,
    required this.showGrid,
    required this.whiteKeys,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.isEmpty) return;

    final linePaint = Paint()
      ..color = Colors.cyan.withOpacity(0.8)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < corners.length - 1; i++) {
      canvas.drawLine(corners[i], corners[i + 1], linePaint);
    }
    if (corners.length == 4) {
      canvas.drawLine(corners[3], corners[0], linePaint);
      if (showGrid) _drawKeyGrid(canvas);
    }
  }

  void _drawKeyGrid(Canvas canvas) {
    if (whiteKeys <= 0) return;

    final gridPaint = Paint()
      ..color = Colors.cyan.withOpacity(0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (int i = 0; i <= whiteKeys; i++) {
      final t = i / whiteKeys;
      canvas.drawLine(
        Offset.lerp(corners[0], corners[1], t)!,
        Offset.lerp(corners[3], corners[2], t)!,
        gridPaint,
      );
    }

    // The approximate black key / white key boundary.
    const blackKeyLine = 0.6;
    canvas.drawLine(
      Offset.lerp(corners[0], corners[3], blackKeyLine)!,
      Offset.lerp(corners[1], corners[2], blackKeyLine)!,
      gridPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CalibrationOverlayPainter oldDelegate) {
    return !listEquals(corners, oldDelegate.corners) ||
        showGrid != oldDelegate.showGrid ||
        whiteKeys != oldDelegate.whiteKeys;
  }
}

/// Side panel shown while the user is calibrating.
class CalibrationEditorPanel extends StatelessWidget {
  final CalibrationDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onReset;
  final VoidCallback onCancel;
  final VoidCallback onApply;

  const CalibrationEditorPanel({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.onReset,
    required this.onCancel,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final range = draft.keyRange;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Calibrating',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                )),
        const SizedBox(height: 8),
        Text(draft.instruction, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        const Text('Keyboard size'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: KeyboardSize.values.map((size) {
            return ChoiceChip(
              label: Text(size.label),
              selected: draft.keyboardSize == size,
              onSelected: (_) {
                draft.keyboardSize = size;
                if (size != KeyboardSize.custom) {
                  draft.lowestNote = size.lowestNote;
                  draft.highestNote = size.highestNote;
                }
                onChanged();
              },
            );
          }).toList(),
        ),
        if (draft.keyboardSize == KeyboardSize.custom) ...[
          const SizedBox(height: 12),
          Text('Lowest: ${KeyRange.noteName(draft.lowestNote)}',
              style: const TextStyle(fontSize: 12)),
          Slider(
            value: draft.lowestNote.toDouble(),
            min: 21,
            max: (draft.highestNote - 1).toDouble(),
            divisions: draft.highestNote - 22,
            onChanged: (v) {
              draft.lowestNote = v.round();
              onChanged();
            },
          ),
          Text('Highest: ${KeyRange.noteName(draft.highestNote)}',
              style: const TextStyle(fontSize: 12)),
          Slider(
            value: draft.highestNote.toDouble(),
            min: (draft.lowestNote + 1).toDouble(),
            max: 108,
            divisions: 107 - draft.lowestNote,
            onChanged: (v) {
              draft.highestNote = v.round();
              onChanged();
            },
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '${KeyRange.noteName(range.lowestNote)} – '
          '${KeyRange.noteName(range.highestNote)} '
          '(${range.whiteKeys} white keys)',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: Text('Frame zoom')),
            Text('${(draft.zoom * 100).round()}%',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        Slider(
          value: draft.zoom,
          min: CalibrationDraft.minZoom,
          max: CalibrationDraft.maxZoom,
          onChanged: (v) {
            draft.zoom = v;
            onChanged();
          },
        ),
        const Text(
          'Zoom out to place corners of a keyboard that extends past the edge '
          'of the recording.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Show key grid'),
          value: draft.showGrid,
          onChanged: (v) {
            draft.showGrid = v;
            onChanged();
          },
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: draft.isComplete ? onApply : null,
          child: const Text('Apply calibration'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: draft.corners.isEmpty ? null : onReset,
          child: const Text('Clear corners'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    );
  }
}
