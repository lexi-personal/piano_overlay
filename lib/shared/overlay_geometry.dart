import 'dart:ui';

import '../models/calibration.dart';
import '../models/midi_note.dart';
import '../models/overlay_style.dart';
import '../features/preview/overlay_painter.dart';

/// Dart-side overlay geometry engine that computes perspective-correct note
/// strips using bilinear interpolation in a linearly-defined fall lane.
///
/// Replaces direct homography extrapolation (which causes singularities at
/// far points) with a safe linear extension of the keyboard edges.
class OverlayGeometry {
  OverlayGeometry._();

  /// Canonical strip height in keyboard-height units for the fall lane.
  static const double _canonicalStripHeight = 6.0;

  /// Trail fade duration in ms for notes that have already ended.
  static const double _trailFadeMs = 200.0;

  /// Strip width per unit of [OverlayStyle.stripThickness], in canonical white
  /// key units. Picked so the default thickness of 0.8 keeps the original
  /// 0.9 / 0.55 widths.
  static const double _whiteStripWidthUnit = 1.125;
  static const double _blackStripWidthUnit = 0.6875;

  /// Compute a full overlay frame for the given timestamp.
  static OverlayFrameData computeFrame({
    required double timestampMs,
    required List<MidiNote> notes,
    required CalibrationData calibration,
    required OverlayStyle style,
    required SyncSettings sync,
    required double displayWidth,
    required double displayHeight,
    double? calibrationWidth,
    double? calibrationHeight,
    double displayOffsetX = 0,
    double displayOffsetY = 0,
  }) {
    final effectiveTime = _applySync(timestampMs, sync);
    final lookahead = style.lookaheadMs;

    final lowestNote = calibration.keyRange.lowestNote;
    final highestNote = calibration.keyRange.highestNote;
    final whiteKeys = calibration.keyRange.whiteKeys;

    // Get scaled homography for current display dimensions.
    final h = _getScaledHomography(
      calibration,
      displayWidth,
      displayHeight,
      calibrationWidth,
      calibrationHeight,
      displayOffsetX,
      displayOffsetY,
    );

    // --- Build the fall lane as an upright, screen-space wall ---
    // Notes travel straight up/down the screen rather than receding along the
    // keyboard plane. Extrapolating the homography past the keyboard degenerates
    // on angled shots -- the plane runs to the horizon, so the lane slides
    // sideways and eventually inverts. An upright wall cannot do either.
    //
    // Top-to-bottom stands the wall on the keyboard's far edge (y = 0) and
    // rises up the screen; bottom-to-top stands it on the near edge (y = 1)
    // and drops down the screen.
    final anchorY = style.fallDirection == FallDirection.bottomToTop ? 1.0 : 0.0;
    final riseSign = style.fallDirection == FallDirection.bottomToTop ? 1.0 : -1.0;

    // Keyboard edge via homography (within calibrated region, safe).
    final kbLeft = _transformPoint(h, 0.0, anchorY);
    final kbRight = _transformPoint(h, whiteKeys.toDouble(), anchorY);

    // A wall of constant height in the world looks taller where it is nearer
    // the camera. The keyboard's own depth at a given x is the perspective cue
    // for that, and it is measured entirely inside the calibrated quad, so it
    // can never blow up the way an extrapolation can.
    final laneHeightLeft = _laneHeightAt(h, 0.0);
    final laneHeightRight = _laneHeightAt(h, whiteKeys.toDouble());

    final laneTopLeft = Offset(
      kbLeft.dx,
      kbLeft.dy + riseSign * laneHeightLeft,
    );
    final laneTopRight = Offset(
      kbRight.dx,
      kbRight.dy + riseSign * laneHeightRight,
    );

    final fallLaneQuad = [kbLeft, kbRight, laneTopRight, laneTopLeft];

    final strips = <NoteStripRenderData>[];
    final keyHighlights = <KeyHighlightRenderData>[];

    for (final note in notes) {
      if (note.pitch < lowestNote || note.pitch > highestNote) continue;

      final startOffset = note.startMs - effectiveTime;
      final endOffset = note.endMs - effectiveTime;

      // Visibility check.
      if (endOffset < -_trailFadeMs || startOffset > lookahead) continue;
      final isSounding = startOffset <= 0 && endOffset >= 0;
      if (!style.showBeforePlay && startOffset > 0) continue;
      if (!style.showDuringPlay && isSounding) continue;

      final isBlack = _isBlackKey(note.pitch);
      final keyX = _keyCanonicalX(note.pitch, lowestNote, isBlack);

      final tBottom = (startOffset / lookahead).clamp(0.0, 1.0);
      final tTop = (endOffset / lookahead).clamp(tBottom, 1.0);

      if (tTop - tBottom < 0.0005) continue;

      // Fractional x positions for left/right edges of the key strip.
      final widthUnit = isBlack ? _blackStripWidthUnit : _whiteStripWidthUnit;
      final halfWidth = widthUnit * style.stripThickness / 2.0;
      final uLeft = keyX - halfWidth;
      final uRight = keyX + halfWidth;

      // Anchor the strip to its own key: the landing edge comes straight from
      // that key's calibrated boundaries, and the strip rises vertically from
      // there. Nothing is interpolated across the whole lane, so a note always
      // lines up with the key it belongs to.
      final baseLeft = _transformPoint(h, uLeft, anchorY);
      final baseRight = _transformPoint(h, uRight, anchorY);
      final heightLeft = _laneHeightAt(h, uLeft, whiteKeys.toDouble());
      final heightRight = _laneHeightAt(h, uRight, whiteKeys.toDouble());

      final bottomLeft = _lanePoint(baseLeft, heightLeft, riseSign, tBottom);
      final bottomRight = _lanePoint(baseRight, heightRight, riseSign, tBottom);
      final topRight = _lanePoint(baseRight, heightRight, riseSign, tTop);
      final topLeft = _lanePoint(baseLeft, heightLeft, riseSign, tTop);

      // Determine color.
      Color baseColor;
      if (style.useHandColors) {
        baseColor = note.track == 0 ? style.leftHandColor : style.rightHandColor;
      } else {
        baseColor = isBlack ? style.blackKeyColor : style.whiteKeyColor;
      }
      // Fade notes that have already ended (trail effect).
      final fade = endOffset < 0
          ? 1.0 - ((-endOffset) / _trailFadeMs).clamp(0.0, 1.0)
          : 1.0;

      final color = baseColor.withOpacity(style.transparency * fade);

      // Corner rounding and outlines are stored as a fraction of the strip
      // width so they look identical in the preview and in the export.
      final stripPxWidth = (bottomRight - bottomLeft).distance;

      strips.add(NoteStripRenderData(
        quad: [topLeft, topRight, bottomRight, bottomLeft],
        color: color,
        glowRadius: style.glowRadius,
        glowIntensity: style.glowStrength,
        cornerRadius: style.cornerRadius * stripPxWidth,
        borderWidth: style.borderWidth * stripPxWidth,
        borderColor: style.borderColor.withOpacity(style.borderColor.opacity * fade),
      ));

      // Key highlights for notes currently being played.
      if (style.keyHighlightEnabled && startOffset <= 0 && endOffset >= 0) {
        final highlightQuad = _computeKeyQuad(note.pitch, lowestNote, isBlack, h);
        keyHighlights.add(KeyHighlightRenderData(
          quad: highlightQuad,
          color: style.keyHighlightColor,
        ));
      }
    }

    return OverlayFrameData(
      strips: strips,
      keyHighlights: keyHighlights,
      timestampMs: timestampMs,
      fallLaneQuad: fallLaneQuad,
    );
  }

