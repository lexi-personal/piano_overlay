import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The core overlay painter that renders note strips on top of the video.
/// Consumes pre-computed OverlayFrame data from the shared Rust geometry engine.
///
/// This painter does NOT compute geometry — it only draws the quads/colors/glow
/// that the Rust engine has already computed. This guarantees preview/export parity.
class OverlayPainter extends CustomPainter {
  final List<NoteStripRenderData> strips;
  final List<KeyHighlightRenderData> keyHighlights;
  final double backgroundDim;
  final List<Offset>? fallLaneQuad;
  final double laneOpacity;

  /// Area the video occupies. Nothing is drawn outside it, matching the
  /// export, where the overlay can only land on the video frame itself.
  final Rect? clipRect;

  OverlayPainter({
    required this.strips,
    required this.keyHighlights,
    this.backgroundDim = 0.0,
    this.fallLaneQuad,
    this.laneOpacity = 0.55,
    this.clipRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (clipRect != null) {
      canvas.save();
      canvas.clipRect(clipRect!);
    }
    _paintContents(canvas, clipRect ?? (Offset.zero & size));
    if (clipRect != null) canvas.restore();
  }

  void _paintContents(Canvas canvas, Rect bounds) {
    // Apply background dimming
    if (backgroundDim > 0.0) {
      final dimPaint = Paint()
        ..color = Colors.black.withOpacity(backgroundDim);
      canvas.drawRect(bounds, dimPaint);
    }

    // Draw the fall-lane background
    if (fallLaneQuad != null && fallLaneQuad!.length == 4 && laneOpacity > 0) {
      final lanePath = Path()
        ..moveTo(fallLaneQuad![0].dx, fallLaneQuad![0].dy)
        ..lineTo(fallLaneQuad![1].dx, fallLaneQuad![1].dy)
        ..lineTo(fallLaneQuad![2].dx, fallLaneQuad![2].dy)
        ..lineTo(fallLaneQuad![3].dx, fallLaneQuad![3].dy)
        ..close();
      final lanePaint = Paint()
        ..color = Colors.black.withOpacity(laneOpacity)
        ..style = PaintingStyle.fill;
      canvas.drawPath(lanePath, lanePaint);
      // Subtle edge line at keyboard top
      final edgePaint = Paint()
        ..color = Colors.white.withOpacity(0.15)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(fallLaneQuad![0], fallLaneQuad![1], edgePaint);
    }

    // Draw key highlights first (below strips)
    for (final highlight in keyHighlights) {
      _drawQuad(canvas, highlight.quad, highlight.color, null);
    }

    // Draw note strips with glow
    for (final strip in strips) {
      if (strip.glowRadius > 0 && strip.glowIntensity > 0) {
        final glowColor = strip.color.withOpacity(strip.color.opacity * strip.glowIntensity * 0.6);
        _drawQuad(canvas, strip.quad, glowColor, strip.glowRadius,
            cornerRadius: strip.cornerRadius);
      }
      _drawQuad(canvas, strip.quad, strip.color, null,
          cornerRadius: strip.cornerRadius);

      if (strip.borderWidth > 0 && strip.borderColor.opacity > 0) {
        _drawQuad(canvas, strip.quad, strip.borderColor, null,
            cornerRadius: strip.cornerRadius, strokeWidth: strip.borderWidth);
      }
    }
  }

  void _drawQuad(
    Canvas canvas,
    List<Offset> quad,
    Color color,
    double? blurRadius, {
    double cornerRadius = 0,
    double strokeWidth = 0,
  }) {
    if (quad.length != 4) return;

    final path = _quadPath(quad, cornerRadius);

    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;

    if (strokeWidth > 0) {
      // Inset the stroke so the outline sits inside the strip, like the
      // export compositor draws it.
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.save();
      canvas.clipPath(path);
      canvas.drawPath(path, paint);
      canvas.restore();
      return;
    }

    paint.style = PaintingStyle.fill;
    if (blurRadius != null && blurRadius > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius);
    }

    canvas.drawPath(path, paint);
  }

  /// Build the strip outline, rounding the corners by [cornerRadius] pixels.
  ///
  /// The rounded shape is the quad eroded by the radius and then swept with a
  /// circle of that radius — the same construction the Rust compositor
  /// rasterises, so preview and export agree.
  static Path _quadPath(List<Offset> quad, double cornerRadius) {
    final radius = cornerRadius <= 0 ? 0.0 : cornerRadius.clamp(0.0, _maxInset(quad));
    if (radius <= 0) {
      return Path()
        ..moveTo(quad[0].dx, quad[0].dy)
        ..lineTo(quad[1].dx, quad[1].dy)
        ..lineTo(quad[2].dx, quad[2].dy)
        ..lineTo(quad[3].dx, quad[3].dy)
        ..close();
    }

    final path = Path();
    for (var i = 0; i < 4; i++) {
      final previous = quad[(i + 3) % 4];
      final current = quad[i];
      final next = quad[(i + 1) % 4];

      final fromPrevious = _towards(current, previous, radius);
      final towardsNext = _towards(current, next, radius);

      if (i == 0) {
        path.moveTo(fromPrevious.dx, fromPrevious.dy);
      } else {
        path.lineTo(fromPrevious.dx, fromPrevious.dy);
      }
      path.quadraticBezierTo(
          current.dx, current.dy, towardsNext.dx, towardsNext.dy);
    }
    path.close();
    return path;
  }