  /// A point on the upright lane: [base] is the landing edge, and the lane
  /// rises [riseSign] * [height] pixels away from it over the full lookahead.
  static Offset _lanePoint(
    Offset base,
    double height,
    double riseSign,
    double t,
  ) {
    return Offset(base.dx, base.dy + riseSign * height * t);
  }

  /// On-screen height of the lane above the key at canonical x [u], in pixels.
  ///
  /// The keyboard's own depth at that x is the perspective cue: a wall of
  /// constant world height looks taller where it is nearer the camera. [u] is
  /// clamped into the calibrated span so the measurement never leaves the quad
  /// -- extrapolating past it is exactly what made the old lane degenerate.
  static double _laneHeightAt(
    List<List<double>> h,
    double u, [
    double? whiteKeys,
  ]) {
    final clamped = whiteKeys == null ? u : u.clamp(0.0, whiteKeys);
    final far = _transformPoint(h, clamped, 0.0);
    final near = _transformPoint(h, clamped, 1.0);
    return (near - far).distance * _canonicalStripHeight;
  }

  /// Apply sync offset to playback time.
  static double _applySync(double playbackTimeMs, SyncSettings sync) {
    if (sync.driftEnabled) {
      return playbackTimeMs + sync.driftStartMs;
    }
    return playbackTimeMs + sync.offsetMs;
  }

  /// Get a homography scaled to the current display dimensions.
  ///
  /// [calibrationWidth]/[calibrationHeight] describe the coordinate space the
  /// calibration corners were recorded in (the native video resolution), while
  /// [displayWidth]/[displayHeight] and [displayOffsetX]/[displayOffsetY]
  /// describe the rectangle the video is actually drawn into, letterbox offset
  /// included.
  static List<List<double>> _getScaledHomography(
    CalibrationData calibration,
    double displayWidth,
    double displayHeight,
    double? calibrationWidth,
    double? calibrationHeight,
    double displayOffsetX,
    double displayOffsetY,
  ) {
    if (calibrationWidth == null ||
        calibrationHeight == null ||
        calibrationWidth <= 0 ||
        calibrationHeight <= 0) {
      return calibration.homography;
    }

    final sx = displayWidth / calibrationWidth;
    final sy = displayHeight / calibrationHeight;

    if ((sx - 1.0).abs() < 1e-6 &&
        (sy - 1.0).abs() < 1e-6 &&
        displayOffsetX.abs() < 1e-6 &&
        displayOffsetY.abs() < 1e-6) {
      return calibration.homography;
    }

    // Rescale corners and recompute homography.
    final corners = calibration.corners;
    final scaledCorners = [
      Offset(corners.topLeft.x * sx + displayOffsetX,
          corners.topLeft.y * sy + displayOffsetY),
      Offset(corners.topRight.x * sx + displayOffsetX,
          corners.topRight.y * sy + displayOffsetY),
      Offset(corners.bottomRight.x * sx + displayOffsetX,
          corners.bottomRight.y * sy + displayOffsetY),
      Offset(corners.bottomLeft.x * sx + displayOffsetX,
          corners.bottomLeft.y * sy + displayOffsetY),
    ];

    return _computeHomography(
      calibration.keyRange.whiteKeys,
      scaledCorners,
    );
  }

  /// The rectangle a video of [videoWidth] x [videoHeight] occupies when it is
  /// drawn with `BoxFit.contain` inside [container].
  ///
  /// Both the preview overlay and the calibration editor use this so taps and
  /// painted strips land on the same pixels as the video itself.
  static Rect fitVideoRect({
    required Size container,
    required double videoWidth,
    required double videoHeight,
  }) {
    if (videoWidth <= 0 ||
        videoHeight <= 0 ||
        container.width <= 0 ||
        container.height <= 0) {
      return Offset.zero & container;
    }

    final scale = (container.width / videoWidth) < (container.height / videoHeight)
        ? container.width / videoWidth
        : container.height / videoHeight;
    final width = videoWidth * scale;
    final height = videoHeight * scale;

    return Rect.fromLTWH(
      (container.width - width) / 2,
      (container.height - height) / 2,
      width,
      height,
    );
  }