  /// Point [distance] pixels from [from] along the line towards [to].
  static Offset _towards(Offset from, Offset to, double distance) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1e-9) return from;
    final t = math.min(distance / length, 0.5);
    return Offset(from.dx + dx * t, from.dy + dy * t);
  }

  /// Largest rounding that still fits inside the quad.
  static double _maxInset(List<Offset> quad) {
    var shortest = double.infinity;
    for (var i = 0; i < 4; i++) {
      final a = quad[i];
      final b = quad[(i + 1) % 4];
      final length = math.sqrt(
          math.pow(b.dx - a.dx, 2) + math.pow(b.dy - a.dy, 2));
      if (length < shortest) shortest = length;
    }
    return shortest / 2;
  }

  @override
  bool shouldRepaint(covariant OverlayPainter oldDelegate) {
    // Always repaint when strips change (they change every frame during playback)
    return true;
  }
}

/// Render data for a single note strip (mirrors Rust NoteStrip).
class NoteStripRenderData {
  /// Four screen-space vertices: TL, TR, BR, BL.
  final List<Offset> quad;
  /// Fill color with alpha.
  final Color color;
  /// Glow radius in pixels.
  final double glowRadius;
  /// Glow intensity (0-1).
  final double glowIntensity;
  /// Corner rounding radius in pixels.
  final double cornerRadius;
  /// Outline width in pixels.
  final double borderWidth;
  /// Outline color.
  final Color borderColor;

  const NoteStripRenderData({
    required this.quad,
    required this.color,
    this.glowRadius = 0,
    this.glowIntensity = 0,
    this.cornerRadius = 0,
    this.borderWidth = 0,
    this.borderColor = const Color(0x00000000),
  });

  /// Parse from JSON (output of Rust ffi_compute_overlay_frame).
  factory NoteStripRenderData.fromJson(Map<String, dynamic> json) {
    final quadData = json['quad'] as List;
    final colorData = json['color'] as List;

    return NoteStripRenderData(
      quad: quadData.map((p) => Offset(
        (p['x'] as num).toDouble(),
        (p['y'] as num).toDouble(),
      )).toList(),
      color: Color.fromRGBO(
        (colorData[0] * 255).round(),
        (colorData[1] * 255).round(),
        (colorData[2] * 255).round(),
        (colorData[3] as num).toDouble(),
      ),
      glowRadius: (json['glow_radius'] as num?)?.toDouble() ?? 0,
      glowIntensity: (json['glow_intensity'] as num?)?.toDouble() ?? 0,
      cornerRadius: (json['corner_radius'] as num?)?.toDouble() ?? 0,
      borderWidth: (json['border_width'] as num?)?.toDouble() ?? 0,
      borderColor: _rgbaToColor(json['border_color']),
    );
  }

  static Color _rgbaToColor(dynamic data) {
    if (data is! List || data.length < 4) return const Color(0x00000000);
    return Color.fromRGBO(
      (data[0] * 255).round(),
      (data[1] * 255).round(),
      (data[2] * 255).round(),
      (data[3] as num).toDouble(),
    );
  }
}

/// Render data for a key highlight (mirrors Rust KeyHighlight).
class KeyHighlightRenderData {
  final List<Offset> quad;
  final Color color;

  const KeyHighlightRenderData({
    required this.quad,
    required this.color,
  });

  factory KeyHighlightRenderData.fromJson(Map<String, dynamic> json) {
    final quadData = json['quad'] as List;
    final colorData = json['color'] as List;

    return KeyHighlightRenderData(
      quad: quadData.map((p) => Offset(
        (p['x'] as num).toDouble(),
        (p['y'] as num).toDouble(),
      )).toList(),
      color: Color.fromRGBO(
        (colorData[0] * 255).round(),
        (colorData[1] * 255).round(),
        (colorData[2] * 255).round(),
        (colorData[3] as num).toDouble(),
      ),
    );
  }
}

/// Parsed overlay frame from Rust (mirrors Rust OverlayFrame).
class OverlayFrameData {
  final List<NoteStripRenderData> strips;
  final List<KeyHighlightRenderData> keyHighlights;
  final double timestampMs;
  final List<Offset>? fallLaneQuad;

  const OverlayFrameData({
    required this.strips,
    required this.keyHighlights,
    required this.timestampMs,
    this.fallLaneQuad,
  });

  factory OverlayFrameData.fromJson(Map<String, dynamic> json) {
    List<Offset>? quad;
    if (json['fall_lane_quad'] != null) {
      quad = (json['fall_lane_quad'] as List)
          .map((p) => Offset(
                (p['x'] as num).toDouble(),
                (p['y'] as num).toDouble(),
              ))
          .toList();
    }
    return OverlayFrameData(
      strips: (json['strips'] as List)
          .map((s) => NoteStripRenderData.fromJson(s))
          .toList(),
      keyHighlights: (json['key_highlights'] as List)
          .map((k) => KeyHighlightRenderData.fromJson(k))
          .toList(),
      timestampMs: (json['timestamp_ms'] as num).toDouble(),
      fallLaneQuad: quad,
    );
  }
}