  /// Public wrapper for computing a homography from corners.
  static List<List<double>> computeHomographyPublic(
    int whiteKeys,
    List<Offset> screenCorners,
  ) {
    return _computeHomography(whiteKeys, screenCorners);
  }

  /// Solve the 8x8 linear system for a 3x3 homography matrix mapping
  /// the canonical rectangle (0,0)-(whiteKeys,1) to 4 screen corners.
  ///
  /// Corner order: TL, TR, BR, BL.
  /// Canonical source points:
  ///   TL -> (0, 0), TR -> (W, 0), BR -> (W, 1), BL -> (0, 1)
  static List<List<double>> _computeHomography(
    int whiteKeys,
    List<Offset> screenCorners,
  ) {
    final w = whiteKeys.toDouble();

    // Source points in canonical space.
    final srcX = [0.0, w, w, 0.0];
    final srcY = [0.0, 0.0, 1.0, 1.0];

    // Destination points in screen space.
    final dstX = [
      screenCorners[0].dx,
      screenCorners[1].dx,
      screenCorners[2].dx,
      screenCorners[3].dx,
    ];
    final dstY = [
      screenCorners[0].dy,
      screenCorners[1].dy,
      screenCorners[2].dy,
      screenCorners[3].dy,
    ];

    // Build the 8x8 matrix for the DLT (Direct Linear Transform).
    // For each point correspondence (sx, sy) -> (dx, dy):
    //   [sx, sy, 1, 0, 0, 0, -dx*sx, -dx*sy] [h00]   [dx]
    //   [0, 0, 0, sx, sy, 1, -dy*sx, -dy*sy] [h01] = [dy]
    //                                          [h02]
    //                                          [h10]
    //                                          [h11]
    //                                          [h12]
    //                                          [h20]
    //                                          [h21]
    // with h22 = 1.

    final a = List.generate(8, (_) => List.filled(8, 0.0));
    final b = List.filled(8, 0.0);

    for (var i = 0; i < 4; i++) {
      final row1 = i * 2;
      final row2 = i * 2 + 1;

      a[row1][0] = srcX[i];
      a[row1][1] = srcY[i];
      a[row1][2] = 1.0;
      a[row1][3] = 0.0;
      a[row1][4] = 0.0;
      a[row1][5] = 0.0;
      a[row1][6] = -dstX[i] * srcX[i];
      a[row1][7] = -dstX[i] * srcY[i];
      b[row1] = dstX[i];

      a[row2][0] = 0.0;
      a[row2][1] = 0.0;
      a[row2][2] = 0.0;
      a[row2][3] = srcX[i];
      a[row2][4] = srcY[i];
      a[row2][5] = 1.0;
      a[row2][6] = -dstY[i] * srcX[i];
      a[row2][7] = -dstY[i] * srcY[i];
      b[row2] = dstY[i];
    }

    // Gaussian elimination with partial pivoting.
    for (var col = 0; col < 8; col++) {
      // Find pivot.
      var maxVal = a[col][col].abs();
      var maxRow = col;
      for (var row = col + 1; row < 8; row++) {
        if (a[row][col].abs() > maxVal) {
          maxVal = a[row][col].abs();
          maxRow = row;
        }
      }

      // Swap rows.
      if (maxRow != col) {
        final tmpRow = a[col];
        a[col] = a[maxRow];
        a[maxRow] = tmpRow;
        final tmpB = b[col];
        b[col] = b[maxRow];
        b[maxRow] = tmpB;
      }

      final pivot = a[col][col];
      if (pivot.abs() < 1e-12) continue;

      // Eliminate below.
      for (var row = col + 1; row < 8; row++) {
        final factor = a[row][col] / pivot;
        for (var k = col; k < 8; k++) {
          a[row][k] -= factor * a[col][k];
        }
        b[row] -= factor * b[col];
      }
    }

    // Back substitution.
    final x = List.filled(8, 0.0);
    for (var i = 7; i >= 0; i--) {
      var sum = b[i];
      for (var j = i + 1; j < 8; j++) {
        sum -= a[i][j] * x[j];
      }
      x[i] = a[i][i].abs() > 1e-12 ? sum / a[i][i] : 0.0;
    }

    // Construct 3x3 matrix (row-major).
    return [
      [x[0], x[1], x[2]],
      [x[3], x[4], x[5]],
      [x[6], x[7], 1.0],
    ];
  }

  /// Apply 3x3 homography to a point, returning the projected screen point.
  static Offset _transformPoint(List<List<double>> h, double x, double y) {
    final xp = h[0][0] * x + h[0][1] * y + h[0][2];
    final yp = h[1][0] * x + h[1][1] * y + h[1][2];
    final w = h[2][0] * x + h[2][1] * y + h[2][2];

    if (w.abs() < 1e-12) return Offset(xp, yp);
    return Offset(xp / w, yp / w);
  }

  /// Compute the canonical X position of a key in white-key units.
  static double _keyCanonicalX(int pitch, int lowestNote, bool isBlack) {
    if (!isBlack) {
      // White key: count white keys below this one, then add 0.5 for center.
      return _countWhiteKeysBelow(pitch, lowestNote) + 0.5;
    }

    // Black key: a black key straddles the seam between two white keys, and
    // `whiteBelow` is exactly that seam because it counts every white key to
    // the left. Real keyboards nudge the keys within a group away from the
    // seam rather than sitting dead on it.
    final whiteBelow = _countWhiteKeysBelow(pitch, lowestNote);
    return whiteBelow + _blackKeySeamOffset(pitch % 12);
  }

  /// How far a black key's centre sits from the seam between its neighbouring
  /// white keys, in white-key widths.
  static double _blackKeySeamOffset(int semitone) {
    switch (semitone) {
      case 1: // C#
        return -0.05;
      case 3: // D#
        return 0.05;
      case 6: // F#
        return -0.10;
      case 8: // G#
        return 0.0;
      case 10: // A#
        return 0.10;
      default:
        return 0.0;
    }
  }

  /// Count non-black keys from [lowest] up to (but not including) [note].
  static int _countWhiteKeysBelow(int note, int lowest) {
    var count = 0;
    for (var n = lowest; n < note; n++) {
      if (!_isBlackKey(n)) count++;
    }
    return count;
  }

  /// Returns true if the MIDI note is a black key.
  static bool _isBlackKey(int note) {
    final semitone = note % 12;
    return const [1, 3, 6, 8, 10].contains(semitone);
  }

  /// Compute the key rectangle on the keyboard surface (y=0 to y=1)
  /// using the homography. This is safe since it maps within the
  /// calibrated region.
  static List<Offset> _computeKeyQuad(
    int pitch,
    int lowestNote,
    bool isBlack,
    List<List<double>> homography,
  ) {
    final keyX = _keyCanonicalX(pitch, lowestNote, isBlack);
    final keyWidth = isBlack ? 0.55 : 0.9;
    final halfWidth = keyWidth / 2.0;

    final xLeft = keyX - halfWidth;
    final xRight = keyX + halfWidth;

    // Map the 4 corners of the key through the homography.
    // y=0 is top of keyboard, y=1 is bottom (front edge).
    final tl = _transformPoint(homography, xLeft, 0.0);
    final tr = _transformPoint(homography, xRight, 0.0);
    final br = _transformPoint(homography, xRight, 1.0);
    final bl = _transformPoint(homography, xLeft, 1.0);

    return [tl, tr, br, bl];
  }
}
